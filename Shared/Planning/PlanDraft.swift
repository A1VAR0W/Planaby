import Foundation
import SwiftData

/// Adjunto recién importado, todavía sin guardar en la base de datos.
struct ImportedAttachment: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    let name: String
    let kind: AttachmentKind
    let fileName: String
    let text: String
}

/// Propuesta pendiente de confirmar. Nada se escribe en el calendario hasta aceptarla.
///
/// Cada evento y cada tarea tiene un identificador estable (`id`) y un código corto para la IA
/// (`E1`, `T2`), que no cambian aunque cambien el título, la fecha, la duración o el plan. Así una
/// modificación nunca crea otro elemento por accidente.
struct PlanDraft: Identifiable, Codable, Equatable, Sendable {
    struct Item: Identifiable, Codable, Equatable, Sendable {
        var id = UUID()
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

        var durationMinutes: Int { Int((end.timeIntervalSince(start) / 60).rounded()) }

        func occurrences(in interval: DateInterval) -> [DateInterval] {
            Recurrence.occurrences(start: start, duration: end.timeIntervalSince(start), recurrence: recurrence, in: interval)
        }
    }

    struct Workload: Identifiable, Codable, Equatable, Sendable {
        let id: UUID
        var title: String
        var mode: PlanMode
        var deadline: Date
        /// Minutos que se reparten (ya corregidos con el desvío habitual de la persona).
        var estimatedMinutes: Int
        var priority: Int
        var difficulty = 3
        var notes = ""
        var attachments: [ImportedAttachment] = []
        /// Tarea que ya existe y se está replanificando (sus bloques nuevos se le enlazan).
        var existing: PersistentIdentifier?
        /// Lo que dijo la persona (o la IA) antes de corregirlo; al cambiar la duración se parte de aquí.
        var statedMinutes: Int?
        /// Bloques guardados de esta tarea que la propuesta sustituye (si se quita, se conservan).
        var replacedBlocks: [PersistentIdentifier] = []

        /// La duración tal como se pidió.
        var requestedMinutes: Int { statedMinutes ?? estimatedMinutes }
    }

    var id = UUID()
    var items: [Item]
    var tasks: [Workload]
    var summary: String
    var warnings: [String]
    /// Bloques actuales que se quitan al aceptar (se vuelven a colocar en `items`).
    var removals: [PersistentIdentifier] = []
    /// Hay tareas que no caben y se podría hacer hueco moviendo otros bloques.
    var canMakeRoom = false
    /// Orden pedido para las tareas («pon el informe primero»); vacío = por fecha límite.
    var order: [UUID] = []
    /// Condiciones generales pedidas durante la conversación («nada después de las 17:00»).
    var constraints = PlanConstraints()
    /// Códigos cortos para la IA y la interfaz: E1, E2… y T1, T2…
    var refs: [UUID: String] = [:]
    var nextEventRef = 1
    var nextTaskRef = 1

    init(items: [Item], tasks: [Workload], summary: String, warnings: [String], removals: [PersistentIdentifier] = []) {
        self.items = items
        self.tasks = tasks
        self.summary = summary
        self.warnings = warnings
        self.removals = removals
        assignRefs()
    }

    var includedItems: [Item] { items.filter(\.isIncluded) }
    /// Eventos nuevos (no bloques), para poder recalcular la propuesta.
    var newEvents: [Item] { items.filter { $0.kind != .workBlock } }
    /// Bloques de trabajo de la propuesta.
    var blocks: [Item] { items.filter { $0.kind == .workBlock } }

    func blocks(of taskID: UUID) -> [Item] { items.filter { $0.taskID == taskID && $0.kind == .workBlock } }

    func ref(_ id: UUID) -> String { refs[id] ?? "" }

    /// Da código a lo que aún no tiene. Los códigos no se reutilizan dentro de una propuesta.
    mutating func assignRefs() {
        for item in newEvents where refs[item.id] == nil {
            refs[item.id] = "E\(nextEventRef)"
            nextEventRef += 1
        }
        for task in tasks where refs[task.id] == nil {
            refs[task.id] = "T\(nextTaskRef)"
            nextTaskRef += 1
        }
    }

