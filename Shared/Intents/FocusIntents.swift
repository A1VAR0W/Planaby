import AppIntents
import Foundation

// Todos son `LiveActivityIntent`: el sistema los ejecuta en el proceso de la app aunque se
// lancen desde un widget, la Live Activity, el Centro de Control o Siri.

struct StartFocusIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Empezar concentración"

    @Parameter(title: "Método")
    var method: FocusMethodEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let library = MethodLibrary.shared
        let chosen = method.flatMap { entity in library.all.first { $0.id == entity.id } } ?? library.selected
        FocusTimer.shared.start(chosen)
        return .result(dialog: "\(chosen.name) en marcha.")
    }
}

struct TogglePauseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pausar o reanudar"

    @MainActor
    func perform() async throws -> some IntentResult {
        FocusTimer.shared.togglePause()
        return .result()
    }
}

struct SkipPhaseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Siguiente fase"

    @MainActor
    func perform() async throws -> some IntentResult {
        FocusTimer.shared.skip()
        return .result()
    }
}

struct StopFocusIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Terminar concentración"

    @MainActor
    func perform() async throws -> some IntentResult {
        FocusTimer.shared.stop()
        return .result()
    }
}

/// Pone al día la Live Activity cuando una fase terminó con la app cerrada.
struct RefreshFocusIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Actualizar concentración"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        FocusTimer.shared.sync()
        return .result()
    }
}

/// Interruptor del Centro de Control.
struct ToggleFocusIntent: SetValueIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Concentración"
    static let isDiscoverable = false

    @Parameter(title: "En marcha")
    var value: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        if value {
            FocusTimer.shared.start(MethodLibrary.shared.selected)
        } else {
            FocusTimer.shared.stop()
        }
        return .result()
    }
}
