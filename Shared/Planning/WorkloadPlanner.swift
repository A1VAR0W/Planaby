import Foundation

/// Franja disponible de un modo para repartir trabajo.
struct Availability: Codable, Equatable, Sendable {
    /// Días de la semana permitidos (1 = domingo … 7 = sábado, como `Calendar`).
    var weekdays: Set<Int>
    /// Minutos desde medianoche.
    var startMinute: Int
    var endMinute: Int
    var minBlockMinutes: Int
    var maxBlockMinutes: Int
    var breakMinutes: Int
    var dailyCapMinutes: Int

    static let work = Availability(
        weekdays: [2, 3, 4, 5, 6], startMinute: 9 * 60, endMinute: 18 * 60,
        minBlockMinutes: 30, maxBlockMinutes: 90, breakMinutes: 15, dailyCapMinutes: 6 * 60
    )

    static let personal = Availability(
        weekdays: [1, 2, 3, 4, 5, 6, 7], startMinute: 18 * 60, endMinute: 22 * 60,
        minBlockMinutes: 20, maxBlockMinutes: 60, breakMinutes: 10, dailyCapMinutes: 3 * 60
    )
}

/// Trabajo con fecha límite que hay que repartir en bloques.
struct WorkItem: Sendable {
    let id: UUID
    let deadline: Date
    let minutes: Int
    /// 0 baja … 2 alta; desempata entre fechas límite iguales.
    let priority: Int
    let availability: Availability
    /// Los bloques del mismo grupo (el modo) comparten el tope diario.
    let capGroup: String
}

struct PlannedBlock: Equatable, Sendable {
    let itemID: UUID
    let start: Date
    let end: Date

    var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
}

struct PlanResult: Sendable {
    var blocks: [PlannedBlock] = []
    /// Minutos que no caben antes de la fecha límite, por tarea.
    var shortfalls: [UUID: Int] = [:]
}

/// Planificador determinista: reparte las tareas en los huecos libres, primero la fecha límite
/// más cercana (EDF). Intenta repartir la carga entre los días disponibles y, si no basta,
/// rellena los huecos que queden lo antes posible.
struct WorkloadPlanner {
    var calendar: Calendar = .current
    /// Los bloques empiezan en múltiplos de este número de minutos.
    var granularity = 5

    func plan(_ items: [WorkItem], busy: [DateInterval], from now: Date) -> PlanResult {
        var result = PlanResult()
        var occupied = busy
        var usedPerDay: [String: Int] = [:]
        let earliest = roundUp(now)

        let ordered = items.sorted {
            $0.deadline != $1.deadline ? $0.deadline < $1.deadline : $0.priority > $1.priority
        }

        for item in ordered {
            var remaining = item.minutes
            let days = dayStarts(from: earliest, to: item.deadline)

            // Primera pasada: carga repartida; segunda: lo que falte, lo antes posible.
            for spread in [true, false] where remaining > 0 {
                for (index, day) in days.enumerated() where remaining > 0 {
                    let rules = item.availability
                    guard rules.weekdays.contains(calendar.component(.weekday, from: day)) else { continue }
                    let capKey = "\(item.capGroup)|\(day.timeIntervalSinceReferenceDate)"
                    let capLeft = rules.dailyCapMinutes - usedPerDay[capKey, default: 0]
                    let wanted = spread
                        ? max(Int((Double(remaining) / Double(days.count - index)).rounded(.up)), min(remaining, rules.minBlockMinutes))
                        : remaining
                    var quota = min(wanted, capLeft, remaining)
                    guard quota > 0 else { continue }

                    guard let windowStart = calendar.date(byAdding: .minute, value: rules.startMinute, to: day),
                          let windowEnd = calendar.date(byAdding: .minute, value: rules.endMinute, to: day) else { continue }
                    let start = max(windowStart, earliest)
                    let end = min(windowEnd, item.deadline)
                    guard start < end else { continue }

                    let padding = TimeInterval(rules.breakMinutes * 60)
                    let blocked = occupied.map {
                        DateInterval(start: $0.start.addingTimeInterval(-padding), end: $0.end.addingTimeInterval(padding))
                    }

                    for slot in Self.subtract(blocked, from: DateInterval(start: start, end: end)) where quota > 0 {
                        var cursor = roundUp(slot.start)
                        while quota > 0 {
                            let available = Int(slot.end.timeIntervalSince(cursor) / 60)
                            let length = min(quota, rules.maxBlockMinutes, available)
                            // Un bloque nunca es más corto que el mínimo, salvo que sea lo último que queda.
                            guard length > 0, length >= min(rules.minBlockMinutes, remaining) else { break }
                            let blockEnd = cursor.addingTimeInterval(TimeInterval(length * 60))
                            result.blocks.append(PlannedBlock(itemID: item.id, start: cursor, end: blockEnd))
                            occupied.append(DateInterval(start: cursor, end: blockEnd))
                            usedPerDay[capKey, default: 0] += length
                            remaining -= length
                            quota -= length
                            cursor = roundUp(blockEnd.addingTimeInterval(padding))
                        }
                    }
                }
            }

            if remaining > 0 {
                result.shortfalls[item.id] = remaining
            }
        }

        result.blocks.sort { $0.start < $1.start }
        return result
    }

    // MARK: - Ayudas

    private func dayStarts(from start: Date, to end: Date) -> [Date] {
        var days: [Date] = []
        var day = calendar.startOfDay(for: start)
        while day < end {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    private func roundUp(_ date: Date) -> Date {
        let step = TimeInterval(granularity * 60)
        let value = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (value / step).rounded(.up) * step)
    }

    /// Partes de `interval` que no tocan ningún intervalo de `blocked`.
    static func subtract(_ blocked: [DateInterval], from interval: DateInterval) -> [DateInterval] {
        var free = [interval]
        for block in blocked.sorted(by: { $0.start < $1.start }) {
            free = free.flatMap { slot -> [DateInterval] in
                guard block.start < slot.end, block.end > slot.start else { return [slot] }
                var pieces: [DateInterval] = []
                if block.start > slot.start { pieces.append(DateInterval(start: slot.start, end: block.start)) }
                if block.end < slot.end { pieces.append(DateInterval(start: block.end, end: slot.end)) }
                return pieces
            }
        }
        return free
    }
}
