import ActivityKit
import Foundation

struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var phase: PhaseKind
        var methodName: String
        var phaseStart: Date
        var phaseEnd: Date?
        var pausedAt: Date?
        var nextPhase: PhaseKind
        // Opcionales: lo mismo que el modo escritorio (DeskPresentation), sin textos de mensajes.
        var taskTitle: String?
        /// «2 comunicaciones laborales importantes» o «Mientras trabajabas: 3 pendientes».
        var commsText: String?
        var commsCount: Int?

        init(_ state: TimerState, comms: CommsSnapshot = .load()) {
            phase = state.phase
            methodName = state.method.name
            phaseStart = state.phaseStart
            phaseEnd = state.phaseEnd
            pausedAt = state.pausedAt
            nextPhase = state.nextPhase
            let presentation = DeskPresentation(state: state, comms: comms, agenda: [], now: .now)
            taskTitle = state.taskTitle
            commsText = presentation.commsText
            commsCount = presentation.commsCount
        }

        /// Intervalo de la fase para los contadores del sistema; nil si es abierta.
        var range: ClosedRange<Date>? {
            phaseEnd.map { phaseStart...$0 }
        }

        /// Progreso congelado mientras está en pausa.
        var pausedProgress: Double {
            guard let pausedAt, let phaseEnd else { return 0 }
            let total = phaseEnd.timeIntervalSince(phaseStart)
            return total > 0 ? min(1, max(0, pausedAt.timeIntervalSince(phaseStart) / total)) : 0
        }

        /// Texto fijo para cuando está en pausa (el contador del sistema no se puede detener).
        var pausedClock: String? {
            guard let pausedAt else { return nil }
            let seconds = phaseEnd.map { $0.timeIntervalSince(pausedAt) } ?? pausedAt.timeIntervalSince(phaseStart)
            return TimerState.format(max(0, seconds))
        }
    }

    var sessionStart: Date

    init(_ state: TimerState) {
        sessionStart = state.sessionStart
    }
}
