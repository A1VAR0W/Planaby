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
/// que la salida se autoriza al tocar la app dentro de Planaby. Desde ahí el tiempo sigue
/// corriendo, no llegan avisos de «vuelve» y al volver no se apunta nada.
enum AllowedApps {
    enum Keys {
        static let chosen = "allowedApps"
        static let custom = "allowedAppsCustom"
        static let limit = "allowedAppsLimit"
    }

    /// Minutos que se puede estar en una app permitida antes de que vuelvan los avisos. 0: sin límite.
    static let limitOptions = [5, 10, 15, 30, 60, 0]
    static let defaultLimit = 15

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

    /// Las elegidas, en el orden del catálogo, y después las añadidas a mano.
    static func chosen(defaults: UserDefaults = .standard) -> [AllowedApp] {
        let ids = Set((defaults.string(forKey: Keys.chosen) ?? "").split(separator: ",").map(String.init))
        return catalog.filter { ids.contains($0.id) } + custom(defaults: defaults)
    }

    static func custom(defaults: UserDefaults = .standard) -> [AllowedApp] {
        guard let data = defaults.data(forKey: Keys.custom) else { return [] }
        return (try? JSONDecoder().decode([AllowedApp].self, from: data)) ?? []
    }

    static func saveCustom(_ apps: [AllowedApp], defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(apps), forKey: Keys.custom)
    }

    static func limit(defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: Keys.limit) as? Int ?? defaultLimit
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
    /// - `authorized`: se salió tocando una app permitida.
    /// - `limit`: segundos que se puede estar en una app permitida (0 = sin límite). Lo que pase de
    ///   ahí cuenta como distracción, desde ese momento.
    static func judge(leftAt: Date, now: Date, grace: TimeInterval, authorized: Bool, limit: TimeInterval) -> LeaveVerdict {
        let away = now.timeIntervalSince(leftAt)
        guard away > 0 else { return .fine }
        if authorized {
            guard limit > 0, away >= limit + grace else { return .fine }
            return .distraction(seconds: away - limit, from: leftAt.addingTimeInterval(limit))
        }
        return away >= grace ? .distraction(seconds: away, from: leftAt) : .fine
    }
}
