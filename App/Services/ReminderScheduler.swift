import Foundation
import SwiftData
import UserNotifications

/// Recordatorios de eventos y bloques. iOS admite 64 avisos pendientes por app: 12 son de las
/// fases del temporizador y aquí se usan hasta 40, en una ventana de los próximos días que se
/// reprograma al abrir la app, al editar el plan y al cambiar de modo.
@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()

    static let category = "planReminder"
    static let startAction = "startBlock"
    static let snoozeAction = "snooze"

    private static let maxScheduled = 40
    private static let window: TimeInterval = 14 * 24 * 3600
    private let ids = (0..<ReminderScheduler.maxScheduled).map { "reminder-\($0)" }
    private let center = UNUserNotificationCenter.current()

    private init() {}

    func registerCategories() {
        let start = UNNotificationAction(identifier: Self.startAction, title: "Empezar a concentrarme", options: [.foreground])
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "Posponer 10 min")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [start, snooze], intentIdentifiers: []),
        ])
    }

    func reschedule() {
        // Se llama tras cada cambio del plan: también se actualiza la copia en el Calendario de iOS.
        CalendarMirror.shared.sync()
        center.removePendingNotificationRequests(withIdentifiers: ids)

        let now = Date.now
        let visible = ModeController.shared.mode.visibleModes
        let range = DateInterval(start: now, duration: Self.window)
        let events = (try? PlanabyStore.container.mainContext.fetch(FetchDescriptor<CalendarEvent>())) ?? []

        let upcoming = events
            .filter { $0.reminderMinutes != nil && visible.contains($0.mode) }
            .flatMap { event in
                event.occurrences(in: range).map { occurrence in
                    (event: event, start: occurrence.start, fire: occurrence.start.addingTimeInterval(-TimeInterval((event.reminderMinutes ?? 0) * 60)))
                }
            }
            .filter { $0.fire > now }
            .sorted { $0.fire < $1.fire }
            .prefix(Self.maxScheduled)

        for (index, item) in upcoming.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = item.event.title
            let minutes = item.event.reminderMinutes ?? 0
            let time = item.start.formatted(date: .omitted, time: .shortened)
            content.body = minutes == 0 ? "Ahora · \(item.event.mode.title)" : "A las \(time) · en \(minutes) min · \(item.event.mode.title)"
            content.sound = .default
            content.threadIdentifier = item.event.mode.rawValue
            if item.event.kind == .workBlock || item.event.kind == .habit {
                content.categoryIdentifier = Self.category
            }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, item.fire.timeIntervalSince(now)), repeats: false)
            center.add(UNNotificationRequest(identifier: ids[index], content: content, trigger: trigger))
        }
    }

    /// Repite un aviso dentro de 10 minutos.
    func snooze(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.category
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10 * 60, repeats: false)
        center.add(UNNotificationRequest(identifier: "snooze-\(UUID().uuidString)", content: content, trigger: trigger))
    }
}
