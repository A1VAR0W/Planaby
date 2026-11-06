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
    /// Desde el arranque, para atender los atajos y controles de captura rápida.
    @State private var capture = CaptureCenter.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(timer)
                .environment(library)
                .environment(modes)
                .environment(inbox)
                .preferredColorScheme(.dark)
                .tint(Theme.orange)
                // planaby://desk (widgets, Live Activity) y vuelta desde Spotify (App Remote).
                .onOpenURL { url in
                    if url.scheme == "planaby" {
                        switch url.host() {
                        case "inbox": CommsCenter.shared.inboxRequested = true
                        // Captura rápida (widget, control) y «Por organizar».
                        case "capture": capture.open()
                        case "captures": capture.inboxRequested = true
                        default: DeskLauncher.shared.requestDesk()
                        }
                    } else {
                        SpotifyController.shared.handleOpenURL(url)
                    }
                }
        }
        .modelContainer(PlanabyStore.container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Antes de poner al día el temporizador (el modo estricto lo ajusta).
                LeaveGuard.shared.didReturn()
                timer.sync()
                ReminderScheduler.shared.reschedule()
                // Outlook y otros calendarios suscritos se descargan de nuevo si hace rato.
                ExternalCalendars.shared.syncIfNeeded()
                Task { await SpotifyController.shared.connectRemote() }
                // Correos nuevos por el filtro de mensajes (si hay cuenta).
                MailInbox.shared.checkIfNeeded(context: PlanabyStore.container.mainContext)
                // «Mientras estabas fuera»: lo nuevo y relevante que no se ha enseñado.
                CommsCenter.shared.checkAway()
            } else if phase == .background {
                LeaveGuard.shared.didLeave()
                SpotifyController.shared.disconnectRemote()
                // Al cerrar no se pierde nada: se guarda lo pendiente y la copia del día.
                PlanabyStore.saveNow()
                BackupService.automaticBackup(context: PlanabyStore.container.mainContext)
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
        // Los cambios de fase los enseña la propia app (tarjeta, sonido y vibración): sin banner
        // para no avisar dos veces. Queda en el Centro de notificaciones.
        if NotificationService.isPhaseAlert(notification.request.identifier) { return [.list] }
        return [.banner, .list, .sound]
    }
}
