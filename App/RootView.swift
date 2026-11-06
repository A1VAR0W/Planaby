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
    @State private var leaveGuard = LeaveGuard.shared
    @State private var transition: FocusTimer.AutomaticTransition?
    @State private var showsStuck = false
    @State private var pendingStuck = false
    @State private var pendingInbox = false
    @State private var comms = CommsCenter.shared
    @State private var desk = DeskLauncher.shared
    @State private var capture = CaptureCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        // Vuelta tras salir de Planaby en mitad de un bloque: «Bienvenido de nuevo».
        .sheet(item: $leaveGuard.returned, onDismiss: {
            tab = .focus
            // «Me he atascado» o la bandeja se abren cuando ya se ha cerrado esta hoja (nunca dos a la vez).
            if pendingStuck {
                pendingStuck = false
                showsStuck = true
            } else if pendingInbox {
                pendingInbox = false
                comms.inboxRequested = true
            }
        }) { info in
            RecoveryView(info: info, onStuck: { pendingStuck = true }, onInbox: { pendingInbox = true })
        }
        .sheet(isPresented: $showsStuck) {
            NavigationStack { StuckSheet() }
        }
        // Bandeja de comunicaciones: desde la píldora, la tarjeta de fase, el escritorio o un widget.
        .sheet(isPresented: Binding(
            get: { comms.inboxRequested && !otherSheet(except: .comms) },
            set: { comms.inboxRequested = $0 }
        )) {
            NavigationStack { InboxView() }
        }
        // «Por organizar»: desde el descanso, el fin de sesión, el escritorio o un atajo.
        .sheet(isPresented: Binding(
            get: { capture.inboxRequested && !otherSheet(except: .captures) },
            set: { capture.inboxRequested = $0 }
        )) {
            NavigationStack {
                CaptureInboxView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Listo") { capture.inboxRequested = false }
                        }
                    }
            }
        }
        // Captura rápida: hoja baja en vertical; en el modo escritorio va flotando dentro de él.
        .quickCaptureSheet(isEnabled: !isDesk && !otherSheet(except: .composer))
        // «✓ Apuntado …» abajo, sin tapar el temporizador ni la tarjeta de fase (que va arriba).
        .modifier(CaptureToastOverlay(bottomPadding: isDesk ? 84 : 150))
        .sensoryFeedback(.warning, trigger: leaveGuard.returned?.id)
        // Cambio de fase con la app delante: tarjeta, sonido y vibración según «Avisos de concentración».
        .overlay(alignment: .top) {
            if let transition {
                PhaseTransitionCard(transition: transition) {
                    withAnimation(.easeIn(duration: 0.18)) { self.transition = nil }
                }
                .padding(.top, Space.s)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .zIndex(1)
            }
        }
        // Las tarjetas de comunicaciones esperan mientras se ve la de cambio de fase.
        .onChange(of: transition == nil) { _, hidden in comms.phaseCardVisible = !hidden }
        // «Abrir escritorio si toca», el widget o la Live Activity: a Enfoque (en horizontal, el escritorio).
        .onChange(of: desk.deskRequested) { tab = .focus }
        .onChange(of: timer.lastTransition) { _, new in
            guard let new, scenePhase == .active else { return }
            let intoBreak = new.next.isBreak
            guard new.endedStarter || AlertPreferences.alerts(intoBreak: intoBreak) else { return }
            if Preferences.phaseAlertsEnabled { PhaseAlertPlayer.shared.play(intoBreak: intoBreak) }
            if AlertPreferences.showsOverlay || new.endedStarter {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.3, bounce: 0.15)) {
                    transition = new
                }
            }
        }
        // Música de concentración o de descanso, si está configurada (solo con la app delante).
        .onChange(of: timer.state?.phase) { old, new in
            if scenePhase == .active { MusicLinks.phaseChanged(to: new, from: old) }
        }
        // Una sesión que empieza desde un bloque, un aviso o Siri se sigue en Enfoque.
        .onChange(of: timer.state?.sessionStart) { old, new in
            if new != nil, new != old { tab = .focus }
            // Al terminar: resumen de los mensajes que llegaron durante la sesión.
            if let old, new == nil {
                MessageTriage.summarize(since: old, context: PlanabyStore.container.mainContext)
                // «Has apuntado 4 tareas durante tu sesión».
                capture.sessionEnded(start: old)
            }
        }
        // Lo dictado a Siri ("Planifica con Planaby") se abre en el chat del plan.
        .onChange(of: inbox.pending, initial: true) { _, pending in
            if pending != nil { tab = .plan }
        }
        // El control del Centro de Control deja la petición en el App Group si no estaba la app.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { capture.consumePendingRequest() }
        }
        .task {
            PlanabyStore.backfillIdentifiers()
            capture.consumePendingRequest()
            // Las fases avanzan solas aunque no se toque nada.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                timer.reconcile()
            }
        }
    }

    private enum SheetKind { case comms, captures, composer }

    /// Hay otra hoja a la vista o esperando: nunca se abren dos a la vez.
    private func otherSheet(except kind: SheetKind) -> Bool {
        if leaveGuard.returned != nil || showsStuck || friction.request != nil { return true }
        if kind != .comms, comms.inboxRequested { return true }
        if kind != .captures, capture.inboxRequested { return true }
        if kind != .composer, capture.composer != nil, !isDesk { return true }
        return false
    }
}
