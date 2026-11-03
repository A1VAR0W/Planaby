import Foundation
import SwiftData

/// Propuesta pendiente de confirmar. Nada se escribe en el calendario hasta aceptarla.
struct PlanDraft: Identifiable {
    struct Item: Identifiable {
        let id = UUID()
        var title: String
        var start: Date
        var end: Date
        var mode: PlanMode
        var kind: EventKind
        var recurrence: Recurrence = .none
        var reminderMinutes: Int?
        /// Tarea a la que pertenece, si es un bloque de trabajo.
        var taskID: UUID?
        var isIncluded = true
    }

    struct Workload: Identifiable {
        let id: UUID
        var title: String
        var mode: PlanMode
        var deadline: Date
        var estimatedMinutes: Int
        var priority: Int
    }

    let id = UUID()
    var items: [Item]
    var tasks: [Workload]
    var summary: String
    var warnings: [String]

    var includedItems: [Item] { items.filter(\.isIncluded) }
}

/// Convierte peticiones (del chat o de las plantillas) en una propuesta y la guarda al aceptarla.
@MainActor
enum PlanBuilder {
    /// Minutos de aviso para los bloques de trabajo.
    static let blockReminder = 5

    static func draft(
        events: [PlanDraft.Item], tasks: [PlanDraft.Workload], context: ModelContext, now: Date = .now
    ) -> PlanDraft {
        let modes = ModeController.shared
        let horizon = tasks.map(\.deadline).max() ?? now
        let range = DateInterval(start: now, end: max(horizon, now.addingTimeInterval(24 * 3600)))
        let existing = (try? context.fetch(FetchDescriptor<CalendarEvent>())) ?? []

        // No se puede estar en dos sitios: los huecos se calculan con los dos planes.
        let busy = existing.flatMap { $0.occurrences(in: range) }
            + events.map { DateInterval(start: $0.start, end: $0.end) }

        let work = tasks.map {
            WorkItem(
                id: $0.id, deadline: $0.deadline, minutes: $0.estimatedMinutes, priority: $0.priority,
                availability: modes.availability(for: $0.mode), capGroup: $0.mode.rawValue
            )
        }
        let result = WorkloadPlanner().plan(work, busy: busy, from: now)

        var items = events
        for block in result.blocks {
            guard let task = tasks.first(where: { $0.id == block.itemID }) else { continue }
            items.append(PlanDraft.Item(
                title: task.title, start: block.start, end: block.end, mode: task.mode,
                kind: .workBlock, reminderMinutes: blockReminder, taskID: task.id
            ))
        }
        items.sort { $0.start < $1.start }

        var warnings: [String] = []
        for task in tasks {
            if task.deadline <= now {
                warnings.append("La fecha límite de «\(task.title)» ya ha pasado.")
            } else if let missing = result.shortfalls[task.id] {
                warnings.append("«\(task.title)»: faltan \(FocusStats.format(TimeInterval(missing * 60))) por colocar antes de la fecha límite. Amplía tu horario en Ajustes o adelanta trabajo.")
            }
        }

        return PlanDraft(items: items, tasks: tasks, summary: summary(events: events, tasks: tasks, blocks: result.blocks), warnings: warnings)
    }

    static func accept(_ draft: PlanDraft, context: ModelContext) {
        var created: [UUID: PlanTask] = [:]
        for task in draft.tasks {
            let model = PlanTask(
                title: task.title, mode: task.mode, deadline: task.deadline,
                estimatedMinutes: task.estimatedMinutes, priority: task.priority
            )
            context.insert(model)
            created[task.id] = model
        }
        for item in draft.includedItems {
            let event = CalendarEvent(
                title: item.title, start: item.start, end: item.end, mode: item.mode,
                kind: item.kind, recurrence: item.recurrence, reminderMinutes: item.reminderMinutes
            )
            context.insert(event)
            if let taskID = item.taskID {
                event.task = created[taskID]
            }
        }
        try? context.save()
        ReminderScheduler.shared.reschedule()
    }

    private static func summary(events: [PlanDraft.Item], tasks: [PlanDraft.Workload], blocks: [PlannedBlock]) -> String {
        var parts: [String] = []
        if !events.isEmpty {
            parts.append(events.count == 1 ? "1 evento" : "\(events.count) eventos")
        }
        if !blocks.isEmpty {
            let minutes = blocks.reduce(0) { $0 + $1.minutes }
            let days = Set(blocks.map { Calendar.current.startOfDay(for: $0.start) }).count
            parts.append("\(blocks.count) bloques de trabajo (\(FocusStats.format(TimeInterval(minutes * 60)))) en \(days == 1 ? "1 día" : "\(days) días")")
        }
        guard !parts.isEmpty else {
            return tasks.isEmpty ? "No hay nada que añadir." : "No he encontrado huecos libres para estas tareas."
        }
        return "Propongo " + parts.joined(separator: " y ") + "."
    }
}
