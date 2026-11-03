import AppIntents
import SwiftUI
import WidgetKit

struct TimerEntry: TimelineEntry {
    let date: Date
    let state: TimerState?
    let method: FocusMethod
}

/// El widget calcula de antemano las próximas fases, así cambia de fase solo aunque la app esté cerrada.
struct TimerProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimerEntry {
        TimerEntry(date: .now, state: TimerState(method: .pomodoro, at: .now), method: .pomodoro)
    }

    func getSnapshot(in context: Context, completion: @escaping (TimerEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entries()[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimerEntry>) -> Void) {
        let entries = entries()
        completion(Timeline(entries: entries, policy: entries.count > 1 ? .atEnd : .never))
    }

    private func entries() -> [TimerEntry] {
        let now = Date.now
        let method = MethodLibrary.storedSelection()
        guard var state = TimerState.loadShared() else {
            return [TimerEntry(date: now, state: nil, method: method)]
        }
        state.catchUp(to: now)
        var entries = [TimerEntry(date: now, state: state, method: method)]
        for transition in state.upcomingTransitions(limit: 8) {
            var next = state
            next.catchUp(to: transition.date)
            entries.append(TimerEntry(date: transition.date, state: next, method: method))
        }
        return entries
    }
}

struct FocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FocusWidget", provider: TimerProvider()) { entry in
            FocusWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [(entry.state?.phase.tint ?? Theme.focus).opacity(0.18), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                }
        }
        .configurationDisplayName("Concentración")
        .description("Temporizador de Planaby en inicio, pantalla bloqueada y StandBy.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct FocusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TimerEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        default: system
        }
    }

    // MARK: - Inicio y StandBy

    @ViewBuilder
    private var system: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let state = entry.state {
                Eyebrow(text: state.phase.title, color: state.phase.tint)
                Spacer(minLength: 4)
                WidgetClock(state: state, date: entry.date)
                    .font(Theme.clock(family == .systemSmall ? 40 : 52))
                    .minimumScaleFactor(0.6)
                Text(state.method.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                HStack(spacing: 8) {
                    Button(intent: TogglePauseIntent()) {
                        Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                    }
                    if family != .systemSmall {
                        Button(intent: SkipPhaseIntent()) {
                            Image(systemName: "forward.end.fill")
                        }
                    }
                    Button(intent: StopFocusIntent()) {
                        Image(systemName: "xmark")
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .tint(state.phase.tint)
            } else {
                Eyebrow(text: "Planaby", color: Theme.focus)
                Spacer(minLength: 4)
                Text(entry.method.focusMinutes.map { TimerState.format(TimeInterval($0 * 60)) } ?? "0:00")
                    .font(Theme.clock(family == .systemSmall ? 40 : 52))
                Text(entry.method.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button(intent: StartFocusIntent()) {
                    Label("Empezar", systemImage: "play.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(Theme.focus)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Pantalla bloqueada

    @ViewBuilder
    private var circular: some View {
        if let state = entry.state, let end = state.phaseEnd, !state.isPaused {
            ProgressView(timerInterval: state.phaseStart...end, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                Image(systemName: state.phase.symbol)
            }
            .progressViewStyle(.circular)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: entry.state?.phase.symbol ?? "timer")
                    .font(.title3)
            }
        }
    }

    @ViewBuilder
    private var rectangular: some View {
        if let state = entry.state {
            VStack(alignment: .leading, spacing: 0) {
                Label(state.phase.title, systemImage: state.phase.symbol)
                    .font(.caption.weight(.semibold))
                WidgetClock(state: state, date: entry.date)
                    .font(.title.weight(.light).monospacedDigit())
                Text(state.method.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading) {
                Label("Planaby", systemImage: "timer")
                    .font(.caption.weight(.semibold))
                Text("Listo · \(entry.method.name)")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct WidgetClock: View {
    let state: TimerState
    let date: Date

    var body: some View {
        if state.isPaused {
            Text(state.clockText(at: date))
        } else if let end = state.phaseEnd {
            Text(timerInterval: state.phaseStart...end, countsDown: true)
        } else {
            Text(state.phaseStart, style: .timer)
        }
    }
}
