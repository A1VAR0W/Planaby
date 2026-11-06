import Foundation
import SwiftData

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
            task.statedMinutes = task.statedMinutes ?? task.estimatedMinutes
            task.estimatedMinutes = personal.adjustedEstimate(task.requestedMinutes)
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
                task.statedMinutes = task.statedMinutes ?? task.estimatedMinutes
                task.estimatedMinutes = personal.adjustedEstimate(task.requestedMinutes)
            }
            return task
        }
        var removals: [CalendarEvent] = []
        for task in chosen + rest {
            let future = task.blocks.filter { $0.start > now }
            removals += future
            guard let workload = workload(replanning: task, now: now) else { continue }
            workloads.append(workload)
        }

        var draft = build(events: newEvents, tasks: workloads, removing: removals, context: context, now: now, ranked: true)
        let moved = removals.count
        if moved > 0 {
            draft.summary = "Reorganizo \(moved == 1 ? "1 bloque" : "\(moved) bloques") que aún no habían empezado. " + draft.summary
        }
        return draft
    }

    /// Repite una propuesta que no cabía, pero moviendo los bloques futuros de otras tareas.
    /// Conserva la propuesta (identificadores, cambios y condiciones) y solo mete el resto de tareas.
    static func makeRoom(for draft: PlanDraft, context: ModelContext) -> PlanDraft {
        var draft = draft
        if draft.order.isEmpty {
            // Primero lo nuevo, como al reorganizar.
            draft.order = draft.tasks.filter { $0.existing == nil }.map(\.id)
        }
        return replan(draft, affected: [], reorganizeAll: true, context: context)
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
                // Solo cambia lo que se cambió en la propuesta (la carga salió de esta misma tarea).
                if task.title != workload.title { task.title = workload.title }
                if task.deadline != workload.deadline { task.deadline = workload.deadline }
                if task.priority != workload.priority { task.priority = workload.priority }
                if task.difficulty != workload.difficulty { task.difficulty = workload.difficulty }
                if task.mode != workload.mode { task.mode = workload.mode }
                if task.notes != workload.notes { task.notes = workload.notes }
                let started = startedMinutes(of: task, now: .now)
                if workload.requestedMinutes != task.estimatedMinutes - started {
                    task.estimatedMinutes = started + workload.requestedMinutes
                }
                tasks[workload.id] = task
                continue
            }
            let task = PlanTask(
                title: workload.title, mode: workload.mode, deadline: workload.deadline,
                estimatedMinutes: workload.estimatedMinutes, priority: workload.priority,
                difficulty: workload.difficulty, notes: workload.notes
            )
            // El mismo identificador que en la propuesta: así se puede enlazar (p. ej. una captura).
            task.uid = workload.id
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

    /// Algún evento nuevo pisa bloques de trabajo ya guardados que aún no han empezado:
    /// entonces hay que reorganizar para moverlos.
    static func clashesWithBlocks(_ events: [PlanDraft.Item], context: ModelContext, now: Date = .now) -> Bool {
        guard !events.isEmpty else { return false }
        let range = DateInterval(start: now, duration: 21 * 24 * 3600)
        let taken = events.flatMap { $0.occurrences(in: range) }
        let blocks = ((try? context.fetch(FetchDescriptor<CalendarEvent>())) ?? [])
            .filter { $0.kind == .workBlock && $0.start > now && $0.task != nil }
        return blocks.contains { block in
            taken.contains { $0.start < block.end && block.start < $0.end }
        }
    }

    private static func pendingTasks(context: ModelContext) -> [PlanTask] {
        ((try? context.fetch(FetchDescriptor<PlanTask>())) ?? []).filter { !$0.isDone }
    }

    private static func startedMinutes(of task: PlanTask, now: Date) -> Int {
        task.blocks.filter { $0.start <= now }.reduce(0) { $0 + Int($1.duration / 60) }
    }

    /// La carga que le queda a una tarea guardada, para volver a colocarla. Sus bloques futuros
    /// quedan como «sustituidos»: si luego se quita de la propuesta, se conservan.
    private static func workload(replanning task: PlanTask, id: UUID = UUID(), now: Date) -> PlanDraft.Workload? {
        let remaining = task.estimatedMinutes - startedMinutes(of: task, now: now)
        guard remaining > 0, task.deadline > now else { return nil }
        return PlanDraft.Workload(
            id: id, title: task.title, mode: task.mode, deadline: task.deadline,
            estimatedMinutes: remaining, priority: task.priority, difficulty: task.difficulty,
            notes: task.notes, existing: task.persistentModelID, statedMinutes: remaining,
            replacedBlocks: task.blocks.filter { $0.start > now }.map(\.persistentModelID)
        )
    }

    // MARK: - Editar una propuesta

    /// Vuelve a colocar los bloques de una propuesta ya editada: solo los de `affected` y los que
    /// han dejado de encajar. Lo guardado no se toca; si una cita nueva pisa bloques guardados,
    /// esa tarea entra en la propuesta para moverlos (al aceptar, nunca antes).
    static func replan(
        _ draft: PlanDraft, affected: Set<UUID>, reorganizeAll: Bool = false, context: ModelContext, now: Date = .now
    ) -> PlanDraft {
        let personal = PersonalProfile.shared
        personal.refresh(context: context, now: now)
        var draft = draft
        var affected = affected

        let pending = pendingTasks(context: context)
        let inDraft = Set(draft.tasks.compactMap(\.existing))
        let horizon = max(draft.tasks.map(\.deadline).max() ?? now, now.addingTimeInterval(21 * 24 * 3600))
        let range = DateInterval(start: now, end: horizon)
        let taken = draft.newEvents.filter(\.isIncluded).flatMap { $0.occurrences(in: range) }
        for task in pending where !inDraft.contains(task.persistentModelID) {
            let future = task.blocks.filter { $0.start > now && !draft.removals.contains($0.persistentModelID) }
            let clashes = future.contains { block in taken.contains { $0.start < block.end && block.start < $0.end } }
            guard reorganizeAll || clashes, let workload = workload(replanning: task, now: now) else { continue }
            draft.tasks.append(workload)
            draft.removals += workload.replacedBlocks.filter { !draft.removals.contains($0) }
            affected.insert(workload.id)
        }
        if reorganizeAll { affected.formUnion(draft.tasks.map(\.id)) }
        draft.assignRefs()

        let removed = Set(draft.removals)
        let existing = ((try? context.fetch(FetchDescriptor<CalendarEvent>())) ?? [])
            .filter { !removed.contains($0.persistentModelID) }
        let busy = existing.flatMap { $0.occurrences(in: range) } + ExternalCalendars.shared.busyIntervals(in: range)
        let placement = ProposalPlacement(
            busy: busy, planner: personal.planner(), availability: { ModeController.shared.availability(for: $0) },
            adjust: { personal.adjustedEstimate($0) }, now: now, blockReminder: blockReminder
        )
        let result = placement.replan(draft, affected: affected)
        draft = result.draft

        var warnings: [String] = []
        for task in draft.tasks {
            if task.deadline <= now {
                warnings.append("La fecha límite de «\(task.title)» ya ha pasado.")
            } else if let missing = result.shortfalls[task.id] {
                warnings.append("«\(task.title)»: faltan \(FocusStats.format(TimeInterval(missing * 60))) por colocar antes de la fecha límite.")
            }
        }
        // Una cita nueva que coincide con otra cita guardada o de Outlook/Teams: se avisa, no se mueve.
        let fixedEvents = existing.filter { $0.kind != .workBlock }.flatMap { $0.occurrences(in: range) }
            + ExternalCalendars.shared.busyIntervals(in: range)
        for event in draft.newEvents where event.isIncluded {
            let slots = event.occurrences(in: range)
            if slots.contains(where: { slot in fixedEvents.contains { $0.start < slot.end && slot.start < $0.end } }) {
                warnings.append("«\(event.title)» coincide con otra cita de tu calendario.")
            }
        }
        if let latest = draft.constraints.latestEndMinute, !result.shortfalls.isEmpty {
            warnings.append("Terminando antes de las \(ProposalFormat.clock(latest)) no cabe todo. Puedes mover la fecha límite, reducir horas o quitar esa condición.")
        }
        draft.warnings = warnings

        let blocks = draft.blocks.compactMap { item in item.taskID.map { PlannedBlock(itemID: $0, start: item.start, end: item.end) } }
        draft.summary = summary(events: draft.newEvents, tasks: draft.tasks, blocks: blocks)
        let otherBlocks = pending.contains { task in
            !draft.tasks.contains { $0.existing == task.persistentModelID } && task.blocks.contains { $0.start > now }
        }
        draft.canMakeRoom = !result.shortfalls.isEmpty && otherBlocks
        return draft
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
            + events.flatMap { $0.occurrences(in: range) }
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
