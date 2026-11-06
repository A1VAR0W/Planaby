import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Live Activity de la sesión con el lenguaje del modo escritorio (horizontal): negro, la fase como
/// etiqueta pequeña en el color de la fase, la cifra fina y grande, la tarea debajo, una línea de
/// progreso y los mismos botones redondos (terminar, pausa destacada y saltar). La pantalla
/// bloqueada y la Dynamic Island son dos tamaños del mismo diseño.
///
/// Estados: concentración, descanso (otro color, halo algo más vivo y un recordatorio para
/// recuperarse), en pausa (cifra atenuada y el porcentaje congelado), fase completada (cuando
/// termina sin la app delante: «Continuar») y sesión terminada (unos minutos, con acceso a Planaby).
///
/// Todo sale del único `TimerState` a través del `ContentState`; las cifras y el progreso avanzan
/// solos con los contadores del sistema, sin actualizaciones cada segundo. De las comunicaciones
/// solo se enseña el recuento, nunca el texto de un mensaje.
struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            LockScreenActivityView(look: ActivityLook(state: context.state, isStale: context.isStale))
                // Al tocarla se vuelve a Planaby (a Enfoque; en horizontal, el modo escritorio).
                .widgetURL(PlanabyLinks.desk)
                .activityBackgroundTint(.black.opacity(0.9))
                .activitySystemActionForegroundColor(Theme.orange)
        } dynamicIsland: { context in
            let look = ActivityLook(state: context.state, isStale: context.isStale)
            return DynamicIsland {
                // A los lados de la cámara: la marca y cuándo acaba la fase.
                DynamicIslandExpandedRegion(.leading) {
                    BrandMark(look: look)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    EndLabel(look: look)
                        .padding(.trailing, 4)
                }
                // Debajo: la esfera del escritorio en pequeño.
                DynamicIslandExpandedRegion(.bottom) {
                    IslandExpandedView(look: look)
                }
            } compactLeading: {
                PhaseRing(look: look)
                    .frame(width: 20, height: 20)
                    .padding(.leading, 2)
            } compactTrailing: {
                ActivityClock(look: look)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(look.tint)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .frame(maxWidth: 54, alignment: .trailing)
            } minimal: {
                PhaseRing(look: look)
                    .frame(width: 20, height: 20)
            }
            .keylineTint(look.tint)
            .contentMargins(.horizontal, 18, for: .expanded)
            .widgetURL(PlanabyLinks.desk)
        }
    }
}

// MARK: - Estado visual

/// Lo que se pinta, calculado una vez a partir del estado: así la isla y la pantalla bloqueada
/// dicen exactamente lo mismo.
private struct ActivityLook {
    let state: FocusActivityAttributes.ContentState
    let isStale: Bool

    var isFinished: Bool { state.isFinished }
    /// La fase terminó sin la app delante (sin push no puede pasar sola a la siguiente).
    var isCompleted: Bool { isStale && !isFinished }
    var isPaused: Bool { state.pausedAt != nil && !isFinished && !isStale }
    var isRunning: Bool { !isFinished && !isStale && !isPaused }
    var tint: Color { state.phase.tint }
    var isBreak: Bool { state.phase.isBreak && !isFinished }

    /// «CONCENTRACIÓN», «DESCANSO», «EN PAUSA · 40 %», «FASE COMPLETADA», «SESIÓN TERMINADA».
    var eyebrow: String {
        if isFinished { return "Sesión terminada" }
        if isPaused {
            return ActivityText.status(phase: state.phase, isPaused: true, progress: state.phaseEnd == nil ? nil : state.pausedProgress)
        }
        return ActivityText.eyebrow(phase: state.phase, isPaused: false, isFinished: isCompleted)
    }

    var symbol: String {
        if isFinished || isCompleted { return "checkmark" }
        if isPaused { return "pause.fill" }
        return state.phase.symbol
    }

    var detail: String {
        if isFinished { return "Buen trabajo. Toca para abrir Planaby" }
        return ActivityText.detail(
            phase: state.phase, task: state.taskTitle, method: state.methodName,
            isFinished: isCompleted, next: state.nextPhase
        )
    }

