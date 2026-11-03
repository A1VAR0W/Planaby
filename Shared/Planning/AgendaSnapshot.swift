import Foundation

/// Un evento o bloque próximo del plan, tal como lo ve el widget.
struct AgendaItem: Codable, Hashable, Sendable {
    var title: String
    var start: Date
    var end: Date
    var modeRaw: String
    var kindRaw: String
    var isAllDay: Bool

    var mode: PlanMode { PlanMode(rawValue: modeRaw) ?? .personal }
    var kind: EventKind { EventKind(rawValue: kindRaw) ?? .event }
}

/// Lo próximo del plan para el widget. La app lo escribe en el App Group cada vez que cambia el
/// plan o el modo; el widget no abre la base de datos de la app.
enum AgendaSnapshot {
    private static let key = "agendaSnapshot"

    private struct Stored: Codable {
        var mode: String
        var items: [AgendaItem]
    }

    static func save(_ items: [AgendaItem], mode: PlanMode) {
        guard let data = try? JSONEncoder().encode(Stored(mode: mode.rawValue, items: items)) else { return }
        AppGroup.defaults.set(data, forKey: key)
    }

    static func load() -> (mode: PlanMode, items: [AgendaItem]) {
        guard let data = AppGroup.defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
            return (.personal, [])
        }
        return (PlanMode(rawValue: stored.mode) ?? .personal, stored.items)
    }
}
