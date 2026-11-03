import CryptoKit
import Foundation
import Observation
import Security
@preconcurrency import SpotifyiOS
import UIKit

/// Planaby como mando del Spotify instalado: qué suena (con su carátula), reproducir, pausar,
/// saltar y poner las listas de concentración o descanso.
///
/// Dos caminos: App Remote (el SDK oficial, que habla con la app de Spotify del iPhone y funciona
/// también con cuentas gratuitas) y, si no está disponible, la API web (ver lo que suena con
/// cualquier cuenta; controlar, solo con Premium). El acceso es con PKCE, sin secreto en la app;
/// el token de renovación va al Llavero.
@Observable
@MainActor
final class SpotifyController {
    static let shared = SpotifyController()

    struct Track: Equatable {
        var title: String
        var artists: String
        var album: String
        var artworkURL: URL?
        var duration: TimeInterval
        var uri: String
    }

    private(set) var track: Track?
    private(set) var isPlaying = false
    private(set) var shuffle = false
    private(set) var deviceName: String?
    /// Posición en el momento `progressDate`; se interpola para la barra.
    private(set) var progress: TimeInterval = 0
    private(set) var progressDate = Date.now
    private(set) var accountName: String?
    private(set) var lastError: String?
    private(set) var isConnected: Bool
    /// Carátula que da App Remote (con la API web se usa `track.artworkURL`).
    private(set) var artwork: UIImage?
    /// Conectado con la app de Spotify del iPhone.
    private(set) var isRemoteConnected = false

    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private var accessExpiry = Date.distantPast
    @ObservationIgnored private var verifier: String?
    @ObservationIgnored private var appRemote: SPTAppRemote?
    @ObservationIgnored private let bridge = RemoteBridge()
    @ObservationIgnored private var artworkID: String?

    enum Keys {
        static let clientID = "spotifyClientID"
        static let account = "spotifyAccountName"
        /// Versión de los permisos pedidos (2 = con app-remote-control).
        static let scopes = "spotifyScopeVersion"
    }

    static let redirectScheme = "planaby-spotify"
    static let redirectURI = "planaby-spotify://callback"
    private static let keychainService = "com.alvaro.planaby.spotify"
    private static let scopes = "app-remote-control user-read-playback-state user-modify-playback-state user-read-currently-playing playlist-read-private"
    private static let scopeVersion = 2

    private init() {
        isConnected = Self.refreshToken() != nil
        accountName = UserDefaults.standard.string(forKey: Keys.account)
    }

    /// Se conectó antes de que Planaby usara App Remote: conviene volver a conectar.
    var needsReconnect: Bool {
        isConnected && UserDefaults.standard.integer(forKey: Keys.scopes) < Self.scopeVersion
    }

