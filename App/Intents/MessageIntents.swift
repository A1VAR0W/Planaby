import AppIntents
import Foundation

/// Para la automatización de Atajos «Al recibir un mensaje»: lo clasifica con Apple Intelligence,
/// lo guarda en la bandeja de Planaby y avisa solo si merece la pena.
struct TriageMessageIntent: AppIntent {
    static let title: LocalizedStringResource = "Filtrar mensaje"
    static let description = IntentDescription(
        "Clasifica un mensaje como urgente, importante, puede esperar o ruido, lo guarda en la bandeja de Planaby y te avisa solo de lo urgente (y de lo importante si no te estás concentrando)."
    )

    @Parameter(title: "Mensaje")
    var message: String

    @Parameter(title: "Remitente")
    var sender: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let item = await MessageTriage.ingest(
            source: .messages, sender: sender ?? "", body: message, context: PlanabyStore.container.mainContext
        )
        return .result(value: item?.category.title ?? "")
    }
}

/// Para el disparador «Notificación» de Atajos (iOS 27): pasa por el filtro lo que llegue de
/// WhatsApp, Teams, Outlook, Gmail, Instagram o Mensajes. Todos los campos son opcionales porque
/// cada app rellena la notificación a su manera y puede venir recortada o vacía; Planaby guarda una
/// copia en su bandeja y nunca lee la app de origen.
struct FilterNotificationIntent: AppIntent {
    static let title: LocalizedStringResource = "Filtrar notificación"
    static let description = IntentDescription(
        "Clasifica una notificación (urgente, importante, puede esperar o irrelevante, y si espera respuesta) y la guarda en la bandeja de Planaby. Concentrándote solo verás lo importante de tus apps de trabajo; lo demás espera al descanso."
    )

    @Parameter(title: "App", description: "Nombre de la app que envió la notificación.")
    var appName: String?

    @Parameter(title: "Identificador de la app", description: "Por ejemplo, com.microsoft.skype.teams. Si no lo tienes, basta con el nombre.")
    var bundleID: String?

    @Parameter(title: "Remitente")
    var sender: String?

    @Parameter(title: "Título")
    var notificationTitle: String?

    @Parameter(title: "Subtítulo")
    var subtitle: String?

    @Parameter(title: "Texto")
    var text: String?

    @Parameter(title: "Fecha")
    var date: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Filtrar notificación de \(\.$appName)") {
            \.$notificationTitle
            \.$text
            \.$subtitle
            \.$sender
            \.$bundleID
            \.$date
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let payload = NotificationPayload(
            appName: appName, bundleID: bundleID, sender: sender, title: notificationTitle,
            subtitle: subtitle, body: text, date: date
        )
        let note = payload.normalized()
        // Una notificación sin texto ni título no da para clasificar nada.
        guard !(note.body.isEmpty && note.subject.isEmpty && note.sender.isEmpty) else {
            IntentLog.record(.filter, result: "Vacía: no se guardó")
            return .result(value: "")
        }
        let item = await MessageTriage.ingest(
            source: .notification, sender: note.sender, subject: note.subject, body: note.body,
            received: note.received, externalID: note.fingerprint, app: note.app,
            appName: note.app == .other ? note.appName : "", bundleID: bundleID ?? "",
            context: PlanabyStore.container.mainContext
        )
        let value = item.map { item in
            item.needsReply ? "\(item.category.title) · espera respuesta" : item.category.title
        } ?? "Repetida"
        IntentLog.record(.filter, result: "\(note.appName): \(value)")
        return .result(value: value)
    }
}

/// Para una automatización «Hora del día» (p. ej. cada hora): mira el correo por IMAP.
struct CheckMailIntent: AppIntent {
    static let title: LocalizedStringResource = "Comprobar correo"
    static let description = IntentDescription("Filtra los correos nuevos de la cuenta configurada en Planaby.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let added = await MailInbox.shared.check(context: PlanabyStore.container.mainContext)
        return .result(value: added)
    }
}
