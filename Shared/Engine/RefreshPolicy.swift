import Foundation

/// Cada cuánto despierta Planaby para poner algo al día. La regla: solo lo necesario para lo que
/// se ve, y nada si no cambia. Despertar la CPU cada segundo «por si acaso» es lo que más batería
/// gasta en una app que pasa horas abierta (el modo escritorio cargando, por ejemplo).
enum RefreshPolicy {
    /// Cada cuánto repintar una pantalla con la hora o una cuenta atrás: cada segundo si algo
    /// corre (una sesión sin pausa o música sonando); si no, al cambiar de minuto.
    static func tickInterval(sessionRunning: Bool, musicPlaying: Bool = false) -> TimeInterval {
        sessionRunning || musicPlaying ? 1 : 60
    }

    /// Desde cuándo contar los ticks: con ticks de un minuto, desde el inicio del minuto, para que
    /// el reloj cambie justo cuando cambia la hora.
    static func tickStart(interval: TimeInterval, now: Date = .now) -> Date {
        guard interval >= 60 else { return now }
        return Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }

    /// Cuánto esperar para pasar de fase: justo hasta que acabe (más un margen mínimo). nil si no
    /// hay que esperar a nada (sin sesión, en pausa o sin final). Si el final ya pasó y aún no se
    /// ha puesto al día, se vuelve a mirar en un segundo, nunca en un bucle sin pausa.
    static func reconcileDelay(phaseEnd: Date?, isPaused: Bool, now: Date = .now) -> TimeInterval? {
        guard let phaseEnd, !isPaused else { return nil }
        let left = phaseEnd.timeIntervalSince(now)
        return left > 0 ? left + 0.05 : 1
    }

    /// Spotify por la API web: cada pocos segundos si suena (para ver el cambio de canción), más
    /// despacio si no. Con App Remote conectado, Spotify avisa él solo y apenas hace falta mirar.
    static func musicPoll(isPlaying: Bool, remoteConnected: Bool) -> TimeInterval {
        if remoteConnected { return 30 }
        return isPlaying ? 4 : 15
    }

    /// Reintentos de conexión con la app de Spotify: cada vez más espaciados (6, 12, 24, 48 y
    /// después cada minuto). Volver a Planaby lo intenta otra vez enseguida.
    static func reconnectDelay(failures: Int) -> TimeInterval {
        min(60, 6 * pow(2, Double(max(0, failures - 1))))
    }
}
