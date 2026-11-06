import Foundation

/// Lo fuerte que frena Planaby al abrir una app que distrae.
enum FrictionIntensity: String, CaseIterable, Identifiable, Codable, Sendable {
    case soft, balanced, strict

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soft: "Suave"
        case .balanced: "Equilibrado"
        case .strict: "Estricto"
        }
    }

    var detail: String {
        switch self {
        case .soft: "Una pausa corta y pases largos. Para recordarte, no para impedir."
        case .balanced: "Respiras unos segundos y decides. Si insistes, la pausa crece."
        case .strict: "Pausa larga, pases cortos y hay que decir para qué la abres."
        }
    }

    /// Segundos de la primera pausa.
    var baseSeconds: Int {
        switch self {
        case .soft: 5
        case .balanced: 10
        case .strict: 20
        }
    }

    /// Minutos del pase de «Abrir igualmente».
    var passMinutes: Int {
        switch self {
        case .soft: 10
        case .balanced: 5
        case .strict: 3
        }
    }

    /// Segundos que se suman por cada intento repetido en la última media hora.
    var escalationStep: Int {
        switch self {
        case .soft: 0
        case .balanced: 5
        case .strict: 10
        }
    }

    var asksMotive: Bool { self == .strict }
}

/// Ajustes propios de una app (si no hay, manda la intensidad general).
struct FrictionRule: Codable, Equatable, Identifiable, Sendable {
    /// Clave de la app, como `PassBook.key(for:)`.
    var app: String
    /// Minutos del pase; nil = los de la intensidad.
    var passMinutes: Int?
    /// Aperturas al día sin pausa fuera de la concentración (0 = ninguna).
    var freeOpensPerDay = 0

    var id: String { app }
}

/// Decide si toca pausa y cómo de larga. Lógica pura para poder probarla.
struct FrictionPolicy {
    var intensity: FrictionIntensity
    var rules: [FrictionRule] = []
    var calendar: Calendar = .current

    struct Decision: Equatable, Sendable {
        var pause: Bool
        var seconds: Int
        var passMinutes: Int
        /// Intentos con esta app en la última media hora (sin contar este).
        var recentAttempts: Int
        var asksMotive: Bool
        /// Por qué no se frena (pase, apertura libre…), para la respuesta del atajo.
        var skipReason: String?
    }

    func rule(for app: String) -> FrictionRule? {
        let key = PassBook.key(for: app)
        return rules.first { $0.app == key }
    }

    /// - Parameters:
    ///   - inScope: según «Cuándo frena», ahora tocaría frenar.
    ///   - focusing: hay una concentración en marcha.
    ///   - onBreak: la sesión está en un descanso (se frena con más suavidad).
    ///   - history: intentos anteriores (de pausa consciente).
    func decide(
        app: String, inScope: Bool, focusing: Bool, onBreak: Bool,
        passes: PassBook, history: [AttemptSample], now: Date
    ) -> Decision {
        let rule = rule(for: app)
        let pass = rule?.passMinutes ?? intensity.passMinutes
        let key = PassBook.key(for: app)
        let sameApp = history.filter { $0.kind == .pause && PassBook.key(for: $0.app) == key && $0.date <= now }
        let recent = sameApp.filter { now.timeIntervalSince($0.date) < 30 * 60 }.count
        var decision = Decision(
            pause: false, seconds: 0, passMinutes: pass, recentAttempts: recent,
            asksMotive: intensity.asksMotive, skipReason: nil
        )
        guard inScope else { decision.skipReason = "fuera de horario"; return decision }
        guard !passes.hasPass(for: app, now: now) else { decision.skipReason = "pase"; return decision }

        // Aperturas libres: solo fuera de la concentración y con nombre de app conocido.
        if !focusing, key != PassBook.unknownKey, let free = rule?.freeOpensPerDay, free > 0 {
            let openedToday = sameApp.filter { !$0.resisted && calendar.isDate($0.date, inSameDayAs: now) }.count
            if openedToday < free {
                decision.skipReason = "apertura libre"
                return decision
            }
        }

        var seconds = intensity.baseSeconds + min(4, recent) * intensity.escalationStep
        if onBreak { seconds = max(3, seconds / 2) }
        decision.pause = true
        decision.seconds = min(60, seconds)
        decision.asksMotive = intensity.asksMotive && !onBreak
        return decision
    }
}
