import ActivityKit
import Foundation

struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var phase: PhaseKind
        var phaseStart: Date
        var phaseEnd: Date?
        var pausedAt: Date?
        var nextPhase: PhaseKind

        init(_ state: TimerState) {
            phase = state.phase
            phaseStart = state.phaseStart
            phaseEnd = state.phaseEnd
            pausedAt = state.pausedAt
            nextPhase = state.nextPhase
        }

        /// Texto fijo para cuando está en pausa (el contador del sistema no se puede detener).
        var pausedClock: String? {
            guard let pausedAt else { return nil }
            let seconds = phaseEnd.map { $0.timeIntervalSince(pausedAt) } ?? pausedAt.timeIntervalSince(phaseStart)
            return TimerState.format(max(0, seconds))
        }
    }

    var methodName: String
    var sessionStart: Date

    init(_ state: TimerState) {
        methodName = state.method.name
        sessionStart = state.sessionStart
    }
}
