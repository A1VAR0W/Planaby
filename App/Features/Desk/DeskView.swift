import Combine
import SwiftUI

/// Modo escritorio con el iPhone en horizontal.
///
/// En reposo solo hay una cifra grande sobre negro y una línea finísima de progreso. Un toque
/// muestra una única barra inferior (método, controles, tareas y atenuar) que se oculta sola; en pausa
/// o sin sesión se queda visible. Mientras carga la pantalla no se apaga, y de noche todo pasa
/// a rojo tenue, como StandBy. La lista de tareas, si se activa, queda a la derecha con checks.
struct DeskView: View {
    @Environment(FocusTimer.self) private var timer
    @Environment(MethodLibrary.self) private var library
    @AppStorage(Preferences.deskDimmed) private var dimmed = false
    @AppStorage(Preferences.deskNightMode) private var nightMode = true
    @AppStorage(Preferences.deskNightStart) private var nightStart = 22
    @AppStorage(Preferences.deskNightEnd) private var nightEnd = 7
    @AppStorage(Preferences.deskKeepAwake) private var keepAwake = true
    @AppStorage(Preferences.deskShowsTasks) private var showsTasks = false
    @State private var isCharging = false
    /// Hasta cuándo se ven los controles mientras la sesión corre.
    @State private var controlsUntil = Date.now.addingTimeInterval(DeskView.controlsTimeout)
    @State private var confirmingStop = false

    private static let controlsTimeout: TimeInterval = 6
    /// Margen extra al abrir el menú de métodos, para elegir con calma.
    private static let menuTimeout: TimeInterval = 15

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let night = isNight(context.date)
            let state = timer.state
            let tint = night ? Theme.night : (state?.phase.tint ?? Theme.orange)
            let ink = night ? Theme.night : Color.white
            let showControls = state == nil || state?.isPaused == true || context.date < controlsUntil

