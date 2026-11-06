import AppIntents
import SwiftUI
import UserNotifications

/// Pestaña Ajustes. Cada hito añadirá aquí su sección (planes y modos, bloqueo, mensajes, Spotify).
struct SettingsView: View {
    @Environment(FocusTimer.self) private var timer
    @Environment(MethodLibrary.self) private var library
    @Environment(ModeController.self) private var modes
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(Preferences.dailyGoalMinutes, store: AppGroup.defaults) private var goalMinutes = Preferences.defaultDailyGoal
    @AppStorage(Preferences.phaseAlerts, store: AppGroup.defaults) private var phaseAlerts = true
    @AppStorage(Preferences.deskKeepAwake) private var keepAwake = true
    @AppStorage(Preferences.deskDimmed) private var dimmed = false
    @AppStorage(Preferences.deskAutoMusic) private var deskAutoMusic = true
    @AppStorage(Preferences.deskNightMode) private var nightMode = true
    @AppStorage(Preferences.deskNightStart) private var nightStart = 22
    @AppStorage(Preferences.deskNightEnd) private var nightEnd = 7
    @AppStorage(LeaveGuard.Keys.enabled) private var leaveGuard = true
    @AppStorage(LeaveGuard.Keys.grace) private var leaveGrace = LeaveGuard.defaultGrace
    @AppStorage(LeaveGuard.Keys.strict) private var leaveStrict = false
    @AppStorage(MusicLinks.Keys.focus) private var focusMusic = ""
    @AppStorage(MusicLinks.Keys.rest) private var restMusic = ""
    @AppStorage(MusicLinks.Keys.autoOpen) private var musicAutoOpen = false

    @State private var notificationStatus: UNAuthorizationStatus?

    private static let updatesURL = URL(string: "https://chat-ink.tail552c89.ts.net/planaby/")!

