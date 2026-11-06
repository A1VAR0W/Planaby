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

    /// Cambio de fase que ha ocurrido solo (no al pulsar «Saltar»), para el aviso dentro de la app.
    struct AutomaticTransition: Equatable {
        let id = UUID()
        let finished: PhaseKind
        let next: PhaseKind
        let nextDuration: TimeInterval?
        /// La concentración que terminó era la de «Empezar ahora».
        let endedStarter: Bool
    }

    private(set) var lastTransition: AutomaticTransition?

    @ObservationIgnored private let notifications = NotificationService()
    @ObservationIgnored private let liveActivity = LiveActivityService()

    private init() {
        state = TimerState.loadShared()
        reconcile()
    }

    func start(_ method: FocusMethod, task: String? = nil, taskID: UUID? = nil) {
        if state != nil { stop() }
        // El plan (Trabajo o Normal) se lee del App Group: también arrancan sesiones los widgets.
        let mode = AppGroup.defaults.string(forKey: "planMode")
        commit(TimerState(method: method, at: .now, taskTitle: task, taskID: taskID, mode: mode))
    }

    /// Cambia la tarea de la sesión en marcha (al retomar con otra o al elegirla después).
    func setTask(_ title: String?, id: UUID?) {
        mutate {
            $0.taskTitle = title
            $0.taskID = id
        }
    }

    /// Retoma ahora con una concentración de `minutes` (por defecto, la del método).
    func refocus(minutes: Int? = nil) {
        mutate { $0.beginFocus(at: .now, minutes: minutes) }
    }

    /// Tras los minutos de «Empezar ahora», sigue con un bloque normal del método elegido.
    func continueWithBlock(_ method: FocusMethod) {
        mutate {
            $0.method = method
            $0.beginFocus(at: .now)
        }
    }

    /// Apunta una salida de Planaby en mitad de la concentración.
    func noteLeave(seconds: TimeInterval) {
        mutate { $0.noteLeave(seconds: seconds) }
    }

    func pause() { mutate { $0.pause(at: .now) } }

    func resume() { mutate { $0.resume(at: .now) } }

    func togglePause() {
        guard let state else { return }
        if state.isPaused { resume() } else { pause() }
    }

    func skip() { mutate { $0.skip(at: .now) } }

    /// Modo estricto: el rato fuera de Planaby no cuenta. La concentración se pausa con efecto
    /// desde que se salió y se reanuda ahora (si el bloque terminó estando fuera, sigue abierto).
    func discount(from leftAt: Date, to now: Date) {
        guard var updated = TimerState.loadShared() ?? state,
              updated.phase == .focus, !updated.isPaused, updated.phaseStart <= leftAt else { return }
        if let end = updated.phaseEnd, end <= leftAt { return }
        // Es una salida, no una pausa: no cuenta en las pausas de la sesión.
        let pauses = updated.pauseCount
        updated.pause(at: leftAt)
        updated.resume(at: now)
        updated.pauseCount = pauses
        commit(updated)
    }

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
        let record = FocusSessionRecord(summary)
        // Una sesión empezada solo con el título (un aviso, Siri…) se liga a su tarea por el nombre.
        if record.taskID == nil, let title = record.taskTitle {
            record.taskID = PlanabyStore.task(titled: title)?.stableID
        }
        context.insert(record)
        try? context.save()
        return summary
    }

    /// Avanza las fases que hayan terminado mientras la app estaba en segundo plano.
    func reconcile(now: Date = .now) {
        guard var updated = state else { return }
        let before = updated.phase
        if updated.catchUp(to: now) > 0 {
            // Solo si acaba de pasar: al abrir la app horas después no se enseña un aviso viejo.
            if now.timeIntervalSince(updated.phaseStart) < 5 {
                lastTransition = AutomaticTransition(
                    finished: before, next: updated.phase,
                    nextDuration: updated.phaseEnd.map { $0.timeIntervalSince(updated.phaseStart) },
                    endedStarter: before == .focus && updated.method.id == FocusMethod.starter.id
                )
            }
            commit(updated)
        }
    }

    /// Relee el estado compartido y vuelve a sincronizar notificaciones, widgets y Live Activity.
    func sync() {
        var current = TimerState.loadShared()
        current?.catchUp(to: .now)
        commit(current)
    }

    /// Vuelve a pintar widgets y Live Activity sin tocar el estado (p. ej. al llegar una
    /// comunicación). La Live Activity solo se actualiza si hay sesión.
    func refreshSurfaces() {
        if state != nil { liveActivity.sync(with: state) }
        WidgetCenter.shared.reloadAllTimelines()
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