            ZStack {
                Color.black.ignoresSafeArea()
                BreathingGlow(tint: tint, strength: night || dimmed ? 0.08 : (state?.phase.isBreak == true ? 0.28 : 0.16))

                VStack(spacing: 0) {
                    HStack(spacing: Space.l) {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            face(state: state, date: context.date, tint: tint, ink: ink)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)

                        if showsTasks {
                            DeskTaskList(tint: tint, ink: ink, onInteract: reveal)
                                .frame(width: 300)
                                .padding(.top, Space.s)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }

                    ZStack(alignment: .bottom) {
                        if showControls {
                            bottomBar(state: state, tint: tint, ink: ink)
                                .transition(.opacity)
                        } else if let state, state.phaseEnd != nil {
                            ProgressLine(progress: state.progress(at: context.date), tint: tint)
                                .padding(.horizontal, Space.xxl)
                                .padding(.bottom, Space.s)
                                .transition(.opacity)
                        }
                    }
                    .frame(height: 72)
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.s)
                .animation(.smooth(duration: 0.4), value: showControls)
                .animation(.smooth(duration: 0.4), value: showsTasks)

                if dimmed {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
        }
        .contentShape(.rect)
        .onTapGesture { reveal() }
        .confirmationDialog("¿Terminar la sesión?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Terminar", role: .destructive) { timer.stop() }
        } message: {
            Text("Se guardará en tu progreso si llevas más de un minuto concentrado.")
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

    /// La cifra, con la fase encima y la hora debajo.
    private func face(state: TimerState?, date: Date, tint: Color, ink: Color) -> some View {
        VStack(spacing: Space.xs) {
            if let state {
                Eyebrow(text: state.isPaused ? "En pausa" : state.phase.title, color: tint)
                Text(state.clockText(at: date))
                    .font(Theme.clock(136))
                    .foregroundStyle(ink.opacity(state.isPaused ? 0.55 : 1))
                    .contentTransition(.numericText(countsDown: true))
                if state.phase.isBreak && !state.isPaused {
                    BreathingHint(tint: tint)
                } else {
                    Text(date, format: .dateTime.hour().minute())
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(ink.opacity(0.64))
                }
            } else {
                Text(date, format: .dateTime.hour().minute())
                    .font(Theme.clock(136))
                    .foregroundStyle(ink)
                Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.title3)
                    .foregroundStyle(ink.opacity(0.64))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }

    /// Una sola barra: método a la izquierda, acción principal en el centro y atenuar a la derecha.
    private func bottomBar(state: TimerState?, tint: Color, ink: Color) -> some View {
        ZStack {
            HStack(spacing: Space.s) {
                methodMenu(ink: ink)
                Spacer(minLength: Space.m)
                tasksButton
                dimButton
            }

            if let state {
                HStack(spacing: Space.l) {
                    RoundButton(label: "Terminar", systemImage: "stop.fill", compact: true) {
                        reveal()
                        confirmingStop = true
                    }
                    RoundButton(
                        label: state.isPaused ? "Reanudar" : "Pausar",
                        systemImage: state.isPaused ? "play.fill" : "pause.fill",
                        prominent: true, tint: tint, compact: true
                    ) {
                        reveal()
                        timer.togglePause()
                    }
                    RoundButton(label: state.skipLabel, systemImage: state.skipSymbol, compact: true) {
                        reveal()
                        timer.skip()
                    }
                }
            } else {
                Button {
                    Task {
                        await NotificationAccess.requestIfNeeded()
                        timer.start(library.selected)
                    }
                } label: {
                    Text("Empezar")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .padding(.horizontal, Space.xl)
                        .frame(minHeight: 36)
                }
                .buttonStyle(.glassProminent)
                .tint(tint)
                .controlSize(.large)
            }
        }
    }

    /// Cambiar de método sin salir del modo escritorio y sin perder la sesión.
    private func methodMenu(ink: Color) -> some View {
        Menu {
            Picker("Método", selection: methodSelection) {
                ForEach(library.all) { method in
                    Text(method.name).tag(method.id)
                }
            }
        } label: {
            HStack(spacing: Space.xs + 2) {
                Text(library.selected.name)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(ink.opacity(0.88))
            .frame(minHeight: 32)
            .padding(.horizontal, Space.xs)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .simultaneousGesture(TapGesture().onEnded {
            controlsUntil = .now.addingTimeInterval(Self.menuTimeout)
        })
        .accessibilityLabel("Método: \(library.selected.name)")
        .accessibilityHint("Cambia de método sin perder la sesión")
    }

    private var tasksButton: some View {
        Button {
            reveal()
            showsTasks.toggle()
        } label: {
            Image(systemName: showsTasks ? "checklist.checked" : "checklist")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(showsTasks ? "Ocultar tareas" : "Mostrar tareas")
    }

    private var dimButton: some View {
        Button {
            reveal()
            dimmed.toggle()
        } label: {
            Image(systemName: dimmed ? "sun.max.fill" : "moon.fill")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(dimmed ? "Brillo normal" : "Atenuar pantalla")
    }

    // MARK: - Ayudas

    private var methodSelection: Binding<String> {
        Binding(
            get: { library.selectedID },
            set: { id in
                guard let method = library.all.first(where: { $0.id == id }) else { return }
                reveal()
                timer.select(method)
            }
        )
    }

    /// Muestra los controles y reinicia la cuenta para ocultarlos.
    private func reveal() {
        controlsUntil = .now.addingTimeInterval(Self.controlsTimeout)
    }

    private func updateCharging() {
        let batteryState = UIDevice.current.batteryState
        isCharging = batteryState == .charging || batteryState == .full
        UIApplication.shared.isIdleTimerDisabled = keepAwake && isCharging
    }

    /// Franja nocturna de Ajustes; admite que cruce la medianoche (22 → 7).
    private func isNight(_ date: Date) -> Bool {
        guard nightMode, nightStart != nightEnd else { return false }
        let hour = Calendar.current.component(.hour, from: date)
        return nightStart < nightEnd
            ? (nightStart..<nightEnd).contains(hour)
            : hour >= nightStart || hour < nightEnd
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
        .accessibilityHidden(true)
    }
}
