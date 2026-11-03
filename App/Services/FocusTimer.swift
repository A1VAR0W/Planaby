import Foundation
import Observation

@Observable
@MainActor
final class FocusTimer {
    private(set) var state: TimerState?

    @ObservationIgnored private let notifications: NotificationService
    private static let storageKey = "timerState"

    init(notifications: NotificationService) {
        self.notifications = notifications
        if let data = AppGroup.defaults.data(forKey: Self.storageKey) {
            state = try? JSONDecoder().decode(TimerState.self, from: data)
        }
        reconcile()
    }

    func start(_ method: FocusMethod) {
        commit(TimerState(method: method, at: .now))
    }

    func pause() { mutate { $0.pause(at: .now) } }

    func resume() { mutate { $0.resume(at: .now) } }

    func skip() { mutate { $0.skip(at: .now) } }

    /// Termina la sesión; devuelve el resumen si hubo al menos un minuto de concentración.
    func stop() -> CompletedSession? {
        guard let state else { return nil }
        let summary = state.summary(endingAt: .now)
        commit(nil)
        return summary.focusedSeconds >= 60 ? summary : nil
    }

    /// Avanza las fases que hayan terminado mientras la app estaba en segundo plano.
    func reconcile(now: Date = .now) {
        guard var updated = state else { return }
        if updated.catchUp(to: now) > 0 {
            commit(updated)
        }
    }

    private func mutate(_ change: (inout TimerState) -> Void) {
        guard var updated = state else { return }
        change(&updated)
        commit(updated)
    }

    private func commit(_ newState: TimerState?) {
        state = newState
        if let newState, let data = try? JSONEncoder().encode(newState) {
            AppGroup.defaults.set(data, forKey: Self.storageKey)
        } else {
            AppGroup.defaults.removeObject(forKey: Self.storageKey)
        }
        notifications.scheduleTransitions(for: newState)
    }
}
