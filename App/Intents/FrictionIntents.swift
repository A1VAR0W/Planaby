import AppIntents

/// La acción única de la automatización «Al abrir una app»: si el bloqueo está activado y toca
/// frenar, abre Planaby con la pausa consciente; si no, no hace nada y la app se abre normal.
struct BlockAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Bloquear app"
    static let description = IntentDescription(
        "Úsala en una automatización «Al abrir una app». Si en Planaby tienes activado «Bloquear apps», te frena unos segundos antes de usarla."
    )
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @Parameter(title: "App (opcional)", description: "El nombre de la app, por ejemplo Instagram")
    var app: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        let guardian = FrictionGuard.shared
        guard guardian.shouldPause(app: app ?? "") else { return .result() }
        guardian.present(app: app ?? "")
        try await continueInForeground(alwaysConfirm: false)
        return .result()
    }
}

/// Versión anterior en dos pasos (se mantiene para las automatizaciones ya creadas).
struct ShouldPauseIntent: AppIntent {
    static let title: LocalizedStringResource = "¿Toca pausa consciente?"
    static let description = IntentDescription("Devuelve Sí si Planaby debe frenarte antes de usar esta app. Es más sencillo usar «Bloquear app».")

    @Parameter(title: "App", description: "El nombre de la app, por ejemplo Instagram")
    var app: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        .result(value: FrictionGuard.shared.shouldPause(app: app ?? ""))
    }
}

/// Abre Planaby con la pausa consciente (versión anterior en dos pasos).
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
