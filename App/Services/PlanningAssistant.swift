import Foundation
import FoundationModels
import Observation
import SwiftData

// MARK: - Estructuras que genera el modelo

// El orden de las propiedades es el orden en que el modelo las escribe: primero decide si la
// petición es de planificación y cuántas cosas nuevas pide; así no se le «olvida» ninguna.

@Generable(description: "Lo que el usuario quiere crear, cambiar o borrar en su plan")
struct ParsedPlan {
    @Guide(description: "true solo si la petición no tiene nada que ver con planificar eventos, tareas o el calendario")
    var offTopic: Bool
    @Guide(description: "Cuántos eventos y tareas NUEVOS pide crear en total, aunque les falten datos; 0 si solo cambia o borra", .range(0...30))
    var requestedCount: Int
    @Guide(description: "Cambios sobre lo que ya existe: la propuesta (códigos E y T) o lo guardado (códigos C y P)")
    var edits: [ParsedEdit]
    @Guide(description: "Cada evento NUEVO que pide, uno por elemento, aunque le falte el día, la hora o la duración")
    var events: [ParsedEvent]
    @Guide(description: "Trabajos NUEVOS con fecha límite que hay que repartir en bloques: entregas, informes, estudiar")
    var tasks: [ParsedTask]
    @Guide(description: "Condiciones sobre todo el plan: dejar libre una franja, nada antes o después de una hora, menos intenso, lo difícil por la mañana, primero lo urgente")
    var conditions: [ParsedCondition]
    @Guide(description: "true si pide reorganizar o replanificar todo, adelantar trabajo o hacer hueco")
    var reorganize: Bool
    @Guide(description: "Títulos exactos de tareas guardadas que quiere adelantar o priorizar, en orden")
    var prioritize: [String]
    @Guide(description: "Respuesta breve si no se puede hacer o falta algo que Planaby no puede deducir; vacía si ya se puede hacer")
    var question: String
}

@Generable(description: "Un cambio sobre un elemento que ya existe")
struct ParsedEdit {
    @Guide(description: "update cambia datos; delete lo borra; remove lo quita de la propuesta sin borrar nada guardado; first lo pone antes que las demás tareas; undo deshace el último cambio", .anyOf(["update", "delete", "remove", "first", "undo"]))
    var action: String
    @Guide(description: "Código del elemento (E1, T2, C3, P1). Si no está claro cuál es, las palabras del usuario («la reunión del jueves»)")
    var target: String
    @Guide(description: "Título nuevo; vacío si no cambia")
    var title: String
    @Guide(description: "Día nuevo de un evento yyyy-MM-dd; vacío si no cambia")
    var day: String
    @Guide(description: "Hora nueva de inicio HH:mm; vacía si no cambia")
    var time: String
    @Guide(description: "Hora nueva de fin HH:mm; vacía si no cambia")
    var endTime: String
    @Guide(description: "Duración nueva de un evento o total nuevo de una tarea, en minutos; 0 si no cambia o no dice cuánto", .range(0...12000))
    var minutes: Int
    @Guide(description: "Día yyyy-MM-dd en que se trabaja una tarea («pásala al viernes»); vacío si no cambia")
    var workDay: String
    @Guide(description: "Fecha límite nueva de una tarea, yyyy-MM-dd HH:mm; vacía si no cambia")
    var deadline: String
    @Guide(description: "Prioridad nueva: 0 baja, 1 media, 2 alta; -1 si no cambia", .range(-1...2))
    var priority: Int
    @Guide(description: "Dificultad nueva de 1 a 5; 0 si no cambia", .range(0...5))
    var difficulty: Int
    @Guide(description: "Plan nuevo; same si no cambia", .anyOf(["same", "work", "personal"]))
    var mode: String
    @Guide(description: "Repetición nueva de un evento; same si no cambia", .anyOf(["same", "none", "weekdays", "daily", "weekly"]))
    var repeats: String
    @Guide(description: "Minutos de aviso nuevos; -1 si no cambia; 0 sin aviso", .range(-1...1440))
    var reminderMinutes: Int
}

@Generable(description: "Una condición sobre todo el plan")
struct ParsedCondition {
    @Guide(description: "free deja libre una franja; latestEnd nada después de una hora; earliestStart nada antes de una hora; lighter menos intenso; hardMorning lo difícil por la mañana; urgentFirst primero lo urgente", .anyOf(["free", "latestEnd", "earliestStart", "lighter", "hardMorning", "urgentFirst"]))
    var kind: String
    @Guide(description: "Día yyyy-MM-dd para free; vacío en los demás")
    var day: String
    @Guide(description: "Hora HH:mm: inicio de la franja libre (la tarde 14:00, la mañana 08:00; vacía si es todo el día) o la hora de latestEnd y earliestStart")
    var from: String
    @Guide(description: "Fin HH:mm de la franja libre (la tarde 21:00, la mañana 14:00); vacía en los demás")
    var to: String
}

@Generable
struct ParsedEvent {
    @Guide(description: "Nombre exacto que usa el usuario, sin la fecha ni la palabra evento")
    var title: String
    @Guide(description: "Día yyyy-MM-dd; vacío si el usuario no lo dice")
    var day: String
    @Guide(description: "Hora de inicio HH:mm; vacía si el usuario no la dice")
    var time: String
    @Guide(description: "Hora de fin HH:mm; vacía si no la dice")
    var endTime: String
    @Guide(description: "Duración en minutos solo si el usuario la dice; 0 si no", .range(0...720))
    var durationMinutes: Int
    @Guide(description: "work si es claramente de trabajo o estudios; personal si es claramente ocio, casa, salud, familia o recados; unknown si no se puede saber", .anyOf(["work", "personal", "unknown"]))
    var mode: String
    @Guide(description: "Minutos de antelación del aviso; 15 si no se indica", .range(0...1440))
    var reminderMinutes: Int
    @Guide(description: "none si es una vez; weekdays de lunes a viernes; daily cada día; weekly cada semana", .anyOf(["none", "weekdays", "daily", "weekly"]))
    var repeats: String
}

@Generable
struct ParsedTask {
    @Guide(description: "Nombre exacto que usa el usuario, sin la fecha")
    var title: String
    @Guide(description: "Fecha límite en formato yyyy-MM-dd HH:mm; si solo hay día, a las 23:59")
    var deadline: String
    @Guide(description: "Minutos de trabajo estimados en total, teniendo en cuenta el material adjunto", .range(15...12000))
    var estimatedMinutes: Int
    @Guide(description: "Dificultad: 1 mecánica, 3 normal, 5 muy exigente y de concentración profunda", .range(1...5))
    var difficulty: Int
    @Guide(description: "work si es claramente de trabajo o estudios; personal si es claramente ocio, casa, salud, familia o recados; unknown si no se puede saber", .anyOf(["work", "personal", "unknown"]))
    var mode: String
    @Guide(description: "Prioridad: 0 baja, 1 media, 2 alta o urgente", .range(0...2))
    var priority: Int
}

@Generable(description: "Estimación de una tarea a partir de su descripción y su material")
struct ComplexityEstimate {
    @Guide(description: "Minutos totales de trabajo estimados, realistas", .range(15...12000))
    var estimatedMinutes: Int
    @Guide(description: "Dificultad: 1 mecánica, 3 normal, 5 muy exigente y de concentración profunda", .range(1...5))
    var difficulty: Int
    @Guide(description: "Por qué, en una o dos frases")
    var reasoning: String
    @Guide(description: "Pasos concretos para hacerla, en orden", .maximumCount(6))
    var steps: [String]
}

/// Lo que se entendió de una petición, ya convertido a borradores y operaciones.
struct Interpretation {
    var events: [PlanDraft.Item] = []
    var tasks: [PlanDraft.Workload] = []
    var reorganize = false
    var prioritize: [PersistentIdentifier] = []
    var question = ""
    var problems: [String] = []
    /// Lo que no se sabe si va al plan de Trabajo o al Normal: se pregunta antes de proponer.
    var undecidedEvents: Set<UUID> = []
    var undecidedTasks: Set<UUID> = []
    /// Cambios sobre la propuesta abierta o lo guardado (y condiciones generales).
    var edits: [ProposalEdit] = []
    var undo = false
    /// Títulos que la IA quiso poner primero y que están en la propuesta.
    var first: [String] = []
    /// No es una petición de planificación.
    var offTopic = false
    /// Elementos nuevos que la petición anuncia («dos eventos»), si lo dice.
    var expectedCount: Int?
    /// La petición tal cual, para lo que se decide con sus palabras (series, duplicados).
    var request = ""

