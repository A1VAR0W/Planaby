import AppIntents

/// «Capturar tarea en Planaby»: apunta algo en «Por organizar» sin abrir la app, sin cambiar de
/// pestaña y sin abrir el chat del plan. Siri pregunta qué apuntar si no se dice en la frase
/// (iOS no deja meter texto libre en la frase de un atajo de app).
///
/// Con el iPhone bloqueado funciona después del primer desbloqueo desde que se encendió (la base de
/// datos está protegida hasta entonces); solo guarda lo dicho y no enseña nada del plan.
struct CaptureTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Capturar tarea en Planaby"
    static let description = IntentDescription(
        "Apunta una tarea en «Por organizar» de Planaby para organizarla después. No interrumpe la sesión de concentración."
    )
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Tarea", requestValueDialog: "¿Qué quieres apuntar?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Capturar \(\.$text) en Planaby")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let capture = try CaptureCenter.shared.save(text, source: .siri)
            let when = FocusTimer.shared.state == nil ? "Lo tienes en Plan › Por organizar." : "Lo organizarás cuando termines."
            return .result(dialog: "Apuntado: «\(capture.text)». \(when)")
        } catch CaptureCenter.Failure.empty {
            throw $text.needsValueError("¿Qué quieres apuntar?")
        } catch {
            // Nunca se dice «apuntado» si no se ha guardado.
            return .result(dialog: "No he podido guardarlo. Prueba otra vez desde Planaby.")
        }
    }
}