    /// «Luego: Descanso» (nada al terminar).
    var nextText: String? {
        guard !isFinished else { return nil }
        return isCompleted ? "Ahora: \(state.nextPhase.title)" : ActivityText.next(state.nextPhase)
    }

    /// Progreso congelado (pausa, fin) o nil si avanza solo con el reloj del sistema.
    var staticProgress: Double? {
        if isFinished || isCompleted { return 1 }
        if isPaused { return state.pausedProgress }
        return state.range == nil ? 0 : nil
    }
}

// MARK: - Pantalla bloqueada (también Centro de Notificaciones y StandBy)

private struct LockScreenActivityView: View {
    let look: ActivityLook
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    PhaseEyebrow(look: look)
                    ActivityClock(look: look)
                        .font(Theme.clock(50))
                        .foregroundStyle(.white.opacity(look.isPaused ? 0.55 : 1))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(look.detail)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                ActivityControls(look: look, diameter: 42)
            }
            VStack(alignment: .leading, spacing: 6) {
                PhaseLine(look: look)
                Footer(look: look)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        // El halo del escritorio, quieto: algo más vivo en los descansos y nunca con la pantalla
        // siempre activa (Always-On), donde iOS atenúa todo.
        .background(alignment: .topLeading) {
            if !isLuminanceReduced {
                RadialGradient(
                    colors: [look.tint.opacity(look.isBreak ? 0.32 : 0.2), .clear],
                    center: .topLeading, startRadius: 0, endRadius: 280
                )
            }
        }
    }
}

/// «Luego: Descanso · 2 pendientes» a la izquierda y «hasta 18:42» a la derecha.
private struct Footer: View {
    let look: ActivityLook

    var body: some View {
        HStack(spacing: 8) {
            if let next = look.nextText {
                Text(next)
            }
            // Solo el recuento: en la pantalla bloqueada nunca se enseña el texto de un mensaje.
            if let comms = look.state.commsText, look.isRunning || look.isPaused {
                HStack(spacing: 5) {
                    Circle()
                        .fill(look.tint)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(comms)
                }
            }
            Spacer(minLength: 4)
            EndLabel(look: look)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white.opacity(0.6))
        .lineLimit(1)
    }
}

// MARK: - Dynamic Island expandida

private struct IslandExpandedView: View {
    let look: ActivityLook

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    PhaseEyebrow(look: look)
                    ActivityClock(look: look)
                        .font(Theme.clock(44))
                        .foregroundStyle(.white.opacity(look.isPaused ? 0.55 : 1))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                ActivityControls(look: look, diameter: 38)
            }
            Text(look.detail)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
            HStack(spacing: 10) {
                PhaseLine(look: look)
                if let next = look.nextText {
                    Text(next)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - Piezas

/// El sol de Planaby y el nombre, en el color de la fase (arriba a la izquierda de la isla).
private struct BrandMark: View {
    let look: ActivityLook

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "sun.horizon.fill")
                .font(.system(size: 12, weight: .semibold))
            Text("Planaby")
                .font(.caption2.weight(.bold))
                .tracking(1.6)
                .textCase(.uppercase)
        }
        .foregroundStyle(look.tint)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// «hasta 18:42», «en pausa», «abierta» o la hora de fin de la sesión.
private struct EndLabel: View {
    let look: ActivityLook

    var body: some View {
        Group {
            if let endedAt = look.state.endedAt {
                Text("a las \(endedAt.formatted(date: .omitted, time: .shortened))")
            } else if look.isCompleted {
                Text("Toca «Continuar»")
            } else if look.isPaused {
                Text("En pausa")
            } else if let end = look.state.phaseEnd {
                Text("hasta \(end.formatted(date: .omitted, time: .shortened))")
            } else {
                Text("Sin límite")
            }
        }
        .font(.caption2.weight(.semibold).monospacedDigit())
        .foregroundStyle(.white.opacity(0.6))
        .lineLimit(1)
    }
}

/// La etiqueta de la fase, como en el escritorio, con su símbolo delante.
private struct PhaseEyebrow: View {
    let look: ActivityLook

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: look.symbol)
                .font(.system(size: 10, weight: .bold))
                .accessibilityHidden(true)
            Eyebrow(text: look.eyebrow, color: look.tint)
        }
        .foregroundStyle(look.tint)
        .lineLimit(1)
    }
}

