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
        var difficulty = 3
        var notes = ""
        var attachments: [ImportedAttachment] = []
        /// Tarea que ya existe y se está replanificando (sus bloques nuevos se le enlazan).
        var existing: PersistentIdentifier?
    }

    let id = UUID()
    var items: [Item]
    var tasks: [Workload]
    var summary: String
    var warnings: [String]
    /// Bloques actuales que se quitan al aceptar (se vuelven a colocar en `items`).
    var removals: [PersistentIdentifier] = []
    /// Hay tareas que no caben y se podría hacer hueco moviendo otros bloques.
    var canMakeRoom = false

    var includedItems: [Item] { items.filter(\.isIncluded) }
    /// Eventos nuevos (no bloques), para poder recalcular la propuesta.
    var newEvents: [Item] { items.filter { $0.kind != .workBlock } }
}

/// Convierte peticiones (chat, plantillas o reorganizar) en una propuesta y la guarda al aceptarla.
/// Usa el perfil personal: horas de energía, preferencia por lo difícil y desvío de estimaciones.
@MainActor
enum PlanBuilder {
    /// Minutos de aviso para los bloques de trabajo.
    static let blockReminder = 5

    /// Coloca tareas nuevas en los huecos libres sin tocar lo que ya hay.
    static func draft(
        events: [PlanDraft.Item], tasks: [PlanDraft.Workload], context: ModelContext, now: Date = .now
    ) -> PlanDraft {
        let personal = PersonalProfile.shared
        personal.refresh(context: context, now: now)
        let adjusted = tasks.map { task in
            var task = task
            task.estimatedMinutes = personal.adjustedEstimate(task.estimatedMinutes)
            return task
        }
        var draft = build(events: events, tasks: adjusted, removing: [], context: context, now: now)
        if adjusted.map(\.estimatedMinutes) != tasks.map(\.estimatedMinutes), let note = personal.estimateNote {
            draft.summary += "\n" + note
        }
        let hasPendingBlocks = pendingTasks(context: context).contains { $0.blocks.contains { $0.start > now } }
        draft.canMakeRoom = !draft.warnings.isEmpty && hasPendingBlocks && !tasks.isEmpty
        return draft
    }

    /// Replanifica: quita los bloques que aún no han empezado y vuelve a colocar lo que falta de
    /// cada tarea siguiendo `order` (primero lo nuevo, luego lo elegido, luego por fecha límite).
    static func reorganize(
        order: [PersistentIdentifier], newEvents: [PlanDraft.Item] = [], newTasks: [PlanDraft.Workload] = [],
        adjustingEstimates: Bool = true, context: ModelContext, now: Date = .now
    ) -> PlanDraft {
        let personal = PersonalProfile.shared
        personal.refresh(context: context, now: now)

        let pending = pendingTasks(context: context)
        let chosen = order.compactMap { id in pending.first { $0.persistentModelID == id } }
        let rest = pending.filter { !order.contains($0.persistentModelID) }.sorted { $0.deadline < $1.deadline }

        var workloads = newTasks.map { task in
            var task = task
            if adjustingEstimates {
                task.estimatedMinutes = personal.adjustedEstimate(task.estimatedMinutes)
            }
            return task
        }
        var removals: [CalendarEvent] = []
        for task in chosen + rest {
            let future = task.blocks.filter { $0.start > now }
            removals += future
            let started = task.blocks.filter { $0.start <= now }.reduce(0) { $0 + Int($1.duration / 60) }
            let remaining = task.estimatedMinutes - started
            guard remaining > 0, task.deadline > now else { continue }
            workloads.append(PlanDraft.Workload(
                id: UUID(), title: task.title, mode: task.mode, deadline: task.deadline,
                estimatedMinutes: remaining, priority: task.priority, difficulty: task.difficulty,
                existing: task.persistentModelID
            ))
        }

        var draft = build(events: newEvents, tasks: workloads, removing: removals, context: context, now: now, ranked: true)
        let moved = removals.count
        if moved > 0 {
            draft.summary = "Reorganizo \(moved == 1 ? "1 bloque" : "\(moved) bloques") que aún no habían empezado. " + draft.summary
        }
        return draft
    }

