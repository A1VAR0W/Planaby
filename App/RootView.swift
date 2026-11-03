import SwiftUI

/// Pestañas principales.
enum AppTab: Hashable {
    case focus, plan, stats, settings
}

struct RootView: View {
    @Environment(FocusTimer.self) private var timer
    @Environment(PlanInbox.self) private var inbox
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var tab: AppTab = .focus

    /// En horizontal, desde Enfoque, el iPhone pasa a modo escritorio a pantalla completa.
    private var isDesk: Bool { verticalSizeClass == .compact && tab == .focus }

    var body: some View {
        Group {
            if isDesk {
                DeskView()
                    .statusBarHidden()
                    .persistentSystemOverlays(.hidden)
            } else {
                TabView(selection: $tab) {
                    Tab("Enfoque", systemImage: "timer", value: AppTab.focus) {
                        NavigationStack {
                            FocusView()
                        }
                    }
                    Tab("Plan", systemImage: "calendar", value: AppTab.plan) {
                        NavigationStack {
                            PlanView()
                        }
                    }
                    Tab("Progreso", systemImage: "chart.bar.fill", value: AppTab.stats) {
                        NavigationStack {
                            StatsView(onStartFocus: { tab = .focus })
                        }
                    }
                    Tab("Ajustes", systemImage: "gearshape.fill", value: AppTab.settings) {
                        NavigationStack {
                            SettingsView()
                        }
                    }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: timer.state?.phase)
        // Una sesión que empieza desde un bloque, un aviso o Siri se sigue en Enfoque.
        .onChange(of: timer.state?.sessionStart) { old, new in
            if new != nil, new != old { tab = .focus }
        }
        // Lo dictado a Siri ("Planifica con Planaby") se abre en el chat del plan.
        .onChange(of: inbox.pending, initial: true) { _, pending in
            if pending != nil { tab = .plan }
        }
        .task {
            // Las fases avanzan solas aunque no se toque nada.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                timer.reconcile()
            }
        }
    }
}
