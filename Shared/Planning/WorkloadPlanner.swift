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
    /// Días con otro horario (p. ej. los viernes hasta las 15:00). Clave: día de la semana.
    var dayHours: [Int: DayHours]? = nil

    struct DayHours: Codable, Equatable, Sendable {
        var startMinute: Int
        var endMinute: Int
    }

    /// Horario de un día de la semana: el suyo propio o el habitual.
    func hours(onWeekday weekday: Int) -> DayHours {
        dayHours?[weekday] ?? DayHours(startMinute: startMinute, endMinute: endMinute)
    }

    /// Todos los horarios tienen el fin después del inicio.
    var isValid: Bool {
        endMinute > startMinute && (dayHours ?? [:]).values.allSatisfy { $0.endMinute > $0.startMinute }
    }

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
    /// 1 mecánica … 5 muy exigente. Lo exigente busca las horas de más energía.
    var difficulty = 3
    /// Orden elegido al reorganizar (0 primero). Si hay orden, manda sobre la fecha límite.
    var rank: Int?
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

/// Planificador determinista. Ordena por la prioridad elegida o, si no la hay, por fecha límite
/// más cercana (EDF); reparte la carga entre los días disponibles y, si no basta, rellena lo
/// que quede lo antes posible. Dentro de cada día, lo exigente va a las horas de más energía
/// de la persona y lo ligero deja esas horas libres.
struct WorkloadPlanner {
    var calendar: Calendar = .current
    /// Los bloques empiezan en múltiplos de este número de minutos.
    var granularity = 5
    /// Energía de 0 a 1 por hora del día (24 valores). Plana = sin preferencias.
    var energyByHour = Array(repeating: 0.5, count: 24)
    /// La persona prefiere empezar por lo difícil: lo ligero evita sus mejores horas.
    var hardFirst = true

    private enum Preference { case peak, valley, earliest }

    /// `used`: minutos ya ocupados por día y grupo (bloques que se quedan donde estaban), con la
    /// clave de `capKey(group:day:)`, para no pasar del tope diario al recolocar solo una parte.
    func plan(_ items: [WorkItem], busy: [DateInterval], from now: Date, used: [String: Int] = [:]) -> PlanResult {
        var result = PlanResult()
        var occupied = busy
        var usedPerDay = used
        let earliest = roundUp(now)

        let ordered = items.sorted { a, b in
            switch (a.rank, b.rank) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.deadline != b.deadline ? a.deadline < b.deadline : a.priority > b.priority
            }
        }

        for item in ordered {
            var remaining = item.minutes
            let days = dayStarts(from: earliest, to: item.deadline)
            let rules = item.availability
            let preference = preference(for: item)
            let padding = TimeInterval(rules.breakMinutes * 60)

            // Primera pasada: carga repartida; segunda: lo que falte, lo antes posible.
            for spread in [true, false] where remaining > 0 {
                for (index, day) in days.enumerated() where remaining > 0 {
                    let weekday = calendar.component(.weekday, from: day)
                    guard rules.weekdays.contains(weekday) else { continue }
                    let hours = rules.hours(onWeekday: weekday)
                    let capKey = Self.capKey(group: item.capGroup, day: day)
                    let capLeft = rules.dailyCapMinutes - usedPerDay[capKey, default: 0]
                    let wanted = spread
                        ? max(Int((Double(remaining) / Double(days.count - index)).rounded(.up)), min(remaining, rules.minBlockMinutes))
                        : remaining
                    var quota = min(wanted, capLeft, remaining)
                    guard quota > 0,
                          let windowStart = calendar.date(byAdding: .minute, value: hours.startMinute, to: day),
                          let windowEnd = calendar.date(byAdding: .minute, value: hours.endMinute, to: day) else { continue }
                    let start = max(windowStart, earliest)
                    let end = min(windowEnd, item.deadline)
                    guard start < end else { continue }

                    while quota > 0 {
                        let blocked = occupied.map {
                            DateInterval(start: $0.start.addingTimeInterval(-padding), end: $0.end.addingTimeInterval(padding))
                        }
                        let free = Self.subtract(blocked, from: DateInterval(start: start, end: end))
                        // Un bloque nunca es más corto que el mínimo, salvo que sea lo último que queda.
                        guard let choice = bestSlot(
                            in: free, target: min(quota, rules.maxBlockMinutes),
                            minimum: min(rules.minBlockMinutes, remaining), preference: preference
                        ) else { break }
                        let blockEnd = choice.start.addingTimeInterval(TimeInterval(choice.length * 60))
                        result.blocks.append(PlannedBlock(itemID: item.id, start: choice.start, end: blockEnd))
                        occupied.append(DateInterval(start: choice.start, end: blockEnd))
                        usedPerDay[capKey, default: 0] += choice.length
                        remaining -= choice.length
                        quota -= choice.length
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

    /// Energía media de un tramo, por cuartos de hora.
    func energy(from start: Date, minutes: Int) -> Double {
        let steps = max(1, minutes / 15)
        var total = 0.0
        for step in 0..<steps {
            let moment = start.addingTimeInterval(TimeInterval(step * 15 * 60))
            let hour = calendar.component(.hour, from: moment)
            total += energyByHour.indices.contains(hour) ? energyByHour[hour] : 0.5
        }
        return total / Double(steps)
    }

    // MARK: - Ayudas

    private func preference(for item: WorkItem) -> Preference {
        if item.difficulty >= 4 || (item.priority == 2 && item.difficulty >= 3) { return .peak }
        if item.difficulty <= 2 && hardFirst { return .valley }
        return .earliest
    }

    /// Mejor inicio para un bloque: el primero posible, o el de más (o menos) energía.
    private func bestSlot(in free: [DateInterval], target: Int, minimum: Int, preference: Preference) -> (start: Date, length: Int)? {
        guard target > 0 else { return nil }
        var best: (start: Date, length: Int, score: Double)?
        for slot in free {
            var cursor = roundUp(slot.start)
            while true {
                let available = Int(slot.end.timeIntervalSince(cursor) / 60)
                let length = min(target, available)
                guard length > 0, length >= minimum else { break }
                if preference == .earliest { return (cursor, length) }

                let energy = energy(from: cursor, minutes: length)
                // Preferir también bloques completos para no trocear el trabajo.
                let completeness = 0.3 * Double(length) / Double(target)
                let score = (preference == .peak ? energy : -energy) + completeness
                if let current = best, score <= current.score + 0.0001 {
                    // Se queda el anterior (el más temprano en caso de empate).
                } else {
                    best = (cursor, length, score)
                }
                cursor = cursor.addingTimeInterval(15 * 60)
            }
        }
        return best.map { ($0.start, $0.length) }
    }

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

    /// Clave del tope diario: grupo (el modo) y comienzo del día.
    static func capKey(group: String, day: Date) -> String {
        "\(group)|\(day.timeIntervalSinceReferenceDate)"
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
