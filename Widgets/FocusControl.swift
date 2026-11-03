import AppIntents
import SwiftUI
import WidgetKit

/// Interruptor para el Centro de Control, la pantalla bloqueada y el botón de Acción.
struct FocusControl: ControlWidget {
    static let kind = "com.alvaro.planaby.focus"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: Provider()) { isRunning in
            ControlWidgetToggle("Concentración", isOn: isRunning, action: ToggleFocusIntent()) { isOn in
                Label(isOn ? "En marcha" : "Empezar", systemImage: isOn ? "timer" : "play.fill")
            }
            .tint(Theme.focus)
        }
        .displayName("Concentración")
        .description("Empieza o termina una sesión de Planaby.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }

        func currentValue() async throws -> Bool {
            TimerState.loadShared() != nil
        }
    }
}
