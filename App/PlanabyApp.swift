import SwiftData
import SwiftUI
import UserNotifications

@main
struct PlanabyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var notifications: NotificationService
    @State private var timer: FocusTimer
    @State private var library = MethodLibrary()

    init() {
        let notifications = NotificationService()
        _notifications = State(initialValue: notifications)
        _timer = State(initialValue: FocusTimer(notifications: notifications))
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                TimerView()
            }
            .environment(timer)
            .environment(library)
            .task { await notifications.requestAuthorization() }
        }
        .modelContainer(for: FocusSessionRecord.self)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { timer.reconcile() }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Muestra los avisos de cambio de fase también con la app abierta.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