    /// Lo que la IA ve de la propuesta: códigos, títulos, fechas y duraciones (sin datos internos).
    func describe(formatter: DateFormatter) -> String {
        var lines: [String] = []
        for event in newEvents {
            var line = "\(ref(event.id)) evento «\(event.title)» \(formatter.string(from: event.start)), \(event.durationMinutes) min, \(event.mode.rawValue)"
            if event.recurrence != .none { line += ", \(event.recurrence.rawValue)" }
            if !event.isIncluded { line += ", quitado" }
            lines.append(line)
        }
        let ordered = orderedTasks
        for (index, task) in ordered.enumerated() {
            let blocks = self.blocks(of: task.id).filter(\.isIncluded)
            var line = "\(ref(task.id)) tarea «\(task.title)» \(task.requestedMinutes) min, entrega \(formatter.string(from: task.deadline)), prioridad \(task.priority), dificultad \(task.difficulty), \(task.mode.rawValue), \(blocks.count) bloques"
            if !order.isEmpty { line += ", puesto \(index + 1)" }
            lines.append(line)
        }
        return lines.isEmpty ? "ninguna" : lines.joined(separator: "\n")
    }

    /// Las tareas en el orden en que se planifican.
    var orderedTasks: [Workload] {
        guard !order.isEmpty else { return tasks.sorted { $0.deadline != $1.deadline ? $0.deadline < $1.deadline : $0.priority > $1.priority } }
        let ranked = order.compactMap { id in tasks.first { $0.id == id } }
        let rest = tasks.filter { !order.contains($0.id) }.sorted { $0.deadline < $1.deadline }
        return ranked + rest
    }

    // Codable: `refs` como lista para que el JSON sea legible y estable.
    private enum CodingKeys: String, CodingKey {
        case id, items, tasks, summary, warnings, removals, canMakeRoom, order, constraints, refs, nextEventRef, nextTaskRef
    }
}

/// Condiciones generales sobre toda la propuesta. Se aplican con el planificador de siempre
/// (franjas, topes diarios y huecos ocupados), no con otro.
struct PlanConstraints: Codable, Equatable, Sendable {
    /// Ningún bloque termina después de esta hora (minutos desde medianoche).
    var latestEndMinute: Int?
    /// Ningún bloque empieza antes de esta hora.
    var earliestStartMinute: Int?
    /// Franjas que hay que dejar libres («el viernes por la tarde»).
    var freeIntervals: [DateInterval] = []
    /// «Hazlo menos intenso»: bloques más cortos y menos horas al día.
    var lighter = false
    /// «Lo difícil por la mañana».
    var hardInMorning = false

    var isEmpty: Bool { self == PlanConstraints() }

    /// La franja de un plan con las condiciones aplicadas.
    func apply(to availability: Availability) -> Availability {
        var rules = availability
        func clamp(_ hours: inout Availability.DayHours) {
            if let latest = latestEndMinute { hours.endMinute = min(hours.endMinute, latest) }
            if let earliest = earliestStartMinute { hours.startMinute = max(hours.startMinute, earliest) }
        }
        var base = Availability.DayHours(startMinute: rules.startMinute, endMinute: rules.endMinute)
        clamp(&base)
        rules.startMinute = base.startMinute
        rules.endMinute = base.endMinute
        if var days = rules.dayHours {
            for key in days.keys { clamp(&days[key]!) }
            rules.dayHours = days
        }
        if lighter {
            rules.maxBlockMinutes = max(rules.minBlockMinutes, Int(Double(rules.maxBlockMinutes) * 0.67))
            rules.dailyCapMinutes = max(rules.minBlockMinutes, Int(Double(rules.dailyCapMinutes) * 0.67))
            rules.breakMinutes = max(rules.breakMinutes, 15)
        }
        return rules
    }

    /// Energía por hora con «lo difícil por la mañana»: la mañana pasa a ser lo mejor.
    func energy(_ energy: [Double]) -> [Double] {
        guard hardInMorning, energy.count == 24 else { return energy }
        return (0..<24).map { hour in (7...12).contains(hour) ? 1 : min(energy[hour], 0.5) }
    }
}
