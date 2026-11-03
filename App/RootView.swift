import SwiftUI

/// Pestañas principales. El hito 3 añadirá `.plan` (calendario y planificación) entre Enfoque y Progreso.
enum AppTab: Hashable {
    case focus, stats, settings
}

struct RootView: View {
    @Environment(FocusTimer.self) private var timer
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
                        FocusView(onShowStats: { tab = .stats })
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
        .task {
            // Las fases avanzan solas aunque no se toque nada.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                timer.reconcile()
            }
        }
    }
}