    var isEmpty: Bool { events.isEmpty && tasks.isEmpty && !reorganize && prioritize.isEmpty && edits.isEmpty && first.isEmpty && !undo }

    var needsMode: Bool { !undecidedEvents.isEmpty || !undecidedTasks.isEmpty }

    var newCount: Int { events.count + tasks.count }

    /// Faltan elementos de los que se pidieron: no se presenta como completo.
    var shortfall: String? {
        guard let expectedCount, newCount < expectedCount else { return nil }
        let found = (events.map(\.title) + tasks.map(\.title)).map { "«\($0)»" }
        let list = found.isEmpty ? "ninguno" : ProposalNarration.join(found)
        return "Pediste \(expectedCount) y solo he podido preparar \(newCount) (\(list)). Dime cuál falta y lo añado."
    }

    /// «¿«Llamar a Juan» va en tu plan de Trabajo o en el Normal?»
    var modeQuestion: String {
        var list: [String] = events.filter { undecidedEvents.contains($0.id) }.map { "«\($0.title)»" }
        list += tasks.filter { undecidedTasks.contains($0.id) }.map { "«\($0.title)»" }
        guard let last = list.last else { return "¿Va en tu plan de Trabajo o en el Normal?" }
        if list.count == 1 {
            return "¿\(last) va en tu plan de Trabajo o en el Normal?"
        }
        let others = list.dropLast().joined(separator: ", ")
        return "¿\(others) y \(last) van en tu plan de Trabajo o en el Normal?"
    }

    /// Pone en `mode` todo lo que estaba sin decidir.
    mutating func assign(_ mode: PlanMode) {
        for index in events.indices where undecidedEvents.contains(events[index].id) {
            events[index].mode = mode
        }
        for index in tasks.indices where undecidedTasks.contains(tasks[index].id) {
            tasks[index].mode = mode
        }
        undecidedEvents = []
        undecidedTasks = []
    }

    /// La propuesta que sale de lo entendido (colocar lo nuevo o reorganizar).
    @MainActor
    func makeDraft(context: ModelContext) -> PlanDraft {
        // Si lo nuevo pisa bloques ya guardados, se reorganizan para hacerle hueco.
        let clashes = PlanBuilder.clashesWithBlocks(events, context: context)
        var draft = reorganize || !prioritize.isEmpty || clashes
            ? PlanBuilder.reorganize(order: prioritize, newEvents: events, newTasks: tasks, context: context)
            : PlanBuilder.draft(events: events, tasks: tasks, context: context)
        if !conditions.isEmpty {
            // Condiciones dichas ya en la primera petición («nada después de las 17»).
            if case .applied(let outcome) = ProposalEditor.apply(conditions, to: draft) {
                draft = PlanBuilder.replan(outcome.draft, affected: Set(outcome.draft.tasks.map(\.id)), context: context)
            }
        }
        draft.warnings = problems + draft.warnings
        return draft
    }

    /// Las operaciones para aplicar sobre una propuesta abierta.
    var proposalEdits: [ProposalEdit] {
        events.map { .addEvent($0) } + tasks.map { .addTask($0) } + edits
            + first.map { .moveFirst(ProposalTarget(text: $0, kind: .task)) }
    }

    /// Solo las condiciones generales («nada después de las 17», «primero lo urgente»).
    var conditions: [ProposalEdit] { edits.filter(\.isCondition) }

    /// Cambios sobre elementos concretos (no condiciones).
    var itemEdits: [ProposalEdit] { edits.filter { !$0.isCondition } }
}

extension ProposalEdit {
    var isCondition: Bool {
        switch self {
        case .constraints, .urgentFirst: true
        default: false
        }
    }
}

// MARK: - Lo guardado, tal como lo ve la IA

/// Foto de lo guardado al hacer una petición: lo que ve la IA (con códigos C y P) y a qué
/// elemento corresponde cada código. Los eventos de otros calendarios solo se leen.
struct SavedIndex {
    var refs: [SavedRef] = []
    var ids: [PersistentIdentifier?] = []
    var lines: [String] = []

    static let empty = SavedIndex()

    @MainActor
    static func make(context: ModelContext, now: Date = .now) -> SavedIndex {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let range = DateInterval(start: today, end: calendar.date(byAdding: .day, value: 21, to: today) ?? now)
        let formatter = ProposalFormat.machine
        var index = SavedIndex()

        let events = ((try? context.fetch(FetchDescriptor<CalendarEvent>())) ?? [])
            .filter { $0.kind != .workBlock }
            .compactMap { event -> (event: CalendarEvent, next: DateInterval)? in
                event.occurrences(in: range).first { $0.end > now }.map { (event, $0) }
            }
            .sorted { $0.next.start != $1.next.start ? $0.next.start < $1.next.start : $0.event.title < $1.event.title }
            .prefix(15)
        for (number, entry) in events.enumerated() {
            let code = "C\(number + 1)"
            let recurring = entry.event.recurrence != .none
            var line = "\(code) evento «\(entry.event.title)» \(formatter.string(from: entry.next.start))–\(ProposalFormat.time.string(from: entry.next.end)), \(entry.event.mode.rawValue)"
            if recurring { line += ", se repite (\(entry.event.recurrence.rawValue))" }
            index.append(
                SavedRef(code: code, title: entry.event.title, date: entry.next.start, kind: .event, isRecurring: recurring),
                id: entry.event.persistentModelID, line: line
            )
        }

        let tasks = ((try? context.fetch(FetchDescriptor<PlanTask>())) ?? [])
            .filter { !$0.isDone }
            .sorted { $0.deadline < $1.deadline }
            .prefix(10)
        for (number, task) in tasks.enumerated() {
            let code = "P\(number + 1)"
            let blocks = task.blocks.filter { $0.end > now }.sorted { $0.start < $1.start }.prefix(3)
                .map { formatter.string(from: $0.start) }
            var line = "\(code) tarea «\(task.title)» entrega \(formatter.string(from: task.deadline)), prioridad \(ProposalFormat.priority(task.priority)), \(task.estimatedMinutes) min, \(task.mode.rawValue)"
            if !blocks.isEmpty { line += ", bloques " + blocks.joined(separator: ", ") }
            index.append(SavedRef(code: code, title: task.title, date: task.deadline, kind: .task), id: task.persistentModelID, line: line)
        }

        let week = DateInterval(start: today, end: calendar.date(byAdding: .day, value: 7, to: today) ?? now)
        let external = ExternalCalendars.shared.events(in: week)
            .filter { !$0.isAllDay && $0.end > now }
            .sorted { $0.start < $1.start }
            .prefix(8)
        for event in external {
            index.append(
                SavedRef(code: "", title: event.title, date: event.start, kind: .external), id: nil,
                line: "- «\(event.title)» \(formatter.string(from: event.start))–\(ProposalFormat.time.string(from: event.end)) (otro calendario, solo lectura)"
            )
        }
        return index
    }

    private mutating func append(_ ref: SavedRef, id: PersistentIdentifier?, line: String) {
        refs.append(ref)
        ids.append(id)
        lines.append(line)
    }

    var text: String { lines.isEmpty ? "nada" : lines.joined(separator: "\n") }
    var titles: [String] { refs.map(\.title) }

    func detail(_ index: Int) -> String {
        let ref = refs[index]
        let when = ProposalFormat.dayTime.string(from: ref.date)
        return ref.kind == .task ? "tarea · entrega \(when)" : when
    }
}

// MARK: - Asistente

/// El asistente de planificación de Planaby. Apple Intelligence (en el dispositivo) interpreta
/// el texto y el material adjunto; el código comprueba lo entendido (que no falte ni sobre nada),
/// el reparto lo hace `WorkloadPlanner` y todo acaba en una propuesta que la persona revisa antes
/// de guardar.
///
/// Mientras no se acepta, hay una sola propuesta activa (`active`), con sus versiones. Cada
/// mensaje la modifica con operaciones deterministas (`ProposalEditor`): nada se duplica ni se
/// pierde, y se puede deshacer. Lo guardado que se pide cambiar o borrar entra en la propuesta
/// y solo cambia en el calendario al aceptarla.
@Observable
@MainActor
final class PlanningAssistant {
    enum Role: String, Codable { case user, assistant }

