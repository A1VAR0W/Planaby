import SwiftUI

/// Pestañas principales.
enum AppTab: Hashable {
    case focus, plan, stats, settings
}

struct RootView: View {
    @Environment(FocusTimer.self) private var timer
    @Environment(PlanInbox.self) private var inbox
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .focus
    @State private var showsRhythmTest = PersonalProfile.shared.shouldOfferTest
    @State private var friction = FrictionGuard.shared

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
        // La primera vez se ofrece el test de ritmo para personalizar el plan.
        .fullScreenCover(isPresented: $showsRhythmTest) {
            FocusProfileTestView(isFirstRun: true)
        }
        // Pausa consciente que llega desde una automatización de Atajos.
        .fullScreenCover(item: $friction.request) { request in
            FrictionView(request: request) { resisted in
                if resisted { tab = .focus }
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: timer.state?.phase)
        // Música de concentración o de descanso, si está configurada (solo con la app delante).
        .onChange(of: timer.state?.phase) { old, new in
            if scenePhase == .active { MusicLinks.phaseChanged(to: new, from: old) }
        }
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