    /// Repite una propuesta que no cabía, pero moviendo los bloques futuros de otras tareas.
    static func makeRoom(for draft: PlanDraft, context: ModelContext) -> PlanDraft {
        let fresh = draft.tasks.filter { $0.existing == nil }
        // Las estimaciones de la propuesta original ya venían corregidas.
        return reorganize(order: [], newEvents: draft.newEvents, newTasks: fresh, adjustingEstimates: false, context: context)
    }

    static func accept(_ draft: PlanDraft, context: ModelContext) {
        for id in draft.removals {
            if let event = context.model(for: id) as? CalendarEvent {
                context.delete(event)
            }
        }

        var tasks: [UUID: PlanTask] = [:]
        for workload in draft.tasks {
            if let existing = workload.existing, let task = context.model(for: existing) as? PlanTask {
                tasks[workload.id] = task
                continue
            }
            let task = PlanTask(
                title: workload.title, mode: workload.mode, deadline: workload.deadline,
                estimatedMinutes: workload.estimatedMinutes, priority: workload.priority,
                difficulty: workload.difficulty, notes: workload.notes
            )
            context.insert(task)
            for file in workload.attachments {
                let attachment = TaskAttachment(name: file.name, kind: file.kind, fileName: file.fileName, extractedText: file.text)
                context.insert(attachment)
                attachment.task = task
            }
            tasks[workload.id] = task
        }

        for item in draft.includedItems {
            let event = CalendarEvent(
                title: item.title, start: item.start, end: item.end, mode: item.mode,
                kind: item.kind, recurrence: item.recurrence, reminderMinutes: item.reminderMinutes
            )
            context.insert(event)
            if let taskID = item.taskID {
                event.task = tasks[taskID]
            }
        }
        try? context.save()
        ReminderScheduler.shared.reschedule()
    }

    // MARK: - Núcleo

    private static func pendingTasks(context: ModelContext) -> [PlanTask] {
        ((try? context.fetch(FetchDescriptor<PlanTask>())) ?? []).filter { !$0.isDone }
    }

    private static func build(
        events: [PlanDraft.Item], tasks: [PlanDraft.Workload], removing removals: [CalendarEvent],
        context: ModelContext, now: Date, ranked: Bool = false
    ) -> PlanDraft {
        let personal = PersonalProfile.shared
        let modes = ModeController.shared
        let horizon = tasks.map(\.deadline).max() ?? now
        let range = DateInterval(start: now, end: max(horizon, now.addingTimeInterval(24 * 3600)))
        let removedIDs = Set(removals.map(\.persistentModelID))
        let existing = ((try? context.fetch(FetchDescriptor<CalendarEvent>())) ?? [])
            .filter { !removedIDs.contains($0.persistentModelID) }

        // No se puede estar en dos sitios: los huecos se calculan con los dos planes.
        // Las reuniones de Outlook, Teams y otros calendarios de iOS también ocupan.
        let busy = existing.flatMap { $0.occurrences(in: range) }
            + events.map { DateInterval(start: $0.start, end: $0.end) }
            + ExternalCalendars.shared.busyIntervals(in: range)

        let work = tasks.enumerated().map { index, task in
            WorkItem(
                id: task.id, deadline: task.deadline, minutes: task.estimatedMinutes, priority: task.priority,
                availability: modes.availability(for: task.mode), capGroup: task.mode.rawValue,
                difficulty: task.difficulty, rank: ranked ? index : nil
            )
        }
        let planner = personal.planner()
        let result = planner.plan(work, busy: busy, from: now)

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
                warnings.append("«\(task.title)»: faltan \(FocusStats.format(TimeInterval(missing * 60))) por colocar antes de la fecha límite.")
            }
        }

        var summary = summary(events: events, tasks: tasks, blocks: result.blocks)
        let demanding = result.blocks.contains { block in
            tasks.first { $0.id == block.itemID }.map { $0.difficulty >= 4 || $0.priority == 2 } ?? false
        }
        if demanding, personal.profile.isCompleted || personal.learnedSessions > 0 {
            let peakBlocks = result.blocks.filter { planner.energy(from: $0.start, minutes: $0.minutes) >= 0.8 }
            if !peakBlocks.isEmpty {
                summary += "\nLo más exigente va en tus mejores horas (\(personal.bestHoursText))."
            }
        }

        return PlanDraft(
            items: items, tasks: tasks, summary: summary, warnings: warnings,
            removals: removals.map(\.persistentModelID)
        )
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
