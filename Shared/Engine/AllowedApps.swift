import Foundation

/// Una app a la que se puede ir en mitad de la concentración sin que cuente como distracción
/// (Teams, el correo, la calculadora…). Planaby la abre por su esquema de URL.
struct AllowedApp: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var symbol: String
    /// Esquema para abrirla («msteams://»). Vacío: no se puede abrir desde aquí, se sale a mano.
    var url: String

    init(id: String, name: String, symbol: String = "app.fill", url: String) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.url = url
    }
}

/// Apps permitidas: iOS no dice a qué app se va uno (haría falta Tiempo de uso, de pago), así
/// que la salida se autoriza al tocar la app dentro de Planaby. Eso da un pase (`AllowedPass`):
/// mientras dura, el tiempo sigue corriendo, no llegan avisos de «vuelve» y al volver no se
/// apunta nada. Planaby sabe que la salida estaba autorizada, no qué app se ha usado.
enum AllowedApps {
    enum Keys {
        /// Las elegidas en cada plan (Trabajo y Normal tienen cada uno las suyas).
        static func chosen(_ mode: PlanMode) -> String { "allowedApps.\(mode.rawValue)" }
        static let custom = "allowedAppsCustom"
        static let limit = "allowedAppsLimit"
        static let pass = "allowedAppsPass"
    }

    /// Minutos que dura el pase. 0: hasta terminar la sesión (solo si se elige expresamente).
    static let limitOptions = [5, 15, 30, 0]
    static let defaultLimit = 15
    /// En Trabajo vienen ya elegidas las de trabajar; en Normal, ninguna.
    static let workDefaults = ["teams", "outlook", "safari", "word", "notes"]

    static func limitTitle(_ minutes: Int) -> String {
        minutes == 0 ? "Hasta terminar la sesión" : "\(minutes) min"
    }

    /// Las que se ofrecen para elegir. El esquema solo abre la app.
    static let catalog: [AllowedApp] = [
        AllowedApp(id: "teams", name: "Teams", symbol: "person.3.fill", url: "msteams://"),
        AllowedApp(id: "outlook", name: "Outlook", symbol: "envelope.fill", url: "ms-outlook://"),
        AllowedApp(id: "mail", name: "Correo", symbol: "envelope.fill", url: "message://"),
        AllowedApp(id: "gmail", name: "Gmail", symbol: "envelope.badge.fill", url: "googlegmail://"),
        AllowedApp(id: "slack", name: "Slack", symbol: "number", url: "slack://"),
        AllowedApp(id: "whatsapp", name: "WhatsApp", symbol: "phone.bubble.fill", url: "whatsapp://"),
        AllowedApp(id: "messages", name: "Mensajes", symbol: "message.fill", url: "sms:"),
        AllowedApp(id: "telegram", name: "Telegram", symbol: "paperplane.fill", url: "tg://"),
        AllowedApp(id: "zoom", name: "Zoom", symbol: "video.fill", url: "zoomus://"),
        AllowedApp(id: "notes", name: "Notas", symbol: "note.text", url: "mobilenotes://"),
        AllowedApp(id: "files", name: "Archivos", symbol: "folder.fill", url: "shareddocuments://"),
        AllowedApp(id: "calendar", name: "Calendario", symbol: "calendar", url: "calshow://"),
        AllowedApp(id: "reminders", name: "Recordatorios", symbol: "checklist", url: "x-apple-reminderkit://"),
        AllowedApp(id: "safari", name: "Safari", symbol: "safari.fill", url: "x-web-search://"),
        AllowedApp(id: "chrome", name: "Chrome", symbol: "globe", url: "googlechrome://"),
        AllowedApp(id: "word", name: "Word", symbol: "doc.text.fill", url: "ms-word://"),
        AllowedApp(id: "excel", name: "Excel", symbol: "tablecells.fill", url: "ms-excel://"),
        AllowedApp(id: "powerpoint", name: "PowerPoint", symbol: "rectangle.on.rectangle.fill", url: "ms-powerpoint://"),
        AllowedApp(id: "onenote", name: "OneNote", symbol: "book.closed.fill", url: "onenote://"),
        AllowedApp(id: "drive", name: "Google Drive", symbol: "externaldrive.fill", url: "googledrive://"),
        AllowedApp(id: "docs", name: "Documentos", symbol: "doc.fill", url: "googledocs://"),
        AllowedApp(id: "notion", name: "Notion", symbol: "square.text.square.fill", url: "notion://"),
        AllowedApp(id: "obsidian", name: "Obsidian", symbol: "diamond.fill", url: "obsidian://"),
        AllowedApp(id: "github", name: "GitHub", symbol: "chevron.left.forwardslash.chevron.right", url: "github://"),
        AllowedApp(id: "chatgpt", name: "ChatGPT", symbol: "bubble.left.and.text.bubble.right.fill", url: "chatgpt://"),
        AllowedApp(id: "claude", name: "Claude", symbol: "sparkle", url: "claude://"),
        AllowedApp(id: "books", name: "Libros", symbol: "book.fill", url: "ibooks://"),
        AllowedApp(id: "kindle", name: "Kindle", symbol: "book.fill", url: "kindle://"),
        AllowedApp(id: "music", name: "Música", symbol: "music.note", url: "music://"),
        AllowedApp(id: "spotify", name: "Spotify", symbol: "music.note.list", url: "spotify://"),
        AllowedApp(id: "maps", name: "Mapas", symbol: "map.fill", url: "maps://"),
        AllowedApp(id: "shortcuts", name: "Atajos", symbol: "square.2.layers.3d.fill", url: "shortcuts://"),
    ]

