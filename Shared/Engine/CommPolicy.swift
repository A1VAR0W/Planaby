import Foundation

/// Qué apps son de trabajo y qué se deja pasar durante la concentración. Se guarda en el App
/// Group para que la app y los widgets cuenten lo mismo.
struct CommSettings: Codable, Equatable, Sendable {
    /// Apps cuyas comunicaciones importantes se ven durante la concentración.
    var workApps: Set<CommApp> = CommApp.defaultWork
    /// Apps personales que, por excepción, también se ven concentrándose.
    var focusExceptions: Set<CommApp> = []
    /// Lo urgente de un remitente prioritario pasa aunque venga de una app personal.
    var priorityUrgentBypass = true

    func isWork(_ app: CommApp) -> Bool { workApps.contains(app) }

    private static let key = "commSettings"

    static func load(from defaults: UserDefaults = AppGroup.defaults) -> CommSettings {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(CommSettings.self, from: $0) } ?? CommSettings()
    }

    func save(to defaults: UserDefaults = AppGroup.defaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}

/// Momento de la sesión que decide qué se enseña.
enum CommPhase: String, Sendable {
    case focus, rest, idle
}

/// Lo que la política necesita de cada comunicación (sin SwiftData, para probarlo aparte).
struct CommEntry: Equatable, Sendable, Identifiable {
    var id: String
    var app: CommApp
    var appName: String
    var sender: String
    var summary: String
    var category: MessageCategory
    var needsReply: Bool
    var received: Date
    var isPriority = false
    var reviewed = false
    var replied = false
    var snoozedUntil: Date?
    var presentedAt: Date?

    var isOpen: Bool { !reviewed && !replied }
    func isSnoozed(at now: Date) -> Bool { (snoozedUntil ?? .distantPast) > now }
}

enum CommPolicy {
    /// Merece la pena tenerlo pendiente: lo urgente, lo importante y lo que espera respuesta.
    static func isRelevant(_ entry: CommEntry) -> Bool {
        switch entry.category {
        case .urgent, .important: true
        case .later: entry.needsReply
        case .noise: false
        }
    }

    /// Pendiente ahora: abierto, relevante y sin posponer.
    static func isPending(_ entry: CommEntry, now: Date) -> Bool {
        entry.isOpen && isRelevant(entry) && !entry.isSnoozed(at: now)
    }

    /// Durante la concentración solo se ve lo importante de trabajo (o una excepción explícita).
    static func showsDuringFocus(_ entry: CommEntry, settings: CommSettings, now: Date) -> Bool {
        guard isPending(entry, now: now), entry.category == .urgent || entry.category == .important else { return false }
        if settings.isWork(entry.app) || settings.focusExceptions.contains(entry.app) { return true }
        return settings.priorityUrgentBypass && entry.isPriority && entry.category == .urgent
    }

    /// Lo que se enseña en cada momento, lo más urgente y reciente primero.
    static func visible(_ entries: [CommEntry], phase: CommPhase, settings: CommSettings, now: Date) -> [CommEntry] {
        entries
            .filter { phase == .focus ? showsDuringFocus($0, settings: settings, now: now) : isPending($0, now: now) }
            .sorted(by: order)
    }

    /// Lo personal que se guarda para el descanso.
    static func heldForBreak(_ entries: [CommEntry], settings: CommSettings, now: Date) -> [CommEntry] {
        entries.filter { isPending($0, now: now) && !showsDuringFocus($0, settings: settings, now: now) }
    }