    /// En qué estado queda la propuesta que enseña un mensaje.
    enum ProposalState: String, Codable { case active, replaced, accepted, discarded }

    struct Message: Identifiable {
        var id = UUID()
        let role: Role
        let text: String
        var attachmentNames: [String] = []
        var proposal: ProposalState?
        /// Lo que cambió respecto a la versión anterior.
        var changes: [ProposalChange] = []
        /// Opciones de una pregunta («¿Cuál quieres mover?»).
        var options: [ProposalOption] = []
        /// Lo entendido, a la espera de saber si va a Trabajo o a Normal.
        var pending: Interpretation?
        /// Pide confirmar: enseña «Aceptar propuesta».
        var asksToAccept = false
        /// Respuestas rápidas a una pregunta sobre un dato («30 min», «1 h»…).
        var choices: [String] = []
        /// La petición falló: se puede reintentar.
        var canRetry = false
    }

    /// Lo que se guarda de cada mensaje. Los campos nuevos son opcionales para leer el historial
    /// de versiones anteriores de Planaby.
    private struct StoredMessage: Codable {
        let role: Role
        let text: String
        let attachmentNames: [String]
        var id: UUID?
        var proposal: ProposalState?
        var changes: [ProposalChange]?
    }

    private(set) var messages: [Message] = []
    private(set) var isThinking = false
    /// La propuesta que se está editando, con sus versiones.
    private(set) var active: ActiveProposal?
    /// Base de los cambios a mano en la revisión (para enseñar qué cambió al volver).
    @ObservationIgnored private var manualBase: PlanDraft?
    @ObservationIgnored private var manualCommitted = false
    /// Lo guardado tal como lo vio la IA en la última petición (los códigos C y P).
    @ObservationIgnored private var lastSaved: SavedIndex?
    /// Una pregunta «¿Cuál?» sobre algo guardado cuando aún no hay propuesta.
    @ObservationIgnored private var loose: (clarification: ProposalClarification, base: PlanDraft)?
    /// La última petición que falló, para reintentarla tal cual.
    @ObservationIgnored private var failed: (text: String, attachments: [ImportedAttachment])?

    /// La conversación se guarda en el iPhone y sigue ahí al cerrar o actualizar la app.
    private static var historyURL: URL { URL.applicationSupportDirectory.appending(path: "chat.json") }
    /// La propuesta sin aceptar, aparte: si no se puede leer, se pierde solo ella.
    private static var proposalURL: URL { URL.applicationSupportDirectory.appending(path: "proposal.json") }
    private static let historyLimit = 100

    static let offTopicText = "Estoy especializado en planificación: puedo crear, cambiar, mover o borrar eventos y tareas, y reorganizar tu semana. ¿Qué quieres planificar?"

    init() {
        let stored = (try? Data(contentsOf: Self.historyURL))
            .flatMap { try? JSONDecoder().decode([StoredMessage].self, from: $0) } ?? []
        messages = stored.map {
            Message(id: $0.id ?? UUID(), role: $0.role, text: $0.text, attachmentNames: $0.attachmentNames,
                    proposal: $0.proposal, changes: $0.changes ?? [])
        }
        active = (try? Data(contentsOf: Self.proposalURL)).flatMap { try? JSONDecoder().decode(ActiveProposal.self, from: $0) }
        // Lo que estaba activo y no tiene propuesta guardada (o es de otra) ya no se puede aceptar.
        for index in messages.indices where messages[index].proposal == .active && messages[index].id != active?.messageID {
            messages[index].proposal = .replaced
        }
        if let active, !messages.contains(where: { $0.id == active.messageID }) {
            // El mensaje se recortó del historial: se vuelve a enseñar la propuesta.
            messages.append(Message(id: active.messageID, role: .assistant, text: active.history.current.summary, proposal: .active))
        }
        // La pregunta pendiente sobre un dato vuelve a tener sus respuestas rápidas.
        if let detail = active?.detail, let last = messages.indices.last, messages[last].role == .assistant {
            messages[last].choices = detail.choices
        }
    }

    var draft: PlanDraft? { active?.history.current }
    var canUndo: Bool { active?.history.canUndo ?? false }
    var canRedo: Bool { active?.history.canRedo ?? false }
    var canRetry: Bool { failed != nil }

    func clearHistory() {
        messages = []
        active = nil
        loose = nil
        failed = nil
        saveHistory()
        saveProposal()
    }

    private func saveHistory() {
        let stored = messages.suffix(Self.historyLimit).map {
            StoredMessage(role: $0.role, text: $0.text, attachmentNames: $0.attachmentNames, id: $0.id,
                          proposal: $0.proposal, changes: $0.changes.isEmpty ? nil : $0.changes)
        }
        if let data = try? JSONEncoder().encode(Array(stored)) {
            try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
            try? data.write(to: Self.historyURL, options: .atomic)
        }
    }

