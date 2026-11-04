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
/// el token de renovación va al Llavero. Sin API web (cuentas gratuitas), la sesión se pide una vez
/// a través de la app de Spotify con el SDK y también es renovable: después Planaby hace de llave
/// de paso y manda las órdenes sin abrir Spotify (solo lo abre si está dormido y pides reproducir).
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
    /// Con sesión de la API web (si no, solo con la app de Spotify).
    private(set) var isWebLinked: Bool
    /// Hay sesión renovable en el Llavero: reconecta sin abrir Spotify.
    private(set) var hasSession: Bool

    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private var accessExpiry = Date.distantPast
    @ObservationIgnored private var verifier: String?
    @ObservationIgnored private var appRemote: SPTAppRemote?
    @ObservationIgnored private var sessionManager: SPTSessionManager?
    @ObservationIgnored private var awaitingSession = false
    /// Renovación del acceso en curso: las demás peticiones la esperan en vez de pedir otra
    /// (el token de renovación cambia en cada uso y dos a la vez se anularían).
    @ObservationIgnored private var renewal: Task<Void, Error>?
    /// Intento de conexión en curso (para no pisarlo con otro).
    @ObservationIgnored private var connectStarted: Date?
    /// Orden que se repite en cuanto Spotify vuelve a conectar (tras pedir acceso de nuevo).
    @ObservationIgnored private var pending: PendingCommand?

    private enum PendingCommand {
        case pause, next, previous, shuffle(Bool)
    }
    @ObservationIgnored private let bridge = RemoteBridge()
    @ObservationIgnored private var artworkID: String?

    enum Keys {
        static let clientID = "spotifyClientID"
        static let account = "spotifyAccountName"
        /// Versión de los permisos pedidos (2 = con app-remote-control).
        static let scopes = "spotifyScopeVersion"
        /// Conectado solo con la app de Spotify, sin API web.
        static let appOnly = "spotifyAppOnly"
        /// La cuenta no puede usar la API web (sesión pedida por la app de Spotify).
        static let noWebAPI = "spotifyNoWebAPI"
        /// Spotify ya se configuró una vez: no se vuelve a pedir en Ajustes (solo «Desconectar» lo quita).
        static let configured = "spotifyConfigured"
    }

    static let redirectScheme = "planaby-spotify"
    static let redirectURI = "planaby-spotify://callback"
    private static let keychainService = "com.alvaro.planaby.spotify"
    private static let scopes = "app-remote-control user-read-playback-state user-modify-playback-state user-read-currently-playing playlist-read-private"
    private static let scopeVersion = 2

    private init() {
        let defaults = UserDefaults.standard
        let session = Self.refreshToken() != nil
        hasSession = session
        isWebLinked = session && !defaults.bool(forKey: Keys.noWebAPI)
        isConnected = defaults.bool(forKey: Keys.configured) || session || defaults.bool(forKey: Keys.appOnly)
        accountName = defaults.string(forKey: Keys.account)
        if isConnected { defaults.set(true, forKey: Keys.configured) }
        // El último acceso sigue valiendo al cerrar y volver a abrir Planaby, hasta que caduque.
        if let saved = Self.savedAccess() {
            accessToken = saved.token
            accessExpiry = saved.expiry
        }
    }

    /// Hay con qué conectar sin abrir Spotify: un acceso vigente o una sesión renovable.
    private var hasUsableToken: Bool {
        (accessToken != nil && accessExpiry > .now.addingTimeInterval(30)) || hasSession
    }

    private func store(access: String, expiry: Date) {
        accessToken = access
        accessExpiry = expiry
        Self.saveAccess(access, expiry: expiry)
    }

    private func markConfigured() {
        UserDefaults.standard.set(true, forKey: Keys.configured)
        isConnected = true
    }

    /// La sesión renovable ya no vale: se olvida, pero Spotify sigue configurado. La próxima
    /// orden pide acceso a la app de Spotify (se abre un instante) sin pasar por Ajustes.
    private func dropSession() {
        Self.deleteRefreshToken()
        hasSession = false
        isWebLinked = false
        UserDefaults.standard.set(true, forKey: Keys.appOnly)
    }

    /// Se conectó antes de que Planaby usara App Remote: conviene volver a conectar.
    var needsReconnect: Bool {
        isWebLinked && UserDefaults.standard.integer(forKey: Keys.scopes) < Self.scopeVersion
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
        markConfigured()
        isWebLinked = true
        hasSession = true
        UserDefaults.standard.removeObject(forKey: Keys.appOnly)
        UserDefaults.standard.removeObject(forKey: Keys.noWebAPI)
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
        Self.deleteAccess()
        pending = nil
        accessToken = nil
        accessExpiry = .distantPast
        isConnected = false
        isWebLinked = false
        hasSession = false
        awaitingSession = false
        accountName = nil
        track = nil
        isPlaying = false
        UserDefaults.standard.removeObject(forKey: Keys.account)
        UserDefaults.standard.removeObject(forKey: Keys.appOnly)
        UserDefaults.standard.removeObject(forKey: Keys.noWebAPI)
        UserDefaults.standard.removeObject(forKey: Keys.scopes)
        UserDefaults.standard.removeObject(forKey: Keys.configured)
    }

    private func validToken() async throws -> String {
        if let accessToken, accessExpiry > .now.addingTimeInterval(30) { return accessToken }
        if let renewal {
            try await renewal.value
        } else {
            guard let refresh = Self.refreshToken() else {
                hasSession = false
                isWebLinked = false
                throw SpotifyError.message(isConnected ? "Toca reproducir para abrir Spotify un instante y reconectar." : "Conecta Spotify en Ajustes › Música.")
            }
            let form = ["grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID]
            let task = Task { try await self.requestToken(form) }
            renewal = task
            defer { renewal = nil }
            try await task.value
        }
        guard let accessToken, accessExpiry > .now else { throw SpotifyError.message("Spotify no ha dado acceso.") }
        return accessToken
    }

    private func requestToken(_ form: [String: String]) async throws {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(form.map { "\($0.key)=\(Self.formEncode($0.value))" }.joined(separator: "&").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let token = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            // Solo un acceso rechazado cierra la sesión; un fallo pasajero de Spotify no.
            guard status == 400 || status == 401 else {
                throw SpotifyError.message("Spotify no responde ahora mismo. Prueba en un momento.")
            }
            if form["grant_type"] == "refresh_token" { dropSession() }
            throw SpotifyError.message("Spotify no ha aceptado el acceso. Revisa el Client ID y la Redirect URI.")
        }
        store(access: token.access_token, expiry: .now.addingTimeInterval(TimeInterval(token.expires_in)))
        if let refresh = token.refresh_token { Self.saveRefreshToken(refresh) }
    }

    // MARK: Estado

    /// Pregunta qué suena. Las vistas lo llaman cada pocos segundos mientras se ven.
    func refresh() async {
        guard isWebLinked, !isRemoteConnected else { return }
        do {
            let state: PlayerState? = try await get("/me/player")
            apply(state)
            lastError = nil
        } catch SpotifyError.forbidden {
            // La cuenta no tiene la API web: a partir de ahora, solo App Remote.
            UserDefaults.standard.set(true, forKey: Keys.noWebAPI)
            isWebLinked = false
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Mientras la vista que lo llama esté en pantalla, se actualiza cada 3 s y, si la app de
    /// Spotify no está conectada, se intenta reconectar en silencio cada 6 s (si suena, responde).
    func watch() async {
        var tick = 0
        while !Task.isCancelled {
            if !isRemoteConnected, tick.isMultiple(of: 2) { await connectRemote() }
            await refresh()
            tick += 1
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
            // Se decide con lo que dice Spotify ahora, no con lo último que se vio.
            let playing = await Self.playingNow(on: api) ?? isPlaying
            if await perform({ api, done in playing ? api.pause(done) : api.resume(done) }) {
                progress = position(at: .now)
                progressDate = .now
                isPlaying = !playing
                return
            }
        }
        guard isWebLinked else {
            // Despertar Spotify ya lo pone a sonar; para pausar, se pausa al conectar.
            if isPlaying { recover(.pause) } else { wakeSpotify() }
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

    /// Reanuda si está en pausa (reproducción automática al concentrarse).
    func resume() async {
        if !isPlaying { await togglePlay() }
    }

    /// Pausa si está sonando (al terminar la sesión).
    func pause() async {
        if await perform({ api, done in api.pause(done) }) {
            progress = position(at: .now)
            isPlaying = false
            return
        }
        if isPlaying, isWebLinked { await togglePlay() }
    }

    func next() async {
        if await perform({ api, done in api.skip(toNext: done) }) { return }
        if isWebLinked { await command("POST", "/me/player/next") } else { recover(.next) }
    }

    func previous() async {
        if await perform({ api, done in api.skip(toPrevious: done) }) { return }
        if isWebLinked { await command("POST", "/me/player/previous") } else { recover(.previous) }
    }

    func toggleShuffle() async {
        shuffle.toggle()
        let value = shuffle
        if await perform({ api, done in api.setShuffle(value, callback: done) }) { return }
        if isWebLinked { await command("PUT", "/me/player/shuffle?state=\(value)") } else { recover(.shuffle(value)) }
    }

    /// Sin conexión con la app de Spotify. Si falta el acceso, se pide de nuevo (Spotify se abre
    /// un instante y vuelve) y la orden se hace al conectar; si hay acceso, Spotify está dormido.
    private func recover(_ command: PendingCommand) {
        guard !hasUsableToken else {
            lastError = Self.asleep
            return
        }
        pending = command
        wakeSpotify()
    }

    private func runPending(_ command: PendingCommand) async {
        switch command {
        case .pause: _ = await perform { api, done in api.pause(done) }
        case .next: _ = await perform { api, done in api.skip(toNext: done) }
        case .previous: _ = await perform { api, done in api.skip(toPrevious: done) }
        case .shuffle(let value): _ = await perform { api, done in api.setShuffle(value, callback: done) }
        }
    }

    /// Pone una lista, un álbum o una canción (spotify:playlist:…).
    func play(uri: String) async {
        if await perform({ api, done in api.play(uri, callback: done) }) { return }
        guard isWebLinked else { wakeSpotify(playing: uri); return }
        let body = uri.contains(":track:") ? ["uris": [uri]] : ["context_uri": uri]
        await command("PUT", "/me/player/play", body: try? JSONSerialization.data(withJSONObject: body))
    }

    private func command(_ method: String, _ path: String, body: Data? = nil) async {
        // Sin API web y sin conexión con la app: no se abre Spotify para esto.
        guard isWebLinked else { lastError = Self.asleep; return }
        do {
            let status = try await send(method, path, body: body)
            if status == 404 {
                // Ningún dispositivo activo: se activa este iPhone y se reintenta.
                if try await activateThisPhone() { _ = try await send(method, path, body: body) }
            } else if status == 403 {
                // Cuenta gratuita y la app de Spotify sin responder.
                lastError = Self.asleep
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
        if let connectStarted, Date.now.timeIntervalSince(connectStarted) < 5 { return }
        guard let token = try? await validToken() else { return }
        connectStarted = .now
        remote.connectionParameters.accessToken = token
        remote.connect()
    }

    private static let asleep = "Spotify está dormido. Pulsa reproducir para despertarlo."

    /// Manda una orden por App Remote y espera su respuesta; si falla, rehace la conexión y lo
    /// intenta una vez más. Devuelve false si la app de Spotify no responde.
    private func perform(_ action: (any SPTAppRemotePlayerAPI, @escaping SPTAppRemoteCallback) -> Void) async -> Bool {
        for attempt in 0..<2 {
            guard let api = await remotePlayer() else { return false }
            let gate = Gate<RemoteOutcome>()
            let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<RemoteOutcome, Never>) in
                gate.set(continuation)
                action(api) { _, error in gate.finish(error == nil ? .done : .rejected) }
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    gate.finish(.timedOut)
                }
            }
            if outcome == .done {
                lastError = nil
                return true
            }
            if outcome == .rejected, appRemote?.isConnected == true {
                // Spotify recibió la orden pero no hacía falta (ya estaba en pausa, sin
                // canción siguiente…): la conexión está bien; se pone al día lo que se ve.
                if let snapshot = await Self.snapshot(on: api) { apply(remote: snapshot) }
                lastError = nil
                return true
            }
            if attempt == 0 {
                // La conexión estaba rota: se suelta y se vuelve a abrir.
                appRemote?.disconnect()
                isRemoteConnected = false
                connectStarted = nil
            }
        }
        return false
    }

    /// Al pasar Planaby a segundo plano se suelta la conexión, como pide el SDK.
    func disconnectRemote() {
        if appRemote?.isConnected == true { appRemote?.disconnect() }
    }

    /// El reproductor de App Remote, conectando si hace falta (espera hasta 4 s).
    private func remotePlayer() async -> (any SPTAppRemotePlayerAPI)? {
        if appRemote?.isConnected == true, let api = appRemote?.playerAPI { return api }
        // Sin acceso no hay nada que esperar: se pedirá a la app de Spotify.
        guard hasUsableToken else { return nil }
        await connectRemote()
        for _ in 0..<20 where appRemote?.isConnected != true {
            try? await Task.sleep(for: .milliseconds(200))
        }
        return appRemote?.isConnected == true ? appRemote?.playerAPI : nil
    }

    /// Qué está sonando según Spotify (nil si no contesta enseguida).
    private static func snapshot(on api: any SPTAppRemotePlayerAPI) async -> RemoteSnapshot? {
        let gate = Gate<RemoteSnapshot?>()
        return await withCheckedContinuation { (continuation: CheckedContinuation<RemoteSnapshot?, Never>) in
            gate.set(continuation)
            api.getPlayerState { result, _ in
                gate.finish((result as? any SPTAppRemotePlayerState).map(RemoteSnapshot.init))
            }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                gate.finish(nil)
            }
        }
    }

    private static func playingNow(on api: any SPTAppRemotePlayerAPI) async -> Bool? {
        await snapshot(on: api).map { !$0.paused }
    }

    /// Abre Spotify un instante para despertarlo; vuelve solo a Planaby y queda conectado.
    func wakeSpotify(playing uri: String = "") {
        guard let remote = remote() else { return }
        lastError = nil
        remote.authorizeAndPlayURI(uri, completionHandler: nil)
    }

    private func sessions() -> SPTSessionManager? {
        if let sessionManager { return sessionManager }
        guard !clientID.isEmpty, let redirect = URL(string: Self.redirectURI) else { return nil }
        let configuration = SPTConfiguration(clientID: clientID, redirectURL: redirect)
        // Al dar permiso sigue sonando lo último, así Spotify queda despierto para conectar.
        configuration.playURI = ""
        let manager = SPTSessionManager(configuration: configuration, delegate: bridge)
        sessionManager = manager
        return manager
    }

    /// Sin API web: Spotify se abre una sola vez para dar permiso y Planaby guarda una sesión
    /// renovable; después lo controla sin abrirlo.
    func connectWithApp() {
        guard let manager = sessions() else { return }
        lastError = nil
        awaitingSession = true
        manager.initiateSession(with: [.appRemoteControl], options: .default, campaign: nil)
    }

    fileprivate func sessionStarted(access: String, refresh: String, expiry: Date) {
        awaitingSession = false
        Self.saveRefreshToken(refresh)
        store(access: access, expiry: expiry)
        if !isWebLinked { UserDefaults.standard.set(true, forKey: Keys.noWebAPI) }
        UserDefaults.standard.removeObject(forKey: Keys.appOnly)
        UserDefaults.standard.set(Self.scopeVersion, forKey: Keys.scopes)
        hasSession = true
        markConfigured()
        lastError = nil
        if let remote = remote(), !remote.isConnected {
            connectStarted = .now
            remote.connectionParameters.accessToken = access
            remote.connect()
        }
    }

    fileprivate func sessionFailed(_ message: String) {
        awaitingSession = false
        lastError = "Spotify no ha dado permiso: \(message)"
    }

    /// Vuelta desde Spotify (planaby-spotify://callback?code=… o #access_token=…).
    func handleOpenURL(_ url: URL) {
        guard url.scheme == Self.redirectScheme else { return }
        if awaitingSession, let sessionManager,
           sessionManager.application(UIApplication.shared, open: url, options: [:]) {
            return
        }
        guard let remote = remote(), let parameters = remote.authorizationParameters(from: url) else { return }
        if let token = parameters[SPTAppRemoteAccessTokenKey] {
            if !hasSession { UserDefaults.standard.set(true, forKey: Keys.appOnly) }
            markConfigured()
            if !hasUsableToken || !hasSession {
                // El acceso que da la app de Spotify dura una hora; se guarda para no pedirlo otra vez.
                store(access: token, expiry: .now.addingTimeInterval(55 * 60))
            }
            remote.connectionParameters.accessToken = token
            remote.connect()
        } else if let error = parameters[SPTAppRemoteErrorDescriptionKey] {
            lastError = "Spotify: \(error)"
        }
    }

    fileprivate func remoteChanged(connected: Bool) {
        isRemoteConnected = connected
        connectStarted = nil
        if connected {
            lastError = nil
            if let command = pending {
                pending = nil
                Task { await self.runPending(command) }
            }
        }
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
        if status == 403 { throw SpotifyError.forbidden }
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

    private static var accessQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keychainService,
         kSecAttrAccount as String: "access"]
    }

    /// El acceso vigente, con su caducidad, para no perderlo al cerrar la app.
    private static func saveAccess(_ token: String, expiry: Date) {
        SecItemDelete(accessQuery as CFDictionary)
        var item = accessQuery
        item[kSecValueData as String] = Data("\(expiry.timeIntervalSince1970)\n\(token)".utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func savedAccess() -> (token: String, expiry: Date)? {
        var request = accessQuery
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let text = String(data: data, encoding: .utf8) else { return nil }
        let parts = text.split(separator: "\n", maxSplits: 1).map(String.init)
        guard parts.count == 2, let seconds = TimeInterval(parts[0]) else { return nil }
        let expiry = Date(timeIntervalSince1970: seconds)
        guard expiry > .now else { return nil }
        return (parts[1], expiry)
    }

    private static func deleteAccess() {
        SecItemDelete(accessQuery as CFDictionary)
    }
}

enum SpotifyError: LocalizedError {
    case message(String)
    case forbidden

    var errorDescription: String? {
        switch self {
        case .message(let text): text
        case .forbidden: "Spotify no permite la API web con esta cuenta."
        }
    }
}

/// Cómo acabó una orden de App Remote.
private enum RemoteOutcome: Sendable {
    /// Hecha.
    case done
    /// Spotify contestó con un error (la conexión funciona).
    case rejected
    /// Sin respuesta: la conexión estaba rota.
    case timedOut
}

/// Espera la respuesta de App Remote una sola vez (respuesta o tiempo agotado).
private final class Gate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    func set(_ continuation: CheckedContinuation<Value, Never>) {
        lock.withLock { self.continuation = continuation }
    }

    func finish(_ value: Value) {
        let pending = lock.withLock { () -> CheckedContinuation<Value, Never>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: value)
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

extension RemoteSnapshot {
    init(_ state: any SPTAppRemotePlayerState) {
        let track = state.track
        self.init(
            title: track.name, artist: track.artist.name, album: track.album.name, uri: track.uri,
            duration: TimeInterval(track.duration) / 1000, position: TimeInterval(state.playbackPosition) / 1000,
            paused: state.isPaused, shuffle: state.playbackOptions.isShuffling, imageID: track.imageIdentifier
        )
    }
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
        let snapshot = RemoteSnapshot(playerState)
        MainActor.assumeIsolated { SpotifyController.shared.apply(remote: snapshot) }
        let imageID = track.imageIdentifier
        remote?.imageAPI?.fetchImage(forItem: track, with: CGSize(width: 640, height: 640)) { result, _ in
            let image = result as? UIImage
            MainActor.assumeIsolated { SpotifyController.shared.setArtwork(image, for: imageID) }
        }
    }
}

// Sesión renovable pedida a la app de Spotify (puede avisar fuera del hilo principal).
extension RemoteBridge: SPTSessionManagerDelegate {
    func sessionManager(manager: SPTSessionManager, didInitiate session: SPTSession) {
        let access = session.accessToken
        let refresh = session.refreshToken
        let expiry = session.expirationDate
        Task { @MainActor in SpotifyController.shared.sessionStarted(access: access, refresh: refresh, expiry: expiry) }
    }

    func sessionManager(manager: SPTSessionManager, didFailWith error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor in SpotifyController.shared.sessionFailed(message) }
    }
}
