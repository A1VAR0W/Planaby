import SwiftData
import SwiftUI

/// Pestaña Enfoque: preparar la sesión o seguirla mientras está en marcha.
struct FocusView: View {
    let onShowStats: () -> Void
    @Environment(FocusTimer.self) private var timer
    @State private var showingMethods = false

    var body: some View {
        ZStack {
            PhaseBackground(
                tint: timer.state?.phase.tint ?? Theme.focus,
                isBreak: timer.state?.phase.isBreak ?? false
            )
            if let state = timer.state {
                ActiveSessionView(state: state, onChangeMethod: { showingMethods = true })
                    .transition(.opacity)
            } else {
                IdleFocusView(onShowStats: onShowStats, onShowMethods: { showingMethods = true })
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.5), value: timer.state == nil)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .sheet(isPresented: $showingMethods) {
            NavigationStack { MethodPickerView() }
                .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Sin sesión

private struct IdleFocusView: View {
    let onShowStats: () -> Void
    let onShowMethods: () -> Void
    @Environment(FocusTimer.self) private var timer
    @Environment(MethodLibrary.self) private var library

    var body: some View {
        let method = library.selected
        VStack(spacing: 0) {
            TodayHeader(onTap: onShowStats)

            Spacer(minLength: Space.l)

            ZStack {
                Circle().stroke(Theme.orange.opacity(0.22), lineWidth: 6)
                VStack(spacing: Space.s) {
                    Eyebrow(text: "Listo para empezar", color: Theme.orange)
                    Text(Self.preview(of: method))
                        .font(Theme.clock(76))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text(method.detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(Space.xl)
            }
            .frame(maxWidth: 300, maxHeight: 300)
            .aspectRatio(1, contentMode: .fit)
            .accessibilityElement(children: .combine)
            .animation(.smooth, value: method.id)

            Spacer(minLength: Space.l)

            MethodStrip(onShowMethods: onShowMethods)
                .padding(.bottom, Space.m)

            Button {
                Task {
                    await NotificationAccess.requestIfNeeded()
                    timer.start(method)
                }
            } label: {
                Label("Empezar", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.orange)
            .controlSize(.large)
            .accessibilityHint("Empieza \(method.name)")
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.s)
        .padding(.bottom, Space.m)
        .sensoryFeedback(.selection, trigger: library.selectedID)
    }

    private static func preview(of method: FocusMethod) -> String {
        guard let minutes = method.focusMinutes else { return "0:00" }
        return TimerState.format(TimeInterval(minutes * 60))
    }
}

/// Saludo y lo concentrado hoy frente al objetivo; lleva a Progreso.
private struct TodayHeader: View {
    let onTap: () -> Void
    @Query(sort: \FocusSessionRecord.start, order: .reverse) private var sessions: [FocusSessionRecord]
    @AppStorage(Preferences.dailyGoalMinutes, store: AppGroup.defaults) private var goalMinutes = Preferences.defaultDailyGoal

    var body: some View {
        let today = sessions
            .filter { Calendar.current.isDateInToday($0.start) }
            .reduce(0) { $0 + $1.focusedSeconds }
        let goal = TimeInterval(goalMinutes * 60)
        let progress = goal > 0 ? min(1, today / goal) : 0

        Button(action: onTap) {
            HStack(spacing: Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.greeting(at: .now))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(today < 60
                         ? "Objetivo de hoy: \(FocusStats.format(goal))"
                         : "Hoy \(FocusStats.format(today)) de \(FocusStats.format(goal))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: Space.s)
                ZStack {
                    ProgressRing(progress: progress, tint: Theme.orange, lineWidth: 4, glows: false)
                    Image(systemName: progress >= 1 ? "checkmark" : "chart.bar.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.orange)
                }
                .frame(width: 44, height: 44)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hoy llevas \(FocusStats.format(today)) de \(FocusStats.format(goal))")
        .accessibilityHint("Abre tu progreso")
        .accessibilityAddTraits(.isButton)
    }

    private static func greeting(at date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 6..<13: "Buenos días"
        case 13..<21: "Buenas tardes"
        default: "Buenas noches"
        }
    }
}

/// Métodos a un toque, con acceso a la lista completa y a crear plantillas.
private struct MethodStrip: View {
    let onShowMethods: () -> Void
    @Environment(FocusTimer.self) private var timer
    @Environment(MethodLibrary.self) private var library

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                    ForEach(library.all) { method in
                        MethodChip(title: method.name, isSelected: method.id == library.selectedID) {
                            timer.select(method)
                        }
                        .id(method.id)
                        .accessibilityHint(method.detail)
                    }
                    MethodChip(title: "Más", systemImage: "slider.horizontal.3", isSelected: false, action: onShowMethods)
                        .accessibilityLabel("Todos los métodos")
                }
            }
            .contentMargins(.horizontal, Space.l, for: .scrollContent)
            .padding(.horizontal, -Space.l)
            .onAppear { proxy.scrollTo(library.selectedID, anchor: .center) }
        }
    }
}

// MARK: - Sesión en marcha

private struct ActiveSessionView: View {
    let state: TimerState
    let onChangeMethod: () -> Void
    @Environment(FocusTimer.self) private var timer
    @State private var confirmingStop = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 0) {
                Text("Concentrado \(FocusStats.format(state.totalFocused(at: context.date))) en esta sesión")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, Space.s)

                Spacer(minLength: Space.l)

                ZStack {
                    ProgressRing(progress: state.progress(at: context.date), tint: state.phase.tint)
                    VStack(spacing: Space.s) {
                        Label(state.isPaused ? "En pausa" : state.phase.title,
                              systemImage: state.isPaused ? "pause.fill" : state.phase.symbol)
                            .labelStyle(EyebrowLabelStyle(color: state.phase.tint))
                        Text(state.clockText(at: context.date))
                            .font(Theme.clock(72))
                            .foregroundStyle(.white.opacity(state.isPaused ? 0.6 : 1))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .contentTransition(.numericText(countsDown: true))
                        if state.phase.isBreak && !state.isPaused {
                            BreathingHint(tint: state.phase.tint)
                        } else {
                            Text(caption)
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .padding(Space.xl)
                }
                .frame(maxWidth: 300, maxHeight: 300)
                .aspectRatio(1, contentMode: .fit)
                .accessibilityElement(children: .combine)

                CycleDots(state: state)
                    .padding(.top, Space.l)
                Text(nextText)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, Space.s)

                Spacer(minLength: Space.l)

                Button(action: onChangeMethod) {
                    HStack(spacing: Space.xs + 2) {
                        Text(state.method.name)
                        Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: 32)
                    .padding(.horizontal, Space.xs)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Método: \(state.method.name)")
                .accessibilityHint("Cambia de método sin perder la sesión")

                HStack(alignment: .top, spacing: Space.xl) {
                    LabeledRoundButton(label: "Terminar", systemImage: "xmark") { confirmingStop = true }
                    LabeledRoundButton(
                        label: state.isPaused ? "Reanudar" : "Pausar",
                        systemImage: state.isPaused ? "play.fill" : "pause.fill",
                        prominent: true, tint: state.phase.tint
                    ) {
                        timer.togglePause()
                    }
                    LabeledRoundButton(label: skipTitle, systemImage: skipIcon) { timer.skip() }
                }
                .padding(.top, Space.l)
            }
            .padding(.horizontal, Space.l)
            .padding(.bottom, Space.m)
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: state.isPaused)
        .confirmationDialog("¿Terminar la sesión?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Terminar", role: .destructive) { timer.stop() }
        } message: {
            Text("Se guardará en tu progreso si llevas más de un minuto concentrado.")
        }
    }

    private var caption: String {
        if state.isPaused { return "Toca Reanudar para seguir" }
        guard let end = state.phaseEnd else { return "Sin límite de tiempo" }
        return "Hasta las \(end.formatted(date: .omitted, time: .shortened))"
    }

    private var nextText: String {
        if let next = state.upcomingTransitions(limit: 1).first, let duration = next.nextDuration {
            return "Después: \(next.next.title.lowercased()) de \(Int((duration / 60).rounded())) min"
        }
        return "Después: \(state.nextPhase.title.lowercased())"
    }

    private var skipTitle: String {
        switch state.phase {
        case .focus: state.method.isOpenEnded ? "Descansar" : "Saltar"
        case .shortBreak, .longBreak: "Volver"
        }
    }

    private var skipIcon: String {
        switch state.phase {
        case .focus: state.method.isOpenEnded ? "cup.and.saucer.fill" : "forward.end.fill"
        case .shortBreak, .longBreak: "flame.fill"
        }
    }
}

/// Etiqueta de fase en mayúsculas espaciadas con su símbolo.
private struct EyebrowLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.xs + 2) {
            configuration.icon.imageScale(.small)
            configuration.title.textCase(.uppercase).tracking(2.4)
        }
        .font(Theme.eyebrow)
        .foregroundStyle(color)
    }
}

/// Puntos de progreso hacia el descanso largo; si el método no tiene, el número de ciclos.
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
                        .frame(width: 8, height: 8)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(filled) de \(total) ciclos hasta el descanso largo")
        } else {
            Text(state.completedCycles == 1 ? "1 ciclo completado" : "\(state.completedCycles) ciclos completados")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.secondaryText)
        }
    }
}
