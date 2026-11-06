import Foundation

/// Cómo avisa Planaby al cambiar de fase.
enum AlertStyle: String, CaseIterable, Identifiable, Sendable {
    case sound, vibration, visual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sound: "Sonido y vibración"
        case .vibration: "Solo vibración"
        case .visual: "Solo visual"
        }
    }
}

/// Juego de sonidos propios (generados con tools/make_sounds.py) o el del sistema.
enum AlertSoundSet: String, CaseIterable, Identifiable, Sendable {
    case soft, wood, glass, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soft: "Campana suave"
        case .wood: "Madera"
        case .glass: "Cristal"
        case .system: "Sonido del sistema"
        }
    }

    /// Nombre del archivo para cuando empieza el descanso (`isBreak`) o vuelve la concentración.
    func fileName(isBreak: Bool) -> String? {
        self == .system ? nil : "planaby-\(rawValue)-\(isBreak ? "break" : "focus").wav"
    }
}

/// Ajustes de «Avisos de concentración». Están en el App Group porque el aviso lo programa el
/// temporizador compartido.
enum AlertPreferences {
    enum Keys {
        static let style = "alertStyle"
        static let soundSet = "alertSoundSet"
        static let breakStart = "alertBreakStart"
        static let breakEnd = "alertBreakEnd"
        /// No sonar dentro de la app si ya suena música (Spotify u otra).
        static let respectMusic = "alertRespectMusic"
        /// Tarjeta de transición dentro de la app.
        static let overlay = "alertOverlay"
    }

    private static var defaults: UserDefaults { AppGroup.defaults }

    static var style: AlertStyle {
        defaults.string(forKey: Keys.style).flatMap(AlertStyle.init(rawValue:)) ?? .sound
    }

    static var soundSet: AlertSoundSet {
        defaults.string(forKey: Keys.soundSet).flatMap(AlertSoundSet.init(rawValue:)) ?? .soft
    }

    static var alertsBreakStart: Bool { defaults.object(forKey: Keys.breakStart) as? Bool ?? true }
    static var alertsBreakEnd: Bool { defaults.object(forKey: Keys.breakEnd) as? Bool ?? true }
    static var respectsMusic: Bool { defaults.object(forKey: Keys.respectMusic) as? Bool ?? true }
    static var showsOverlay: Bool { defaults.object(forKey: Keys.overlay) as? Bool ?? true }

    /// Si hay que avisar de este cambio (empieza un descanso o vuelve la concentración).
    static func alerts(intoBreak: Bool) -> Bool {
        intoBreak ? alertsBreakStart : alertsBreakEnd
    }
}

/// Lo que se está haciendo en la sesión, para retomar sin pensar: se escribe al empezar (opcional)
/// y se enseña al volver de un descanso o de una interrupción.
struct SessionContext: Codable, Equatable, Sendable {
    /// Inicio de la sesión a la que pertenece (si no coincide, está caducado).
    var sessionStart: Date
    var objective = ""
    var nextStep = ""
    var note = ""
    /// Lo que falta o lo que está pendiente de otra persona.
    var missing = ""

    var isEmpty: Bool {
        [objective, nextStep, note, missing].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static let key = "sessionContext"

    /// El contexto de la sesión que empezó en `start`, si hay.
    static func load(for start: Date?) -> SessionContext? {
        guard let start,
              let data = AppGroup.defaults.data(forKey: key),
              let context = try? JSONDecoder().decode(SessionContext.self, from: data),
              abs(context.sessionStart.timeIntervalSince(start)) < 1 else { return nil }
        return context
    }

    static func save(_ context: SessionContext?) {
        if let context, !context.isEmpty, let data = try? JSONEncoder().encode(context) {
            AppGroup.defaults.set(data, forKey: key)
        } else {
            AppGroup.defaults.removeObject(forKey: key)
        }
    }
}
