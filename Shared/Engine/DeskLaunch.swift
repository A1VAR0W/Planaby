import Foundation

/// Qué automatización de Atajos ha llamado a «Abrir escritorio si toca».
enum DeskTrigger: String, Codable, Sendable, CaseIterable {
    /// «Al conectar el cargador» (automatización A).
    case charger
    /// «Al activar la Concentración Trabajo» (automatización B): la Concentración ya está activa.
    case focusOn
    /// A mano, desde la app Atajos, Siri o la prueba del tutorial.
    case manual
}

/// Por qué no se abre el modo escritorio (para el diagnóstico del tutorial).
enum DeskSkipReason: String, Codable, Sendable {
    case disabled, focusOff, notCharging, portrait, unknownOrientation

    var text: String {
        switch self {
        case .disabled: "La apertura automática está desactivada en Ajustes › Modo escritorio."
        case .focusOff: "La Concentración elegida no está activa (el plan Trabajo de Planaby no cuenta)."
        case .notCharging: "El iPhone no está cargando."
        case .portrait: "El iPhone está en vertical."
        case .unknownOrientation: "No se pudo saber la orientación (¿está plano sobre la mesa?)."
        }
    }
}

enum DeskLaunchDecision: Equatable, Sendable {
    case open
    case skip(DeskSkipReason)
}

/// Decide si «Abrir escritorio si toca» abre Planaby. Solo con las tres cosas a la vez:
/// la Concentración elegida del iPhone (no el plan Trabajo de Planaby), cargando y en horizontal.
///
/// | Concentración | Cargando | Horizontal | Resultado |
/// |---|---|---|---|
/// | sí | sí | sí | Abre el modo escritorio |
/// | sí | sí | no | No abre (al girarlo no hay disparador: widget o Live Activity) |
/// | sí | no | – | No abre |
/// | no | – | – | No abre, aunque el plan Trabajo de Planaby esté activo |
/// | se desactiva | – | – | No hace nada: no reabre ni cierra Planaby |
struct DeskLaunchInput: Equatable, Sendable {
    var enabled: Bool
    var trigger: DeskTrigger
    /// Nombre que pasa Atajos con «Obtener concentración actual» (vacío o nil si no hay ninguna).
    var currentFocusName: String?
    /// Concentración elegida en Ajustes (por defecto «Trabajo»).
    var configuredFocus: String
    /// Lo que dejó el filtro de Concentración de Planaby al activarse.
    var filterSaysActive: Bool
    /// nil si iOS no lo sabe.
    var charging: Bool?
    /// nil si la orientación no se pudo medir.
    var landscape: Bool?
}

enum DeskLaunchPolicy {
    static func decide(_ input: DeskLaunchInput) -> DeskLaunchDecision {
        guard input.enabled else { return .skip(.disabled) }
        guard focusIsActive(input) else { return .skip(.focusOff) }
        // Con el disparador del cargador se sabe que se acaba de conectar.
        let charging = input.charging ?? (input.trigger == .charger)
        guard charging else { return .skip(.notCharging) }
        guard let landscape = input.landscape else { return .skip(.unknownOrientation) }
        return landscape ? .open : .skip(.portrait)
    }

    static func focusIsActive(_ input: DeskLaunchInput) -> Bool {
        if input.trigger == .focusOn { return true }
        if let name = input.currentFocusName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return matches(name, input.configuredFocus)
        }
        return input.filterSaysActive
    }

    /// Orientación física a partir de la gravedad (Core Motion). nil si está casi plano o no está claro.
    static func landscape(fromGravityX x: Double, y: Double, z: Double) -> Bool? {
        if abs(z) > 0.8 { return nil }
        if abs(x) > abs(y) + 0.15 { return true }
        if abs(y) > abs(x) + 0.15 { return false }
        return nil
    }

    /// «Trabajo», «trabajo» o «Work» cuentan como la misma Concentración de trabajo.
    static func matches(_ current: String, _ configured: String) -> Bool {
        func fold(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let a = fold(current), b = fold(configured.isEmpty ? "Trabajo" : configured)
        if a == b { return true }
        let work: Set<String> = ["trabajo", "work"]
        return work.contains(a) && work.contains(b)
    }
}

