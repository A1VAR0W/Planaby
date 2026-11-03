import AppIntents

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
