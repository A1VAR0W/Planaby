import SwiftData
import SwiftUI
import UserNotifications

@main
struct PlanabyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var timer = FocusTimer.shared
    @State private var library = MethodLibrary.shared

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                TimerView()
            }
            .environment(timer)
            .environment(library)
            .task {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            }
        }
        .modelContainer(PlanabyStore.container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { timer.sync() }
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