/// La línea de progreso del escritorio: avanza sola con el reloj del sistema.
private struct PhaseLine: View {
    let look: ActivityLook

    var body: some View {
        Group {
            if let value = look.staticProgress {
                ProgressView(value: value)
            } else if let range = look.state.range {
                ProgressView(timerInterval: range, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            }
        }
        .progressViewStyle(.linear)
        .tint(look.tint)
        .accessibilityLabel("Progreso de la fase")
    }
}

/// Anillo de la isla compacta y mínima.
private struct PhaseRing: View {
    let look: ActivityLook

    var body: some View {
        Group {
            if let value = look.staticProgress {
                ProgressView(value: value)
            } else if let range = look.state.range {
                ProgressView(timerInterval: range, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            }
        }
        .progressViewStyle(.circular)
        .tint(look.tint)
        .overlay {
            if look.isFinished || look.isCompleted || look.isPaused {
                Image(systemName: look.symbol)
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(look.tint)
            }
        }
        .accessibilityLabel(look.eyebrow)
    }
}

private struct ActivityClock: View {
    let look: ActivityLook

    var body: some View {
        if look.isFinished {
            Text("Hecho")
        } else if look.isCompleted {
            Text(TimerState.format(0))
        } else if let paused = look.state.pausedClock {
            Text(paused)
        } else if let range = look.state.range {
            Text(timerInterval: range, countsDown: true)
        } else {
            Text(look.state.phaseStart, style: .timer)
        }
    }
}

/// Los botones redondos de la barra del escritorio: terminar y saltar en cristal oscuro, y la pausa
/// destacada en el color de la fase. Al completar la fase, «Continuar»; al terminar la sesión,
/// «Abrir» (solo vuelve a Planaby). Son intents reales del motor de la app: nada decorativo.
private struct ActivityControls: View {
    let look: ActivityLook
    let diameter: CGFloat

    var body: some View {
        if look.isFinished {
            // Toda la actividad ya abre Planaby (`widgetURL`); el botón lo hace evidente.
            if let url = PlanabyLinks.desk {
                Link(destination: url) {
                    capsule("Abrir", systemImage: "arrow.up.forward.app")
                }
                .accessibilityLabel("Abrir Planaby")
            }
        } else if look.isCompleted {
            Button(intent: RefreshFocusIntent()) {
                capsule("Continuar", systemImage: "arrow.right")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Continuar con \(look.state.nextPhase.title)")
        } else {
            HStack(spacing: 8) {
                Button(intent: StopFocusIntent()) {
                    circle("stop.fill", prominent: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Terminar")

                Button(intent: TogglePauseIntent()) {
                    circle(look.isPaused ? "play.fill" : "pause.fill", prominent: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(look.isPaused ? "Reanudar" : "Pausar")

                Button(intent: SkipPhaseIntent()) {
                    circle(look.state.phase == .focus ? "forward.end.fill" : "flame.fill", prominent: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(look.state.phase == .focus ? "Saltar al descanso" : "Volver a concentrarse")
            }
        }
    }

    private func circle(_ symbol: String, prominent: Bool) -> some View {
        let size = prominent ? diameter + 6 : diameter
        return Image(systemName: symbol)
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(prominent ? Color.black : Color.white)
            .frame(width: size, height: size)
            .background(prominent ? AnyShapeStyle(look.tint) : AnyShapeStyle(Color.white.opacity(0.14)), in: .circle)
            .overlay(Circle().strokeBorder(.white.opacity(prominent ? 0 : 0.1)))
    }

    private func capsule(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.black)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 16)
            .frame(minHeight: diameter)
            .background(look.tint, in: .capsule)
    }
}
