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
        case .noise: "Ruido"
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
    case messages, mail

    var title: String {
        switch self {
        case .messages: "Mensajes"
        case .mail: "Correo"
        }
    }

    var symbol: String {
        switch self {
        case .messages: "message.fill"
        case .mail: "envelope.fill"
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
    /// Para no repetir correos (cuenta y UID).
    var externalID: String = ""

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
    var category: MessageCategory {
        get { MessageCategory(rawValue: categoryRaw) ?? .later }
        set { categoryRaw = newValue.rawValue }
    }
}
