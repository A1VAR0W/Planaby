import Foundation
import SwiftData

/// Cómo de importante es un mensaje según la IA.
enum MessageCategory: String, CaseIterable, Identifiable, Sendable {
    case urgent, important, later, noise

    var id: String { rawValue }

    var title: String {
        switch self {
        case .urgent: "Urgente"
        case .important: "Importante"
        case .later: "Puede esperar"
        case .noise: "Irrelevante"
        }
    }

    var symbol: String {
        switch self {
        case .urgent: "exclamationmark.circle.fill"
        case .important: "star.fill"
        case .later: "clock"
        case .noise: "speaker.slash"
        }
    }
}

enum MessageSource: String, Sendable {
    /// `notification`: llegó por el disparador «Notificación» de Atajos (iOS 27).
    case messages, mail, notification

    var title: String {
        switch self {
        case .messages: "Mensajes"
        case .mail: "Correo"
        case .notification: "Notificación"
        }
    }

    var symbol: String {
        switch self {
        case .messages: "message.fill"
        case .mail: "envelope.fill"
        case .notification: "bell.badge.fill"
        }
    }
}

/// Mensaje o correo que ha pasado por el filtro. Es una copia: el original sigue en su app.
@Model
final class MessageItem {
    var received: Date
    var sourceRaw: String
    var sender: String
    var subject: String
    var body: String
    var categoryRaw: String
    var summary: String
    var isRead: Bool = false
    /// Para no repetir correos (cuenta y UID) ni avisos (huella de la notificación).
    var externalID: String = ""
    // Lo siguiente tiene valor por defecto para que los datos de versiones anteriores se lean sin migrar.
    /// App de origen (`CommApp`); vacío en los mensajes antiguos.
    var appRaw: String = ""
    /// Nombre que llegó de Atajos, para las apps que Planaby no conoce.
    var appName: String = ""
    var bundleID: String = ""
    /// Espera que contestes (independiente de la categoría).
    var needsReply: Bool = false
    /// Revisado en la bandeja (además de `isRead`, que se mantiene por compatibilidad).
    var reviewedAt: Date?
    /// Marcado a mano como respondido (Planaby no puede saber si contestaste en la otra app).
    var repliedAt: Date?
    var snoozedUntil: Date?
    /// Cuándo se enseñó en «Mientras estabas fuera», para no repetirlo.
    var presentedAt: Date?
    var addedToPlanAt: Date?

    init(
        received: Date, source: MessageSource, sender: String, subject: String, body: String,
        category: MessageCategory, summary: String, externalID: String = ""
    ) {
        self.received = received
        sourceRaw = source.rawValue
        self.sender = sender
        self.subject = subject
        self.body = body
        categoryRaw = category.rawValue
        self.summary = summary
        self.externalID = externalID
    }

    var source: MessageSource { MessageSource(rawValue: sourceRaw) ?? .messages }

    var app: CommApp {
        if let app = CommApp(rawValue: appRaw) { return app }
        return source == .mail ? .mail : .messages
    }

    /// Nombre corto de la app para las listas.
    var appTitle: String { app == .other && !appName.isEmpty ? appName : app.title }

    var isOpen: Bool { !isRead && repliedAt == nil }

    func entry(rules: TriageRules) -> CommEntry {
        CommEntry(
            id: String(describing: persistentModelID.hashValue), app: app, appName: appTitle, sender: sender,
            summary: summary.isEmpty ? subject : summary, category: category, needsReply: needsReply, received: received,
            isPriority: rules.isPriority(sender), reviewed: isRead, replied: repliedAt != nil,
            snoozedUntil: snoozedUntil, presentedAt: presentedAt
        )
    }
    var category: MessageCategory {
        get { MessageCategory(rawValue: categoryRaw) ?? .later }
        set { categoryRaw = newValue.rawValue }
    }
}
