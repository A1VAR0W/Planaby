import Combine
import SwiftUI

/// Modo escritorio con el iPhone en horizontal.
///
/// En reposo solo hay una cifra grande sobre negro y una línea finísima de progreso. Un toque
/// muestra una única barra inferior (método, controles, tareas y atenuar) que se oculta sola; en pausa
/// o sin sesión se queda visible. Mientras carga la pantalla no se apaga, y de noche todo pasa
/// a rojo tenue, como StandBy. La lista de tareas, si se activa, queda a la derecha con checks.
///
/// Comparte diseño y datos con los widgets de StandBy y la Live Activity (`DeskPresentation`):
/// tres disposiciones (concentración, descanso y sin sesión), la tarea, lo siguiente y un recuento
/// de comunicaciones sin textos de mensajes. Es la pantalla de Planaby en horizontal; el StandBy de
/// iOS es otra cosa y solo puede mostrar los widgets y la Live Activity.
struct DeskView: View {
    @Environment(FocusTimer.self) private var timer
    @Environment(MethodLibrary.self) private var library
    @State private var comms = CommsCenter.shared
    @AppStorage(Preferences.deskDimmed) private var dimmed = false
    @AppStorage(Preferences.deskNightMode) private var nightMode = true
    @AppStorage(Preferences.deskNightStart) private var nightStart = 22
    @AppStorage(Preferences.deskNightEnd) private var nightEnd = 7
    @AppStorage(Preferences.deskKeepAwake) private var keepAwake = true
    @AppStorage(Preferences.deskShowsTasks) private var showsTasks = false
    @AppStorage(Preferences.deskShowsMusic) private var showsMusic = false
    @AppStorage(Preferences.deskAutoMusic) private var autoMusic = true
    /// La carátula se puso sola al empezar a sonar la música.
    @State private var autoShown = false
    /// Se ocultó a mano mientras sonaba; vuelve a aparecer sola con la siguiente reproducción.
    @State private var hidesMusic = false
    @State private var isCharging = false
    /// Hasta cuándo se ven los controles mientras la sesión corre.
    @State private var controlsUntil = Date.now.addingTimeInterval(DeskView.controlsTimeout)
    @State private var confirmingStop = false
    /// Dictado en curso (añadir tarea por voz).
    @State private var voice: VoiceTaskFlow?

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
            let presentation = DeskPresentation(
                state: state, comms: comms.revision >= 0 ? CommsSnapshot.load() : .empty,
                agenda: AgendaSnapshot.load().items, now: context.date
            )

