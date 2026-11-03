import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            LockScreenActivityView(context: context)
                .activitySystemActionForegroundColor(context.state.phase.tint)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(state.phase.title, systemImage: state.phase.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(state.phase.tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.methodName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.center) {
                    ActivityClock(state: state, isStale: context.isStale)
                        .font(Theme.clock(44))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityControls(state: state, isStale: context.isStale)
                }
            } compactLeading: {
                Image(systemName: state.phase.symbol)
                    .foregroundStyle(state.phase.tint)
            } compactTrailing: {
                ActivityClock(state: state, isStale: context.isStale)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(state.phase.tint)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: state.phase.symbol)
                    .foregroundStyle(state.phase.tint)
            }
            .keylineTint(state.phase.tint)
        }
    }
}

private struct LockScreenActivityView: View {
    let context: ActivityViewContext<FocusActivityAttributes>

    var body: some View {
        let state = context.state
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: context.isStale ? "\(state.phase.title) terminado" : state.phase.title, color: state.phase.tint)
                ActivityClock(state: state, isStale: context.isStale)
                    .font(Theme.clock(46))
                Text(context.isStale ? "Siguiente: \(state.nextPhase.title)" : context.attributes.methodName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ActivityControls(state: state, isStale: context.isStale)
        }
        .padding(20)
    }
}

private struct ActivityClock: View {
    let state: FocusActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if isStale {
            Text("0:00")
        } else if let paused = state.pausedClock {
            Text(paused)
        } else if let end = state.phaseEnd {
            Text(timerInterval: state.phaseStart...end, countsDown: true)
                .multilineTextAlignment(.center)
        } else {
            Text(state.phaseStart, style: .timer)
                .multilineTextAlignment(.center)
        }
    }
}

private struct ActivityControls: View {
    let state: FocusActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isStale {
                Button(intent: RefreshFocusIntent()) {
                    Label("Continuar", systemImage: "forward.end.fill")
                }
                .buttonBorderShape(.capsule)
            } else {
                Button(intent: TogglePauseIntent()) {
                    Image(systemName: state.pausedAt == nil ? "pause.fill" : "play.fill")
                }
                Button(intent: StopFocusIntent()) {
                    Image(systemName: "xmark")
                }
            }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .tint(state.phase.tint)
    }
}
