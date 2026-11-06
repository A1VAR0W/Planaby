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
        /// Segundos de pausa (crecen si se insiste).
        var seconds = 10
        var passMinutes = 5
        /// Intentos con esta app en la última media hora.
        var recentAttempts = 0
        var asksMotive = false
        var onBreak = false
    }

    enum Keys {
        /// Interruptor general «Bloquear apps».
        static let enabled = "frictionEnabled"
        static let scope = "frictionScope"
        static let pauseSeconds = "frictionPauseSeconds"
        static let passMinutes = "frictionPassMinutes"
        static let passes = "frictionPasses"
        /// Apps elegidas en Planaby (rawValue de BlockableApp separados por comas).
        static let apps = "frictionApps"
        /// Última vez que la automatización avisó a Planaby (segundos desde 1970).
        static let lastTrigger = "frictionLastTrigger"
        static let intensity = "frictionIntensity"
        /// [FrictionRule] en JSON.
        static let rules = "frictionRules"
    }

    static let defaultPauseSeconds = 10
    static let defaultPassMinutes = 5

    /// Pausa consciente que hay que enseñar.
    var request: Request?

    private init() {}

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? true
    }

    static var scope: FrictionScope {
        UserDefaults.standard.string(forKey: Keys.scope).flatMap { FrictionScope(rawValue: $0) } ?? .focus
    }

    static var intensity: FrictionIntensity {
        UserDefaults.standard.string(forKey: Keys.intensity).flatMap(FrictionIntensity.init(rawValue:)) ?? .balanced
    }

    static var rules: [FrictionRule] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Keys.rules) else { return [] }
            return (try? JSONDecoder().decode([FrictionRule].self, from: data)) ?? []
        }
        set {
            let clean = newValue.filter { $0.passMinutes != nil || $0.freeOpensPerDay > 0 }
            UserDefaults.standard.set(try? JSONEncoder().encode(clean), forKey: Keys.rules)
        }
    }

    /// Minutos del pase para una app (su regla o los de la intensidad).
    static func passMinutes(for app: String) -> Int {
        FrictionPolicy(intensity: intensity, rules: rules).rule(for: app)?.passMinutes ?? intensity.passMinutes
    }

    /// Las apps elegidas en Ajustes › Bloqueo con fricción.
    static var chosenApps: [BlockableApp] {
        (UserDefaults.standard.string(forKey: Keys.apps) ?? "")
            .split(separator: ",")
            .compactMap { BlockableApp(rawValue: String($0)) }
    }

    /// La automatización ha llamado a Planaby: así Ajustes sabe que está bien hecha.
    func noteTrigger() {
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: Keys.lastTrigger)
    }

    /// Con «la app que se abre» y una sola app elegida, se sabe cuál es.
    func resolvedName(_ name: String) -> String {
        guard name.isEmpty else { return name }
        let chosen = Self.chosenApps
        return chosen.count == 1 ? chosen[0].name : ""
    }

    /// Hay una sesión en marcha, en fase de concentración y sin pausar.
    var isFocusing: Bool {
        guard let state = FocusTimer.shared.state else { return false }
        return state.phase == .focus && !state.isPaused
    }

    private var isOnBreak: Bool {
        guard let state = FocusTimer.shared.state else { return false }
        return state.phase != .focus && !state.isPaused
    }

    /// Lo que decide la política para esta app ahora mismo.
    func decision(app: String, now: Date = .now) -> FrictionPolicy.Decision {
        let inScope: Bool = switch Self.scope {
        case .focus: isFocusing
        case .workHours: isFocusing || isWorkTime(now)
        case .always: true
        }
        let policy = FrictionPolicy(intensity: Self.intensity, rules: Self.rules)
        return policy.decide(
            app: app, inScope: Self.isEnabled && inScope, focusing: isFocusing, onBreak: isOnBreak,
            passes: passBook, history: recentAttempts(now: now), now: now
        )
    }

    /// Lo que responde la acción «¿Toca pausa consciente?». Una apertura libre queda apuntada.
    func shouldPause(app: String, now: Date = .now) -> Bool {
        let result = decision(app: app, now: now)
        if result.skipReason == "apertura libre" {
            let context = PlanabyStore.container.mainContext
            context.insert(DistractionRecord(app: app, reason: "Apertura libre", resisted: false, duringFocus: false))
            try? context.save()
        }
        return result.pause
    }

    func present(app: String) {
        let name = app.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = decision(app: name)
        request = Request(
            app: name, seconds: max(3, result.seconds == 0 ? Self.intensity.baseSeconds : result.seconds),
            passMinutes: result.passMinutes, recentAttempts: result.recentAttempts,
            asksMotive: result.asksMotive, onBreak: isOnBreak
        )
    }

    /// Guarda cómo acabó la pausa; si la abre igualmente, solo esa app tiene pase durante unos minutos.
    /// - Parameter openedApp: la app que se abre (en un aviso sin nombre, la que se eligió).
    func finish(
        _ request: Request, openedApp: String? = nil, reason: String, motive: DistractionMotive?,
        resisted: Bool, context: ModelContext
    ) {
        let app = openedApp ?? request.app
        context.insert(DistractionRecord(
            app: app, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
            resisted: resisted, duringFocus: isFocusing, kind: .pause, motive: motive
        ))
        try? context.save()
        if !resisted {
            var book = passBook
            book.grant(app: app, fromUnknownTrigger: request.app.isEmpty, minutes: request.passMinutes, now: .now)
            passBook = book
        }
        self.request = nil
    }

    // MARK: Pases

    /// Se guardan como [clave: fin] (mismo formato que antes, así los pases en curso siguen valiendo).
    var passBook: PassBook {
        get {
            let stored = UserDefaults.standard.dictionary(forKey: Keys.passes) as? [String: Date] ?? [:]
            var book = PassBook()
            for (key, end) in stored where end > .now {
                book.setEnd(end, forKey: key)
            }
            return book
        }
        set {
            var book = newValue
            book.prune(now: .now)
            UserDefaults.standard.set(book.passes, forKey: Keys.passes)
        }
    }

    /// Intentos de pausa consciente de las últimas 24 h, para la escalada y las aperturas libres.
    private func recentAttempts(now: Date) -> [AttemptSample] {
        let since = now.addingTimeInterval(-24 * 3600)
        let descriptor = FetchDescriptor<DistractionRecord>(predicate: #Predicate { $0.date >= since })
        let records = (try? PlanabyStore.container.mainContext.fetch(descriptor)) ?? []
        return records.map(\.sample)
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
