import SwiftData
import SwiftUI
import UserNotifications

@main
struct PlanabyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var timer = FocusTimer.shared
    @State private var library = MethodLibrary.shared
    @State private var modes = ModeController.shared
    @State private var inbox = PlanInbox.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(timer)
                .environment(library)
                .environment(modes)
                .environment(inbox)
                .preferredColorScheme(.dark)
                .tint(Theme.orange)
        }
        .modelContainer(PlanabyStore.container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                timer.sync()
                ReminderScheduler.shared.reschedule()
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        MainActor.assumeIsolated {
            ReminderScheduler.shared.registerCategories()
        }
        return true
    }

    /// Acciones de los recordatorios: empezar a concentrarse o posponer.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let title = response.notification.request.content.title
        let body = response.notification.request.content.body
        await MainActor.run {
            switch action {
            case ReminderScheduler.startAction:
                // El título del aviso es el del bloque: así la sesión queda ligada a su tarea.
                FocusTimer.shared.start(MethodLibrary.shared.selected, task: title)
            case ReminderScheduler.snoozeAction:
                ReminderScheduler.shared.snooze(title: title, body: body)
            default:
                break
            }
        }
    }

    /// Muestra los avisos de cambio de fase también con la app abierta.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
