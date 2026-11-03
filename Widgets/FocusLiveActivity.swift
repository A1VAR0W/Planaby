import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            LockScreenActivityView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(.black.opacity(0.88))
                .activitySystemActionForegroundColor(Theme.orange)
        } dynamicIsland: { context in
            let state = context.state
            let stale = context.isStale
            return DynamicIsland {
                // Arriba: anillo a la izquierda y fase a la derecha, a ambos lados de la cámara.
                DynamicIslandExpandedRegion(.leading) {
                    PhaseRing(state: state, isStale: stale)
                        .frame(width: 40, height: 40)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PhaseLabels(state: state, isStale: stale, alignment: .trailing)
                }
                // Abajo: el tiempo con espacio de sobra y los controles.
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .center, spacing: 10) {
                        ActivityClock(state: state, isStale: stale)
                            .font(Theme.clock(44))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ActivityControls(state: state, isStale: stale, style: .circles)
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                PhaseRing(state: state, isStale: stale, showsSymbol: false)
                    .frame(width: 20, height: 20)
            } compactTrailing: {
                ActivityClock(state: state, isStale: stale)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(state.phase.tint)
                    .lineLimit(1)
                    .frame(maxWidth: 56)
            } minimal: {
                PhaseRing(state: state, isStale: stale, showsSymbol: false)
                    .frame(width: 20, height: 20)
            }
            .keylineTint(state.phase.tint)
            .contentMargins(.horizontal, 16, for: .expanded)
        }
    }
}

private struct LockScreenActivityView: View {
    let state: FocusActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                PhaseRing(state: state, isStale: isStale)
                    .frame(width: 44, height: 44)
                PhaseLabels(state: state, isStale: isStale, alignment: .leading)
                Spacer(minLength: 8)
                ActivityClock(state: state, isStale: isStale)
                    .font(Theme.clock(44))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .layoutPriority(1)
            }
            ActivityControls(state: state, isStale: isStale, style: .pills)
        }
        .padding(16)
    }
}

private struct PhaseLabels: View {
    let state: FocusActivityAttributes.ContentState
    let isStale: Bool
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Eyebrow(text: isStale ? "Completado" : (state.pausedAt == nil ? state.phase.title : "En pausa"), color: state.phase.tint)
            Text(isStale ? "Ahora: \(state.nextPhase.title)" : state.methodName)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .lineLimit(1)
    }
}

/// Anillo de progreso que avanza solo con el reloj del sistema.
private struct PhaseRing: View {
    let state: FocusActivityAttributes.ContentState
    let isStale: Bool
    var showsSymbol = true

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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(state.phase.tint)
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
        } else {
            Text(state.phaseStart, style: .timer)
        }
    }
}

private struct ActivityControls: View {
    enum Style { case circles, pills }

    let state: FocusActivityAttributes.ContentState
    let isStale: Bool
    let style: Style

    var body: some View {
        HStack(spacing: 8) {
            if isStale {
                Button(intent: RefreshFocusIntent()) {
                    Label("Continuar", systemImage: "arrow.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: style == .pills ? .infinity : nil)
                        .padding(.horizontal, style == .circles ? 6 : 0)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .foregroundStyle(.black)
            } else {
                let paused = state.pausedAt != nil
                Button(intent: TogglePauseIntent()) {
                    if style == .pills {
                        Label(paused ? "Seguir" : "Pausa", systemImage: paused ? "play.fill" : "pause.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    } else {
                        icon(paused ? "play.fill" : "pause.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(style == .pills ? .capsule : .circle)
                .foregroundStyle(.black)
                .accessibilityLabel(paused ? "Reanudar" : "Pausar")

                Button(intent: SkipPhaseIntent()) {
                    icon(state.phase == .focus ? "cup.and.saucer.fill" : "flame.fill")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Siguiente fase")

                Button(intent: StopFocusIntent()) {
                    icon("xmark")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Terminar")
            }
        }
        .tint(state.phase.tint)
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 22, height: 22)
    }
}
