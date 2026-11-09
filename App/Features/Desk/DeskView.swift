import Combine
import SwiftUI

/// Modo escritorio con el iPhone en horizontal.
///
/// En reposo solo hay una cifra grande sobre negro y una línea finísima de progreso. Un toque
/// muestra una única barra inferior (método, controles, tareas y atenuar) que se oculta sola; en pausa
/// o sin sesión se queda visible. Mientras carga la pantalla no se apaga, y de noche todo pasa
/// a rojo tenue, como StandBy. Música y tareas pueden verse a la vez: mitad y mitad.
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
    /// Cápsula vertical del volumen abierta (nace del botón del altavoz, a la derecha de la barra).
    @State private var showsVolume = false
    /// Captura rápida: el panel flota a la derecha y la cifra sigue a la vista.
    @State private var capture = CaptureCenter.shared
    /// La agenda y el recuento de comunicaciones se leen al cambiar (y una vez por minuto), no en
    /// cada repintado: son JSON del App Group.
    @State private var agenda = AgendaSnapshot.load().items
    @State private var commsSnapshot = CommsSnapshot.load()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let controlsTimeout: TimeInterval = 6
    /// Margen extra al abrir el menú de métodos, para elegir con calma.
    private static let menuTimeout: TimeInterval = 15

    var body: some View {
        // Puede pasar horas encendido cargando: cada segundo solo si corre una sesión o suena
        // música (la cuenta atrás y la barra de la canción); si no, al cambiar de minuto (el reloj).
        let tick = RefreshPolicy.tickInterval(
            sessionRunning: timer.state.map { !$0.isPaused } ?? false,
            musicPlaying: musicVisible && SpotifyController.shared.isPlaying
        )
        TimelineView(.periodic(from: RefreshPolicy.tickStart(interval: tick), by: tick)) { context in
            let night = isNight(context.date)
            let state = timer.state
            let tint = night ? Theme.night : (state?.phase.tint ?? Theme.orange)
            let ink = night ? Theme.night : Color.white
            let showControls = state == nil || state?.isPaused == true || showsVolume || context.date < controlsUntil
            let presentation = DeskPresentation(state: state, comms: commsSnapshot, agenda: agenda, now: context.date)

            ZStack {
                Color.black.ignoresSafeArea()
                // El halo respira (apenas cuesta: ver `BreathingGlow`), salvo de noche o atenuado,
                // cuando la pantalla debe quedar lo más oscura y quieta posible.
                BreathingGlow(
                    tint: tint, strength: night || dimmed ? 0.08 : (state?.phase.isBreak == true ? 0.28 : 0.16),
                    animated: !night && !dimmed
                )

                VStack(spacing: 0) {
                    panels(state: state, presentation: presentation, date: context.date, tint: tint, ink: ink, night: night)
                        // Con el volumen abierto, tocar fuera de él lo recoge (sin pulsar nada debajo).
                        .overlay {
                            if showsVolume {
                                Color.clear
                                    .contentShape(.rect)
                                    .onTapGesture { closeVolume() }
                                    .accessibilityHidden(true)
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
                    // La cápsula del volumen sube por encima de los paneles.
                    .zIndex(1)
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.s)
                .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: showControls)
                .animation(layoutAnimation, value: showsTasks)
                .animation(layoutAnimation, value: musicVisible)

                if dimmed {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            if showsVolume { closeVolume() }
            reveal()
        }
        // Nunca el volumen y la captura a la vez.
        .onChange(of: capture.composer?.id) { _, id in
            if id != nil { showsVolume = false }
        }
        // Reproductor automático: escucha a Spotify aunque la carátula no esté a la vista.
        .task(id: autoMusic && !musicVisible) {
            guard autoMusic, !musicVisible, SpotifyController.shared.isConnected else { return }
            await SpotifyController.shared.connectRemote()
            await SpotifyController.shared.watch()
        }
        .onAppear { updateAutoMusic(playing: SpotifyController.shared.isPlaying) }
        .onAppear(perform: reloadSnapshots)
        .onChange(of: comms.revision) { commsSnapshot = CommsSnapshot.load() }
        // Lo que llega de fuera (widgets, Atajos, recordatorios) se mira una vez por minuto.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                reloadSnapshots()
            }
        }
        .onChange(of: SpotifyController.shared.isPlaying) { _, playing in updateAutoMusic(playing: playing) }
        .onChange(of: SpotifyController.shared.track == nil) { _, empty in
            if empty { autoShown = false }
        }
        // Captura rápida en horizontal: tarjeta ancha arriba (el teclado ocupa la mitad de abajo),
        // dentro de las áreas seguras para no quedar bajo la Dynamic Island. La sesión sigue detrás.
        .overlay(alignment: .top) {
            if let request = capture.composer {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture {
                            // Cerrar tocando fuera no borra lo escrito: vuelve al abrirlo.
                            capture.close()
                            reveal()
                        }
                        .accessibilityHidden(true)
                    QuickCapturePanel(startsDictation: request.dictation, tint: deskTint, ink: deskInk, compact: true) {
                        capture.close()
                        // La barra vuelve un momento: se ve la marca del botón y se encuentra a la primera.
                        reveal()
                    }
                    .id(request.id)
                    .frame(maxWidth: 640)
                    .background(Color(white: 0.06).opacity(0.94), in: .rect(cornerRadius: Theme.cardRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.hairline)
                    }
                    .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
                    .padding(.horizontal, Space.l)
                    .padding(.top, Space.s)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.adaptive(Motion.emphasized, reduceMotion: reduceMotion), value: capture.composer?.id)
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
            // Fuera del modo escritorio no hace falta saber si está cargando.
            UIDevice.current.isBatteryMonitoringEnabled = false
        }
    }

    // MARK: - Partes

    /// Solo música, solo tareas o las dos a la vez (mitad y mitad del sitio que queda sobre la
    /// barra). Siempre la misma composición —panel principal y lista de tareas— y solo cambian
    /// los anchos: el reproductor no se vuelve a crear, la lista conserva su desplazamiento y el
    /// temporizador no se toca.
    private func panels(state: TimerState?, presentation: DeskPresentation, date: Date, tint: Color, ink: Color, night: Bool) -> some View {
        let music = musicVisible
        let tasks = showsTasks
        return GeometryReader { proxy in
            let widths = DeskPanels.widths(total: proxy.size.width, spacing: Space.m, music: music, tasks: tasks)
            let openWidth = DeskPanels.widths(total: proxy.size.width, spacing: Space.m, music: music, tasks: true).tasks
            HStack(alignment: .top, spacing: tasks ? Space.m : 0) {
                ZStack {
                    if music {
                        // Modo carátula: lo que suena en Spotify, como en StandBy. Con las tareas
                        // al lado pasa a columna (carátula y controles se recolocan sin cortes).
                        DeskNowPlaying(state: state, date: date, tint: tint, ink: ink, night: night, compact: tasks)
                            .padding(.top, tasks ? Space.s : 0)
                            .transition(panelTransition(edge: .leading))
                    } else {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            face(state: state, date: date, tint: tint, ink: ink)
                            details(presentation, date: date, tint: tint, ink: ink)
                                .padding(.top, Space.s)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                    }
                }
                .frame(width: widths.main, height: proxy.size.height)

                // La lista se queda montada aunque esté cerrada: se recoge hacia la derecha y
                // vuelve con lo que tenía (desplazamiento incluido).
                DeskTaskList(tint: tint, ink: ink, isOpen: tasks, onInteract: reveal)
                    .frame(width: openWidth)
                    .padding(.top, Space.s)
                    .frame(width: widths.tasks, height: proxy.size.height, alignment: .leading)
                    .clipped()
                    .opacity(tasks ? 1 : 0)
                    .allowsHitTesting(tasks)
                    .accessibilityHidden(!tasks)
            }
        }
    }

    private var layoutAnimation: Animation {
        Motion.adaptive(Motion.panel, reduceMotion: reduceMotion)
    }

    private func panelTransition(edge: Edge) -> AnyTransition {
        .panel(from: edge, reduceMotion: reduceMotion)
    }

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
    private func reloadSnapshots() {
        agenda = AgendaSnapshot.load().items
        commsSnapshot = CommsSnapshot.load()
    }

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
                QuickCaptureButton()
                    .simultaneousGesture(TapGesture().onEnded { reveal() })
                SectionsMenu(tint: ink.opacity(0.88))
                    .simultaneousGesture(TapGesture().onEnded {
                        controlsUntil = .now.addingTimeInterval(Self.menuTimeout)
                    })
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
                // En el borde derecho: el volumen real del iPhone, que se despliega hacia arriba.
                DeskVolumeControl(isOpen: $showsVolume, tint: tint, ink: ink, onInteract: reveal)
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
                .contentTransition(.symbolEffect(.replace))
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
                .contentTransition(.symbolEffect(.replace))
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
                .contentTransition(.symbolEffect(.replace))
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

    /// Colores del panel de captura: rojo tenue de noche, como el resto del modo escritorio.
    private var deskTint: Color { isNight(.now) ? Theme.night : (timer.state?.phase.tint ?? Theme.orange) }
    private var deskInk: Color { isNight(.now) ? Theme.night : .white }

    private func closeVolume() {
        withAnimation(DeskVolumeControl.animation(reduceMotion: reduceMotion)) { showsVolume = false }
        reveal()
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
