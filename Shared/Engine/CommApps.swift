import Foundation

/// Apps de comunicación que Planaby reconoce. El resto entra como `.other` con su nombre.
enum CommApp: String, CaseIterable, Identifiable, Codable, Sendable {
    case whatsapp, instagram, teams, outlook, gmail, messages, mail, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whatsapp: "WhatsApp"
        case .instagram: "Instagram"
        case .teams: "Teams"
        case .outlook: "Outlook"
        case .gmail: "Gmail"
        case .messages: "Mensajes"
        case .mail: "Correo"
        case .other: "Otra app"
        }
    }

    var symbol: String {
        switch self {
        case .whatsapp: "phone.bubble.fill"
        case .instagram: "camera.fill"
        case .teams: "person.3.fill"
        case .outlook, .mail: "envelope.fill"
        case .gmail: "envelope.badge.fill"
        case .messages: "message.fill"
        case .other: "app.badge.fill"
        }
    }

    /// Identificadores conocidos (la app oficial y alguna variante).
    var bundleIDs: [String] {
        switch self {
        case .whatsapp: ["net.whatsapp.WhatsApp", "net.whatsapp.WhatsAppSMB"]
        case .instagram: ["com.burbn.instagram"]
        case .teams: ["com.microsoft.skype.teams"]
        case .outlook: ["com.microsoft.Office.Outlook"]
        case .gmail: ["com.google.Gmail"]
        case .messages: ["com.apple.MobileSMS"]
        case .mail: ["com.apple.mobilemail"]
        case .other: []
        }
    }

    /// Esquema oficial para abrir la app (solo la abre; no lleva a un mensaje concreto).
    var openURL: URL? {
        let scheme: String? = switch self {
        case .whatsapp: "whatsapp://"
        case .instagram: "instagram://"
        case .teams: "msteams://"
        case .outlook: "ms-outlook://"
        case .gmail: "googlegmail://"
        case .messages: "sms:"
        case .mail: "message://"
        case .other: nil
        }
        return scheme.flatMap(URL.init(string:))
    }

    /// Las que cuentan como trabajo si no se cambia en Ajustes.
    static let defaultWork: Set<CommApp> = [.teams, .outlook]

    /// Reconoce la app por su identificador o, si no llega, por el nombre que manda Atajos.
    static func identify(bundleID: String?, appName: String?) -> CommApp {
        let bundle = (bundleID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !bundle.isEmpty, let match = allCases.first(where: { app in app.bundleIDs.contains { $0.lowercased() == bundle } }) {
            return match
        }
        let name = (appName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else { return .other }
        let aliases: [(String, CommApp)] = [
            ("whatsapp", .whatsapp), ("instagram", .instagram), ("teams", .teams), ("outlook", .outlook),
            ("gmail", .gmail), ("mensajes", .messages), ("messages", .messages), ("imessage", .messages),
            ("sms", .messages), ("mail", .mail), ("correo", .mail),
        ]
        return aliases.first { name.contains($0.0) }?.1 ?? .other
    }
}

/// Lo que llega del disparador «Notificación» de Atajos (iOS 27). Ningún campo está garantizado:
/// cada app decide qué pone en el título, el subtítulo y el texto, y el aviso puede venir recortado.
struct NotificationPayload: Equatable, Sendable {
    var appName: String?
    var bundleID: String?
    var sender: String?
    var title: String?
    var subtitle: String?
    var body: String?
    var date: Date?

    /// Datos listos para el filtro: en WhatsApp, Teams o Mensajes el título suele ser el remitente;
    /// en el correo, el subtítulo suele ser el asunto.
    struct Normalized: Equatable, Sendable {
        var app: CommApp
        var appName: String
        var sender: String
        var subject: String
        var body: String
        var received: Date
        /// Para no guardar dos veces el mismo aviso si el atajo se ejecuta de nuevo.
        var fingerprint: String
    }

    func normalized(now: Date = .now) -> Normalized {
        func clean(_ text: String?) -> String { (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        let app = CommApp.identify(bundleID: bundleID, appName: appName)
        let title = clean(title), subtitle = clean(subtitle), text = clean(body)
        var sender = clean(sender)
        var subject = subtitle
        if sender.isEmpty {
            sender = title
        } else if subject.isEmpty, title != sender {
            subject = title
        }
        let received = date ?? now
        let minute = Int(received.timeIntervalSince1970 / 60)
        let key = [clean(bundleID).isEmpty ? app.rawValue : clean(bundleID).lowercased(), sender, subject, String(text.prefix(80)), String(minute)]
            .joined(separator: "|")
        return Normalized(
            app: app, appName: app == .other ? (clean(appName).isEmpty ? "Notificación" : clean(appName)) : app.title,
            sender: sender, subject: subject, body: text, received: received,
            fingerprint: "notif:" + String(key.hashValueStable, radix: 36)
        )
    }
}

extension String {
    /// Hash estable entre ejecuciones (el de Swift cambia en cada arranque).
    var hashValueStable: UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
