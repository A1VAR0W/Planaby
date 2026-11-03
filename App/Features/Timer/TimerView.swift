import SwiftUI

struct TimerView: View {
    @Environment(FocusTimer.self) private var timer
    @Environment(MethodLibrary.self) private var library
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showingMethods = false
    @State private var showingHistory = false

    /// En horizontal el iPhone pasa a modo escritorio.
    private var isDesk: Bool { verticalSizeClass == .compact }

    var body: some View {
        Group {
            if isDesk {
                DeskView()
            } else {
                Group {
                    if let state = timer.state {
                        ActiveTimerView(state: state) { timer.stop() }
                    } else {
                        idleView
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PhaseBackground(tint: timer.state?.phase.tint ?? Theme.focus))
            }
        }
        .toolbar(isDesk ? .hidden : .automatic, for: .navigationBar)
        .statusBarHidden(isDesk)
        .persistentSystemOverlays(isDesk ? .hidden : .automatic)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Historial", systemImage: "chart.bar.xaxis") { showingHistory = true }
            }
        }
        .sheet(isPresented: $showingMethods) {
            NavigationStack { MethodPickerView() }
        }
        .sheet(isPresented: $showingHistory) {
            NavigationStack { HistoryView() }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: timer.state?.phase)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                timer.reconcile()
            }
        }
    }

    private var idleView: some View {
        let method = library.selected
        return VStack(spacing: 0) {
            Spacer()
            Eyebrow(text: "Listo para concentrarte")
            Text(Self.preview(of: method))
                .font(Theme.clock(96))
                .padding(.top, 12)

            Button { showingMethods = true } label: {
                HStack(spacing: 6) {
                    Text(method.name)
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .buttonStyle(.glass)
            .padding(.top, 20)

            Text(method.detail)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.top, 12)
            Spacer()

            Button { timer.start(method) } label: {
                Text("Empezar")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.focus)
            .controlSize(.large)
        }
    }

    private static func preview(of method: FocusMethod) -> String {
        guard let minutes = method.focusMinutes else { return "0:00" }
        return Duration.seconds(minutes * 60)
            .formatted(.time(pattern: minutes >= 60 ? .hourMinuteSecond : .minuteSecond))
    }
}

private struct ActiveTimerView: View {
    let state: TimerState
    let onStop: () -> Void
    @Environment(FocusTimer.self) private var timer
    @State private var confirmingStop = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Eyebrow(text: state.phase.title, color: state.phase.tint)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                ZStack {
                    ProgressRing(progress: state.progress(at: context.date), tint: state.phase.tint)
                    VStack(spacing: 8) {
                        Text(state.clockText(at: context.date))
                            .font(Theme.clock(72))
                            .contentTransition(.numericText(countsDown: true))
                        Text(caption)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 300, height: 300)
            }
            .padding(.vertical, 32)

            CycleDots(state: state)
            Text(state.method.name)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.top, 14)
            Spacer()

            HStack(spacing: 28) {
                RoundButton(label: "Terminar", systemImage: "xmark") { confirmingStop = true }
                RoundButton(
                    label: state.isPaused ? "Reanudar" : "Pausar",
                    systemImage: state.isPaused ? "play.fill" : "pause.fill",
                    prominent: true, tint: state.phase.tint
                ) {
                    if state.isPaused { timer.resume() } else { timer.pause() }
                }
                RoundButton(label: skipTitle, systemImage: skipIcon) { timer.skip() }
            }
        }
        .confirmationDialog("¿Terminar la sesión?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Terminar", role: .destructive, action: onStop)
        } message: {
            Text("Se guardará en el historial si llevas más de un minuto concentrado.")
        }
    }

    private var caption: String {
        if state.isPaused { return "En pausa" }
        guard let end = state.phaseEnd else { return "Sin límite" }
        return "Hasta las \(end.formatted(date: .omitted, time: .shortened))"
    }

    private var skipTitle: String {
        switch state.phase {
        case .focus: state.method.isOpenEnded ? "Descansar" : "Saltar"
        case .shortBreak, .longBreak: "Saltar descanso"
        }
    }

    private var skipIcon: String {
        state.phase == .focus && state.method.isOpenEnded ? "cup.and.saucer" : "forward.end"
    }
}

/// Puntos de progreso hacia el descanso largo; si el método no tiene, el número de ciclos.
private struct CycleDots: View {
    let state: TimerState

    var body: some View {
        let total = state.method.cyclesBeforeLongBreak
        if total > 0 {
            let filled = state.phase == .longBreak ? total : state.completedCycles % total
            HStack(spacing: 8) {
                ForEach(0..<total, id: \.self) { index in
                    Circle()
                        .fill(index < filled ? state.phase.tint : Color.primary.opacity(0.12))
                        .frame(width: 7, height: 7)
                }
            }
        } else {
            Text(state.completedCycles == 1 ? "1 ciclo" : "\(state.completedCycles) ciclos")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}