            ZStack {
                Color.black.ignoresSafeArea()
                // Pantalla OLED encendida mucho rato: el halo solo respira en los descansos y nunca de noche.
                BreathingGlow(
                    tint: tint, strength: night || dimmed ? 0.08 : (state?.phase.isBreak == true ? 0.28 : 0.16),
                    animated: state?.phase.isBreak == true && !night && !dimmed
                )

                VStack(spacing: 0) {
                    HStack(spacing: Space.l) {
                        if musicVisible {
                            // Modo carátula: lo que suena en Spotify, como en StandBy.
                            DeskNowPlaying(state: state, date: context.date, tint: tint, ink: ink, night: night)
                                .transition(.opacity)
                        } else {
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                face(state: state, date: context.date, tint: tint, ink: ink)
                                details(presentation, date: context.date, tint: tint, ink: ink)
                                    .padding(.top, Space.s)
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity)
                        }

                        if showsTasks && !musicVisible {
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
                .animation(.smooth(duration: 0.4), value: musicVisible)

                if dimmed {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
        }
        .contentShape(.rect)
        .onTapGesture { reveal() }
        // Reproductor automático: escucha a Spotify aunque la carátula no esté a la vista.
        .task(id: autoMusic && !musicVisible) {
            guard autoMusic, !musicVisible, SpotifyController.shared.isConnected else { return }
            await SpotifyController.shared.connectRemote()
            await SpotifyController.shared.watch()
        }
        .onAppear { updateAutoMusic(playing: SpotifyController.shared.isPlaying) }
        .onChange(of: SpotifyController.shared.isPlaying) { _, playing in updateAutoMusic(playing: playing) }
        .onChange(of: SpotifyController.shared.track == nil) { _, empty in
            if empty { autoShown = false }
        }
        .overlay {
            if let voice {
                ZStack {
                    Color.black.opacity(0.7)
                        .ignoresSafeArea()
                        .contentShape(.rect)
                        .onTapGesture {}
                    VoiceTaskPanel(flow: voice, tint: deskTint, ink: deskInk) {
                        if voice.phase == .saved { showsTasks = true }
                        self.voice = nil
                        reveal()
                    }
                    .frame(maxWidth: 520)
                    .background(Color(white: 0.08), in: .rect(cornerRadius: Theme.cardRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.hairline)
                    }
                    .padding(Space.l)
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: voice == nil)
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

    /// Debajo de la cifra: la tarea y lo siguiente, y el recuento de comunicaciones (sin textos).
    private func details(_ presentation: DeskPresentation, date: Date, tint: Color, ink: Color) -> some View {
        VStack(spacing: Space.xs) {
            switch presentation.layout {
            case .focus, .rest:
                if let task = presentation.taskTitle {
                    Text(task)
                        .font(.headline)
                        .foregroundStyle(ink.opacity(0.85))
                }
                // Una sola línea: la fase que viene y lo siguiente del plan.
                let next = [presentation.nextPhaseText, presentation.nextItemTitle.map { "Luego: \($0)" }]
                    .compactMap { $0 }.joined(separator: " · ")
                if !next.isEmpty {
                    Text(next)
                        .font(.footnote)
                        .foregroundStyle(ink.opacity(0.55))
                }
            case .idle:
                if let title = presentation.nextItemTitle, let start = presentation.nextItemStart {
                    Text(start > date ? "\(start.formatted(date: .omitted, time: .shortened)) · \(title)" : "Ahora · \(title)")
                        .font(.headline)
                        .foregroundStyle(ink.opacity(0.8))
                }
            }
            if let text = presentation.commsText {
                Button { comms.inboxRequested = true } label: {
                    HStack(spacing: Space.s) {
                        Circle()
                            .fill(tint)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                        Text(text)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(ink.opacity(0.75))
                    }
                    .frame(minHeight: 36)
                    .padding(.horizontal, Space.s)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Abre la bandeja")
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .multilineTextAlignment(.center)
    }

    /// La cifra, con la fase encima y la hora debajo.
    private func face(state: TimerState?, date: Date, tint: Color, ink: Color) -> some View {
        VStack(spacing: Space.xs) {
            if let state {
                Eyebrow(text: state.isPaused ? "En pausa" : state.phase.title, color: tint)
                Text(state.clockText(at: date))
                    .font(Theme.clock(120))
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
                    .font(Theme.clock(120))
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
    /// Tres columnas: las laterales se reparten el sitio que deja la central, así los controles
    /// de la sesión nunca se montan sobre los botones (el nombre del método se acorta si hace falta).
    private func bottomBar(state: TimerState?, tint: Color, ink: Color) -> some View {
        HStack(spacing: Space.m) {
            HStack(spacing: Space.s) {
                methodMenu(ink: ink)
                VoiceButton(compact: true) {
                    voice = VoiceTaskFlow()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let state {
                HStack(spacing: Space.m) {
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

            HStack(spacing: Space.s) {
                if SpotifyController.shared.isConnected { musicButton }
                tasksButton
                dimButton
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
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

    private var musicVisible: Bool { (showsMusic || autoShown) && SpotifyController.shared.isConnected }

    private func updateAutoMusic(playing: Bool) {
        if !playing {
            hidesMusic = false
        } else if autoMusic, !hidesMusic, SpotifyController.shared.track != nil {
            autoShown = true
        }
    }

    private var musicButton: some View {
        Button {
            reveal()
            if musicVisible {
                showsMusic = false
                autoShown = false
                hidesMusic = SpotifyController.shared.isPlaying
            } else {
                showsMusic = true
                hidesMusic = false
            }
        } label: {
            Image(systemName: musicVisible ? "music.note.list" : "music.note")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(musicVisible ? "Ocultar la música" : "Mostrar la música")
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

    /// Colores del panel de voz: rojo tenue de noche, como el resto del modo escritorio.
    private var deskTint: Color { isNight(.now) ? Theme.night : (timer.state?.phase.tint ?? Theme.orange) }
    private var deskInk: Color { isNight(.now) ? Theme.night : .white }

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
