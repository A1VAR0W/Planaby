import AppIntents

/// Apps que se pueden bloquear. Cada una aparece en Atajos con su acción ya preparada
/// («Bloquear Instagram»), así no hay que escribir nada al crear la automatización.
enum BlockableApp: String, AppEnum, CaseIterable, Identifiable {
    case any, instagram, tiktok, youtube, x, whatsapp, facebook, threads, snapchat, reddit, telegram, discord, twitch, netflix, pinterest, linkedin

    var id: String { rawValue }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "App"
    static let caseDisplayRepresentations: [BlockableApp: DisplayRepresentation] = [
        .any: "la app que se abre",
        .instagram: "Instagram",
        .tiktok: "TikTok",
        .youtube: "YouTube",
        .x: "X",
        .whatsapp: "WhatsApp",
        .facebook: "Facebook",
        .threads: "Threads",
        .snapchat: "Snapchat",
        .reddit: "Reddit",
        .telegram: "Telegram",
        .discord: "Discord",
        .twitch: "Twitch",
        .netflix: "Netflix",
        .pinterest: "Pinterest",
        .linkedin: "LinkedIn",
    ]

    /// Nombre de la app; vacío para «la app que se abre».
    var name: String {
        switch self {
        case .any: ""
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .youtube: "YouTube"
        case .x: "X"
        case .whatsapp: "WhatsApp"
        case .facebook: "Facebook"
        case .threads: "Threads"
        case .snapchat: "Snapchat"
        case .reddit: "Reddit"
        case .telegram: "Telegram"
        case .discord: "Discord"
        case .twitch: "Twitch"
        case .netflix: "Netflix"
        case .pinterest: "Pinterest"
        case .linkedin: "LinkedIn"
        }
    }

    /// Las que se pueden elegir en Planaby (todas menos «la app que se abre»).
    static var choosable: [BlockableApp] { allCases.filter { $0 != .any } }
}

/// La acción única de la automatización «Al abrir una app»: si el bloqueo está activado y toca
/// frenar, abre Planaby con la pausa consciente; si no, no hace nada y la app se abre normal.
struct BlockAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Bloquear app"
    static let description = IntentDescription(
        "Úsala en una automatización «Al abrir una app». Si en Planaby tienes activado «Frenar al abrirlas», te frena unos segundos antes de usarla."
    )
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @Parameter(title: "App", default: .any)
    var app: BlockableApp

    static var parameterSummary: some ParameterSummary {
        Summary("Bloquear \(\.$app)")
    }

    init() {}

    init(app: BlockableApp) {
        self.app = app
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let guardian = FrictionGuard.shared
        // Aunque no toque frenar, queda constancia de que la automatización funciona.
        guardian.noteTrigger()
        let name = guardian.resolvedName(app.name)
        guard guardian.shouldPause(app: name) else { return .result() }
        guardian.present(app: name)
        try await continueInForeground(alwaysConfirm: false)
        return .result()
    }
}

/// Versión anterior en dos pasos (se mantiene para las automatizaciones ya creadas).
struct ShouldPauseIntent: AppIntent {
    static let title: LocalizedStringResource = "¿Toca pausa consciente?"
    static let description = IntentDescription("Devuelve Sí si Planaby debe frenarte antes de usar esta app. Es más sencillo usar «Bloquear app».")

    @Parameter(title: "App", description: "El nombre de la app, por ejemplo Instagram")
    var app: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        FrictionGuard.shared.noteTrigger()
        return .result(value: FrictionGuard.shared.shouldPause(app: app ?? ""))
    }
}

/// Abre Planaby con la pausa consciente (versión anterior en dos pasos).
struct MindfulPauseIntent: AppIntent {
    static let title: LocalizedStringResource = "Pausa consciente"
    static let description = IntentDescription("Abre Planaby para respirar unos segundos antes de usar una app que te distrae.")
    static let openAppWhenRun = true

    @Parameter(title: "App", description: "El nombre de la app, por ejemplo Instagram")
    var app: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        FrictionGuard.shared.present(app: app ?? "")
        return .result()
    }
}
