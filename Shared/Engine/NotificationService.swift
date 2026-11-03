import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    private let center = UNUserNotificationCenter.current()
    /// Se programan varias transiciones por adelantado porque la app no se ejecuta en segundo plano.
    private static let maxScheduled = 12
    private let transitionIDs = (0..<NotificationService.maxScheduled).map { "phase-\($0)" }

    func scheduleTransitions(for state: TimerState?) {
        center.removePendingNotificationRequests(withIdentifiers: transitionIDs)
        guard let state else { return }

        for (index, transition) in state.upcomingTransitions(limit: Self.maxScheduled).enumerated() {
            let content = UNMutableNotificationContent()
            content.sound = .default
            switch transition.next {
            case .focus:
                content.title = "Vuelta al trabajo"
                content.body = transition.nextDuration.map { "\(Self.minutes($0)) min de concentración." }
                    ?? "Concentración libre: para cuando lo necesites."
            case .shortBreak, .longBreak:
                content.title = "¡Bloque completado!"
                content.body = "\(transition.next.title) de \(Self.minutes(transition.nextDuration ?? 0)) min."
            }

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, transition.date.timeIntervalSinceNow), repeats: false
            )
            center.add(UNNotificationRequest(identifier: transitionIDs[index], content: content, trigger: trigger))
        }
    }

    private static func minutes(_ seconds: TimeInterval) -> Int {
        Int((seconds / 60).rounded())
    }
}
