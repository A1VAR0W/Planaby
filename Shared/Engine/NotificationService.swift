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
        // Los avisos ya pasados de esta sesión sobran: así no se amontonan ni se repiten.
        center.removeDeliveredNotifications(withIdentifiers: transitionIDs)
        guard let state, Preferences.phaseAlertsEnabled else { return }
        let context = SessionContext.load(for: state.sessionStart)
        let style = AlertPreferences.style
        let soundSet = AlertPreferences.soundSet

        var index = 0
        for transition in state.upcomingTransitions(limit: Self.maxScheduled) {
            let intoBreak = transition.next.isBreak
            guard AlertPreferences.alerts(intoBreak: intoBreak) else { continue }
            let content = UNMutableNotificationContent()
            content.threadIdentifier = "planaby-phase"
            content.interruptionLevel = .active
            content.relevanceScore = 0.8
            switch style {
            case .sound:
                content.sound = soundSet.fileName(isBreak: intoBreak)
                    .map { UNNotificationSound(named: UNNotificationSoundName($0)) } ?? .default
            case .vibration, .visual:
                content.sound = nil
            }
            if intoBreak {
                content.title = "Buen trabajo. Es hora de descansar"
                var body = "\(transition.next.title) de \(Self.minutes(transition.nextDuration ?? 0)) min."
                if let step = context?.nextStep, !step.isEmpty { body += " Después: \(step)." }
                content.body = body
            } else {
                content.title = "Es hora de continuar"
                var body = transition.nextDuration.map { "\(Self.minutes($0)) min de concentración." }
                    ?? "Concentración libre: para cuando lo necesites."
                if let step = context?.nextStep, !step.isEmpty {
                    body += " Siguiente paso: \(step)."
                } else if let task = state.taskTitle {
                    body += " Con «\(task)»."
                }
                content.body = body
            }

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, transition.date.timeIntervalSinceNow), repeats: false
            )
            center.add(UNNotificationRequest(identifier: transitionIDs[index], content: content, trigger: trigger))
            index += 1
        }
    }

    static func isPhaseAlert(_ identifier: String) -> Bool { identifier.hasPrefix("phase-") }

    private static func minutes(_ seconds: TimeInterval) -> Int {
        Int((seconds / 60).rounded())
    }
}
