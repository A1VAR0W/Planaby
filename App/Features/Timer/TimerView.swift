import SwiftData
import SwiftUI

struct TimerView: View {
    @Environment(FocusTimer.self) private var timer
    @Environment(MethodLibrary.self) private var library
    @Environment(\.modelContext) private var modelContext
    @State private var showingMethods = false
    @State private var showingHistory = false

    var body: some View {
        Group {
            if let state = timer.state {
                ActiveTimerView(state: state, onStop: stop)
            } else {
                idleView
            }
        }
        .padding()
        .navigationTitle("Planaby")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Historial", systemImage: "chart.bar") { showingHistory = true }
            }
        }
        .sheet(isPresented: $showingMethods) {
            NavigationStack { MethodPickerView() }
        }
        .sheet(isPresented: $showingHistory) {
            NavigationStack { HistoryView() }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                timer.reconcile()
            }
        }
    }

    private var idleView: some View {
        VStack(spacing: 32) {
            Spacer()
            Button { showingMethods = true } label: {
                MethodCard(method: library.selected)
            }
            .buttonStyle(.plain)

            Button { timer.start(library.selected) } label: {
                Label("Empezar", systemImage: "play.fill")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
    }

    private func stop() {
        if let session = timer.stop() {
            modelContext.insert(FocusSessionRecord(session))
        }
    }
}

private struct ActiveTimerView: View {
    let state: TimerState
    let onStop: () -> Void
    @Environment(FocusTimer.self) private var timer

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 4) {
                Text(state.phase.title)
                    .font(.title2.bold())
                    .foregroundStyle(state.phase.tint)
                Text(state.method.name)
                    .foregroundStyle(.secondary)
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 20) {
                    ZStack {
                        ProgressRing(progress: state.progress(at: context.date), tint: state.phase.tint)
                        Text(clock(at: context.date))
                            .font(.system(size: 64, weight: .light, design: .rounded))
                            .monospacedDigit()
                    }
                    .frame(width: 280, height: 280)

                    Text("\(state.completedCycles) ciclos · \(Self.format(state.totalFocused(at: context.date))) concentrado")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 16) {
                Button(state.isPaused ? "Reanudar" : "Pausar", systemImage: state.isPaused ? "play.fill" : "pause.fill") {
                    if state.isPaused { timer.resume() } else { timer.pause() }
                }
                Button(skipTitle, systemImage: "forward.fill") { timer.skip() }
                Button("Terminar", systemImage: "stop.fill", role: .destructive, action: onStop)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .labelStyle(.iconOnly)
            Spacer()
        }
    }

    private var skipTitle: String {
        switch state.phase {
        case .focus: state.method.isOpenEnded ? "Descansar" : "Saltar"
        case .shortBreak, .longBreak: "Saltar descanso"
        }
    }

    private func clock(at date: Date) -> String {
        let seconds = state.remaining(at: date) ?? state.elapsed(at: date)
        return Duration.seconds(seconds.rounded(.up))
            .formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }

    static func format(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

struct MethodCard: View {
    let method: FocusMethod

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(method.name).font(.title2.bold())
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            Text(method.summary).foregroundStyle(.secondary)
            Text(method.detail).font(.footnote).foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: .rect(cornerRadius: 20))
    }
}

struct ProgressRing: View {
    let progress: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.15), lineWidth: 14)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
        }
    }
}

extension PhaseKind {
    var tint: Color {
        switch self {
        case .focus: .orange
        case .shortBreak: .green
        case .longBreak: .teal
        }
    }
}
