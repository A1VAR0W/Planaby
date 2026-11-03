import SwiftUI

/// Pestaña Enfoque. Una sola acción principal por pantalla: la cifra manda y todo lo demás calla.
/// Mientras la sesión corre se oculta la barra de pestañas; al pausar vuelve.
struct FocusView: View {
    @Environment(FocusTimer.self) private var timer
    @State private var showingMethods = false

    var body: some View {
        let isRunning = timer.state.map { !$0.isPaused } ?? false

        ZStack {
            PhaseBackground(
                tint: timer.state?.phase.tint ?? Theme.focus,
                isBreak: timer.state?.phase.isBreak ?? false
            )
            if let state = timer.state {
                ActiveSessionView(state: state, onChangeMethod: { showingMethods = true })
                    .transition(.opacity)
            } else {
                IdleFocusView(onChangeMethod: { showingMethods = true })
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.5), value: timer.state == nil)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .toolbarVisibility(isRunning ? .hidden : .visible, for: .tabBar)
        .animation(.smooth(duration: 0.35), value: isRunning)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .sheet(isPresented: $showingMethods) {
            NavigationStack { MethodPickerView() }
                .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Sin sesión

private struct IdleFocusView: View {
    let onChangeMethod: () -> Void
    @Environment(FocusTimer.self) private var timer
    @Environment(MethodLibrary.self) private var library

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
                .animation(.smooth, value: method.id)
                .accessibilityLabel("Duración \(Self.preview(of: method))")

            MethodButton(name: method.name, detail: method.detail, action: onChangeMethod)
                .padding(.top, Space.s)

            Spacer()

            Button {
                Task {
                    await NotificationAccess.requestIfNeeded()
                    timer.start(method)
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
    @Environment(FocusTimer.self) private var timer
    @State private var confirmingStop = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            if let task = state.taskTitle {
                Label(task, systemImage: "square.stack.3d.up.fill")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.l)
                    .padding(.bottom, Space.l)
                    .accessibilityLabel("Tarea: \(task)")
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
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
            Button("Terminar", role: .destructive) { timer.stop() }
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
