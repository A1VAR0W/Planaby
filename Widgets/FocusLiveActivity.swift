import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            LockScreenActivityView(context: context)
                .activityBackgroundTint(.black.opacity(0.88))
                .activitySystemActionForegroundColor(Theme.orange)
        } dynamicIsland: { context in
            let state = context.state
            let stale = context.isStale
            let tint = state.phase.tint
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PhaseRing(state: state, isStale: stale, showsSymbol: true)
                        .frame(width: 54, height: 54)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityClock(state: state, isStale: stale)
                        .font(Theme.clock(42))
                        .foregroundStyle(.white)
                        .frame(maxWidth: 140, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(text: stale ? "Completado" : state.phase.title, color: tint)
                        Text(stale ? "Siguiente: \(state.nextPhase.title)" : context.attributes.methodName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 12) {
                        PhaseBar(state: state, isStale: stale)
                        ActivityControls(state: state, isStale: stale)
                    }
                    .padding(.top, 6)
                }
            } compactLeading: {
                PhaseRing(state: state, isStale: stale, showsSymbol: false)
                    .frame(width: 20, height: 20)
            } compactTrailing: {
                ActivityClock(state: state, isStale: stale)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(tint)
                    .frame(maxWidth: 54)
            } minimal: {
                PhaseRing(state: state, isStale: stale, showsSymbol: false)
                    .frame(width: 20, height: 20)
            }
            .keylineTint(tint)
            .contentMargins(.horizontal, 14, for: .expanded)
        }
    }
}

private struct LockScreenActivityView: View {
    let context: ActivityViewContext<FocusActivityAttributes>

    var body: some View {
        let state = context.state
        let stale = context.isStale
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                PhaseRing(state: state, isStale: stale, showsSymbol: true)
                    .frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: stale ? "\(state.phase.title) completado" : state.phase.title, color: state.phase.tint)
                    Text(stale ? "Siguiente: \(state.nextPhase.title)" : context.attributes.methodName)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                ActivityClock(state: state, isStale: stale)
                    .font(Theme.clock(46))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 150, alignment: .trailing)
            }
            PhaseBar(state: state, isStale: stale)
            ActivityControls(state: state, isStale: stale)
        }
        .padding(18)
    }
}

/// Anillo de progreso naranja que avanza solo con el reloj del sistema.
private struct PhaseRing: View {
    let state: FocusActivityAttributes.ContentState
    let isStale: Bool
    let showsSymbol: Bool

    var body: some View {
        ZStack {
            if let range = state.range, state.pausedAt == nil, !isStale {
                ProgressView(timerInterval: range, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
            } else {
                ProgressView(value: isStale ? 1 : state.pausedProgress)
                    .progressViewStyle(.circular)
            }
            if showsSymbol {
                Image(systemName: isStale ? "checkmark" : state.phase.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(state.phase.tint)
            }
        }
        .tint(state.phase.tint)
    }
}

private struct PhaseBar: View {
    let state: FocusActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        Group {
            if let range = state.range, state.pausedAt == nil, !isStale {
                ProgressView(timerInterval: range, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            } else {
                ProgressView(value: isStale ? 1 : state.pausedProgress)
            }
        }
        .tint(state.phase.tint)
    }
}

private struct ActivityClock: View {
    let state: FocusActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if isStale {
            Text("Listo")
        } else if let paused = state.pausedClock {
            Text(paused).opacity(0.6)
        } else if let range = state.range {
            Text(timerInterval: range, countsDown: true)
                .multilineTextAlignment(.trailing)
        } else {
            Text(state.phaseStart, style: .timer)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Botones en forma de píldora: el principal en naranja con texto negro.
private struct ActivityControls: View {
    let state: FocusActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isStale {
                Button(intent: RefreshFocusIntent()) {
                    pill("Continuar", systemImage: "arrow.right")
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(.black)
            } else {
                Button(intent: TogglePauseIntent()) {
                    pill(state.pausedAt == nil ? "Pausa" : "Seguir", systemImage: state.pausedAt == nil ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(.black)

                Button(intent: SkipPhaseIntent()) {
                    Image(systemName: "forward.end.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.bordered)

                Button(intent: StopFocusIntent()) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.bordered)
            }
        }
        .buttonBorderShape(.capsule)
        .tint(state.phase.tint)
    }

    private func pill(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
    }
}
