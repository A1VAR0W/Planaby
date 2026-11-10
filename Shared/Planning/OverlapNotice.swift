import Foundation

/// Tener varias cosas a la misma hora está permitido (es para organizarse): no se mueve ni se
/// impide nada. Solo se avisa de lo que ya hay ahí: en la revisión, en la agenda y con una
/// alerta al guardar («Ya tienes algo a esa hora», con «Guardar igualmente»).
enum OverlapNotice {
    /// Algo que se va a guardar y lo que ya hay a esa hora.
    struct Clash: Equatable, Sendable, Identifiable {
        var title: String
        var times: EventTimes
        var others: [EventConflict]
        var id: String { "\(title)-\(times.start.timeIntervalSinceReferenceDate)" }
    }

    /// Algo que se va a guardar: su nombre y cuándo ocurre (varias veces si se repite).
    struct Slot: Sendable {
        var title: String
        var intervals: [DateInterval]
    }

    /// Una fila de la agenda del día.
    struct Entry: Sendable {
        var id: String
        var title: String
        var interval: DateInterval
    }

    static let alertTitle = "Ya tienes algo a esa hora"

    /// Lo que coincide de cada cosa nueva con lo que ya había y con las otras nuevas. Cada pareja
    /// de nuevas se cuenta una sola vez (en la segunda), y de cada una basta la primera vez que
    /// coincide (un hábito diario no avisa de cada día).
    static func clashes(_ slots: [Slot], outside: [EventConflict]) -> [Clash] {
        var found: [Clash] = []
        for (index, slot) in slots.enumerated() {
            let earlier = slots.prefix(index).flatMap { other in
                other.intervals.map { EventConflict(title: other.title, interval: $0) }
            }
            for interval in slot.intervals {
                let times = EventTimes(start: interval.start, end: interval.end)
                let others = EventSchedule.conflicts(times, with: outside + earlier)
                guard !others.isEmpty else { continue }
                found.append(Clash(title: slot.title, times: times, others: others))
                break
            }
        }
        return found
    }

    /// «Ensayo» coincide con «Cena» (sábado 18:00–21:00).
    /// Hay dos «Actuación Natalia» a la vez (sábado 18:00–20:00).
    static func line(_ clash: Clash, now: Date = .now) -> String {
        let twins = clash.others.filter { same($0.title, clash.title) }
        let named = clash.others.filter { !same($0.title, clash.title) }
        guard let first = named.first else {
            let count = twins.count + 1
            return "Hay \(count == 2 ? "dos" : "\(count)") «\(clash.title)» a la vez (\(when(clash.times, now: now)))."
        }
        var titles = unique(named.map(\.title)).map { "«\($0)»" }
        if !twins.isEmpty { titles.append("otro «\(clash.title)»") }
        let times = EventTimes(start: first.interval.start, end: first.interval.end)
        return "«\(clash.title)» coincide con \(list(titles)) (\(when(times, now: now)))."
    }

    /// El texto de la alerta: qué coincide (como mucho cuatro cosas) y que se puede guardar igual.
    static func alertMessage(_ clashes: [Clash], now: Date = .now) -> String {
        var lines = clashes.prefix(4).map { line($0, now: now) }
        if clashes.count > 4 { lines.append("Y \(clashes.count - 4) más.") }
        lines.append(clashes.count == 1 && clashes[0].others.count == 1
            ? "Puedes guardarlo igualmente: los dos se quedan en tu calendario."
            : "Puedes guardarlo igualmente: todo se queda en tu calendario.")
        return lines.joined(separator: "\n")
    }

    /// Para la agenda: con qué coincide cada fila (por su identificador), en orden de hora.
    static func alongside(_ entries: [Entry]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for entry in entries {
            let times = EventTimes(start: entry.interval.start, end: entry.interval.end)
            let others = entries
                .filter { $0.id != entry.id }
                .map { EventConflict(title: $0.title, interval: $0.interval) }
            let found = EventSchedule.conflicts(times, with: others)
            if !found.isEmpty { result[entry.id] = unique(found.map(\.title)) }
        }
        return result
    }

    /// «A la vez que «Cena»», «A la vez que «Cena» y «Cine»».
    static func alongsideText(_ titles: [String]) -> String {
        "A la vez que \(list(titles.map { "«\($0)»" }))"
    }

    // MARK: - Piezas

    /// «sábado 18:00–21:00» (con la fecha si no es de esta semana).
    private static func when(_ times: EventTimes, now: Date) -> String {
        "\(ProposalFormat.dayName(times.start, now: now)) \(EventSchedule.rangeText(times))"
    }

    /// «A», «A y B», «A, B y C», «A, B y 2 más».
    private static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2, 3: return items.dropLast().joined(separator: ", ") + " y " + items[items.count - 1]
        default: return items.prefix(2).joined(separator: ", ") + " y \(items.count - 2) más"
        }
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespaces).compare(b.trimmingCharacters(in: .whitespaces), options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private static func unique(_ titles: [String]) -> [String] {
        var seen: [String] = []
        for title in titles where !seen.contains(where: { same($0, title) }) { seen.append(title) }
        return seen
    }
}
