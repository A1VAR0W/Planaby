import AppIntents
import SwiftUI
import WidgetKit

/// Botón de captura rápida para el Centro de Control, la pantalla bloqueada y el botón de Acción.
/// Va en la misma extensión de widgets (sin App ID nuevo). Abre Planaby con el panel; con el iPhone
/// bloqueado, iOS pide Face ID o el código antes de abrirlo.
struct CaptureControl: ControlWidget {
    static let kind = "com.alvaro.planaby.capture"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenQuickCaptureIntent()) {
                Label("Captura rápida", systemImage: "square.and.pencil")
            }
            .tint(Theme.orange)
        }
        .displayName("Captura rápida")
        .description("Apunta una tarea en Planaby sin interrumpir la sesión.")
    }
}
