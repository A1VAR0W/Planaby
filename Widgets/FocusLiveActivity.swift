import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            LockScreenActivityView(state: context.state, isStale: context.isStale)
                // Al tocarla se vuelve a Planaby (a Enfoque; en horizontal, el modo escritorio).
                .widgetURL(PlanabyLinks.desk)
                .activityBackgroundTint(.black.opacity(0.88))
                .activitySystemActionForegroundColor(Theme.orange)
        } dynamicIsland: { context in
            let state = context.state
            let stale = context.isStale
            return DynamicIsland {
                // Arriba, a los lados de la cámara, solo piezas estrechas: anillo y tiempo.
                DynamicIslandExpandedRegion(.leading) {
                    PhaseRing(state: state, isStale: stale)
                        .frame(width: 34, height: 34)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityClock(state: state, isStale: stale)
                        .font(.system(size: 28, weight: .light, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: 104, minHeight: 34, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                // Abajo, a todo el ancho: fase y método en una línea y los controles.
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        PhaseLine(state: state, isStale: stale)
                        ActivityControls(state: state, isStale: stale, style: .bar)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
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
            .widgetURL(PlanabyLinks.desk)
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
                    .font(.system(size: 52, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .layoutPriority(1)
            }
            // Solo el recuento: en la pantalla bloqueada nunca se enseña el texto de un mensaje.
            if let comms = state.commsText, !isStale {
                HStack(spacing: 6) {
                    Circle()
                        .fill(state.phase.tint)
                        .frame(width: 6, height: 6)
                    Text(comms)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer(minLength: 0)
                }
                .lineLimit(1)
                .accessibilityElement(children: .combine)
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
            Text(isStale ? "Ahora: \(state.nextPhase.title)" : (state.taskTitle ?? state.methodName))
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .lineLimit(1)
    }
}

/// Fase y método en una sola línea, para la isla ampliada.
private struct PhaseLine: View {
    let state: FocusActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        HStack(spacing: 6) {
            Eyebrow(text: isStale ? "Completado" : (state.pausedAt == nil ? state.phase.title : "En pausa"), color: state.phase.tint)
                .layoutPriority(1)
            Text("·").foregroundStyle(Theme.secondaryText)
            Text(isStale ? "Ahora: \(state.nextPhase.title)" : state.methodName)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 0)
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
    /// `.bar`: tres botones de igual ancho, solo icono (isla). `.pills`: con texto (pantalla bloqueada).
    enum Style { case bar, pills }

    let state: FocusActivityAttributes.ContentState
    let isStale: Bool
    let style: Style

    var body: some View {
        HStack(spacing: 8) {
            if isStale {
                Button(intent: RefreshFocusIntent()) {
                    Label("Continuar", systemImage: "arrow.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(.black)
            } else {
                let paused = state.pausedAt != nil
                Button(intent: StopFocusIntent()) {
                    icon("stop.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Terminar")

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
                .foregroundStyle(.black)
                .accessibilityLabel(paused ? "Reanudar" : "Pausar")

                Button(intent: SkipPhaseIntent()) {
                    icon(state.phase == .focus ? "forward.end.fill" : "flame.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(state.phase == .focus ? "Saltar al descanso" : "Volver a concentrarse")
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.regular)
        .tint(state.phase.tint)
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 22)
    }
}
