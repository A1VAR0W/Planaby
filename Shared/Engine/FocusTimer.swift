import Foundation
import Observation
import SwiftData
import WidgetKit

/// Motor único del temporizador. Lo usan la interfaz y los App Intents (que se ejecutan
/// en el proceso de la app como `LiveActivityIntent`), así que todo cambio pasa por aquí.
@Observable
@MainActor
final class FocusTimer {
    static let shared = FocusTimer()

    private(set) var state: TimerState?

    @ObservationIgnored private let notifications = NotificationService()
    @ObservationIgnored private let liveActivity = LiveActivityService()

    private init() {
        state = TimerState.loadShared()
        reconcile()
    }

    func start(_ method: FocusMethod, task: String? = nil) {
        if state != nil { stop() }
        commit(TimerState(method: method, at: .now, taskTitle: task))
    }

    func pause() { mutate { $0.pause(at: .now) } }

    func resume() { mutate { $0.resume(at: .now) } }

    func togglePause() {
        guard let state else { return }
        if state.isPaused { resume() } else { pause() }
    }

    func skip() { mutate { $0.skip(at: .now) } }

    /// Elige método: si hay sesión en marcha, se cambia sin reiniciarla.
    func select(_ method: FocusMethod) {
        MethodLibrary.shared.selectedID = method.id
        mutate { $0.switchMethod(to: method, at: .now) }
    }

    /// Termina la sesión y la guarda en el historial si hubo al menos un minuto de concentración.
    @discardableResult
    func stop() -> CompletedSession? {
        guard let state else { return nil }
        let summary = state.summary(endingAt: .now)
        commit(nil)
        guard summary.focusedSeconds >= 60 else { return nil }
        let context = PlanabyStore.container.mainContext
        context.insert(FocusSessionRecord(summary))
        try? context.save()
        return summary
    }

    /// Avanza las fases que hayan terminado mientras la app estaba en segundo plano.
    func reconcile(now: Date = .now) {
        guard var updated = state else { return }
        if updated.catchUp(to: now) > 0 {
            commit(updated)
        }
    }

    /// Relee el estado compartido y vuelve a sincronizar notificaciones, widgets y Live Activity.
    func sync() {
        var current = TimerState.loadShared()
        current?.catchUp(to: .now)
        commit(current)
    }

    private func mutate(_ change: (inout TimerState) -> Void) {
        guard var updated = state else { return }
        change(&updated)
        commit(updated)
    }

    private func commit(_ newState: TimerState?) {
        state = newState
        TimerState.saveShared(newState)
        notifications.scheduleTransitions(for: newState)
        liveActivity.sync(with: newState)
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
    }
}
