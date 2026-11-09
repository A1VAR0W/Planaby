import SwiftData
import SwiftUI

/// Pestaña Enfoque. Una sola acción principal por pantalla: la cifra manda y todo lo demás calla.
/// Mientras la sesión corre se oculta la barra de pestañas (al pausar vuelve); el menú de
/// secciones lleva a Plan, Progreso o Ajustes sin parar el temporizador.
struct FocusView: View {
    @Environment(FocusTimer.self) private var timer
    @State private var showingMethods = false
    @State private var comms = CommsCenter.shared
    @State private var showsPlayer = false
    @State private var showsStartNow = false
    @State private var showsContext = false
    @State private var showsStuck = false
    @State private var ratingStart: Date?
    @AppStorage("askFocusRating") private var asksRating = true
    @Query(filter: #Predicate<MessageItem> { !$0.isRead }) private var unread: [MessageItem]
    @AppStorage(MusicLinks.Keys.focus) private var focusMusic = ""
    @AppStorage(MusicLinks.Keys.rest) private var restMusic = ""

    var body: some View {
        let isRunning = timer.state.map { !$0.isPaused } ?? false

        ZStack {
            PhaseBackground(
                tint: timer.state?.phase.tint ?? Theme.focus,
                isBreak: timer.state?.phase.isBreak ?? false
            )
            if let state = timer.state {
                ActiveSessionView(
                    state: state, onChangeMethod: { showingMethods = true },
                    onContext: { showsContext = true }, onStuck: { showsStuck = true },
                    onStopped: { summary in
                        // Valoración opcional, solo en sesiones de al menos 10 minutos.
                        if asksRating, let summary, summary.focusedSeconds >= 600 { ratingStart = summary.start }
                    }
                )
                .transition(.opacity)
            } else {
                IdleFocusView(onChangeMethod: { showingMethods = true }, onStartNow: { showsStartNow = true })
                    .transition(.opacity)
            }
        }
        .animation(Motion.panel, value: timer.state == nil)
        // Captura rápida siempre a mano (también concentrándose, con la barra de pestañas oculta):
        // apuntar algo no pausa ni cambia la sesión. La bandeja solo con la sesión parada.
        .overlay(alignment: .topTrailing) {
            HStack(spacing: Space.s) {
                if !isRunning {
                    let pending = comms.items(for: .idle, from: unread).count
                    if !unread.isEmpty {
                        Button { comms.inboxRequested = true } label: {
                            Image(systemName: "tray.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .overlay(alignment: .topTrailing) {
                            if pending > 0 {
                                Text("\(pending)")
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 5)
                                    .frame(minWidth: 18, minHeight: 18)
                                    .background(Theme.orange, in: .capsule)
                                    .offset(x: 4, y: -4)
                                    .accessibilityHidden(true)
                            }
                        }
                        .accessibilityLabel("Bandeja de mensajes")
                        .accessibilityValue(pending == 1 ? "1 pendiente" : "\(pending) pendientes")
                        .transition(.opacity)
                    }
                }
                if timer.state != nil, isRunning {
                    SectionsMenu()
                        .transition(.opacity)
                }
                QuickCaptureButton()
            }
            .padding(Space.m)
        }
        // Música de la fase actual, si hay un enlace en Ajustes › Música.
        .overlay(alignment: .topLeading) {
            let phase = timer.state?.phase ?? .focus
            if SpotifyController.shared.isConnected {
                // Lo que suena en Spotify; al tocarlo, la carátula grande con los controles.
                MiniPlayer { showsPlayer = true }
                    .padding(Space.m)
            } else if MusicLinks.url(from: phase.isBreak ? restMusic : focusMusic) != nil {
                Button { MusicLinks.open(for: phase) } label: {
                    Image(systemName: "music.note")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .padding(Space.m)
                .accessibilityLabel(phase.isBreak ? "Música de descanso" : "Música para concentrarte")
            }
        }
        .sheet(isPresented: $showsPlayer) {
            NavigationStack { NowPlayingView() }
                .presentationDetents([.large])
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .toolbarVisibility(isRunning ? .hidden : .visible, for: .tabBar)
        .animation(Motion.standard, value: isRunning)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .sheet(isPresented: $showingMethods) {
            NavigationStack { MethodPickerView() }
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsStartNow) {
            NavigationStack { StartNowView() }
        }
        .sheet(isPresented: $showsContext) {
            NavigationStack { SessionContextSheet() }
        }
        .sheet(isPresented: $showsStuck) {
            NavigationStack { StuckSheet() }
        }
        .sheet(item: Binding(get: { ratingStart.map(RatingTarget.init) }, set: { ratingStart = $0?.start })) { target in
            SessionRatingSheet(sessionStart: target.start)
        }
    }
}

private struct RatingTarget: Identifiable {
    let start: Date
    var id: Date { start }
}

// MARK: - Sin sesión

private struct IdleFocusView: View {
    let onChangeMethod: () -> Void
    let onStartNow: () -> Void
    @Environment(FocusTimer.self) private var timer
    @Environment(MethodLibrary.self) private var library
    @Environment(ModeController.self) private var modes
    @Query(filter: #Predicate<PlanTask> { !$0.isDone }, sort: \PlanTask.deadline) private var tasks: [PlanTask]
    @Query private var events: [CalendarEvent]
    @State private var comms = CommsCenter.shared
    @State private var capture = CaptureCenter.shared

    var body: some View {
        let method = library.selected
        VStack(spacing: 0) {
            Spacer()

            Text(Self.preview(of: method))
                .font(Theme.clock(96))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .animation(Motion.standard, value: method.id)
                .accessibilityLabel("Duración \(Self.preview(of: method))")

            MethodButton(name: method.name, detail: method.detail, action: onChangeMethod)
                .padding(.top, Space.s)

            Spacer()

            // Una sola tarjeta: «Mientras estabas fuera» > lo apuntado en la sesión > sugerencia.
            if let away = comms.away, !comms.phaseCardVisible {
                AwayDigestCard(digest: away)
                    .padding(.bottom, Space.m)
            } else if let summary = capture.sessionSummary {
                CaptureSummaryCard(
                    title: summary.title,
                    primary: "Organizar ahora",
                    onPrimary: {
                        capture.dismissSessionSummary()
                        capture.inboxRequested = true
                    },
                    onLater: { capture.dismissSessionSummary() }
                )
                .padding(.bottom, Space.m)
            } else {
                AdaptiveSuggestionCard()
                    .padding(.bottom, Space.m)
            }

            let main = MainTask.pick(from: tasks, events: events, mode: modes.mode)
            if let main {
                VStack(spacing: 2) {
                    Text(main.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let step = main.firstStep {
                        Text(step)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.bottom, Space.s)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Lo siguiente: \(main.title)")
            }

            Button {
                Task {
                    await NotificationAccess.requestIfNeeded()
                    timer.start(method, task: main?.title, taskID: main?.stableID)
                }
            } label: {
                Text("Empezar")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.orange)
            .controlSize(.large)

            // Para cuando no apetece: cinco minutos y un primer paso.
            Button(action: onStartNow) {
                Label("Sin ganas: empezar 5 minutos", systemImage: "figure.walk")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .padding(.top, Space.s)
        }
        .padding(.horizontal, Space.l)
        .padding(.bottom, Space.l)
        .sensoryFeedback(.selection, trigger: library.selectedID)
    }

    private static func preview(of method: FocusMethod) -> String {
        guard let minutes = method.focusMinutes else { return "0:00" }
        return TimerState.format(TimeInterval(minutes * 60))
    }
}

// MARK: - Sesión en marcha

private struct ActiveSessionView: View {
    let state: TimerState
    let onChangeMethod: () -> Void
    let onContext: () -> Void
    let onStuck: () -> Void
    let onStopped: (CompletedSession?) -> Void
    @Environment(FocusTimer.self) private var timer
    @State private var confirmingStop = false

    private var nextStep: String? {
        let step = SessionContext.load(for: state.sessionStart)?.nextStep ?? ""
        return step.isEmpty ? nil : step
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if state.phase.isBreak {
                    VStack(spacing: Space.s) {
                        BreakCommsStrip()
                        CaptureBreakStrip(sessionStart: state.sessionStart)
                    }
                } else {
                    WorkCommsPill()
                }
            }
            .padding(.top, Space.xxl)
            .animation(Motion.panel, value: state.phase.isBreak)

            Spacer()

            if let task = state.taskTitle {
                Label(task, systemImage: "square.stack.3d.up.fill")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.l)
                    .padding(.bottom, nextStep == nil ? Space.l : Space.xs)
                    .accessibilityLabel("Tarea: \(task)")
            }
            if let nextStep {
                Text(nextStep)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.l)
                    .padding(.bottom, Space.l)
                    .accessibilityLabel("Siguiente paso: \(nextStep)")
            }

            // En pausa la cifra no cambia: basta con mirar cada minuto.
            let tick = RefreshPolicy.tickInterval(sessionRunning: !state.isPaused)
            TimelineView(.periodic(from: RefreshPolicy.tickStart(interval: tick), by: tick)) { context in
                ZStack {
                    ProgressRing(progress: state.progress(at: context.date), tint: state.phase.tint, lineWidth: 4)
                    VStack(spacing: Space.s) {
                        Eyebrow(text: state.isPaused ? "En pausa" : state.phase.title, color: state.phase.tint)
                        Text(state.clockText(at: context.date))
                            .font(Theme.clock(76))
                            .foregroundStyle(.white.opacity(state.isPaused ? 0.6 : 1))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .contentTransition(.numericText(countsDown: true))
                        if state.phase.isBreak && !state.isPaused {
                            BreathingHint(tint: state.phase.tint)
                        }
                    }
                    .padding(Space.xl)
                }
                .frame(maxWidth: 290, maxHeight: 290)
                .aspectRatio(1, contentMode: .fit)
                .accessibilityElement(children: .combine)
            }

            CycleDots(state: state)
                .padding(.top, Space.l)

            MethodButton(name: state.method.name, action: onChangeMethod)
                .padding(.top, Space.s)

            HStack(spacing: Space.l) {
                Button(action: onContext) {
                    Label(nextStep == nil ? "Siguiente paso" : "Contexto", systemImage: "text.alignleft")
                }
                Button(action: onStuck) {
                    Label("Me he atascado", systemImage: "questionmark.circle")
                }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.secondaryText)
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .padding(.top, Space.xs)

            Spacer()

            HStack(spacing: Space.xl) {
                RoundButton(label: "Terminar", systemImage: "stop.fill") { confirmingStop = true }
                RoundButton(
                    label: state.isPaused ? "Reanudar" : "Pausar",
                    systemImage: state.isPaused ? "play.fill" : "pause.fill",
                    prominent: true, tint: state.phase.tint
                ) {
                    timer.togglePause()
                }
                RoundButton(label: state.skipLabel, systemImage: state.skipSymbol) { timer.skip() }
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.bottom, Space.l)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: state.isPaused)
        .confirmationDialog("¿Terminar la sesión?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Terminar", role: .destructive) { onStopped(timer.stop()) }
        } message: {
            Text("Se guardará en tu progreso si llevas más de un minuto concentrado.")
        }
    }
}

// MARK: - Piezas

/// Nombre del método como texto tocable; abre la lista de métodos.
private struct MethodButton: View {
    let name: String
    var detail: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                HStack(spacing: Space.xs) {
                    Text(name)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.orange)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.horizontal, Space.m)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Método: \(name)")
        .accessibilityHint("Cambia de método")
    }
}

/// Puntos hacia el descanso largo; si el método no tiene, el número de ciclos.
private struct CycleDots: View {
    let state: TimerState

    var body: some View {
        let total = state.method.cyclesBeforeLongBreak
        if total > 0 {
            let filled = state.phase == .longBreak ? total : state.completedCycles % total
            HStack(spacing: Space.s) {
                ForEach(0..<total, id: \.self) { index in
                    Circle()
                        .fill(index < filled ? state.phase.tint : Color.white.opacity(0.16))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(filled) de \(total) ciclos hasta el descanso largo")
        } else if state.completedCycles > 0 {
            Text(state.completedCycles == 1 ? "1 ciclo" : "\(state.completedCycles) ciclos")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}
