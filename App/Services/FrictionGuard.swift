import Foundation
import Observation
import SwiftData

/// Cuándo frena Planaby al abrir una app que distrae.
enum FrictionScope: String, CaseIterable, Identifiable {
    case focus, workHours, always

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: "Solo concentrándome"
        case .workHours: "También en horario de Trabajo"
        case .always: "Siempre"
        }
    }
}

/// Bloqueo con fricción sin Family Controls: una automatización de Atajos («al abrir Instagram…»)
/// pregunta a Planaby si toca frenar y, si es así, abre la pausa consciente. Tras respirar, se
/// puede volver a lo suyo o abrirla igualmente con un pase de unos minutos.
@Observable
@MainActor
final class FrictionGuard {
    static let shared = FrictionGuard()

    struct Request: Identifiable {
        let id = UUID()
        let app: String
    }

    enum Keys {
        static let scope = "frictionScope"
        static let pauseSeconds = "frictionPauseSeconds"
        static let passMinutes = "frictionPassMinutes"
        static let passes = "frictionPasses"
    }

    static let defaultPauseSeconds = 10
    static let defaultPassMinutes = 5

    /// Pausa consciente que hay que enseñar.
    var request: Request?

    private init() {}

    static var scope: FrictionScope {
        UserDefaults.standard.string(forKey: Keys.scope).flatMap { FrictionScope(rawValue: $0) } ?? .focus
    }

    static var pauseSeconds: Int {
        UserDefaults.standard.object(forKey: Keys.pauseSeconds) as? Int ?? defaultPauseSeconds
    }

    static var passMinutes: Int {
        UserDefaults.standard.object(forKey: Keys.passMinutes) as? Int ?? defaultPassMinutes
    }

    /// Hay una sesión en marcha, en fase de concentración y sin pausar.
    var isFocusing: Bool {
        guard let state = FocusTimer.shared.state else { return false }
        return state.phase == .focus && !state.isPaused
    }

    /// Lo que responde la acción «¿Toca pausa consciente?».
    func shouldPause(app: String, now: Date = .now) -> Bool {
        if hasPass(for: app, now: now) { return false }
        switch Self.scope {
        case .focus: return isFocusing
        case .workHours: return isFocusing || isWorkTime(now)
        case .always: return true
        }
    }

    func present(app: String) {
        request = Request(app: app.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Guarda cómo acabó la pausa; si la abre igualmente, no se le vuelve a frenar durante el pase.
    func finish(_ request: Request, reason: String, resisted: Bool, context: ModelContext) {
        context.insert(DistractionRecord(
            app: request.app, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
            resisted: resisted, duringFocus: isFocusing
        ))
        try? context.save()
        if !resisted { grantPass(for: request.app) }
        self.request = nil
    }

    // MARK: Pases

    private func key(for app: String) -> String {
        let name = app.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return name.isEmpty ? "*" : name
    }

    private var passes: [String: Date] {
        get {
            let stored = UserDefaults.standard.dictionary(forKey: Keys.passes) as? [String: Date] ?? [:]
            return stored.filter { $0.value > .now }
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.passes) }
    }

    private func hasPass(for app: String, now: Date) -> Bool {
        let current = passes
        return (current[key(for: app)] ?? .distantPast) > now || (current["*"] ?? .distantPast) > now
    }

    private func grantPass(for app: String) {
        var current = passes
        current[key(for: app)] = Date.now.addingTimeInterval(TimeInterval(Self.passMinutes * 60))
        passes = current
    }

    // MARK: Ayudas

    private func isWorkTime(_ now: Date) -> Bool {
        let rules = ModeController.shared.availability(for: .work)
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        guard rules.weekdays.contains(weekday) else { return false }
        let hours = rules.hours(onWeekday: weekday)
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        return minute >= hours.startMinute && minute < hours.endMinute
    }

    /// Enlace para abrir apps habituales al pulsar «Abrir igualmente».
    static func url(for app: String) -> URL? {
        let name = app.lowercased().replacingOccurrences(of: " ", with: "")
        let schemes: [String: String] = [
            "instagram": "instagram://", "tiktok": "snssdk1233://", "youtube": "youtube://",
            "x": "twitter://", "twitter": "twitter://", "facebook": "fb://", "whatsapp": "whatsapp://",
            "telegram": "tg://", "reddit": "reddit://", "twitch": "twitch://", "netflix": "nflx://",
            "spotify": "spotify://", "linkedin": "linkedin://", "pinterest": "pinterest://",
            "snapchat": "snapchat://", "threads": "barcelona://", "discord": "discord://",
        ]
        return schemes[name].flatMap(URL.init(string:))
    }
}
