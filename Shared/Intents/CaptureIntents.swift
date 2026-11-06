import AppIntents

/// Abre Planaby con el panel de captura rápida. Para el control del Centro de Control, la
/// pantalla bloqueada y el botón de Acción. No cambia de pestaña ni toca la sesión en curso.
struct OpenQuickCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Abrir captura rápida"
    static let description = IntentDescription("Abre Planaby con la captura rápida para apuntar algo sin interrumpir la sesión.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        CaptureRequest.post()
        return .result()
    }
}
