import Foundation

// Horas de inicio y fin de un evento. La persona dice cuándo empieza y cuándo termina; la
// duración sale de ahí. Todo se calcula con el calendario (y su zona horaria), así que los
// cambios de hora de verano y los eventos de varios días conservan las horas de reloj.

struct EventTimes: Equatable, Sendable {
    var start: Date
    var end: Date

    var minutes: Int { Int((end.timeIntervalSince(start) / 60).rounded()) }
}

/// Lo que impide guardar unas horas.
enum EventTimeIssue: Equatable, Sendable {
    /// El fin no es posterior al inicio.
    case endNotAfterStart
    /// Más de lo que tiene sentido para un evento.
    case tooLong

    var message: String {
        switch self {
        case .endNotAfterStart: "La hora de fin tiene que ser posterior a la de inicio."
        case .tooLong: "Un evento no puede durar más de 14 días."
        }
    }
}

/// Algo del calendario que ocupa una franja (para avisar de que coincide).
struct EventConflict: Equatable, Sendable, Identifiable {
    var title: String
    var interval: DateInterval
    var id: String { "\(title)-\(interval.start.timeIntervalSinceReferenceDate)" }
}

enum EventSchedule {
    static let maxLength: TimeInterval = 14 * 24 * 3600

    static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// `minute` (desde medianoche) de ese día. En un cambio de hora, una hora que no existe pasa a
    /// la siguiente que sí.
    static func at(_ minute: Int, on day: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        let clamped = max(0, min(minute, 24 * 60 - 1))
        return calendar.date(bySettingHour: clamped / 60, minute: clamped % 60, second: 0, of: start)
            ?? start.addingTimeInterval(TimeInterval(clamped * 60))
    }

    /// Días de calendario entre el día del inicio y el del fin (0 = el mismo día).
    static func daySpan(_ times: EventTimes, calendar: Calendar = .current) -> Int {
        let first = calendar.startOfDay(for: times.start)
        let last = calendar.startOfDay(for: times.end)
        return max(0, calendar.dateComponents([.day], from: first, to: last).day ?? 0)
    }

    /// Lleva el evento a otro día con las mismas horas de reloj y los mismos días de duración
    /// (un evento de 22:00 a 01:00 sigue terminando al día siguiente).
    static func moving(_ times: EventTimes, toDay day: Date, calendar: Calendar = .current) -> EventTimes {
        let span = daySpan(times, calendar: calendar)
        let start = at(minuteOfDay(times.start, calendar: calendar), on: day, calendar: calendar)
        let endDay = calendar.date(byAdding: .day, value: span, to: calendar.startOfDay(for: day)) ?? day
        var end = at(minuteOfDay(times.end, calendar: calendar), on: endDay, calendar: calendar)
        if end <= start { end = start.addingTimeInterval(times.end.timeIntervalSince(times.start)) }
        return EventTimes(start: start, end: end)
    }

    /// Nueva hora de inicio el mismo día. `keepEnd`: el fin no se mueve mientras siga siendo
    /// posterior; si no (o sin `keepEnd`), se conserva la duración.
    static func settingStart(_ minute: Int, of times: EventTimes, keepEnd: Bool, calendar: Calendar = .current) -> EventTimes {
        let start = at(minute, on: times.start, calendar: calendar)
        return placing(start: start, of: times, keepEnd: keepEnd)
    }

    /// Mueve el inicio `delta` minutos («adelanta media hora» = −30).
    static func shiftingStart(by delta: Int, of times: EventTimes, keepEnd: Bool) -> EventTimes {
        placing(start: times.start.addingTimeInterval(TimeInterval(delta * 60)), of: times, keepEnd: keepEnd)
    }

    private static func placing(start: Date, of times: EventTimes, keepEnd: Bool) -> EventTimes {
        if keepEnd, times.end > start { return EventTimes(start: start, end: times.end) }
        return EventTimes(start: start, end: start.addingTimeInterval(times.end.timeIntervalSince(times.start)))
    }

    /// Nueva hora de fin, sin tocar el inicio. Va el día en que ya terminaba (el del inicio si era
    /// el mismo) o, con `nextDay`, el día siguiente al inicio. «De 3 a 4» dicho en la misma parte
    /// del día: si queda antes del inicio, se entiende 12 horas después. nil si sigue sin quedar
    /// después del inicio (no se cruza la medianoche sin decirlo).
    static func settingEnd(_ minute: Int, of times: EventTimes, nextDay: Bool, calendar: Calendar = .current) -> EventTimes? {
        let startDay = calendar.startOfDay(for: times.start)
        let base: Date
        if nextDay {
            base = calendar.date(byAdding: .day, value: 1, to: startDay) ?? startDay
        } else {
            base = daySpan(times, calendar: calendar) > 0 ? times.end : startDay
        }
        var end = at(minute, on: base, calendar: calendar)
        if !nextDay, end <= times.start, minute + 12 * 60 < 24 * 60 {
            let later = at(minute + 12 * 60, on: base, calendar: calendar)
            if later > times.start { end = later }
        }
        guard end > times.start else { return nil }
        return EventTimes(start: times.start, end: end)
    }

    /// Fin a la hora de reloj de `time`, el día `day` (selectores del formulario). Puede quedar
    /// antes del inicio: lo dice `issue`.
    static func end(atTimeOf time: Date, onDay day: Date, calendar: Calendar = .current) -> Date {
        at(minuteOfDay(time, calendar: calendar), on: day, calendar: calendar)
    }

    static func issue(_ times: EventTimes) -> EventTimeIssue? {
        if times.end <= times.start { return .endNotAfterStart }
        if times.end.timeIntervalSince(times.start) > maxLength { return .tooLong }
        return nil
    }

    /// Lo que coincide con esa franja (tocarse en el borde no cuenta).
    static func conflicts(_ times: EventTimes, with candidates: [EventConflict]) -> [EventConflict] {
        guard times.end > times.start else { return [] }
        return candidates
            .filter { $0.interval.start < times.end && times.start < $0.interval.end }
            .sorted { $0.interval.start < $1.interval.start }
    }

    /// «09:00–11:30», o «22:00 – jue 26 01:00» si termina otro día.
    static func rangeText(_ times: EventTimes, calendar: Calendar = .current) -> String {
        let start = ProposalFormat.time.string(from: times.start)
        if daySpan(times, calendar: calendar) == 0 {
            return "\(start)–\(ProposalFormat.time.string(from: times.end))"
        }
        return "\(start) – \(ProposalFormat.dayTime.string(from: times.end))"
    }

    /// «09:00–11:30 · 2 h 30 min».
    static func summary(_ times: EventTimes, calendar: Calendar = .current) -> String {
        "\(rangeText(times, calendar: calendar)) · \(ProposalFormat.minutes(max(0, times.minutes)))"
    }
}
