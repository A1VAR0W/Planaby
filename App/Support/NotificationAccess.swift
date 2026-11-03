import UserNotifications

/// Permiso de notificaciones. Se pide en contexto, al empezar la primera sesión, y no al abrir la app.
enum NotificationAccess {
    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    static func request() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func requestIfNeeded() async {
        if await status() == .notDetermined {
            await request()
        }
    }
}
