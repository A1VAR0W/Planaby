import AppIntents
import Foundation
import Observation

extension PlanMode: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Modo"
    static let caseDisplayRepresentations: [PlanMode: DisplayRepresentation] = [
        .work: DisplayRepresentation(title: "Trabajo", image: .init(systemName: "briefcase.fill")),
        .personal: DisplayRepresentation(title: "Normal", image: .init(systemName: "house.fill")),
    ]
}

struct SetPlanModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Cambiar de modo"

    @Parameter(title: "Modo")
    var mode: PlanMode

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        ModeController.shared.set(mode)
        return .result(dialog: "Modo \(mode.title) activado.")
    }
}

/// Filtro de Concentración: al activar una Concentración del iPhone, Planaby cambia de modo.
/// Al desactivarla, iOS vuelve a ejecutarlo sin modo y Planaby regresa a Normal.
struct PlanModeFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Modo de Planaby"

    @Parameter(title: "Modo")
    var mode: PlanMode?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Planaby: modo \(mode?.title ?? "Normal")")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let controller = ModeController.shared
        if let mode {
            controller.set(mode, source: .focus)
        } else if controller.source == .focus {
            controller.set(.personal, source: .manual)
        }
        return .result()
    }
}

/// "Planifica con Planaby": abre el chat del plan con lo que se dicte a Siri.
struct AddToPlanIntent: AppIntent {
    static let title: LocalizedStringResource = "Planificar con Planaby"
    static let openAppWhenRun = true

    @Parameter(title: "¿Qué quieres planificar?")
    var request: String

    @MainActor
    func perform() async throws -> some IntentResult {
        PlanInbox.shared.pending = request
        return .result()
    }
}

/// Peticiones que llegan desde Siri o Atajos para que el chat las recoja al abrirse.
@Observable
@MainActor
final class PlanInbox {
    static let shared = PlanInbox()
    var pending: String?
    private init() {}
}