    var body: some View {
        Form {
            focusSection
            planSection
            frictionSection
            musicSection
            messagesSection
            dataSection
            notificationsSection
            deskSection
            shortcutsSection
            aboutSection
        }
        .navigationTitle("Ajustes")
        .task { await refreshNotificationStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshNotificationStatus() } }
        }
        .onChange(of: phaseAlerts) {
            // Reprograma (o quita) los avisos de la sesión en marcha.
            timer.sync()
        }
    }

    // MARK: - Secciones

    private var focusSection: some View {
        Section {
            NavigationLink {
                MethodPickerView(dismissesOnSelect: false)
            } label: {
                LabeledContent {
                    Text(library.selected.name)
                } label: {
                    Label("Método", systemImage: "timer")
                }
            }
            Stepper(value: $goalMinutes, in: 15...600, step: 15) {
                LabeledContent {
                    Text(FocusStats.format(TimeInterval(goalMinutes * 60)))
                        .monospacedDigit()
                } label: {
                    Label("Objetivo diario", systemImage: "target")
                }
            }
        } header: {
            Text("Concentración")
        } footer: {
            Text("El objetivo marca el anillo de Enfoque y la línea de referencia en Progreso.")
        }
    }

    private var dataSection: some View {
        let mirror = CalendarMirror.shared
        return Section {
            Toggle(isOn: Binding(
                get: { mirror.isEnabled },
                set: { $0 ? mirror.enable() : mirror.disable() }
            )) {
                Label("Sincronizar con el Calendario de iOS", systemImage: "calendar")
            }
            NavigationLink {
                BackupsView()
            } label: {
                LabeledContent {
                    Text(BackupService.lastAutomaticBackup?.formatted(.relative(presentation: .named)) ?? "Ninguna")
                } label: {
                    Label("Copias de seguridad", systemImage: "externaldrive.badge.checkmark")
                }
            }
        } header: {
            Text("Tus datos")
        } footer: {
            if let error = mirror.lastError {
                Text(error).foregroundStyle(Theme.orange)
            } else if let note = PlanabyStore.recoveryNote {
                Text(note).foregroundStyle(Theme.orange)
            } else {
                Text("Tus eventos del Calendario del iPhone aparecen en Planaby (plan Normal; elige cuáles en Calendarios externos) y el plan Normal de Planaby se copia a un calendario «Planaby» del iPhone. El plan de Trabajo nunca sale de Planaby. Al desactivarlo se quita ese calendario. Planaby guarda todo al cerrarse y hace una copia de seguridad cada día.")
            }
        }
    }

    private var planSection: some View {
        Section {
            Picker(selection: Binding(get: { modes.mode }, set: { modes.set($0) })) {
                ForEach(PlanMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                Label("Modo", systemImage: modes.mode.symbol)
            }
            NavigationLink {
                PersonalProfileView()
            } label: {
                LabeledContent {
                    Text(PersonalProfile.shared.profile.isCompleted ? PersonalProfile.shared.bestHoursText : "Sin hacer")
                } label: {
                    Label("Tu ritmo", systemImage: "waveform.path.ecg")
                }
            }
            NavigationLink {
                ExternalCalendarsView()
            } label: {
                LabeledContent {
                    Text(externalSummary)
                } label: {
                    Label("Calendarios externos", systemImage: "calendar.badge.clock")
                }
            }
            ForEach(PlanMode.allCases) { mode in
                NavigationLink {
                    ModeScheduleView(mode: mode)
                } label: {
                    LabeledContent {
                        Text(Self.scheduleSummary(modes.availability(for: mode)))
                    } label: {
                        Label("Horario de \(mode.title)", systemImage: "clock")
                    }
                }
            }
        } header: {
            Text("Plan")
        } footer: {
            Text("En modo Normal se silencian los recordatorios de Trabajo. Para cambiar de modo con una Concentración del iPhone: Ajustes de iOS › Concentración › (p. ej. Trabajo) › Filtros › Planaby.")
        }
    }

    private var notificationsSection: some View {
        Section {
            switch notificationStatus {
            case .denied:
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                } label: {
                    Label("Activar en Ajustes de iOS", systemImage: "bell.slash")
                }
            case .notDetermined:
                Button {
                    Task {
                        await NotificationAccess.request()
                        await refreshNotificationStatus()
                    }
                } label: {
                    Label("Permitir notificaciones", systemImage: "bell")
                }
            case nil:
                Label("Comprobando permiso…", systemImage: "bell")
                    .foregroundStyle(Theme.secondaryText)
            default:
                LabeledContent {
                    Text("Permitidas")
                } label: {
                    Label("Permiso", systemImage: "bell.fill")
                }
            }
            Toggle(isOn: $phaseAlerts) {
                Label("Avisar al cambiar de fase", systemImage: "bell.badge")
            }
            .disabled(notificationStatus == .denied)
            NavigationLink {
                AlertSettingsView()
            } label: {
                Label("Avisos de concentración", systemImage: "speaker.wave.2")
            }
            .disabled(!phaseAlerts)
        } header: {
            Text("Notificaciones")
        } footer: {
            Text(notificationStatus == .denied
                 ? "Las notificaciones están desactivadas para Planaby en iOS."
                 : "Te avisa cuando termina un bloque o un descanso, aunque la app esté cerrada.")
        }
    }

    private var deskSection: some View {
        Section {
            Toggle(isOn: $keepAwake) {
                Label("Pantalla encendida al cargar", systemImage: "bolt.fill")
            }
            Toggle(isOn: $dimmed) {
                Label("Atenuar", systemImage: "sun.min")
            }
            Toggle(isOn: $nightMode) {
                Label("Tono rojo por la noche", systemImage: "moon.stars")
            }
            Toggle(isOn: $deskAutoMusic) {
                Label("Carátula al sonar música", systemImage: "music.note")
            }
            if nightMode {
                Picker("Desde", selection: $nightStart) {
                    ForEach(0..<24, id: \.self) { Text(Self.hourLabel($0)).tag($0) }
                }
                Picker("Hasta", selection: $nightEnd) {
                    ForEach(0..<24, id: \.self) { Text(Self.hourLabel($0)).tag($0) }
                }
            }
        } header: {
            Text("Modo escritorio")
        } footer: {
            Text("Gira el iPhone en horizontal en la pestaña Enfoque. Con el iPhone cargando, la pantalla no se apaga.")
        }
    }

    private var shortcutsSection: some View {
        Section {
            ShortcutsLink()
                .shortcutsLinkStyle(.automaticOutline)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)

            DisclosureGroup {
                VStack(alignment: .leading, spacing: Space.s) {
                    Step(number: 1, text: "Atajos › Automatización › Nueva › Cargador.")
                    Step(number: 2, text: "Elige «Se conecta» y «Ejecutar inmediatamente».")
                    Step(number: 3, text: "Añade la acción de Planaby «Abrir modo escritorio».")
                }
                .padding(.vertical, Space.xs)
                Button("Abrir Atajos") {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                }
            } label: {
                Label("Abrir al conectar el cargador", systemImage: "powerplug")
            }

            DisclosureGroup {
                Text("Centro de Control › Añadir un control › Planaby › «Concentración». También puedes asignarlo al botón de Acción en Ajustes de iOS.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.vertical, Space.xs)
            } label: {
                Label("Centro de Control y botón de Acción", systemImage: "switch.2")
            }
        } header: {
            Text("Atajos y Siri")
        } footer: {
            Text("Di «Concentración en Planaby» para empezar, o «Planifica con Planaby» para dictar algo a tu plan.")
        }
    }

    @AppStorage(FrictionGuard.Keys.lastTrigger) private var lastBlockTrigger: Double = 0
    @AppStorage(FrictionGuard.Keys.apps) private var blockedAppsRaw = ""

    private var blockSetupStatus: String {
        if lastBlockTrigger > 0 { return "Activo" }
        return blockedAppsRaw.isEmpty ? "Opcional" : "Falta Atajos"
    }

    private var frictionSection: some View {
        Section {
            Toggle(isOn: $leaveGuard) {
                Label("Avisar si salgo de Planaby", systemImage: "hand.raised.fill")
            }
            Picker(selection: $leaveGrace) {
                ForEach(LeaveGuard.graceOptions, id: \.self) { Text(LeaveGuard.minutes(TimeInterval($0))).tag($0) }
            } label: {
                Label("Margen", systemImage: "hourglass")
            }
            .disabled(!leaveGuard)
            Toggle(isOn: $leaveStrict) {
                Label("Modo estricto", systemImage: "lock.fill")
            }
            .disabled(!leaveGuard)
            NavigationLink {
                BlockSetupView()
            } label: {
                LabeledContent {
                    Text(blockSetupStatus)
                } label: {
                    Label("Frenar apps concretas", systemImage: "wand.and.stars")
                }
            }
        } header: {
            Text("Bloqueo")
        } footer: {
            Text("Sin configurar nada: mientras te concentras, si te vas a otra app más de \(LeaveGuard.minutes(TimeInterval(leaveGrace))) te llegan avisos para volver, y al volver ves cuánto rato estuviste fuera. Bloquear el iPhone no cuenta. " + (leaveStrict ? "Modo estricto: el rato fuera no cuenta como concentración y el bloque sigue donde lo dejaste." : "Con el modo estricto, el rato fuera no cuenta como concentración.") + " «Frenar apps concretas» es opcional y usa Atajos.")
        }
    }

    private var musicSection: some View {
        Section {
            NavigationLink {
                SpotifySettingsView()
            } label: {
                LabeledContent {
                    Text(SpotifyController.shared.isConnected ? (SpotifyController.shared.accountName ?? "Conectado") : "Sin conectar")
                } label: {
                    Label("Spotify", systemImage: "dot.radiowaves.left.and.right")
                }
            }
            LabeledContent {
                TextField("Enlace de la lista", text: $focusMusic)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .multilineTextAlignment(.trailing)
            } label: {
                Label("Concentración", systemImage: "headphones")
            }
            LabeledContent {
                TextField("Enlace de la lista", text: $restMusic)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .multilineTextAlignment(.trailing)
            } label: {
                Label("Descanso", systemImage: "cup.and.saucer")
            }
            Toggle(isOn: $musicAutoOpen) {
                Label("Reproducir al empezar cada fase", systemImage: "play.circle")
            }
            .disabled(!SpotifyController.shared.isConnected && MusicLinks.url(from: focusMusic) == nil && MusicLinks.url(from: restMusic) == nil)
        } header: {
            Text("Música")
        } footer: {
            Text("Con Spotify conectado, Planaby muestra lo que suena con su carátula (Enfoque y modo escritorio) y lo controla. Las listas: pega el enlace de una lista de Spotify (Compartir › Copiar enlace), Apple Music o YouTube Music. Con «Reproducir al empezar cada fase», al empezar una sesión o un descanso con Planaby abierta suena su lista; con Spotify conectado y sin lista, al concentrarte reanuda lo que tenías y al terminar la sesión lo pausa. En el modo escritorio, la carátula aparece sola cuando empieza a sonar (se cambia en Modo escritorio).")
        }
    }

    private var messagesSection: some View {
        Section {
            NavigationLink {
                MessageSettingsView()
            } label: {
                LabeledContent {
                    Text(MailInbox.shared.account?.username ?? "Solo Mensajes")
                } label: {
                    Label("Filtro de mensajes", systemImage: "tray.full")
                }
            }
        } footer: {
            Text("Apple Intelligence clasifica tus mensajes y correos en el iPhone y Planaby solo te interrumpe por lo urgente. La bandeja está en Enfoque.")
        }
    }

    private var aboutSection: some View {
        Section("Acerca de") {
            LabeledContent("Versión", value: Self.version)
            Link(destination: Self.updatesURL) {
                Label("Página de actualizaciones", systemImage: "arrow.down.circle")
            }
        }
    }

    // MARK: - Ayudas

    private func refreshNotificationStatus() async {
        notificationStatus = await NotificationAccess.status()
    }

    private var externalSummary: String {
        let external = ExternalCalendars.shared
        let count = external.subscriptions.count + (external.usesDeviceCalendars ? external.selection.count : 0)
        return count == 0 ? "Ninguno" : (count == 1 ? "1 en uso" : "\(count) en uso")
    }

    private static func scheduleSummary(_ availability: Availability) -> String {
        let start = availability.startMinute, end = availability.endMinute
        let text = String(format: "%d:%02d–%d:%02d", start / 60, start % 60, end / 60, end % 60)
        let special = availability.dayHours?.count ?? 0
        return special == 0 ? text : text + " · \(special) con otro horario"
    }

    private static func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

private struct Step: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text("\(number)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.black)
                .frame(width: 20, height: 20)
                .background(Theme.orange, in: .circle)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}
