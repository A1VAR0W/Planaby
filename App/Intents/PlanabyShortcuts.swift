import AppIntents

/// Abre Planaby; pensado para la automatización "Al conectar el cargador" junto al modo escritorio.
struct OpenDeskIntent: AppIntent {
    static let title: LocalizedStringResource = "Abrir modo escritorio"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
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
        AppShortcut(
            intent: OpenDeskIntent(),
            phrases: ["Modo escritorio en \(.applicationName)"],
            shortTitle: "Modo escritorio",
            systemImageName: "rectangle.landscape.rotate"
        )
    }
}
