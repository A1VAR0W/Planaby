import AppIntents

/// Para la automatización de Atajos «Al abrir una app»: responde si Planaby debe frenarte
/// (estás concentrándote o en horario de Trabajo, según Ajustes, y no tienes un pase).
struct ShouldPauseIntent: AppIntent {
    static let title: LocalizedStringResource = "¿Toca pausa consciente?"
    static let description = IntentDescription(
        "Devuelve Sí si Planaby debe frenarte antes de usar esta app. Úsalo con «Si» y «Pausa consciente» en una automatización «Al abrir una app»."
    )

    @Parameter(title: "App", description: "El nombre de la app, por ejemplo Instagram")
    var app: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        .result(value: FrictionGuard.shared.shouldPause(app: app ?? ""))
    }
}

/// Abre Planaby con la pausa consciente: respirar unos segundos y decidir.
struct MindfulPauseIntent: AppIntent {
    static let title: LocalizedStringResource = "Pausa consciente"
    static let description = IntentDescription("Abre Planaby para respirar unos segundos antes de usar una app que te distrae.")
    static let openAppWhenRun = true

    @Parameter(title: "App", description: "El nombre de la app, por ejemplo Instagram")
    var app: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        FrictionGuard.shared.present(app: app ?? "")
        return .result()
    }
}