    private func saveProposal() {
        guard let active else {
            try? FileManager.default.removeItem(at: Self.proposalURL)
            return
        }
        if let data = try? JSONEncoder().encode(active) {
            try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
            try? data.write(to: Self.proposalURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    /// Al abrir el chat: la propuesta recuperada se comprueba contra la base de datos (lo
    /// borrado desde entonces se olvida) y se recolocan los bloques que ya han pasado.
    func restore(context: ModelContext) {
        guard var current = active?.history.current else { return }
        let events = Set(((try? context.fetch(FetchDescriptor<CalendarEvent>())) ?? []).map(\.persistentModelID))
        let tasks = Set(((try? context.fetch(FetchDescriptor<PlanTask>())) ?? []).filter { !$0.isDone }.map(\.persistentModelID))
        current.removals.removeAll { !events.contains($0) }
        for index in current.tasks.indices {
            current.tasks[index].replacedBlocks.removeAll { !events.contains($0) }
        }
        let gone = current.tasks.filter { $0.existing.map { !tasks.contains($0) } ?? false }.map(\.id)
        for id in gone { ProposalEditor.remove(id, from: &current) }
        // Lo guardado que se iba a cambiar o borrar y ya no existe.
        current.deletions.removeAll { $0.isTask ? !tasks.contains($0.id) : !events.contains($0.id) }
        current.items.removeAll { item in item.replaces.map { !events.contains($0) } ?? false }
        current.items.removeAll { $0.kind != .workBlock && $0.recurrence == .none && $0.end < .now && $0.replaces == nil }

        let stale = current.blocks.contains { $0.start < .now }
        guard current != active?.history.current || stale else { return }
        if current.items.isEmpty && current.tasks.isEmpty && current.deletions.isEmpty {
            dropActive(as: .replaced)
            reply("La propuesta que tenías pendiente ya había pasado. Dime qué quieres planificar.")
            return
        }
        current = PlanBuilder.replan(current, affected: Set(gone), context: context)
        active?.history.replaceCurrent(current)
        active?.updated = .now
        saveProposal()
    }

    /// nil si está disponible; si no, el motivo para mostrarlo.
    static var unavailableReason: String? { AIProvider.unavailableReason }

    var unavailableReason: String? { Self.unavailableReason }

    // MARK: Chat

    /// Atiende un mensaje. Devuelve false si no se pudo (error, cancelación o IA no disponible):
    /// entonces la vista devuelve el texto al campo para no perderlo.
    @discardableResult
    func send(_ text: String, attachments: [ImportedAttachment] = [], context: ModelContext, isRetry: Bool = false) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty, !isThinking else { return false }
        clearPrompts()
        if !isRetry {
            messages.append(Message(role: .user, text: trimmed.isEmpty ? "Organiza esto" : trimmed, attachmentNames: attachments.map(\.name)))
        }
        failed = nil
        saveHistory()

        if attachments.isEmpty, answerWithoutAI(trimmed, context: context) { return true }

        guard unavailableReason == nil else {
            reply(active == nil
                  ? (unavailableReason ?? "")
                  : "Sin Apple Intelligence no puedo entender ese cambio. Puedes editar la propuesta en «Revisar propuesta», o decir «deshaz».")
            return false
        }

        // Una pregunta «¿Cuál?» que no se ha contestado deja de valer: la petición es otra.
        active?.clarification = nil
        loose = nil
        isThinking = true
        defer { isThinking = false }
        let saved = SavedIndex.make(context: context)
        do {
            let prompt = Self.prompt(
                for: trimmed, attachments: attachments, saved: saved, context: context,
                proposal: activeProposalText, recent: recentConversation
            )
            var sources = [trimmed] + attachments.map(\.text)
            sources += messages.dropLast().suffix(4).filter { $0.role == .user }.map(\.text)
            var result = try await Self.respond(
                to: prompt, request: trimmed, sources: sources, saved: saved, context: context, proposal: draft
            )
            try Task.checkCancellation()
            // El material adjunto queda guardado con las tareas que salgan de él.
            for index in result.tasks.indices {
                result.tasks[index].attachments = attachments
            }
            lastSaved = saved
            respond(to: result, saved: saved, context: context)
            return true
        } catch is CancellationError {
            reply(active == nil ? "Cancelado." : "Cancelado. Tu propuesta sigue igual.")
            return false
        } catch {
            // La propuesta no se toca: el error solo se cuenta, y se puede reintentar.
            failed = (trimmed, attachments)
            messages.append(Message(
                role: .assistant, text: Self.message(for: error) + (active == nil ? "" : " Tu propuesta sigue igual."), canRetry: true
            ))
            saveHistory()
            return false
        }
    }

    /// Vuelve a enviar la última petición que falló.
    func retry(context: ModelContext) async {
        guard let failed else { return }
        await send(failed.text, attachments: failed.attachments, context: context, isRetry: true)
    }

    /// Lo que se entiende sin el modelo: respuestas a una pregunta sobre un dato («1 h»), a
    /// «¿Cuál?», y deshacer, rehacer y aceptar.
    private func answerWithoutAI(_ text: String, context: ModelContext) -> Bool {
        if var proposal = active, let detail = proposal.detail {
            let current = proposal.history.current
            switch detail.answer(text, in: current, now: .now) {
            case .edits(let edits):
                proposal.detail = nil
                active = proposal
                applyEdits(edits, mergeSimilar: false, request: text, saved: .empty, oneByOne: detail.oneByOne, context: context)
                return true
            case .eachSeparately:
                proposal.detail = nil
                active = proposal
                askDetailIfNeeded(oneByOne: true)
                return true
            case .keep:
                var next = current
                detail.keep(in: &next)
                proposal.detail = nil
                proposal.history.commit(next)
                commit(proposal, text: "De acuerdo, lo dejo así.", changes: [])
                askDetailIfNeeded(oneByOne: detail.oneByOne)
                return true
            case .unknown:
                // Se lo pregunta a la IA, con la pregunta en la conversación reciente.
                proposal.detail = nil
                active = proposal
                saveProposal()
            }
        }
        if let clarification = active?.clarification ?? loose?.clarification,
           let option = clarification.option(matching: text), let edits = clarification.resolved(with: option.id) {
            resolveClarification(edits, request: text, context: context)
            return true
        }
        if active != nil {
            switch ProposalCommand.detect(text) {
            case .undo: undo(context: context); return true
            case .redo: redo(context: context); return true
            case .accept: askToAccept(); return true
            case nil: break
            }
        }
        return false
    }

    /// Respuesta a «¿Trabajo o Normal?».
    func chooseMode(_ mode: PlanMode, for messageID: Message.ID, context: ModelContext) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              var result = messages[index].pending else { return }
        messages[index].pending = nil
        result.assign(mode)
        messages.append(Message(role: .user, text: mode.title))
        saveHistory()
        respond(to: result, saved: lastSaved ?? SavedIndex.make(context: context), context: context)
    }

    /// Respuesta a «¿Cuál quieres mover?» tocando una opción.
    func choose(_ option: ProposalOption, context: ModelContext) {
        guard let clarification = active?.clarification ?? loose?.clarification,
              let edits = clarification.resolved(with: option.id) else { return }
        clearPrompts()
        messages.append(Message(role: .user, text: "\(option.title) (\(option.detail))"))
        saveHistory()
        resolveClarification(edits, request: "", context: context)
    }

    private func resolveClarification(_ edits: [ProposalEdit], request: String, context: ModelContext) {
        let base = active == nil ? loose?.base : nil
        active?.clarification = nil
        loose = nil
        applyEdits(edits, mergeSimilar: false, request: request, saved: lastSaved ?? SavedIndex.make(context: context),
                   start: base, context: context)
    }

    private func respond(to result: Interpretation, saved: SavedIndex, context: ModelContext) {
        if result.offTopic {
            reply(Self.offTopicText)
            return
        }
        if result.needsMode {
            messages.append(Message(role: .assistant, text: result.modeQuestion, pending: result))
            saveHistory()
            return
        }
        if result.undo, active != nil, result.proposalEdits.isEmpty, !result.reorganize, result.prioritize.isEmpty {
            undo(context: context)
            return
        }
        guard !result.isEmpty else {
            let text = ([result.question] + result.problems).filter { !$0.isEmpty }.joined(separator: "\n")
            if active != nil {
                reply(text.isEmpty ? "No he entendido qué cambiar. Prueba con «Mueve la reunión al viernes», «Que el informe dure 3 horas» o «Quita la llamada»." : text)
            } else {
                reply(text.isEmpty ? "No he encontrado nada que planificar. Prueba con algo como «Reunión con Marta el jueves a las 10», «Estudiar para el examen del día 20» o «Borra la tarea de revisar documentación del jueves»." : text)
            }
            return
        }

        if active != nil {
            // Tareas ya guardadas que se quieren adelantar: entran en la propuesta al reorganizar.
            let reorganize = result.reorganize || !result.prioritize.isEmpty
            if result.undo { undo(context: context) }
            applyEdits(result.proposalEdits, mergeSimilar: !ProposalCommand.wantsAnother(result.request), request: result.request,
                       reorganize: reorganize, prioritize: result.prioritize, problems: result.problems,
                       question: [result.shortfall, result.question].compactMap { $0 }.joined(separator: "\n"),
                       saved: saved, context: context)
            return
        }

        let hasNew = !result.events.isEmpty || !result.tasks.isEmpty || result.reorganize || !result.prioritize.isEmpty
        guard hasNew else {
            guard !result.itemEdits.isEmpty else {
                reply("Primero dime qué quieres planificar; luego aplico esa condición a la propuesta.")
                return
            }
            // Solo cambios sobre lo guardado: la propuesta empieza vacía.
            applyEdits(result.edits, mergeSimilar: false, request: result.request, problems: result.problems,
                       question: result.question, saved: saved, context: context)
            return
        }

        let draft = result.makeDraft(context: context)
        let id = UUID()
        var lines: [String] = []
        if let narration = ProposalNarration.created(events: draft.createdEvents, tasks: draft.createdTasks) {
            lines.append(narration)
            if !draft.blocks.isEmpty || result.reorganize { lines.append(draft.summary) }
        } else {
            lines.append(draft.summary)
        }
        lines += [result.shortfall, result.question].compactMap { $0 }
        retireProposals()
        active = ActiveProposal(history: ProposalHistory(draft), messageID: id)
        messages.append(Message(id: id, role: .assistant, text: lines.filter { !$0.isEmpty }.joined(separator: "\n"), proposal: .active))
        saveHistory()
        saveProposal()
        if result.itemEdits.isEmpty {
            askDetailIfNeeded()
        } else {
            // Lo nuevo y, a la vez, cambios sobre lo guardado («añade… y borra el duplicado»).
            applyEdits(result.itemEdits, mergeSimilar: false, request: result.request, saved: saved, context: context)
        }
    }

    // MARK: Editar la propuesta (y lo guardado)

    private enum EditStep {
        case done(next: PlanDraft, base: PlanDraft, changes: [ProposalChange], notes: [String])
        case clarify(ProposalClarification, base: PlanDraft)
        case stop(String)
    }

    /// A qué se refiere una operación: la propuesta, algo guardado o algo de otro calendario.
    private enum Located {
        case proposal
        case saved(Int)
        case external(String)
        case ambiguous([Int])
        case notFound
    }

    /// Aplica operaciones a la propuesta activa (o a una nueva, si solo se cambia lo guardado):
    /// resuelve referencias (o pregunta), cambia solo lo pedido, recoloca lo necesario y guarda
    /// una versión nueva. Si algo falla, la propuesta no cambia.
    private func applyEdits(
        _ edits: [ProposalEdit], mergeSimilar: Bool, request: String, reorganize: Bool = false,
        prioritize: [PersistentIdentifier] = [], problems: [String] = [], question: String = "",
        saved: SavedIndex, start: PlanDraft? = nil, oneByOne: Bool = false, context: ModelContext
    ) {
        let initial = start ?? active?.history.current ?? PlanDraft(items: [], tasks: [], summary: "", warnings: [])
        let step = runEdits(edits, on: initial, mergeSimilar: mergeSimilar, request: request, reorganize: reorganize,
                            prioritize: prioritize, saved: saved, context: context)
        switch step {
        case .stop(let text):
            reply(text + (active == nil ? "" : " Tu propuesta sigue igual."))
        case .clarify(let clarification, let base):
            if var proposal = active {
                // Lo guardado que ya se ha localizado entra en la propuesta sin cambios.
                proposal.history.replaceCurrent(base)
                proposal.clarification = clarification
                active = proposal
            } else {
                loose = (clarification, base)
            }
            messages.append(Message(role: .assistant, text: clarification.question, options: clarification.options))
            saveHistory()
            saveProposal()
        case .done(var next, let base, let changes, let notes):
            let extra = notes + problems + [question]
            let confirmed = next.items.map(\.unconfirmed) != base.items.map(\.unconfirmed)
            guard !changes.isEmpty || reorganize || confirmed else {
                let text = extra.filter { !$0.isEmpty }.joined(separator: "\n")
                reply(text.isEmpty ? (active == nil ? "No hay nada que cambiar." : "Eso ya estaba así en la propuesta.") : text)
                return
            }
            next.warnings = next.warnings.filter { !notes.contains($0) }
            let text = updateText(changes: changes, isNew: active == nil, extra: extra)
            if var proposal = active {
                proposal.history.commit(next)
                proposal.clarification = nil
                commit(proposal, text: text, changes: changes)
            } else {
                commit(ActiveProposal(history: ProposalHistory(next), messageID: UUID()), text: text, changes: changes)
            }
            askDetailIfNeeded(oneByOne: oneByOne)
        }
    }

    private func runEdits(
        _ edits: [ProposalEdit], on initial: PlanDraft, mergeSimilar: Bool, request: String, reorganize: Bool,
        prioritize: [PersistentIdentifier], saved: SavedIndex, context: ModelContext
    ) -> EditStep {
        let now = Date.now
        var base = initial
        var kept: [ProposalEdit] = []
        var notes: [String] = []
        for (position, edit) in edits.enumerated() {
            guard let target = edit.target else {
                kept.append(edit)
                continue
            }
            switch locate(target, in: base, saved: saved, now: now) {
            case .proposal:
                kept.append(edit)
            case .saved(let index):
                switch materialize(index, saved: saved, into: &base, request: request, context: context, now: now) {
                case .success(let code):
                    // «Quita» algo guardado que no estaba en la propuesta solo puede ser borrarlo.
                    var operation = edit.with(target: ProposalTarget(text: code, kind: target.kind))
                    if case .remove = edit { operation = .delete(ProposalTarget(text: code, kind: target.kind)) }
                    kept.append(operation)
                case .failure(let problem):
                    notes.append(problem.text)
                }
            case .external(let title):
                notes.append("«\(title)» es de otro calendario y aquí solo se puede ver: cámbialo desde su app.")
            case .ambiguous(let candidates):
                let options = candidates.map { index in
                    ProposalOption(id: UUID(), ref: saved.refs[index].code, title: saved.refs[index].title, detail: saved.detail(index))
                }
                return .clarify(ProposalClarification(
                    question: Self.question(for: edit), options: options, edits: edits, index: position
                ), base: base)
            case .notFound:
                return .stop("No encuentro «\(target.text)» ni en la propuesta ni en tu calendario.")
            }
        }
        if kept.isEmpty && !reorganize && prioritize.isEmpty {
            return .stop(notes.isEmpty ? "No he entendido qué cambiar." : notes.joined(separator: "\n"))
        }

        var outcome = ProposalEditOutcome(draft: base, affectedTasks: [], problems: [])
        if !kept.isEmpty {
            switch ProposalEditor.apply(kept, to: base, mergeSimilar: mergeSimilar) {
            case .applied(let result):
                outcome = result
            case .clarify(let clarification):
                return .clarify(clarification, base: base)
            case .failed(let reason):
                return .stop(reason)
            }
        }

        var next = PlanBuilder.replan(outcome.draft, affected: outcome.affectedTasks, reorganizeAll: reorganize, context: context)
        if !prioritize.isEmpty {
            // Lo elegido va primero, en el orden dicho.
            let chosen = prioritize.compactMap { id in next.tasks.first { $0.existing == id }?.id }
            next.order = chosen + next.orderedTasks.map(\.id).filter { !chosen.contains($0) }
            next = PlanBuilder.replan(next, affected: Set(next.tasks.map(\.id)), context: context)
        }
        next.warnings = outcome.problems + next.warnings
        let changes = ProposalDiff.changes(from: base, to: next)
        return .done(next: next, base: base, changes: changes, notes: outcome.problems + notes)
    }

    /// Primero la propuesta (por código o por nombre); si no está ahí, lo guardado.
    private func locate(_ target: ProposalTarget, in draft: PlanDraft, saved: SavedIndex, now: Date) -> Located {
        if ProposalText.code(in: target.text) != nil { return .proposal }
        if let code = ProposalText.savedCode(in: target.text) {
            guard let index = saved.refs.firstIndex(where: { $0.code == code }) else { return .notFound }
            return .saved(index)
        }
        let query = ProposalText.keywords(target.text)
        var titles: [String] = []
        if target.kind != .task { titles += draft.newEvents.map(\.title) }
        if target.kind != .event { titles += draft.tasks.map(\.title) }
        if query.isEmpty { return titles.isEmpty ? .notFound : .proposal }
        let inProposal = titles.map { ProposalText.score(query: query, title: $0) }.max() ?? 0

        switch SavedResolver.resolve(target.text, kind: target.kind, in: saved.refs, now: now) {
        case .found(let index):
            let savedScore = ProposalText.score(query: query, title: saved.refs[index].title)
            if inProposal > 0, inProposal >= savedScore { return .proposal }
            return saved.refs[index].kind == .external ? .external(saved.refs[index].title) : .saved(index)
        case .ambiguous(let candidates):
            if inProposal > 0 { return .proposal }
            let editable = candidates.filter { saved.refs[$0].kind != .external }
            if editable.isEmpty, let first = candidates.first { return .external(saved.refs[first].title) }
            return editable.count == 1 ? .saved(editable[0]) : .ambiguous(editable)
        case .notFound:
            return inProposal > 0 ? .proposal : .notFound
        }
    }

    private struct EditProblem: Error { let text: String }

    /// Mete en la propuesta, sin cambiarlo, el elemento guardado al que se refiere la persona,
    /// para editarlo o borrarlo con las mismas operaciones que lo nuevo. Devuelve su código.
    private func materialize(
        _ index: Int, saved: SavedIndex, into draft: inout PlanDraft, request: String, context: ModelContext, now: Date
    ) -> Result<String, EditProblem> {
        let ref = saved.refs[index]
        guard let id = saved.ids[index] else {
            return .failure(EditProblem(text: "«\(ref.title)» es de otro calendario y aquí solo se puede ver."))
        }
        switch ref.kind {
        case .event:
            if let existing = draft.items.first(where: { $0.replaces == id }) { return .success(draft.ref(existing.id)) }
            guard let event = ((try? context.fetch(FetchDescriptor<CalendarEvent>())) ?? []).first(where: { $0.persistentModelID == id }) else {
                return .failure(EditProblem(text: "«\(ref.title)» ya no está en tu calendario."))
            }
            if event.recurrence != .none, !SavedResolver.wantsWholeSeries(request) {
                return .failure(EditProblem(text: "«\(event.title)» se repite (\(event.recurrence.title.lowercased())). Planaby solo puede cambiar o borrar la serie entera; si es lo que quieres, dímelo con «todas», por ejemplo «borra todas las \(event.title)»."))
            }
            let item = PlanDraft.Item(
                title: event.title, start: event.start, end: event.end, mode: event.mode, kind: event.kind,
                recurrence: event.recurrence, reminderMinutes: event.reminderMinutes, replaces: id
            )
            draft.items.append(item)
            draft.assignRefs()
            return .success(draft.ref(item.id))
        case .task:
            if let existing = draft.tasks.first(where: { $0.existing == id }) { return .success(draft.ref(existing.id)) }
            guard let task = ((try? context.fetch(FetchDescriptor<PlanTask>())) ?? []).first(where: { $0.persistentModelID == id }) else {
                return .failure(EditProblem(text: "«\(ref.title)» ya no está entre tus tareas."))
            }
            let workload = PlanBuilder.editableWorkload(task, now: now)
            draft.tasks.append(workload)
            draft.removals += workload.replacedBlocks.filter { !draft.removals.contains($0) }
            // Sus bloques siguen donde estaban mientras no se pida moverlos.
            for block in task.blocks where block.start > now {
                draft.items.append(PlanDraft.Item(
                    title: task.title, start: block.start, end: block.end, mode: task.mode, kind: .workBlock,
                    reminderMinutes: block.reminderMinutes, taskID: workload.id
                ))
            }
            draft.items.sort { $0.start < $1.start }
            draft.assignRefs()
            return .success(draft.ref(workload.id))
        case .external:
            return .failure(EditProblem(text: "«\(ref.title)» es de otro calendario y aquí solo se puede ver."))
        }
    }

    private static func question(for edit: ProposalEdit) -> String {
        switch edit {
        case .remove, .delete: "¿Cuál quieres borrar?"
        case .moveFirst: "¿Cuál va primero?"
        case .update(_, let changes): changes.isReschedule ? "¿Cuál quieres mover?" : "¿Cuál quieres cambiar?"
        default: "¿A cuál te refieres?"
        }
    }

    /// Si a un evento le falta un dato (día, duración u hora), se pregunta con respuestas rápidas.
    private func askDetailIfNeeded(oneByOne: Bool = false) {
        guard var proposal = active, var question = DetailQuestion.next(in: proposal.history.current) else { return }
        if oneByOne, question.itemIDs.count > 1,
           let first = proposal.history.current.items.first(where: { $0.id == question.itemIDs[0] }) {
            question = DetailQuestion.make(question.field, items: [first])
        }
        question.oneByOne = oneByOne
        proposal.detail = question
        active = proposal
        messages.append(Message(role: .assistant, text: question.question, choices: question.choices))
        saveHistory()
        saveProposal()
    }

    /// Vuelve a la versión anterior de la propuesta (nunca a algo ya aceptado: al aceptar se
    /// borran las versiones).
    func undo(context: ModelContext) {
        guard var proposal = active else {
            reply("No hay ninguna propuesta abierta.")
            return
        }
        let before = proposal.history.current
        guard let previous = proposal.history.undo() else {
            reply("No hay nada que deshacer.")
            return
        }
        proposal.clarification = nil
        proposal.detail = nil
        let changes = ProposalDiff.changes(from: before, to: previous)
        commit(proposal, text: "He deshecho el último cambio.", changes: changes)
    }

    func redo(context: ModelContext) {
        guard var proposal = active else { return }
        let before = proposal.history.current
        guard let next = proposal.history.redo() else {
            reply("No hay nada que rehacer.")
            return
        }
        proposal.detail = nil
        let changes = ProposalDiff.changes(from: before, to: next)
        commit(proposal, text: "He vuelto a aplicar el cambio.", changes: changes)
    }

    /// La propuesta nueva pasa a ser la activa y la anterior queda sustituida.
    private func commit(_ proposal: ActiveProposal, text: String, changes: [ProposalChange]) {
        var proposal = proposal
        let id = UUID()
        proposal.messageID = id
        proposal.updated = .now
        retireProposals()
        clearPrompts()
        active = proposal
        messages.append(Message(id: id, role: .assistant, text: text, proposal: .active, changes: changes))
        saveHistory()
        saveProposal()
    }

    private func retireProposals() {
        for index in messages.indices where messages[index].proposal == .active {
            messages[index].proposal = .replaced
            messages[index].asksToAccept = false
        }
    }

    /// Las respuestas rápidas y los «¿Cuál?» de mensajes anteriores ya no valen.
    private func clearPrompts() {
        for index in messages.indices {
            messages[index].options = []
            messages[index].choices = []
            messages[index].canRetry = false
        }
    }

    private func updateText(changes: [ProposalChange], isNew: Bool, extra: [String]) -> String {
        var lines = [isNew ? "He preparado los cambios. No se guarda nada hasta que aceptes." : "He actualizado tu planificación."]
        if changes.contains(where: { $0.kind == .deleted }) {
            lines.append("Revisa lo que se borrará antes de aceptar.")
        }
        return (lines + extra.filter { !$0.isEmpty }).joined(separator: "\n")
    }

    private func askToAccept() {
        guard let draft else { return }
        let id = active?.messageID
        for index in messages.indices where messages[index].id == id { messages[index].asksToAccept = false }
        let text = "Esta es la versión final: \(draft.summary)\nPulsa «Aceptar propuesta» para guardarla en tu calendario."
        retireProposals()
        let message = UUID()
        active?.messageID = message
        messages.append(Message(id: message, role: .assistant, text: text, proposal: .active, asksToAccept: true))
        saveHistory()
        saveProposal()
    }

    /// Guarda la última versión. Es lo único que escribe en el calendario.
    func acceptActive(context: ModelContext) {
        guard let draft else { return }
        PlanBuilder.accept(draft, context: context)
        markAccepted()
    }

    /// La propuesta activa se aceptó (desde aquí o desde la revisión).
    func markAccepted() {
        dropActive(as: .accepted)
        reply("Hecho: tu calendario está actualizado.")
    }

    /// Se descarta la propuesta: no se guarda nada.
    func discardActive() {
        guard active != nil else { return }
        clearPrompts()
        dropActive(as: .discarded)
        reply("He descartado la propuesta. No se ha guardado nada.")
    }

    private func dropActive(as state: ProposalState) {
        let id = active?.messageID
        for index in messages.indices where messages[index].id == id {
            messages[index].proposal = state
            messages[index].asksToAccept = false
            messages[index].options = []
        }
        active = nil
        loose = nil
        manualBase = nil
        saveHistory()
        saveProposal()
    }

    func isActive(_ message: Message) -> Bool { message.id == active?.messageID }

    private func reply(_ text: String) {
        messages.append(Message(role: .assistant, text: text))
        saveHistory()
    }

    // MARK: Cambios a mano (revisión)

    func beginManualEdits() {
        manualBase = draft
        manualCommitted = false
    }

    /// Cada cambio hecho en la revisión: el primero crea una versión (para poder deshacerlo);
    /// los siguientes la completan.
    func updateManually(_ new: PlanDraft) {
        guard var active, new != active.history.current else { return }
        if manualCommitted {
            active.history.replaceCurrent(new)
        } else {
            active.history.commit(new)
            manualCommitted = true
        }
        active.updated = .now
        self.active = active
        saveProposal()
    }

    /// Al volver de la revisión, el chat enseña lo que se cambió a mano.
    func endManualEdits() {
        defer { manualBase = nil; manualCommitted = false }
        guard let base = manualBase, var active, manualCommitted else { return }
        let changes = ProposalDiff.changes(from: base, to: active.history.current)
        guard !changes.isEmpty else { return }
        // Una pregunta pendiente sobre un dato que se ha cambiado a mano ya no hace falta.
        if active.detail != nil, DetailQuestion.next(in: active.history.current) != active.detail { active.detail = nil }
        commit(active, text: "He guardado tus cambios en la propuesta.", changes: changes)
        if self.active?.detail == nil { askDetailIfNeeded() }
    }

    // MARK: Contexto de la propuesta

    /// La propuesta activa para el modelo: códigos, datos y condiciones.
    private var activeProposalText: String {
        guard let draft else { return "ninguna" }
        var text = draft.describe(formatter: ProposalFormat.machine)
        var conditions: [String] = []
        if let latest = draft.constraints.latestEndMinute { conditions.append("nada después de las \(ProposalFormat.clock(latest))") }
        if let earliest = draft.constraints.earliestStartMinute { conditions.append("nada antes de las \(ProposalFormat.clock(earliest))") }
        if !draft.constraints.freeIntervals.isEmpty { conditions.append("\(draft.constraints.freeIntervals.count) franjas libres") }
        if draft.constraints.lighter { conditions.append("menos intenso") }
        if draft.constraints.hardInMorning { conditions.append("lo difícil por la mañana") }
        if !conditions.isEmpty { text += "\nCondiciones: " + conditions.joined(separator: ", ") }
        return text
    }

    /// Los últimos mensajes, para entender respuestas cortas («1 hora», «la de Jonatan»).
    private var recentConversation: String {
        let recent = messages.dropLast().suffix(4).map { message in
            (message.role == .user ? "Usuario: " : "Planaby: ") + String(message.text.prefix(200))
        }
        return recent.isEmpty ? "ninguna" : recent.joined(separator: "\n")
    }

    // MARK: Interpretación

    /// Interpreta una petición suelta (también la usan Reorganizar y la voz).
    static func interpret(
        _ text: String, attachments: [ImportedAttachment] = [], session: LanguageModelSession? = nil, context: ModelContext
    ) async throws -> Interpretation {
        let saved = SavedIndex.make(context: context)
        return try await respond(
            to: prompt(for: text, attachments: attachments, saved: saved, context: context), request: text,
            sources: [text] + attachments.map(\.text), saved: saved, context: context, proposal: nil, session: session
        )
    }

    /// Una sesión nueva por petición: el contexto va en el mensaje (propuesta, últimos mensajes),
    /// así una conversación larga no llena la memoria del modelo del iPhone. Si faltan elementos
    /// de los que se pidieron, se intenta una vez más diciéndoselo.
    private static func respond(
        to prompt: String, request: String, sources: [String], saved: SavedIndex, context: ModelContext,
        proposal: PlanDraft?, session: LanguageModelSession? = nil
    ) async throws -> Interpretation {
        let session = session ?? makeSession()
        let options = GenerationOptions(temperature: 0.2)
        let response = try await session.respond(to: prompt, generating: ParsedPlan.self, options: options)
        var result = convert(response.content, request: request, sources: sources, saved: saved, context: context, proposal: proposal)
        if let expected = result.expectedCount, result.newCount < expected {
            try Task.checkCancellation()
            let found = (result.events.map(\.title) + result.tasks.map(\.title)).map { "«\($0)»" }.joined(separator: ", ")
            let correction = prompt + "\nAtención: el usuario pide \(expected) elementos nuevos y solo has devuelto \(result.newCount) (\(found.isEmpty ? "ninguno" : found)). Devuélvelos todos, uno por elemento, con su nombre exacto; deja vacío lo que no diga."
            if let second = try? await makeSession().respond(to: correction, generating: ParsedPlan.self, options: options) {
                let again = convert(second.content, request: request, sources: sources, saved: saved, context: context, proposal: proposal)
                if again.newCount > result.newCount { result = again }
            }
        }
        return result
    }

    /// Convierte lo que devuelve el modelo en borradores y operaciones, y lo comprueba con la
    /// petición: nombres exactos, fechas escritas, nada inventado y lo que falta marcado como
    /// provisional (para preguntarlo).
    private static func convert(
        _ parsed: ParsedPlan, request: String, sources: [String], saved: SavedIndex, context: ModelContext,
        proposal: PlanDraft?, now: Date = .now
    ) -> Interpretation {
        let fallbackMode = ModeController.shared.mode
        let calendar = Calendar.current
        var result = Interpretation()
        result.request = request

        let titles = parsed.events.map { RequestGrounding.exactTitle($0.title, in: request) }
        let written = RequestDates.days(for: titles, in: request, now: now, calendar: calendar)
        let saysWhen = RequestDates.saysWhen(request, now: now, calendar: calendar)
        let saysTime = AnswerParsing.time(request) != nil
        let saysDuration = AnswerParsing.duration(request) != nil
        let defaultStart = ModeController.shared.availability(for: .work).startMinute
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now

        var events: [PlanDraft.Item] = []
        var undecidedEvents: Set<UUID> = []
        for (index, event) in parsed.events.enumerated() {
            let title = titles[index]
            guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let recurrence = Recurrence(rawValue: event.repeats) ?? .none
            var missing: [ItemField] = []
            // El día escrito en la petición («Subida PRE para el 25 de noviembre») manda.
            let day = written[index] ?? ProposalFormat.day(event.day, calendar: calendar)
            if written[index] == nil, recurrence == .none, day == nil || !saysWhen { missing.append(.day) }
            let startMinute = ProposalFormat.minute(event.time)
            if startMinute == nil || !saysTime { missing.append(.time) }
            var minutes = event.durationMinutes > 0 ? event.durationMinutes : nil
            if let endMinute = ProposalFormat.minute(event.endTime), let startMinute {
                var end = endMinute
                if end <= startMinute, end + 12 * 60 > startMinute { end += 12 * 60 }
                if end > startMinute { minutes = end - startMinute }
            }
            if minutes == nil || !(saysDuration || ProposalFormat.minute(event.endTime) != nil) { missing.append(.duration) }
            let start = ProposalEditor.at(minute: startMinute ?? defaultStart, on: day ?? tomorrow, calendar: calendar)
            var item = PlanDraft.Item(
                title: title, start: start, end: start.addingTimeInterval(TimeInterval((minutes ?? 60) * 60)),
                mode: PlanMode(rawValue: event.mode) ?? fallbackMode, kind: .event, recurrence: recurrence,
                reminderMinutes: event.reminderMinutes > 0 ? event.reminderMinutes : nil
            )
            item.unconfirmed = missing.isEmpty ? nil : missing
            if PlanMode(rawValue: event.mode) == nil { undecidedEvents.insert(item.id) }
            events.append(item)
        }

        var tasks: [PlanDraft.Workload] = []
        var undecidedTasks: Set<UUID> = []
        for task in parsed.tasks {
            guard let deadline = ProposalFormat.dateTime(task.deadline) else {
                result.problems.append("No entendí la fecha límite de «\(task.title)».")
                continue
            }
            let workload = PlanDraft.Workload(
                id: UUID(), title: RequestGrounding.exactTitle(task.title, in: request),
                mode: PlanMode(rawValue: task.mode) ?? fallbackMode,
                deadline: deadline, estimatedMinutes: task.estimatedMinutes, priority: task.priority,
                difficulty: task.difficulty
            )
            if PlanMode(rawValue: task.mode) == nil { undecidedTasks.insert(workload.id) }
            tasks.append(workload)
        }

        // Nada inventado: fuera lo que nadie pidió y es una rutina («Comida») o la copia de algo
        // que ya está en la agenda o en la propuesta.
        let deterministic = RequestCheck.expectedNewItems(in: request)
        result.expectedCount = deterministic ?? (parsed.requestedCount > 1 ? parsed.requestedCount : nil)
        let agenda = saved.titles + (proposal.map { $0.newEvents.map(\.title) + $0.tasks.map(\.title) } ?? [])
        let keep = RequestGrounding.keep(
            titles: events.map(\.title) + tasks.map(\.title), sources: sources, agenda: agenda, expected: result.expectedCount
        )
        result.events = events.indices.filter { keep[$0] }.map { events[$0] }
        result.tasks = tasks.indices.filter { keep[events.count + $0] }.map { tasks[$0] }
        result.undecidedEvents = undecidedEvents.intersection(result.events.map(\.id))
        result.undecidedTasks = undecidedTasks.intersection(result.tasks.map(\.id))

        for edit in parsed.edits {
            let fields = ProposalEditFields(
                action: edit.action, target: edit.target, title: edit.title, day: edit.day, time: edit.time,
                endTime: edit.endTime, minutes: edit.minutes, deadline: edit.deadline, priority: edit.priority,
                difficulty: edit.difficulty, mode: edit.mode, repeats: edit.repeats, reminderMinutes: edit.reminderMinutes,
                workDay: edit.workDay
            )
            if fields.isUndo {
                if proposal != nil { result.undo = true }
            } else if let operation = fields.makeEdit(), !fields.target.trimmingCharacters(in: .whitespaces).isEmpty {
                result.edits.append(operation)
            }
        }
        for condition in parsed.conditions {
            let fields = ProposalConditionFields(kind: condition.kind, day: condition.day, from: condition.from, to: condition.to)
            if let operation = fields.makeEdit() { result.edits.append(operation) }
        }

        // Lo que se quiere priorizar: si está en la propuesta, se pone primero ahí; si no, se
        // busca entre las tareas guardadas.
        let pending = ((try? context.fetch(FetchDescriptor<PlanTask>())) ?? []).filter { !$0.isDone }
        for title in parsed.prioritize {
            if let proposal, case .found = ProposalEditor.resolve(ProposalTarget(text: title, kind: .task), in: proposal) {
                result.first.append(title)
                continue
            }
            let needle = title.lowercased()
            if let match = pending.first(where: { $0.title.lowercased().contains(needle) || needle.contains($0.title.lowercased()) }),
               !result.prioritize.contains(match.persistentModelID) {
                result.prioritize.append(match.persistentModelID)
            }
        }
        result.reorganize = parsed.reorganize && (proposal == nil || result.edits.isEmpty)
        result.question = parsed.question.trimmingCharacters(in: .whitespacesAndNewlines)
        // Los datos que faltan de un evento los pregunta Planaby, con opciones.
        if result.events.contains(where: { $0.unconfirmed != nil }) { result.question = "" }
        result.offTopic = parsed.offTopic && result.isEmpty
        return result
    }

    // MARK: Estimación de complejidad

    /// Estima tiempo y dificultad de una tarea a partir de su descripción y el texto de su material.
    static func estimate(title: String, notes: String, deadline: Date, attachmentTexts: [String]) async throws -> ComplexityEstimate {
        let session = AIProvider.session(instructions: """
            Eres un asistente que estima tareas de trabajo y estudio. A partir del título, las notas y el material \
            adjunto (texto extraído de capturas o documentos), estima el tiempo total realista y la dificultad, \
            explica brevemente por qué y propone pasos concretos. Escribe en español.
            """)
        let material = attachmentTexts
            .filter { !$0.isEmpty }
            .joined(separator: "\n---\n")
            .prefix(5_000)
        let prompt = """
            Tarea: \(title)
            Entrega: \(deadline.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))
            Notas: \(notes.isEmpty ? "ninguna" : notes)
            Material adjunto:
            \(material.isEmpty ? "ninguno" : AIProvider.wrap(String(material), limit: 5_000))
            """
        let response = try await session.respond(to: prompt, generating: ComplexityEstimate.self, options: GenerationOptions(temperature: 0.3))
        return response.content
    }

    static func message(for error: Error) -> String {
        guard let error = error as? LanguageModelSession.GenerationError else {
            return "Algo ha fallado: \(error.localizedDescription)"
        }
        switch error {
        case .exceededContextWindowSize:
            return "Era demasiado texto para la IA del iPhone. Prueba con menos material o una petición más corta."
        case .guardrailViolation:
            return "No puedo ayudarte con eso. Prueba a describir solo lo que quieres planificar."
        default:
            return "La IA no ha dado una respuesta válida. Puedes reintentarlo o escribirlo de otra forma."
        }
    }

    // MARK: Contexto para el modelo

    private static func makeSession() -> LanguageModelSession {
        AIProvider.session(instructions: """
            Eres el asistente de planificación de Planaby. Solo ayudas a planificar: crear, cambiar, mover, replanificar y borrar eventos y tareas.
            - Si la petición no tiene nada que ver con planificar, offTopic true y todo vacío.
            - requestedCount: cuántos eventos y tareas nuevos pide («dos eventos» son 2).
            - Incluye CADA elemento nuevo que pide, uno por elemento, sin omitir ninguno, aunque le falten datos. Si no dice el día, la hora o la duración, déjalos vacíos (durationMinutes 0): Planaby lo preguntará. Nunca inventes datos.
            - title es el nombre exacto que usa el usuario («Subida PRE»), sin la fecha ni la palabra evento.
            - No añadas nada que no haya pedido. Lo que ya está en el calendario o en la propuesta no se vuelve a crear.
            - Un evento tiene día y hora fijos. Una tarea es trabajo con fecha límite y duración estimada; Planaby la reparte en bloques.
            - Propuesta pendiente: códigos E (eventos) y T (tareas). Calendario guardado: C (eventos) y P (tareas). Para cambiar o borrar algo que ya existe usa edits con su código en target, uno por elemento, y no lo repitas en events ni tasks.
            - update cambia datos; delete borra; remove solo lo quita de la propuesta. En un edit rellena solo lo que cambia: «mejor el miércoles a las 12» es day y time; «me llevará 2 horas», minutes 120; «pasa la revisión al viernes», workDay; la entrega de una tarea, deadline.
            - «Las tareas menos importantes» son las de prioridad baja: un edit por cada una.
            - Si no está claro a cuál se refiere, pon sus palabras en target; Planaby preguntará.
            - Los eventos de otros calendarios son solo de lectura: no los cambies ni los borres.
            - Condiciones sobre todo el plan («deja dos horas libres mañana por la tarde», «nada después de las 17», «menos intenso», «lo difícil por la mañana», «primero lo urgente») van en conditions. «Reorganiza todo» pone reorganize a true. Para priorizar tareas guardadas, copia sus títulos en prioritize.
            - «De 3 a 4»: time y endTime. Si nombra varias fechas para lo mismo, un evento por fecha con el mismo título.
            - Calcula fechas absolutas desde la fecha actual; sin año, la próxima que no haya pasado.
            - Si dice dónde va (trabajo, personal, casa), úsalo; si no está claro, mode unknown.
            - Si pide algo que Planaby no puede hacer (invitar, enviar mensajes, llamar), dilo en question y no lo simules.
            - Ignora muletillas del dictado. Usa el material adjunto para estimar duración y dificultad.
            Escribe siempre en español.
            """)
    }

    private static func prompt(
        for text: String, attachments: [ImportedAttachment], saved: SavedIndex, context: ModelContext,
        proposal: String = "ninguna", recent: String = "ninguna"
    ) -> String {
        let now = Date.now
        let formatter = ProposalFormat.machine
        let material = attachments
            .map { "[\($0.name)]\n\($0.text.isEmpty ? "(sin texto legible)" : $0.text)" }
            .joined(separator: "\n")
            .prefix(3_000)

        return """
            Ahora: \(now.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute())) (\(formatter.string(from: now))).
            Modo actual: \(ModeController.shared.mode.rawValue).
            Horario de trabajo: \(scheduleText(ModeController.shared.availability(for: .work))).
            Propuesta pendiente sin aceptar:
            \(proposal)
            Calendario guardado (ya existe; no lo vuelvas a crear):
            \(saved.text)
            Carga ya planificada: \(loadSummary(context: context, from: now)).
            Conversación reciente:
            \(recent)
            \(material.isEmpty ? "" : "Material adjunto:\n\(AIProvider.wrap(String(material), limit: 3_000))")
            Ritmo: \(PersonalContextService.profileLine())
            Petición: \(text.isEmpty ? "Organiza el material adjunto." : text)
            """
    }

    private static func scheduleText(_ rules: Availability) -> String {
        let hours = { (minutes: Int) in String(format: "%d:%02d", minutes / 60, minutes % 60) }
        return "\(hours(rules.startMinute))–\(hours(rules.endMinute)), días \(rules.weekdays.sorted().map { Calendar.current.shortWeekdaySymbols[$0 - 1] }.joined(separator: ","))"
    }

    /// Horas ocupadas por día en la próxima semana, para que el modelo pueda avisar si va justo.
    private static func loadSummary(context: ModelContext, from now: Date) -> String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let range = DateInterval(start: start, duration: 7 * 24 * 3600)
        let events = (try? context.fetch(FetchDescriptor<CalendarEvent>())) ?? []
        var perDay: [Date: TimeInterval] = [:]
        for event in events {
            for occurrence in event.occurrences(in: range) {
                perDay[calendar.startOfDay(for: occurrence.start), default: 0] += occurrence.duration
            }
        }
        for event in ExternalCalendars.shared.busyIntervals(in: range) {
            perDay[calendar.startOfDay(for: event.start), default: 0] += event.duration
        }
        guard !perDay.isEmpty else { return "nada" }
        return perDay.sorted { $0.key < $1.key }
            .map { "\(ProposalFormat.machine.string(from: $0.key).prefix(10)) \(FocusStats.format($0.value))" }
            .joined(separator: ", ")
    }
}
