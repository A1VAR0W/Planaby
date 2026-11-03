import Foundation
import SwiftData

/// Los dos planes de Planaby. En modo Normal se silencian los recordatorios de Trabajo;
/// en modo Trabajo suenan los de ambos.
enum PlanMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case work, personal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .work: "Trabajo"
        case .personal: "Normal"
        }
    }

    var symbol: String {
        switch self {
        case .work: "briefcase.fill"
        case .personal: "house.fill"
        }
    }

    /// Qué planes se ven y avisan en este modo.
    var visibleModes: Set<PlanMode> {
        switch self {
        case .work: [.work, .personal]
        case .personal: [.personal]
        }
    }
}

enum EventKind: String, Codable, Sendable {
    /// Cita con hora fija.
    case event
    /// Bloque de trabajo repartido por el planificador para una tarea.
    case workBlock
    /// Hábito recurrente.
    case habit

    var symbol: String {
        switch self {
        case .event: "calendar"
        case .workBlock: "square.stack.3d.up.fill"
        case .habit: "repeat"
        }
    }
}

enum Recurrence: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, daily, weekdays, weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "No se repite"
        case .daily: "Cada día"
        case .weekdays: "De lunes a viernes"
        case .weekly: "Cada semana"
        }
    }
}

@Model
final class CalendarEvent {
    var title: String
    var notes: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var modeRaw: String
    var kindRaw: String
    var recurrenceRaw: String
    /// Minutos de antelación del recordatorio; nil = sin aviso.
    var reminderMinutes: Int?
    var task: PlanTask?

    init(
        title: String, notes: String = "", start: Date, end: Date, isAllDay: Bool = false,
        mode: PlanMode, kind: EventKind, recurrence: Recurrence = .none, reminderMinutes: Int? = nil
    ) {
        self.title = title
        self.notes = notes
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        modeRaw = mode.rawValue
        kindRaw = kind.rawValue
        recurrenceRaw = recurrence.rawValue
        self.reminderMinutes = reminderMinutes
    }

    var mode: PlanMode {
        get { PlanMode(rawValue: modeRaw) ?? .personal }
        set { modeRaw = newValue.rawValue }
    }

    var kind: EventKind {
        get { EventKind(rawValue: kindRaw) ?? .event }
        set { kindRaw = newValue.rawValue }
    }

    var recurrence: Recurrence {
        get { Recurrence(rawValue: recurrenceRaw) ?? .none }
        set { recurrenceRaw = newValue.rawValue }
    }

    var duration: TimeInterval { end.timeIntervalSince(start) }

    /// Apariciones del evento dentro de un intervalo, teniendo en cuenta la repetición.
    func occurrences(in interval: DateInterval, calendar: Calendar = .current) -> [DateInterval] {
        let length = max(0, duration)
        guard recurrence != .none else {
            let own = DateInterval(start: start, duration: length)
            return own.intersects(interval) ? [own] : []
        }

        var result: [DateInterval] = []
        let startDay = calendar.startOfDay(for: max(start, interval.start.addingTimeInterval(-length)))
        let time = calendar.dateComponents([.hour, .minute], from: start)
        let originalWeekday = calendar.component(.weekday, from: start)
        var day = startDay
        while day <= interval.end {
            let weekday = calendar.component(.weekday, from: day)
            let matches = switch recurrence {
            case .none: false
            case .daily: true
            case .weekdays: (2...6).contains(weekday)
            case .weekly: weekday == originalWeekday
            }
            if matches,
               let occurrenceStart = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day),
               occurrenceStart >= start {
                let occurrence = DateInterval(start: occurrenceStart, duration: length)
                if occurrence.intersects(interval) { result.append(occurrence) }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }
}

@Model
final class PlanTask {
    var title: String
    var modeRaw: String
    var deadline: Date
    var estimatedMinutes: Int
    /// 0 baja, 1 media, 2 alta.
    var priority: Int
    var isDone: Bool
    var created: Date
    @Relationship(deleteRule: .cascade, inverse: \CalendarEvent.task)
    var blocks: [CalendarEvent] = []

    init(title: String, mode: PlanMode, deadline: Date, estimatedMinutes: Int, priority: Int) {
        self.title = title
        modeRaw = mode.rawValue
        self.deadline = deadline
        self.estimatedMinutes = estimatedMinutes
        self.priority = priority
        isDone = false
        created = .now
    }

    var mode: PlanMode {
        get { PlanMode(rawValue: modeRaw) ?? .work }
        set { modeRaw = newValue.rawValue }
    }

    var scheduledMinutes: Int {
        blocks.reduce(0) { $0 + Int($1.duration / 60) }
    }

    /// Minutos de bloques que ya han terminado.
    var completedMinutes: Int {
        blocks.filter { $0.end <= .now }.reduce(0) { $0 + Int($1.duration / 60) }
    }
}