/// Estado de la Concentración del iPhone tal como lo dejó el filtro de Planaby. Está separado del
/// plan Trabajo/Normal: activar el plan a mano no enciende esto.
enum SystemFocusState {
    private enum Keys {
        static let active = "systemFocusActive"
        static let desk = "systemFocusOpensDesk"
        static let since = "systemFocusSince"
        static let autoOpen = "deskAutoOpen"
        static let focusName = "deskFocusName"
    }

    static func set(active: Bool, opensDesk: Bool, now: Date = .now, defaults: UserDefaults = AppGroup.defaults) {
        defaults.set(active, forKey: Keys.active)
        defaults.set(opensDesk, forKey: Keys.desk)
        defaults.set(now, forKey: Keys.since)
    }

    /// La Concentración con el filtro de Planaby está activa y abre el escritorio.
    static func isActive(defaults: UserDefaults = AppGroup.defaults) -> Bool {
        isOn(defaults: defaults) && (defaults.object(forKey: Keys.desk) as? Bool ?? true)
    }

    /// La Concentración con el filtro de Planaby está activa (abra o no el escritorio).
    static func isOn(defaults: UserDefaults = AppGroup.defaults) -> Bool {
        defaults.bool(forKey: Keys.active)
    }

    static func since(defaults: UserDefaults = AppGroup.defaults) -> Date? {
        defaults.object(forKey: Keys.since) as? Date
    }

    /// «Abrir al cargar en horizontal» (Ajustes › Modo escritorio).
    static func autoOpenEnabled(defaults: UserDefaults = AppGroup.defaults) -> Bool {
        defaults.object(forKey: Keys.autoOpen) as? Bool ?? true
    }

    static func setAutoOpen(_ value: Bool, defaults: UserDefaults = AppGroup.defaults) {
        defaults.set(value, forKey: Keys.autoOpen)
    }

    /// Nombre de la Concentración que abre el escritorio (por defecto «Trabajo»).
    static func focusName(defaults: UserDefaults = AppGroup.defaults) -> String {
        let name = defaults.string(forKey: Keys.focusName) ?? ""
        return name.isEmpty ? "Trabajo" : name
    }

    static func setFocusName(_ name: String, defaults: UserDefaults = AppGroup.defaults) {
        defaults.set(name.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.focusName)
    }
}

/// Última ejecución de cada App Intent, para el diagnóstico del tutorial. Un atajo cuenta como
/// configurado cuando se ha ejecutado de verdad, no por abrir la app Atajos.
enum IntentLog {
    enum Kind: String, CaseIterable, Sendable {
        /// «Filtrar notificación».
        case filter
        /// «Abrir modo escritorio» o «Abrir escritorio si toca» a mano.
        case desk
        /// «Abrir escritorio si toca» desde la automatización del cargador.
        case deskCharger
        /// «Abrir escritorio si toca» desde la automatización de la Concentración.
        case deskFocus
        /// El filtro de Concentración de Planaby.
        case focusFilter

        static func deskKind(for trigger: DeskTrigger) -> Kind {
            switch trigger {
            case .charger: .deskCharger
            case .focusOn: .deskFocus
            case .manual: .desk
            }
        }
    }

    struct Entry: Codable, Equatable, Sendable {
        var date: Date
        var result: String
    }

    static func record(_ kind: Kind, result: String, now: Date = .now, defaults: UserDefaults = AppGroup.defaults) {
        let entry = Entry(date: now, result: result)
        if let data = try? JSONEncoder().encode(entry) { defaults.set(data, forKey: "intentLog." + kind.rawValue) }
    }

    static func last(_ kind: Kind, defaults: UserDefaults = AppGroup.defaults) -> Entry? {
        defaults.data(forKey: "intentLog." + kind.rawValue).flatMap { try? JSONDecoder().decode(Entry.self, from: $0) }
    }
}
