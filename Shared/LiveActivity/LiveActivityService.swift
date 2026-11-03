import ActivityKit
import Foundation

/// Mantiene una única Live Activity por sesión. Sin push, no puede cambiar de fase sola:
/// al terminar la fase queda "stale" y muestra el botón para continuar.
@MainActor
final class LiveActivityService {
    func sync(with state: TimerState?) {
        let activities = Activity<FocusActivityAttributes>.activities

        guard let state else {
            end(activities)
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

    private func end(_ activities: [Activity<FocusActivityAttributes>]) {
        for activity in activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
