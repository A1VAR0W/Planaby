import Foundation

/// Aparición concreta de un evento de un calendario ICS (las repeticiones ya expandidas).
struct ICSOccurrence: Codable, Equatable, Sendable {
    var uid: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    /// Ocupa tiempo: no está marcado como libre (TRANSP / estado de Outlook).
    var isBusy: Bool
}

/// Lector de calendarios ICS (iCalendar), como el enlace «Publicar calendario» de Outlook.
/// Entiende las zonas horarias de Windows que usa Outlook, las repeticiones (RRULE) más
/// comunes, las excepciones (EXDATE) y las reuniones movidas o canceladas (RECURRENCE-ID).
enum ICSCalendar {
    struct Event: Sendable {
        var uid = ""
        var title = ""
        var start: Date?
        var end: Date?
        var duration: TimeInterval?
        var isAllDay = false
        var isBusy = true
        var isCancelled = false
        var rule: [String: String]?
        var exceptions: [Date] = []
        var recurrenceID: Date?
        var timeZone = TimeZone.current
    }

    /// Todas las apariciones que se solapan con [from, to).
    static func occurrences(in text: String, from: Date, to: Date) -> [ICSOccurrence] {
        let events = parseEvents(text)
        let overrides = Dictionary(grouping: events.filter { $0.recurrenceID != nil }, by: \.uid)
        var result: [ICSOccurrence] = []

        for event in events where event.recurrenceID == nil {
            guard !event.isCancelled, let start = event.start else { continue }
            let span = length(of: event, start: start)
            guard let rule = event.rule else {
                let occurrence = make(event, start: start, length: span)
                if occurrence.end > from && occurrence.start < to { result.append(occurrence) }
                continue
            }

            var changes: [TimeInterval: Event] = [:]
            for change in overrides[event.uid] ?? [] {
                if let original = change.recurrenceID { changes[original.timeIntervalSinceReferenceDate.rounded()] = change }
            }
            let skipped = Set(event.exceptions.map { $0.timeIntervalSinceReferenceDate.rounded() })
            // Se amplía la ventana hacia atrás para no perder apariciones que empiezan antes y siguen dentro.
            let starts = expand(rule, start: start, zone: event.timeZone, from: from.addingTimeInterval(-max(span, 0)), to: to)

            for occurrenceStart in starts {
                let key = occurrenceStart.timeIntervalSinceReferenceDate.rounded()
                guard !skipped.contains(key) else { continue }
                if let change = changes.removeValue(forKey: key) {
                    guard !change.isCancelled, let changedStart = change.start else { continue }
                    let occurrence = make(change, start: changedStart, length: length(of: change, start: changedStart))
                    if occurrence.end > from && occurrence.start < to { result.append(occurrence) }
                } else {
                    let occurrence = make(event, start: occurrenceStart, length: span)
                    if occurrence.end > from && occurrence.start < to { result.append(occurrence) }
                }
            }
            // Apariciones movidas a la ventana desde fuera de ella.
            for change in changes.values where !change.isCancelled && !skipped.contains(change.recurrenceID!.timeIntervalSinceReferenceDate.rounded()) {
                guard let changedStart = change.start else { continue }
                let occurrence = make(change, start: changedStart, length: length(of: change, start: changedStart))
                if occurrence.end > from && occurrence.start < to { result.append(occurrence) }
            }
        }
        // Cambios sueltos cuya serie no viene en el archivo.
        let masters = Set(events.filter { $0.recurrenceID == nil }.map(\.uid))
        for (uid, changes) in overrides where !masters.contains(uid) {
            for change in changes where !change.isCancelled {
                guard let changedStart = change.start else { continue }
                let occurrence = make(change, start: changedStart, length: length(of: change, start: changedStart))
                if occurrence.end > from && occurrence.start < to { result.append(occurrence) }
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    // MARK: - Lectura

    static func parseEvents(_ text: String) -> [Event] {
        var events: [Event] = []
        var current: Event?
        var depth = 0 // Bloques anidados dentro del evento (VALARM).

        for line in unfold(text) {
            guard let property = Property(line) else { continue }
            switch (property.name, property.value.uppercased()) {
            case ("BEGIN", "VEVENT"):
                current = Event()
                depth = 0
                continue
            case ("END", "VEVENT"):
                if let event = current { events.append(event) }
                current = nil
                continue
            case ("BEGIN", _) where current != nil:
                depth += 1
                continue
            case ("END", _) where current != nil:
                depth -= 1
                continue
            default:
                break
            }
            guard var event = current, depth == 0 else { continue }

            switch property.name {
            case "UID":
                event.uid = property.value
            case "SUMMARY":
                event.title = unescape(property.value)
            case "DTSTART":
                if let parsed = parseDate(property.value, params: property.params) {
                    event.start = parsed.date
                    event.isAllDay = parsed.isAllDay
                    event.timeZone = parsed.zone
                }
            case "DTEND":
                event.end = parseDate(property.value, params: property.params)?.date
            case "DURATION":
                event.duration = parseDuration(property.value)
            case "RRULE":
                event.rule = parseRule(property.value)
            case "EXDATE":
                event.exceptions += property.value.split(separator: ",").compactMap {
                    parseDate(String($0), params: property.params)?.date
                }
            case "RECURRENCE-ID":
                event.recurrenceID = parseDate(property.value, params: property.params)?.date
            case "STATUS":
                event.isCancelled = property.value.uppercased() == "CANCELLED"
            case "TRANSP":
                if property.value.uppercased() == "TRANSPARENT" { event.isBusy = false }
            case "X-MICROSOFT-CDO-BUSYSTATUS":
                event.isBusy = property.value.uppercased() != "FREE"
            default:
                break
            }
            current = event
        }
        return events
    }

    private struct Property {
        let name: String
        let params: [String: String]
        let value: String

        init?(_ line: Substring) {
            // El primer «:» fuera de comillas separa nombre y parámetros del valor.
            var inQuotes = false
            var colon: Substring.Index?
            for index in line.indices {
                let character = line[index]
                if character == "\"" { inQuotes.toggle() }
                if character == ":" && !inQuotes { colon = index; break }
            }
            guard let colon else { return nil }
            let head = line[..<colon].split(separator: ";", omittingEmptySubsequences: false)
            guard let first = head.first else { return nil }
            name = first.uppercased()
            var params: [String: String] = [:]
            for part in head.dropFirst() {
                let pair = part.split(separator: "=", maxSplits: 1)
                guard pair.count == 2 else { continue }
                params[pair[0].uppercased()] = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
            self.params = params
            value = String(line[line.index(after: colon)...])
        }
    }

    /// Junta las líneas partidas (las que empiezan por espacio o tabulador continúan la anterior).
    private static func unfold(_ text: String) -> [Substring] {
        var lines: [String] = []
        for raw in text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            if let first = raw.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else {
                lines.append(String(raw))
            }
        }
        return lines.map { Substring($0) }
    }

    private static func unescape(_ text: String) -> String {
        var result = ""
        var escaping = false
        for character in text {
            if escaping {
                result.append(character == "n" || character == "N" ? "\n" : character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parseDate(_ value: String, params: [String: String]) -> (date: Date, isAllDay: Bool, zone: TimeZone)? {
        let digits = value.trimmingCharacters(in: .whitespaces)
        let isAllDay = params["VALUE"]?.uppercased() == "DATE" || digits.count == 8
        let isUTC = digits.hasSuffix("Z")
        let zone = isUTC ? TimeZone(identifier: "UTC")! : (isAllDay ? TimeZone.current : timeZone(for: params["TZID"]))

        let characters = Array(digits)
        func number(_ range: Range<Int>) -> Int? {
            guard range.upperBound <= characters.count else { return nil }
            return Int(String(characters[range]))
        }
        guard let year = number(0..<4), let month = number(4..<6), let day = number(6..<8) else { return nil }
        var components = DateComponents(year: year, month: month, day: day)
        if !isAllDay {
            guard characters.count >= 15, characters[8] == "T",
                  let hour = number(9..<11), let minute = number(11..<13), let second = number(13..<15) else { return nil }
            components.hour = hour
            components.minute = minute
            components.second = second
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let date = calendar.date(from: components) else { return nil }
        return (date, isAllDay, zone)
    }

    /// Duración ISO 8601 (P1D, PT1H30M, P2W…).
    static func parseDuration(_ value: String) -> TimeInterval? {
        var text = value.uppercased()
        var sign = 1.0
        if text.hasPrefix("-") { sign = -1; text.removeFirst() } else if text.hasPrefix("+") { text.removeFirst() }
        guard text.hasPrefix("P") else { return nil }
        var total = 0.0
        var number = ""
        var inTime = false
        for character in text.dropFirst() {
            if character.isNumber { number.append(character); continue }
            let amount = Double(number) ?? 0
            number = ""
            switch character {
            case "T": inTime = true
            case "W": total += amount * 7 * 86_400
            case "D": total += amount * 86_400
            case "H": total += amount * 3_600
            case "M": total += inTime ? amount * 60 : amount * 30 * 86_400
            case "S": total += amount
            default: return nil
            }
        }
        return sign * total
    }

    private static func parseRule(_ value: String) -> [String: String] {
        var rule: [String: String] = [:]
        for part in value.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1)
            if pair.count == 2 { rule[pair[0].uppercased()] = String(pair[1]).uppercased() }
        }
        return rule
    }

    private static func length(of event: Event, start: Date) -> TimeInterval {
        if let end = event.end { return max(0, end.timeIntervalSince(start)) }
        if let duration = event.duration { return max(0, duration) }
        return event.isAllDay ? 86_400 : 0
    }

    private static func make(_ event: Event, start: Date, length: TimeInterval) -> ICSOccurrence {
        ICSOccurrence(
            uid: event.uid, title: event.title.isEmpty ? "Sin título" : event.title,
            start: start, end: start.addingTimeInterval(length), isAllDay: event.isAllDay, isBusy: event.isBusy
        )
    }

    // MARK: - Repeticiones

    private static let weekdayCodes = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]

    /// Inicios de las repeticiones desde `start` hasta `to`, en la zona horaria del evento.
    static func expand(_ rule: [String: String], start: Date, zone: TimeZone, from: Date, to: Date) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.firstWeekday = rule["WKST"].flatMap { weekdayCodes[$0] } ?? 2

        let frequency = rule["FREQ"] ?? "DAILY"
        let interval = max(1, Int(rule["INTERVAL"] ?? "") ?? 1)
        let count = rule["COUNT"].flatMap(Int.init)
        let until = rule["UNTIL"].flatMap { parseDate($0, params: [:]) }.map { value in
            // Un UNTIL sin hora incluye todo ese día.
            value.isAllDay ? calendar.date(byAdding: .day, value: 1, to: value.date)!.addingTimeInterval(-1) : value.date
        }
        let byDay = (rule["BYDAY"] ?? "").split(separator: ",").compactMap { part -> (ordinal: Int?, weekday: Int)? in
            let code = String(part.suffix(2))
            guard let weekday = weekdayCodes[code] else { return nil }
            let prefix = part.dropLast(2)
            return (prefix.isEmpty ? nil : Int(prefix), weekday)
        }
        let byMonthDay = (rule["BYMONTHDAY"] ?? "").split(separator: ",").compactMap { Int($0) }
        let byMonth = Set((rule["BYMONTH"] ?? "").split(separator: ",").compactMap { Int($0) })
        let bySetPos = (rule["BYSETPOS"] ?? "").split(separator: ",").compactMap { Int($0) }
        let time = calendar.dateComponents([.hour, .minute, .second], from: start)

        func at(_ day: Date) -> Date? {
            calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day)
        }

        /// Días de un mes que cumplen BYMONTHDAY / BYDAY (o el mismo día que el inicio).
        func days(inMonthOf monthStart: Date) -> [Date] {
            guard let range = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
            let total = range.count
            var days: [Int] = []
            if !byMonthDay.isEmpty {
                days = byMonthDay.map { $0 < 0 ? total + $0 + 1 : $0 }.filter { (1...total).contains($0) }
            } else if !byDay.isEmpty {
                for (ordinal, weekday) in byDay {
                    let matches = (1...total).filter { day in
                        calendar.date(byAdding: .day, value: day - 1, to: monthStart).map { calendar.component(.weekday, from: $0) == weekday } ?? false
                    }
                    if let ordinal {
                        let index = ordinal > 0 ? ordinal - 1 : matches.count + ordinal
                        if matches.indices.contains(index) { days.append(matches[index]) }
                    } else {
                        days += matches
                    }
                }
            } else {
                let day = calendar.component(.day, from: start)
                if day <= total { days = [day] }
            }
            days = Array(Set(days)).sorted()
            if !bySetPos.isEmpty {
                days = bySetPos.compactMap { position in
                    let index = position > 0 ? position - 1 : days.count + position
                    return days.indices.contains(index) ? days[index] : nil
                }.sorted()
            }
            return days.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: monthStart) }.compactMap(at)
        }

        let startDay = calendar.startOfDay(for: start)
        let startWeek = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? startDay
        let startMonth = calendar.dateInterval(of: .month, for: start)?.start ?? startDay
        let startYear = calendar.dateInterval(of: .year, for: start)?.start ?? startDay

        func candidates(period: Int) -> [Date] {
            switch frequency {
            case "WEEKLY":
                guard let week = calendar.date(byAdding: .weekOfYear, value: period * interval, to: startWeek) else { return [] }
                let weekdays = byDay.isEmpty ? [calendar.component(.weekday, from: start)] : byDay.map(\.weekday)
                return weekdays.compactMap { weekday in
                    calendar.date(byAdding: .day, value: (weekday - calendar.firstWeekday + 7) % 7, to: week).flatMap(at)
                }.sorted()
            case "MONTHLY":
                guard let month = calendar.date(byAdding: .month, value: period * interval, to: startMonth) else { return [] }
                if !byMonth.isEmpty && !byMonth.contains(calendar.component(.month, from: month)) { return [] }
                return days(inMonthOf: month)
            case "YEARLY":
                guard let year = calendar.date(byAdding: .year, value: period * interval, to: startYear) else { return [] }
                let months = byMonth.isEmpty ? [calendar.component(.month, from: start)] : byMonth.sorted()
                return months.flatMap { month in
                    calendar.date(byAdding: .month, value: month - 1, to: year).map { days(inMonthOf: $0) } ?? []
                }
            default: // DAILY
                guard let day = calendar.date(byAdding: .day, value: period * interval, to: startDay) else { return [] }
                if !byDay.isEmpty && !byDay.contains(where: { $0.weekday == calendar.component(.weekday, from: day) }) { return [] }
                if !byMonth.isEmpty && !byMonth.contains(calendar.component(.month, from: day)) { return [] }
                return [day].compactMap(at)
            }
        }

        // Sin COUNT se puede saltar directamente cerca de la ventana.
        var period = 0
        if count == nil, from > start {
            let unit: Calendar.Component = switch frequency {
            case "WEEKLY": .weekOfYear
            case "MONTHLY": .month
            case "YEARLY": .year
            default: .day
            }
            let distance = calendar.dateComponents([unit], from: start, to: from).value(for: unit) ?? 0
            period = max(0, distance / interval - 1)
        }

        var result: [Date] = []
        var produced = 0
        let limit = period + 5_000
        while period < limit {
            for candidate in candidates(period: period) where candidate >= start {
                if let until, candidate > until { return result }
                produced += 1
                if let count, produced > count { return result }
                if candidate >= to { return result }
                if candidate >= from { result.append(candidate) }
            }
            period += 1
        }
        return result
    }

    // MARK: - Zonas horarias

    /// Outlook usa nombres de Windows («Romance Standard Time»); se traducen a IANA.
    static func timeZone(for identifier: String?) -> TimeZone {
        guard let identifier, !identifier.isEmpty else { return .current }
        if let zone = TimeZone(identifier: identifier) { return zone }
        if let mapped = windowsZones[identifier], let zone = TimeZone(identifier: mapped) { return zone }
        // «(UTC+01:00) Bruselas, Copenhague…»
        if let range = identifier.range(of: #"UTC([+-])(\d{2}):(\d{2})"#, options: .regularExpression) {
            let text = identifier[range]
            let sign = text.contains("-") ? -1 : 1
            let digits = text.filter(\.isNumber)
            if let hours = Int(digits.prefix(2)), let minutes = Int(digits.suffix(2)),
               let zone = TimeZone(secondsFromGMT: sign * (hours * 3600 + minutes * 60)) {
                return zone
            }
        }
        return .current
    }

    private static let windowsZones: [String: String] = [
        "Romance Standard Time": "Europe/Madrid",
        "W. Europe Standard Time": "Europe/Berlin",
        "Central Europe Standard Time": "Europe/Budapest",
        "Central European Standard Time": "Europe/Warsaw",
        "GMT Standard Time": "Europe/London",
        "Greenwich Standard Time": "Atlantic/Reykjavik",
        "UTC": "UTC",
        "Coordinated Universal Time": "UTC",
        "E. Europe Standard Time": "Europe/Chisinau",
        "FLE Standard Time": "Europe/Kiev",
        "GTB Standard Time": "Europe/Bucharest",
        "Turkey Standard Time": "Europe/Istanbul",
        "Russian Standard Time": "Europe/Moscow",
        "Morocco Standard Time": "Africa/Casablanca",
        "W. Central Africa Standard Time": "Africa/Lagos",
        "South Africa Standard Time": "Africa/Johannesburg",
        "Egypt Standard Time": "Africa/Cairo",
        "Israel Standard Time": "Asia/Jerusalem",
        "Arabian Standard Time": "Asia/Dubai",
        "India Standard Time": "Asia/Kolkata",
        "China Standard Time": "Asia/Shanghai",
        "Singapore Standard Time": "Asia/Singapore",
        "Tokyo Standard Time": "Asia/Tokyo",
        "AUS Eastern Standard Time": "Australia/Sydney",
        "Eastern Standard Time": "America/New_York",
        "Central Standard Time": "America/Chicago",
        "Mountain Standard Time": "America/Denver",
        "US Mountain Standard Time": "America/Phoenix",
        "Pacific Standard Time": "America/Los_Angeles",
        "Alaskan Standard Time": "America/Anchorage",
        "Hawaiian Standard Time": "Pacific/Honolulu",
        "Atlantic Standard Time": "America/Halifax",
        "Central Standard Time (Mexico)": "America/Mexico_City",
        "SA Pacific Standard Time": "America/Bogota",
        "SA Western Standard Time": "America/La_Paz",
        "Venezuela Standard Time": "America/Caracas",
        "Pacific SA Standard Time": "America/Santiago",
        "Argentina Standard Time": "America/Argentina/Buenos_Aires",
        "E. South America Standard Time": "America/Sao_Paulo",
    ]
}