    /// Los identificadores elegidos en un plan. Mientras no se toque, Trabajo trae los suyos.
    static func chosenIDs(_ mode: PlanMode, defaults: UserDefaults = .standard) -> Set<String> {
        guard let raw = defaults.string(forKey: Keys.chosen(mode)) else {
            return mode == .work ? Set(workDefaults) : []
        }
        return Set(raw.split(separator: ",").map(String.init))
    }

    static func setChosen(_ ids: Set<String>, for mode: PlanMode, defaults: UserDefaults = .standard) {
        defaults.set(ids.sorted().joined(separator: ","), forKey: Keys.chosen(mode))
    }

    /// Las elegidas en un plan, en el orden del catálogo, y después las añadidas a mano.
    static func chosen(_ mode: PlanMode, defaults: UserDefaults = .standard) -> [AllowedApp] {
        let ids = chosenIDs(mode, defaults: defaults)
        return (catalog + custom(defaults: defaults)).filter { ids.contains($0.id) }
    }

    static func custom(defaults: UserDefaults = .standard) -> [AllowedApp] {
        guard let data = defaults.data(forKey: Keys.custom) else { return [] }
        return (try? JSONDecoder().decode([AllowedApp].self, from: data)) ?? []
    }

    static func saveCustom(_ apps: [AllowedApp], defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(apps), forKey: Keys.custom)
    }

    static func limit(defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.object(forKey: Keys.limit) as? Int ?? defaultLimit
        return limitOptions.contains(stored) ? stored : defaultLimit
    }

    /// Una app escrita a mano: el nombre y, si se sabe, su esquema («miapp» → «miapp://»).
    /// nil si no hay nombre.
    static func makeCustom(name: String, scheme: String) -> AllowedApp? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        return AllowedApp(id: "custom-" + String(clean.lowercased().hashValueStable, radix: 36), name: clean, url: normalizedURL(scheme))
    }

    /// «miapp», «miapp:», «miapp://» o una dirección entera. Vacío si no sirve como esquema.
    static func normalizedURL(_ text: String) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "" }
        if clean.contains(":") { return URL(string: clean) == nil ? "" : clean }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+-."))
        guard clean.unicodeScalars.allSatisfy(allowed.contains), clean.first?.isLetter == true else { return "" }
        return clean + "://"
    }
}

/// Qué se hace al volver a Planaby tras salir en mitad de un bloque.
enum LeaveVerdict: Equatable, Sendable {
    /// No pasa nada: se volvió dentro del margen, o se estaba en una app permitida.
    case fine
    /// Distracción: los segundos que cuentan y desde cuándo (para el modo estricto).
    case distraction(seconds: TimeInterval, from: Date)

    /// - `grace`: margen normal al salir a cualquier app.
    /// - `pass`: el pase que había al salir, si lo había. Lo que pase de su final cuenta como
    ///   distracción, desde ese momento. Con un pase «hasta terminar la sesión» no cuenta nada.
    static func judge(leftAt: Date, now: Date, grace: TimeInterval, pass: AllowedPass?) -> LeaveVerdict {
        let away = now.timeIntervalSince(leftAt)
        guard away > 0 else { return .fine }
        if let pass, pass.isActive(at: leftAt) {
            guard let expiry = pass.expiry, now >= expiry.addingTimeInterval(grace) else { return .fine }
            return .distraction(seconds: now.timeIntervalSince(expiry), from: expiry)
        }
        return away >= grace ? .distraction(seconds: away, from: leftAt) : .fine
    }
}

/// Salida autorizada: se ha tocado una app permitida durante la concentración. Vale para la
/// sesión en la que se pidió y durante el rato elegido; se guarda para sobrevivir a que iOS
/// cierre Planaby mientras se está fuera.
struct AllowedPass: Codable, Equatable, Sendable {
    /// Lo que se tocó («Teams»). Es lo que se pidió, no una comprobación de la app usada.
    var app: String
    var grantedAt: Date
    /// 0: hasta terminar la sesión.
    var minutes: Int
    /// Comienzo de la sesión para la que vale.
    var session: Date

    var expiry: Date? {
        minutes > 0 ? grantedAt.addingTimeInterval(TimeInterval(minutes * 60)) : nil
    }

    func isActive(at now: Date) -> Bool {
        guard now >= grantedAt else { return false }
        return expiry.map { now < $0 } ?? true
    }

    /// Vale ahora y para esta sesión (otra sesión, o ninguna, lo anula).
    func isValid(at now: Date, session current: Date?) -> Bool {
        current == session && isActive(at: now)
    }

    func remaining(at now: Date) -> TimeInterval? {
        expiry.map { max(0, $0.timeIntervalSince(now)) }
    }

    static func load(defaults: UserDefaults = .standard) -> AllowedPass? {
        defaults.data(forKey: AllowedApps.Keys.pass).flatMap { try? JSONDecoder().decode(AllowedPass.self, from: $0) }
    }

    static func save(_ pass: AllowedPass?, defaults: UserDefaults = .standard) {
        if let pass, let data = try? JSONEncoder().encode(pass) {
            defaults.set(data, forKey: AllowedApps.Keys.pass)
        } else {
            defaults.removeObject(forKey: AllowedApps.Keys.pass)
        }
    }
}
