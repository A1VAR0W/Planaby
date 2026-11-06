import Foundation
import FoundationModels
import SwiftData
import UserNotifications

@Generable(description: "Clasificación de un mensaje recibido")
struct MessageVerdict {
    @Guide(
        description: "urgent si pide actuar hoy o en pocas horas (una emergencia, algo que vence hoy, alguien esperando); important si es personal o de trabajo y relevante pero puede esperar a una pausa; later si es informativo o una conversación sin prisa; noise si es publicidad, boletín, aviso automático, código o spam",
        .anyOf(["urgent", "important", "later", "noise"])
    )
    var category: String
    @Guide(description: "Qué dice o qué pide, en una frase corta en español que empiece por el nombre de quien escribe si se sabe (p. ej. «Jonatan necesita que revises un documento»)")
    var summary: String
    @Guide(description: "true si quien escribe espera una respuesta tuya (una pregunta o una petición directa); false si es informativo, automático o no pide nada")
    var needsReply: Bool
}

/// Resultado del filtro: categoría, resumen y si espera respuesta (independiente de la categoría).
struct TriageResult: Equatable {
    var category: MessageCategory
    var summary: String
    var needsReply: Bool
}

/// Filtro de mensajes: Apple Intelligence (en el iPhone) decide si un mensaje o un correo es
/// urgente, importante, puede esperar o es ruido, y Planaby solo avisa de lo que merece la pena.
/// Los mensajes llegan con una automatización de Atajos; los correos, por IMAP.
@MainActor
enum MessageTriage {
    enum Keys {
        static let notifyLevel = "messageNotifyLevel"
        static let prioritySenders = "prioritySenders"
        static let overrides = "senderOverrides"
    }

    /// Remitentes prioritarios y lo aprendido de las correcciones a mano.
    static var rules: TriageRules {
        get {
            TriageRules(
                prioritySenders: UserDefaults.standard.stringArray(forKey: Keys.prioritySenders) ?? [],
                overrides: UserDefaults.standard.dictionary(forKey: Keys.overrides) as? [String: String] ?? [:]
            )
        }
        set {
            UserDefaults.standard.set(newValue.prioritySenders, forKey: Keys.prioritySenders)
            UserDefaults.standard.set(newValue.overrides, forKey: Keys.overrides)
        }
    }

    /// «Mover a…» en la bandeja: los siguientes mensajes de esa persona van ahí directamente.
    static func learn(_ item: MessageItem, category: MessageCategory) {
        item.category = category
        var current = rules
        current.learn(sender: item.sender, category: category)
        rules = current
    }

    /// Hasta qué categoría se avisa: 0 solo urgentes, 1 también importantes (no durante la concentración).
    static var notifyLevel: Int { UserDefaults.standard.object(forKey: Keys.notifyLevel) as? Int ?? 1 }

