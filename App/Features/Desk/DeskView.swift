import Combine
import SwiftUI

/// Modo escritorio con el iPhone en horizontal.
///
/// En reposo solo se ve la cifra grande sobre negro. Tocar la pantalla muestra los controles
/// (métodos, pausa, saltar, terminar, atenuar), que se ocultan solos a los pocos segundos.
/// En pausa o sin sesión los controles se quedan visibles. Mientras carga la pantalla no se
/// apaga, y de noche todo pasa a rojo tenue, como StandBy.
struct DeskView: View {
    @Environment(FocusTimer.self) private var timer
    @Environment(MethodLibrary.self) private var library
    @AppStorage("deskDimmed") private var dimmed = false
    @State private var isCharging = false
    @State private var lastInteraction = Date.now
    @State private var confirmingStop = false

    private static let controlsTimeout: TimeInterval = 6

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let night = Self.isNight(context.date)
            let state = timer.state
            let tint = night ? Theme.night : (state?.phase.tint ?? Theme.orange)
            let ink = night ? Theme.night : Color.white
            let showControls = state == nil || state?.isPaused == true
                || context.date.timeIntervalSince(lastInteraction) < Self.controlsTimeout

            ZStack {
                Color.black.ignoresSafeArea()
                BreathingGlow(tint: tint, strength: night || dimmed ? 0.08 : (state?.phase.isBreak == true ? 0.30 : 0.18))

                VStack(spacing: 0) {
                    topBar(tint: tint, ink: ink)
                        .opacity(showControls ? 1 : 0)
                        .allowsHitTesting(showControls)

                    Spacer(minLength: 0)
                    center(state: state, date: context.date, tint: tint, ink: ink, compact: showControls)
                    Spacer(minLength: 0)

                    ZStack(alignment: .bottom) {
                        if showControls {
                            controls(state: state, tint: tint)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else if let state, state.phaseEnd != nil {
                            ProgressLine(progress: state.progress(at: context.date), tint: tint)
                                .padding(.horizontal, 40)
                                .padding(.bottom, 8)
                                .transition(.opacity)
                        }
                    }
                    .frame(height: 72)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .animation(.smooth(duration: 0.45), value: showControls)

                if dimmed {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
        }
        .contentShape(.rect)
        .onTapGesture { lastInteraction = .now }
        .confirmationDialog("¿Terminar la sesión?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Terminar", role: .destructive) { timer.stop() }
        } message: {
            Text("Se guardará en el historial si llevas más de un minuto concentrado.")
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: timer.state?.isPaused)
        .sensoryFeedback(.selection, trigger: library.selectedID)
        .environment(\.colorScheme, .dark)
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            updateCharging()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            updateCharging()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // MARK: - Partes

    /// Métodos a la izquierda; atenuar y carga a la derecha.
    private func topBar(tint: Color, ink: Color) -> some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(library.all) { method in
                        MethodChip(method: method, isSelected: method.id == library.selectedID, tint: tint) {
                            interact { timer.select(method) }
                        }
                    }
                }
            }
            .scrollClipDisabled()

            if isCharging {
                Image(systemName: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(ink.opacity(0.4))
                    .accessibilityLabel("Cargando")
            }

            Button {
                interact { dimmed.toggle() }
            } label: {
                Image(systemName: dimmed ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(dimmed ? "Brillo normal" : "Atenuar pantalla")
        }
        .frame(height: 48)
    }

    @ViewBuilder
    private func center(state: TimerState?, date: Date, tint: Color, ink: Color, compact: Bool) -> some View {
        VStack(spacing: 4) {
            if let state {
                Eyebrow(text: state.isPaused ? "En pausa" : state.phase.title, color: tint)
                Text(state.clockText(at: date))
                    .font(Theme.clock(compact ? 110 : 150))
                    .foregroundStyle(ink.opacity(state.isPaused ? 0.55 : 1))
                    .contentTransition(.numericText(countsDown: true))
                if state.phase.isBreak && !state.isPaused {
                    BreathingHint(tint: tint)
                } else {
                    Text("\(date.formatted(date: .omitted, time: .shortened)) · \(state.method.name)")
                        .font(.footnote)
                        .foregroundStyle(ink.opacity(0.4))
                }
            } else {
                Text(date, format: .dateTime.hour().minute())
                    .font(Theme.clock(compact ? 120 : 150))
                    .foregroundStyle(ink)
                Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.title3)
                    .foregroundStyle(ink.opacity(0.4))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }

    @ViewBuilder
    private func controls(state: TimerState?, tint: Color) -> some View {
        if let state {
            HStack(spacing: 28) {
                RoundButton(label: "Terminar", systemImage: "xmark", compact: true) {
                    interact { confirmingStop = true }
                }
                RoundButton(
                    label: state.isPaused ? "Reanudar" : "Pausar",
                    systemImage: state.isPaused ? "play.fill" : "pause.fill",
                    prominent: true, tint: tint, compact: true
                ) {
                    interact { timer.togglePause() }
                }
                RoundButton(
                    label: state.phase == .focus ? "Pasar al descanso" : "Volver a concentrarse",
                    systemImage: state.phase == .focus ? "cup.and.saucer.fill" : "flame.fill",
                    compact: true
                ) {
                    interact { timer.skip() }
                }
            }
        } else {
            Button {
                interact { timer.start(library.selected) }
            } label: {
                Label("Empezar \(library.selected.name)", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.glassProminent)
            .tint(tint)
        }
    }

    // MARK: - Ayudas

    /// Toda acción reinicia la cuenta para ocultar los controles.
    private func interact(_ action: () -> Void) {
        lastInteraction = .now
        action()
    }

    private func updateCharging() {
        let batteryState = UIDevice.current.batteryState
        isCharging = batteryState == .charging || batteryState == .full
        UIApplication.shared.isIdleTimerDisabled = isCharging
    }

    private static func isNight(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 22 || hour < 7
    }
}

private struct MethodChip: View {
    let method: FocusMethod
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(method.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.85))
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(isSelected ? tint : Color.white.opacity(0.08), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Cambia el método sin perder la sesión")
    }
}

/// Línea de progreso finísima en la parte inferior.
private struct ProgressLine: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * progress)
                    .shadow(color: tint.opacity(0.6), radius: 6)
                    .animation(.linear(duration: 1), value: progress)
            }
        }
        .frame(height: 3)
    }
}
