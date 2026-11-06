import AppIntents

/// Abre Planaby en el modo escritorio, sin comprobar nada (se mantiene para las automatizaciones ya creadas).
struct OpenDeskIntent: AppIntent {
    static let title: LocalizedStringResource = "Abrir modo escritorio"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DeskLauncher.shared.requestDesk()
        IntentLog.record(.desk, result: "Abierto sin comprobar")
        return .result()
    }
}

extension DeskTrigger: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Cuándo"
    static let caseDisplayRepresentations: [DeskTrigger: DisplayRepresentation] = [
        .charger: DisplayRepresentation(title: "Al conectar el cargador", image: .init(systemName: "bolt.fill")),
        .focusOn: DisplayRepresentation(title: "Al activar la Concentración", image: .init(systemName: "moon.fill")),
        .manual: DisplayRepresentation(title: "A mano", image: .init(systemName: "hand.tap.fill")),
    ]
}

/// Para las automatizaciones «Al conectar el cargador» y «Al activar la Concentración Trabajo»:
/// abre el modo escritorio solo si a la vez está activa la Concentración elegida, el iPhone carga y
/// está en horizontal. Si falta algo, no hace nada y el iPhone sigue como estaba (StandBy incluido).
/// No desbloquea el iPhone: con él bloqueado, iOS pide Face ID o el código para abrir la app.
struct OpenDeskIfReadyIntent: AppIntent {
    static let title: LocalizedStringResource = "Abrir escritorio si toca"
    static let description = IntentDescription(
        "Abre el modo escritorio de Planaby solo si está activa tu Concentración Trabajo, el iPhone se está cargando y está en horizontal. Si no, no hace nada."
    )
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @Parameter(title: "Cuándo", default: .charger)
    var trigger: DeskTrigger

    @Parameter(
        title: "Concentración actual",
        description: "Opcional: el resultado de «Obtener concentración actual». Si no se pasa, Planaby usa lo que dejó su filtro de Concentración."
    )
    var focusName: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Abrir escritorio si toca \(\.$trigger)") {
            \.$focusName
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let check = await DeskLauncher.shared.evaluate(trigger: trigger, focusName: focusName)
        guard check.decision == .open else { return .result(value: false) }
        DeskLauncher.shared.requestDesk()
        try await continueInForeground(alwaysConfirm: false)
        return .result(value: true)
    }
}

struct PlanabyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartFocusIntent(),
            phrases: [
                "Empieza a concentrarme con \(.applicationName)",
                "Concentración en \(.applicationName)",
            ],
            shortTitle: "Concentrarse",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: TogglePauseIntent(),
            phrases: ["Pausa \(.applicationName)", "Reanuda \(.applicationName)"],
            shortTitle: "Pausar o reanudar",
            systemImageName: "playpause.fill"
        )
        AppShortcut(
            intent: StopFocusIntent(),
            phrases: ["Termina la concentración en \(.applicationName)"],
            shortTitle: "Terminar",
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: AddToPlanIntent(),
            phrases: ["Planifica con \(.applicationName)", "Añade a mi plan de \(.applicationName)"],
            shortTitle: "Planificar",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: SetPlanModeIntent(),
            phrases: ["Cambia de modo en \(.applicationName)", "Modo \(\.$mode) en \(.applicationName)"],
            shortTitle: "Cambiar de modo",
            systemImageName: "briefcase.fill"
        )
        // Una acción por app, ya con su nombre: «Bloquear Instagram con Planaby».
        AppShortcut(
            intent: BlockAppIntent(),
            phrases: ["Bloquear \(\.$app) con \(.applicationName)", "Frenar \(\.$app) con \(.applicationName)"],
            shortTitle: "Bloquear app",
            systemImageName: "hand.raised.fill"
        )
        AppShortcut(
            intent: OpenDeskIntent(),
            phrases: ["Modo escritorio en \(.applicationName)"],
            shortTitle: "Modo escritorio",
            systemImageName: "rectangle.landscape.rotate"
        )
        AppShortcut(
            intent: OpenDeskIfReadyIntent(),
            phrases: ["Escritorio si toca en \(.applicationName)"],
            shortTitle: "Escritorio si toca",
            systemImageName: "bolt.horizontal.fill"
        )
        // La décima (el máximo de iOS): apuntar sin interrumpir la sesión.
        AppShortcut(
            intent: CaptureTaskIntent(),
            phrases: ["Captura una tarea en \(.applicationName)", "Apunta algo en \(.applicationName)", "Capturar tarea en \(.applicationName)"],
            shortTitle: "Captura rápida",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: FilterNotificationIntent(),
            phrases: ["Filtrar notificación con \(.applicationName)"],
            shortTitle: "Filtrar notificación",
            systemImageName: "bell.badge.fill"
        )
    }
}