    /// Clasifica y guarda un mensaje. Devuelve nil si ya estaba (mismo `externalID`).
    @discardableResult
    static func ingest(
        source: MessageSource, sender: String, subject: String = "", body: String, received: Date = .now,
        externalID: String = "", app: CommApp? = nil, appName: String = "", bundleID: String = "",
        context: ModelContext
    ) async -> MessageItem? {
        if !externalID.isEmpty {
            let id = externalID
            let existing = (try? context.fetchCount(FetchDescriptor<MessageItem>(predicate: #Predicate { $0.externalID == id }))) ?? 0
            if existing > 0 { return nil }
        }
        let text = String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1_500))
        let app = app ?? (source == .mail ? .mail : .messages)
        let result = await classify(source: source, app: app, appName: appName, sender: sender, subject: subject, body: text)
        let item = MessageItem(
            received: received, source: source, sender: sender, subject: subject, body: text,
            category: result.category, summary: result.summary, externalID: externalID
        )
        item.appRaw = app.rawValue
        item.appName = appName
        item.bundleID = bundleID
        item.needsReply = result.needsReply
        context.insert(item)
        try? context.save()
        notify(item)
        CommsCenter.shared.refresh()
        return item
    }

    static func classify(
        source: MessageSource, app: CommApp? = nil, appName: String = "", sender: String, subject: String, body: String
    ) async -> TriageResult {
        let rules = Self.rules
        let fallbackSummary = String((subject.isEmpty ? body : subject).prefix(120))
        let heuristicReply = { (category: MessageCategory) in
            CommPolicy.needsReply(sender: sender, subject: subject, body: body, category: category)
        }
        // Lo que la persona ya decidió para este remitente manda sobre la IA.
        if let chosen = rules.override(for: sender) {
            return TriageResult(category: chosen, summary: fallbackSummary, needsReply: heuristicReply(chosen))
        }
        let channel = app.map { $0 == .other && !appName.isEmpty ? appName : $0.title } ?? source.title
        let isWork = app.map { CommsCenter.shared.settings.isWork($0) } ?? false
        if AIProvider.isAvailable {
            let session = AIProvider.session(instructions: """
                Eres el filtro de mensajes de Planaby, una app de concentración. Decides si un mensaje merece \
                interrumpir a la persona. Sé exigente: casi nada es urgente. La palabra «urgente» sola no basta: \
                tiene que haber un motivo concreto o un plazo de horas. Escribe en español.
                """)
            let prompt = """
                Ahora: \(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))
                Canal: \(channel)\(isWork ? " (trabajo)" : "")
                Remitente prioritario: \(rules.isPriority(sender) ? "sí" : "no")
                Mensaje:
                \(AIProvider.wrap("De: \(sender.isEmpty ? "desconocido" : sender)\n\(subject.isEmpty ? "" : "Asunto: \(subject)\n")Texto: \(body.isEmpty ? "(vacío)" : body)", limit: 1_400))
                """
            if let response = try? await session.respond(to: prompt, generating: MessageVerdict.self, options: GenerationOptions(temperature: 0.1)),
               let category = MessageCategory(rawValue: response.content.category) {
                let adjusted = rules.adjust(category, sender: sender, text: "\(subject) \(body)")
                // Lo automático nunca espera respuesta, diga lo que diga la IA.
                let reply = adjusted != .noise && response.content.needsReply
                return TriageResult(category: adjusted, summary: response.content.summary, needsReply: reply)
            }
        }
        let category = rules.heuristic(fromMessages: source != .mail, sender: sender, subject: subject, body: body)
        return TriageResult(category: category, summary: fallbackSummary, needsReply: heuristicReply(category))
    }

    // MARK: Avisos

    private static func notify(_ item: MessageItem) {
        let center = CommsCenter.shared
        let focusing = center.phase == .focus
        // Concentrándose, lo personal se guarda para el descanso salvo las excepciones elegidas.
        if focusing, !CommPolicy.showsDuringFocus(item.entry(rules: rules), settings: center.settings, now: .now) { return }
        let shouldNotify = switch item.category {
        case .urgent: true
        case .important: notifyLevel >= 1 && !focusing && item.source != .notification
        case .later, .noise: false
        }
        // Lo que llega de una notificación ya lo ha avisado su app: Planaby solo repite lo urgente.
        guard shouldNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(item.category.title): \(item.sender.isEmpty ? item.appTitle : item.sender)"
        content.body = item.summary.isEmpty ? item.subject : item.summary
        content.sound = item.category == .urgent ? .default : nil
        content.threadIdentifier = "messages"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "message-\(UUID().uuidString)", content: content, trigger: nil))
    }

    /// Al terminar una sesión: resumen de lo que llegó mientras tanto.
    static func summarize(since start: Date, context: ModelContext) {
        let items = ((try? context.fetch(FetchDescriptor<MessageItem>(predicate: #Predicate { $0.received >= start }))) ?? [])
            .filter { !$0.isRead }
        guard !items.isEmpty else { return }
        let counts = Dictionary(grouping: items, by: \.category).mapValues(\.count)
        let parts = MessageCategory.allCases.compactMap { category -> String? in
            guard let count = counts[category], category != .noise else { return nil }
            let name = switch category {
            case .urgent: count == 1 ? "urgente" : "urgentes"
            case .important: count == 1 ? "importante" : "importantes"
            case .later, .noise: count == 1 ? "que puede esperar" : "que pueden esperar"
            }
            return "\(count) \(name)"
        }
        guard !parts.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = "Mientras te concentrabas"
        content.body = parts.joined(separator: ", ") + ". Están en la bandeja de Enfoque."
        content.threadIdentifier = "messages"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "message-summary", content: content, trigger: nil))
    }
}