    /// Recuento por app para «Mientras te concentrabas…», de más a menos.
    static func breakdown(_ entries: [CommEntry]) -> [(app: String, count: Int)] {
        Dictionary(grouping: entries, by: \.appName)
            .map { (app: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.app < $1.app }
    }

    /// Lo nuevo que aún no se ha enseñado al volver a Planaby. Solo se basa en fechas de llegada y
    /// en lo ya presentado: iOS no dice si el iPhone estuvo bloqueado.
    static func awayDigest(
        _ entries: [CommEntry], lastPresented: Date?, phase: CommPhase, settings: CommSettings, now: Date
    ) -> [CommEntry] {
        let since = lastPresented ?? .distantPast
        return visible(entries, phase: phase, settings: settings, now: now)
            .filter { $0.presentedAt == nil && $0.received > since }
    }

    /// «Teams — Jonatan necesita revisar un documento.»
    static func line(_ entry: CommEntry) -> String {
        var text = entry.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { text = entry.needsReply ? "espera respuesta" : "mensaje nuevo" }
        let who = entry.sender.trimmingCharacters(in: .whitespacesAndNewlines)
        // Si el resumen no nombra a quien escribe, se añade delante.
        let firstName = who.split(separator: " ").first.map { String($0).lowercased() } ?? ""
        if !firstName.isEmpty, !text.lowercased().contains(firstName) {
            text = "\(who): \(text)"
        }
        if let last = text.last, !".!?…".contains(last) { text += "." }
        return "\(entry.appName) — \(text)"
    }

    /// Lo más urgente y lo más reciente primero.
    static func order(_ a: CommEntry, _ b: CommEntry) -> Bool {
        func rank(_ category: MessageCategory) -> Int {
            switch category {
            case .urgent: 0
            case .important: 1
            case .later: 2
            case .noise: 3
            }
        }
        if rank(a.category) != rank(b.category) { return rank(a.category) < rank(b.category) }
        return a.received > b.received
    }

    // MARK: Necesita respuesta

    /// Sin IA: ¿espera que contestes? Preguntas directas y peticiones; nunca lo automático.
    static func needsReply(sender: String, subject: String, body: String, category: MessageCategory) -> Bool {
        guard category != .noise else { return false }
        let text = "\(subject) \(body)".lowercased()
        let automatic = ["noreply", "no-reply", "no responder", "do not reply", "newsletter", "unsubscribe"]
        if automatic.contains(where: { text.contains($0) || sender.lowercased().contains($0) }) { return false }
        if text.contains("?") || text.contains("¿") { return true }
        let asks = [
            "puedes", "podrías", "podrias", "me dices", "dime", "avísame", "avisame", "confirma", "confírmame",
            "responde", "contesta", "me pasas", "necesito que", "qué te parece", "que te parece", "cuándo",
            "revisa", "revisar", "échale un ojo", "me ayudas", "llámame", "llamame",
            "can you", "could you", "let me know", "please reply", "please confirm",
        ]
        return asks.contains { text.contains($0) }
    }
}

/// Recuento sin textos que se comparte con widgets, Live Activity y StandBy. Nunca lleva el
/// cuerpo de los mensajes: puede verse con el iPhone bloqueado.
struct CommsSnapshot: Codable, Equatable, Sendable {
    var updated: Date
    /// Lo que se vería concentrándose (trabajo importante y excepciones).
    var focusVisible: Int
    /// Todo lo pendiente.
    var pending: Int
    var urgent: Int
    /// Nombre de la app → pendientes.
    var byApp: [String: Int]

    static let empty = CommsSnapshot(updated: .distantPast, focusVisible: 0, pending: 0, urgent: 0, byApp: [:])

    static func make(_ entries: [CommEntry], settings: CommSettings, now: Date) -> CommsSnapshot {
        let pending = entries.filter { CommPolicy.isPending($0, now: now) }
        return CommsSnapshot(
            updated: now,
            focusVisible: CommPolicy.visible(entries, phase: .focus, settings: settings, now: now).count,
            pending: pending.count,
            urgent: pending.filter { $0.category == .urgent }.count,
            byApp: Dictionary(grouping: pending, by: \.appName).mapValues(\.count)
        )
    }

    /// Texto corto para cada momento; nil si no hay nada que decir.
    func text(for phase: CommPhase) -> String? {
        switch phase {
        case .focus:
            guard focusVisible > 0 else { return nil }
            return focusVisible == 1 ? "1 comunicación laboral importante" : "\(focusVisible) comunicaciones laborales importantes"
        case .rest:
            guard pending > 0 else { return nil }
            return "Mientras trabajabas: \(pending) \(pending == 1 ? "pendiente" : "pendientes")"
        case .idle:
            guard pending > 0 else { return nil }
            return pending == 1 ? "1 pendiente" : "\(pending) pendientes"
        }
    }

    /// Número que se enseña en cada momento.
    func count(for phase: CommPhase) -> Int { phase == .focus ? focusVisible : pending }

    private static let key = "commsSnapshot"

    static func load(from defaults: UserDefaults = AppGroup.defaults) -> CommsSnapshot {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(CommsSnapshot.self, from: $0) } ?? .empty
    }

    func save(to defaults: UserDefaults = AppGroup.defaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}
