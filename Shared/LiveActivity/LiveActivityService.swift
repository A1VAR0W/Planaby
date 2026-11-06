import ActivityKit
import Foundation

/// Mantiene una única Live Activity por sesión. Sin push, no puede cambiar de fase sola:
/// al terminar la fase queda "stale" y muestra el botón para continuar.
@MainActor
final class LiveActivityService {
    func sync(with state: TimerState?) {
        let activities = Activity<FocusActivityAttributes>.activities

        guard let state else {
            finish(activities)
            return
        }

        let content = ActivityContent(
            state: FocusActivityAttributes.ContentState(state),
            staleDate: state.isPaused ? nil : state.phaseEnd
        )
        if let current = activities.first(where: { $0.attributes.sessionStart == state.sessionStart }) {
            Task { await current.update(content) }
        } else {
            end(activities)
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            _ = try? Activity.request(attributes: FocusActivityAttributes(state), content: content)
        }
    }

    /// Al empezar otra sesión: las anteriores (también la de «Sesión terminada») se quitan ya,
    /// así nunca hay dos actividades de Planaby a la vez.
    private func end(_ activities: [Activity<FocusActivityAttributes>]) {
        for activity in activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Al terminar la sesión: la actividad se queda unos minutos como «Sesión terminada» (tocarla
    /// abre Planaby) y después iOS la retira. Las que ya terminaron no se tocan.
    private func finish(_ activities: [Activity<FocusActivityAttributes>]) {
        for activity in activities where activity.activityState == .active || activity.activityState == .stale {
            var final = activity.content.state
            final.endedAt = .now
            final.pausedAt = nil
            let content = ActivityContent(state: final, staleDate: nil)
            Task { await activity.end(content, dismissalPolicy: .after(.now.addingTimeInterval(Self.finishedLinger))) }
        }
    }

    /// Cuánto se ve «Sesión terminada» en la pantalla bloqueada.
    static let finishedLinger: TimeInterval = 5 * 60
}
