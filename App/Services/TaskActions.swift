import Foundation
import SwiftData

/// Acciones sobre tareas que tocan más de un sitio (bloques, adjuntos y avisos).
@MainActor
enum TaskActions {
    /// Marca la tarea como hecha y libera los bloques que aún no han empezado.
    static func complete(_ task: PlanTask, context: ModelContext, now: Date = .now) {
        task.setDone(true)
        for block in task.blocks where block.start > now {
            context.delete(block)
        }
        try? context.save()
        ReminderScheduler.shared.reschedule()
    }

    static func reopen(_ task: PlanTask, context: ModelContext) {
        task.setDone(false)
        try? context.save()
    }

    /// Borra la tarea, sus bloques y los archivos adjuntos.
    static func delete(_ task: PlanTask, context: ModelContext) {
        task.attachments.forEach { AttachmentStore.delete($0.fileName) }
        context.delete(task)
        try? context.save()
        ReminderScheduler.shared.reschedule()
    }
}