    var clientID: String {
        (UserDefaults.standard.string(forKey: Keys.clientID) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Posición actual estimada.
    func position(at date: Date) -> TimeInterval {
        guard let track else { return 0 }
        let elapsed = isPlaying ? date.timeIntervalSince(progressDate) : 0
        return min(track.duration, progress + max(0, elapsed))
    }

    // MARK: Acceso (PKCE)

    /// Enlace de autorización; la vista lo abre con `webAuthenticationSession`.
    func authorizationURL() -> URL? {
        guard !clientID.isEmpty else { return nil }
        let verifier = Self.randomVerifier()
        self.verifier = verifier
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
            URLQueryItem(name: "scope", value: Self.scopes),
        ]
        return components?.url
    }

    /// Recibe la vuelta de Spotify (planaby-spotify://callback?code=…) y pide los tokens.
    func finishLogin(callback: URL) async throws {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value {
            throw SpotifyError.message(error == "access_denied" ? "Has cancelado el acceso a Spotify." : "Spotify respondió: \(error)")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, let verifier else {
            throw SpotifyError.message("Spotify no devolvió el código de acceso.")
        }
        try await requestToken([
            "grant_type": "authorization_code", "code": code, "redirect_uri": Self.redirectURI,
            "client_id": clientID, "code_verifier": verifier,
        ])
        self.verifier = nil
        isConnected = true
        lastError = nil
        UserDefaults.standard.set(Self.scopeVersion, forKey: Keys.scopes)
        if let me: Profile = try? await get("/me") {
            accountName = me.display_name ?? me.id
            UserDefaults.standard.set(accountName, forKey: Keys.account)
        }
        await refresh()
    }

    func disconnect() {
        appRemote?.disconnect()
        appRemote = nil
        isRemoteConnected = false
        artwork = nil
        Self.deleteRefreshToken()
        accessToken = nil
        accessExpiry = .distantPast
        isConnected = false
        accountName = nil
        track = nil
        isPlaying = false
        UserDefaults.standard.removeObject(forKey: Keys.account)
        UserDefaults.standard.removeObject(forKey: Keys.scopes)
    }

    private func validToken() async throws -> String {
        if let accessToken, accessExpiry > .now.addingTimeInterval(30) { return accessToken }
        guard let refresh = Self.refreshToken() else {
            isConnected = false
            throw SpotifyError.message("Conecta Spotify en Ajustes › Música.")
        }
        try await requestToken(["grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID])
        guard let accessToken else { throw SpotifyError.message("Spotify no ha dado acceso.") }
        return accessToken
    }

    private func requestToken(_ form: [String: String]) async throws {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(form.map { "\($0.key)=\(Self.formEncode($0.value))" }.joined(separator: "&").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let token = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            if form["grant_type"] == "refresh_token" { disconnect() }
            throw SpotifyError.message("Spotify no ha aceptado el acceso. Revisa el Client ID y la Redirect URI.")
        }
        accessToken = token.access_token
        accessExpiry = .now.addingTimeInterval(TimeInterval(token.expires_in))
        if let refresh = token.refresh_token { Self.saveRefreshToken(refresh) }
    }

    // MARK: Estado

    /// Pregunta qué suena. Las vistas lo llaman cada pocos segundos mientras se ven.
    func refresh() async {
        guard isConnected, !isRemoteConnected else { return }
        do {
            let state: PlayerState? = try await get("/me/player")
            apply(state)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Mientras la vista que lo llama esté en pantalla, se actualiza cada 3 s.
    func watch() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func apply(_ state: PlayerState?) {
        guard let state, let item = state.item else {
            track = nil
            isPlaying = false
            return
        }
        let image = item.album?.images?.max { ($0.width ?? 0) < ($1.width ?? 0) }
        track = Track(
            title: item.name,
            artists: (item.artists ?? []).map(\.name).joined(separator: ", "),
            album: item.album?.name ?? "",
            artworkURL: image.flatMap { URL(string: $0.url) },
            duration: TimeInterval(item.duration_ms) / 1000,
            uri: item.uri
        )
        artwork = nil
        isPlaying = state.is_playing
        shuffle = state.shuffle_state ?? false
        deviceName = state.device?.name
        progress = TimeInterval(state.progress_ms ?? 0) / 1000
        progressDate = .now
    }

    // MARK: Controles

    func togglePlay() async {
        if let api = await remotePlayer() {
            if isPlaying { api.pause(nil) } else { api.resume(nil) }
            progress = position(at: .now)
            progressDate = .now
            isPlaying.toggle()
            return
        }
        if isPlaying {
            isPlaying = false
            progress = position(at: .now)
            await command("PUT", "/me/player/pause")
        } else {
            progressDate = .now
            isPlaying = true
            await command("PUT", "/me/player/play")
        }
    }

    func next() async {
        if let api = await remotePlayer() { api.skip(toNext: nil); return }
        await command("POST", "/me/player/next")
    }

    func previous() async {
        if let api = await remotePlayer() { api.skip(toPrevious: nil); return }
        await command("POST", "/me/player/previous")
    }

    func toggleShuffle() async {
        shuffle.toggle()
        if let api = await remotePlayer() { api.setShuffle(shuffle, callback: nil); return }
        await command("PUT", "/me/player/shuffle?state=\(shuffle)")
    }

    /// Pone una lista, un álbum o una canción (spotify:playlist:…).
    func play(uri: String) async {
        if let api = await remotePlayer() { api.play(uri, callback: nil); return }
        let body = uri.contains(":track:") ? ["uris": [uri]] : ["context_uri": uri]
        await command("PUT", "/me/player/play", body: try? JSONSerialization.data(withJSONObject: body))
    }

    private func command(_ method: String, _ path: String, body: Data? = nil) async {
        do {
            let status = try await send(method, path, body: body)
            if status == 404 {
                // Ningún dispositivo activo: se activa este iPhone y se reintenta.
                if try await activateThisPhone() { _ = try await send(method, path, body: body) }
            } else if status == 403 {
                // Cuenta gratuita: se despierta la app de Spotify y se controla con App Remote.
                wakeSpotify()
            }
            try? await Task.sleep(for: .milliseconds(350))
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Pasa la reproducción a este iPhone; si Spotify está cerrado, lo abre para despertarlo.
    private func activateThisPhone() async throws -> Bool {
        let list: Devices? = try await get("/me/player/devices")
        let devices = list?.devices ?? []
        if let phone = devices.first(where: { $0.type == "Smartphone" }) ?? devices.first, let id = phone.id {
            let body = try JSONSerialization.data(withJSONObject: ["device_ids": [id]])
            _ = try await send("PUT", "/me/player", body: body)
            try? await Task.sleep(for: .milliseconds(500))
            return true
        }
        if let url = URL(string: "spotify:") { _ = await UIApplication.shared.open(url) }
        lastError = "Abre Spotify un momento para que Planaby pueda controlarlo."
        return false
    }

    // MARK: App Remote

    private func remote() -> SPTAppRemote? {
        if let appRemote { return appRemote }
        guard !clientID.isEmpty, let redirect = URL(string: Self.redirectURI) else { return nil }
        let remote = SPTAppRemote(configuration: SPTConfiguration(clientID: clientID, redirectURL: redirect), logLevel: .error)
        remote.delegate = bridge
        bridge.remote = remote
        appRemote = remote
        return remote
    }

    /// Conecta con la app de Spotify si ya está abierta (aunque sea en segundo plano). No la abre.
    func connectRemote() async {
        guard isConnected, let remote = remote(), !remote.isConnected else { return }
        guard let token = try? await validToken() else { return }
        remote.connectionParameters.accessToken = token
        remote.connect()
    }

    /// Al pasar Planaby a segundo plano se suelta la conexión, como pide el SDK.
    func disconnectRemote() {
        if appRemote?.isConnected == true { appRemote?.disconnect() }
    }

    /// El reproductor de App Remote, conectando si hace falta (espera hasta 2 s).
    private func remotePlayer() async -> (any SPTAppRemotePlayerAPI)? {
        if appRemote?.isConnected == true, let api = appRemote?.playerAPI { return api }
        await connectRemote()
        for _ in 0..<10 where appRemote?.isConnected != true {
            try? await Task.sleep(for: .milliseconds(200))
        }
        return appRemote?.isConnected == true ? appRemote?.playerAPI : nil
    }

    /// Abre Spotify un instante para despertarlo; vuelve solo a Planaby y queda conectado.
    func wakeSpotify(playing uri: String = "") {
        guard let remote = remote() else { return }
        lastError = nil
        remote.authorizeAndPlayURI(uri, completionHandler: nil)
    }

    /// Vuelta desde Spotify (planaby-spotify://callback#access_token=…).
    func handleOpenURL(_ url: URL) {
        guard url.scheme == Self.redirectScheme, let remote = remote(),
              let parameters = remote.authorizationParameters(from: url) else { return }
        if let token = parameters[SPTAppRemoteAccessTokenKey] {
            if accessToken == nil || accessExpiry < .now {
                accessToken = token
                accessExpiry = .now.addingTimeInterval(50 * 60)
            }
            remote.connectionParameters.accessToken = token
            remote.connect()
        } else if let error = parameters[SPTAppRemoteErrorDescriptionKey] {
            lastError = "Spotify: \(error)"
        }
    }

    fileprivate func remoteChanged(connected: Bool) {
        isRemoteConnected = connected
        if connected { lastError = nil }
    }

    fileprivate func apply(remote snapshot: RemoteSnapshot) {
        track = Track(
            title: snapshot.title, artists: snapshot.artist, album: snapshot.album,
            artworkURL: nil, duration: snapshot.duration, uri: snapshot.uri
        )
        isPlaying = !snapshot.paused
        shuffle = snapshot.shuffle
        progress = snapshot.position
        progressDate = .now
        deviceName = "este iPhone"
        if snapshot.imageID != artworkID {
            artworkID = snapshot.imageID
            artwork = nil
        }
    }

    fileprivate func setArtwork(_ image: UIImage?, for imageID: String) {
        if imageID == artworkID { artwork = image }
    }

    // MARK: Red

    private func get<T: Decodable>(_ path: String) async throws -> T? {
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1" + path)!)
        request.setValue("Bearer \(try await validToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 204 || data.isEmpty { return nil }
        if status == 401 { accessExpiry = .distantPast }
        guard (200..<300).contains(status) else { throw SpotifyError.message("Spotify no responde (\(status)).") }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func send(_ method: String, _ path: String, body: Data?) async throws -> Int {
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1" + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(try await validToken())", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else {
            request.setValue("0", forHTTPHeaderField: "Content-Length")
        }
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    // MARK: Ayudas

    private static func randomVerifier() -> String {
        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<64).map { _ in characters.randomElement()! })
    }

    private static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static var keychainQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keychainService,
         kSecAttrAccount as String: "refresh"]
    }

    private static func saveRefreshToken(_ token: String) {
        SecItemDelete(keychainQuery as CFDictionary)
        var item = keychainQuery
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func refreshToken() -> String? {
        var request = keychainQuery
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteRefreshToken() {
        SecItemDelete(keychainQuery as CFDictionary)
    }
}

enum SpotifyError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): text
        }
    }
}

// MARK: - Respuestas de la API

private struct TokenResponse: Decodable {
    let access_token: String
    let expires_in: Int
    let refresh_token: String?
}

private struct Profile: Decodable {
    let id: String
    let display_name: String?
}

private struct PlayerState: Decodable {
    struct Device: Decodable { let name: String? }
    struct Item: Decodable {
        struct Artist: Decodable { let name: String }
        struct Album: Decodable {
            struct Image: Decodable { let url: String; let width: Int? }
            let name: String?
            let images: [Image]?
        }
        let name: String
        let uri: String
        let duration_ms: Int
        let artists: [Artist]?
        let album: Album?
    }
    let is_playing: Bool
    let progress_ms: Int?
    let shuffle_state: Bool?
    let device: Device?
    let item: Item?
}

private struct Devices: Decodable {
    struct Device: Decodable {
        let id: String?
        let type: String
    }
    let devices: [Device]
}

// MARK: - Puente con el SDK (sus avisos llegan en el hilo principal)

fileprivate struct RemoteSnapshot: Sendable {
    let title: String
    let artist: String
    let album: String
    let uri: String
    let duration: TimeInterval
    let position: TimeInterval
    let paused: Bool
    let shuffle: Bool
    let imageID: String
}

private final class RemoteBridge: NSObject, SPTAppRemoteDelegate, SPTAppRemotePlayerStateDelegate {
    weak var remote: SPTAppRemote?

    func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        appRemote.playerAPI?.delegate = self
        appRemote.playerAPI?.subscribe(toPlayerState: nil)
        MainActor.assumeIsolated { SpotifyController.shared.remoteChanged(connected: true) }
    }

    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: (any Error)?) {
        MainActor.assumeIsolated { SpotifyController.shared.remoteChanged(connected: false) }
    }

    func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: (any Error)?) {
        MainActor.assumeIsolated { SpotifyController.shared.remoteChanged(connected: false) }
    }

    func playerStateDidChange(_ playerState: any SPTAppRemotePlayerState) {
        let track = playerState.track
        let snapshot = RemoteSnapshot(
            title: track.name, artist: track.artist.name, album: track.album.name, uri: track.uri,
            duration: TimeInterval(track.duration) / 1000, position: TimeInterval(playerState.playbackPosition) / 1000,
            paused: playerState.isPaused, shuffle: playerState.playbackOptions.isShuffling, imageID: track.imageIdentifier
        )
        MainActor.assumeIsolated { SpotifyController.shared.apply(remote: snapshot) }
        let imageID = track.imageIdentifier
        remote?.imageAPI?.fetchImage(forItem: track, with: CGSize(width: 640, height: 640)) { result, _ in
            let image = result as? UIImage
            MainActor.assumeIsolated { SpotifyController.shared.setArtwork(image, for: imageID) }
        }
    }
}
