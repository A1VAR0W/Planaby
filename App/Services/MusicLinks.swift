import Foundation
import UIKit

/// Música para cada fase: un enlace de Spotify (o Apple Music, YouTube Music…) para concentrarse
/// y otro para descansar. Al empezar una sesión o un descanso con la app abierta se puede abrir solo.
@MainActor
enum MusicLinks {
    enum Keys {
        static let focus = "musicFocusURL"
        static let rest = "musicBreakURL"
        static let autoOpen = "musicAutoOpen"
    }

    static var autoOpen: Bool { UserDefaults.standard.bool(forKey: Keys.autoOpen) }

    static func link(for phase: PhaseKind) -> String {
        UserDefaults.standard.string(forKey: phase.isBreak ? Keys.rest : Keys.focus) ?? ""
    }

    static func hasLink(for phase: PhaseKind) -> Bool { url(from: link(for: phase)) != nil }

    /// Abre la música de la fase. Los enlaces de Spotify se abren directamente en su app.
    static func open(for phase: PhaseKind) {
        guard let web = url(from: link(for: phase)) else { return }
        // Con Spotify conectado se pone desde Planaby, sin salir de la app.
        let spotify = SpotifyController.shared
        if spotify.isConnected, let uri = spotifyURI(for: web) {
            Task { await spotify.play(uri: uri.absoluteString) }
            return
        }
        LeaveGuard.shared.excuse(for: 60)
        if let app = spotifyURI(for: web) {
            UIApplication.shared.open(app) { opened in
                if !opened { UIApplication.shared.open(web) }
            }
        } else {
            UIApplication.shared.open(web)
        }
    }

    /// Lo llama la interfaz cuando cambia la fase con la app delante.
    static func phaseChanged(to phase: PhaseKind?, from old: PhaseKind?) {
        guard autoOpen else { return }
        let spotify = SpotifyController.shared
        guard let phase else {
            // Fin de la sesión: se pausa lo que sonara en Spotify.
            if old != nil, spotify.isConnected { Task { await spotify.pause() } }
            return
        }
        // De un descanso a otro (corto → largo) no hace falta cambiar de música.
        if let old, old.isBreak == phase.isBreak { return }
        if hasLink(for: phase) {
            open(for: phase)
        } else if !phase.isBreak, spotify.isConnected {
            // Sin lista de concentración: sigue lo que estabas escuchando.
            Task { await spotify.resume() }
        }
    }

    /// Acepta enlaces https y URIs spotify:; nil si no es un enlace válido.
    static func url(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "spotify" { return url }
        guard scheme == "https", url.host() != nil else { return nil }
        return url
    }

    /// https://open.spotify.com/playlist/ID?si=… → spotify:playlist:ID
    private static func spotifyURI(for url: URL) -> URL? {
        if url.scheme == "spotify" { return url }
        guard url.host()?.hasSuffix("spotify.com") == true else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" && !$0.hasPrefix("intl-") }
        guard parts.count >= 2 else { return nil }
        return URL(string: "spotify:\(parts[0]):\(parts[1])")
    }
}
