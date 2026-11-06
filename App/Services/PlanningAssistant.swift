import Foundation
import FoundationModels
import Observation
import SwiftData

// MARK: - Estructuras que genera el modelo

@Generable(description: "Lo que el usuario quiere añadir o cambiar en su plan")
struct ParsedPlan {
    @Guide(description: "Cambios sobre elementos que ya están en la propuesta pendiente (con su código E1, T1): mover, cambiar hora, duración, fecha límite, prioridad o plan, quitar, poner primero, deshacer. Vacío si no hay propuesta")
    var edits: [ParsedEdit]
    @Guide(description: "Citas NUEVAS con fecha y hora fijas: reuniones, clases, médico, quedadas. Nunca algo que ya está en la propuesta")
    var events: [ParsedEvent]
    @Guide(description: "Trabajos NUEVOS con fecha límite que hay que repartir en bloques: entregas, informes, estudiar. Nunca algo que ya está en la propuesta")
    var tasks: [ParsedTask]
    @Guide(description: "Condiciones generales sobre todo el plan: dejar libre una franja, nada después o antes de una hora, menos intenso, lo difícil por la mañana, primero lo urgente")
    var conditions: [ParsedCondition]
    @Guide(description: "true si el usuario pide reorganizar o replanificar todo, adelantar trabajo o hacer hueco")
    var reorganize: Bool
    @Guide(description: "Títulos exactos de tareas pendientes ya guardadas que el usuario quiere adelantar o priorizar, en orden")
    var prioritize: [String]
    @Guide(description: "Pregunta breve solo si falta un dato imprescindible (el día de una cita, cuánto debe durar). Vacía si ya se puede hacer")
    var question: String
}

@Generable(description: "Un cambio sobre un elemento de la propuesta pendiente")
struct ParsedEdit {
    @Guide(description: "update cambia datos; remove lo quita; first lo pone antes que las demás tareas; undo deshace el último cambio", .anyOf(["update", "remove", "first", "undo"]))
    var action: String
    @Guide(description: "Código del elemento (E1, T2). Si no está claro cuál es, las palabras del usuario («la reunión»)")
    var target: String
    @Guide(description: "Título nuevo; vacío si no cambia")
    var title: String
    @Guide(description: "Día nuevo yyyy-MM-dd; vacío si no cambia")
    var day: String
    @Guide(description: "Hora nueva de inicio HH:mm; vacía si no cambia")
    var time: String
    @Guide(description: "Hora nueva de fin HH:mm; vacía si no cambia")
    var endTime: String
    @Guide(description: "Duración nueva de un evento o total nuevo de una tarea, en minutos; 0 si no cambia o si no dice cuánto", .range(0...12000))
    var minutes: Int
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
    @Guide(description: "Título corto, sin la fecha")
    var title: String
    @Guide(description: "Inicio en formato yyyy-MM-dd HH:mm")
    var start: String
    @Guide(description: "Duración en minutos; 60 si no se indica", .range(5...720))
    var durationMinutes: Int
    @Guide(description: "work si es claramente de trabajo o estudios; personal si es claramente ocio, casa, salud, familia o recados; unknown si no se puede saber", .anyOf(["work", "personal", "unknown"]))
    var mode: String
    @Guide(description: "Minutos de antelación del aviso; 15 si no se indica; 0 para la comida", .range(0...1440))
    var reminderMinutes: Int
    @Guide(description: "none si es una vez; weekdays si se repite de lunes a viernes (la comida o descansos de cada día laborable); daily si es cada día; weekly si es cada semana", .anyOf(["none", "weekdays", "daily", "weekly"]))
    var repeats: String
}

@Generable
struct ParsedTask {
    @Guide(description: "Título corto, sin la fecha")
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
    /// Cambios sobre la propuesta abierta (y condiciones generales).
    var edits: [ProposalEdit] = []
    var undo = false
    /// Títulos que la IA quiso poner primero y que están en la propuesta.
    var first: [String] = []

    var isEmpty: Bool { events.isEmpty && tasks.isEmpty && !reorganize && prioritize.isEmpty && edits.isEmpty && first.isEmpty && !undo }

    var needsMode: Bool { !undecidedEvents.isEmpty || !undecidedTasks.isEmpty }

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
    var conditions: [ProposalEdit] {
        edits.filter { edit in
            switch edit {
            case .constraints, .urgentFirst: true
            default: false
            }
        }
    }
}

// MARK: - Asistente

/// La secretaria de Planaby. Apple Intelligence (en el dispositivo) interpreta el texto y el
/// material adjunto; el reparto lo hace `WorkloadPlanner` con el perfil personal, y todo acaba
/// en una propuesta que la persona revisa antes de guardar.
///
/// Mientras no se acepta, hay una sola propuesta activa (`active`), con sus versiones. Cada
/// mensaje la modifica con operaciones deterministas (`ProposalEditor`): nada se duplica ni se
/// pierde, y se puede deshacer.
@Observable
@MainActor
final class PlanningAssistant {
    enum Role: String, Codable { case user, assistant }

    /// En qué estado queda la propuesta que enseña un mensaje.
    enum ProposalState: String, Codable { case active, replaced, accepted }

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

    /// La conversación se guarda en el iPhone y sigue ahí al cerrar o actualizar la app.
    private static var historyURL: URL { URL.applicationSupportDirectory.appending(path: "chat.json") }
    /// La propuesta sin aceptar, aparte: si no se puede leer, se pierde solo ella.
    private static var proposalURL: URL { URL.applicationSupportDirectory.appending(path: "proposal.json") }
    private static let historyLimit = 100

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
    }

    var draft: PlanDraft? { active?.history.current }
    var canUndo: Bool { active?.history.canUndo ?? false }
    var canRedo: Bool { active?.history.canRedo ?? false }

    func clearHistory() {
        messages = []
        active = nil
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
        current.items.removeAll { $0.kind != .workBlock && $0.recurrence == .none && $0.end < .now }

        let stale = current.blocks.contains { $0.start < .now }
        guard current != active?.history.current || stale else { return }
        if current.items.isEmpty && current.tasks.isEmpty {
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

    func send(_ text: String, attachments: [ImportedAttachment] = [], context: ModelContext) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty, !isThinking else { return }
        messages.append(Message(role: .user, text: trimmed.isEmpty ? "Organiza esto" : trimmed, attachmentNames: attachments.map(\.name)))
        saveHistory()

        // Sin IA: deshacer, rehacer, aceptar y responder a «¿Cuál?».
        if active != nil, attachments.isEmpty {
            if let clarification = active?.clarification, let option = clarification.option(matching: trimmed),
               let edits = clarification.resolved(with: option.id) {
                active?.clarification = nil
                apply(edits, mergeSimilar: false, request: trimmed, context: context)
                return
            }
            switch ProposalCommand.detect(trimmed) {
            case .undo: undo(context: context); return
            case .redo: redo(context: context); return
            case .accept: askToAccept(); return
            case nil: break
            }
        }
        guard unavailableReason == nil else {
            reply(active == nil
                  ? (unavailableReason ?? "")
                  : "Sin Apple Intelligence no puedo entender ese cambio. Puedes editar la propuesta en «Revisar propuesta», o decir «deshaz».")
            return
        }

        isThinking = true
        defer { isThinking = false }
        do {
            let prompt = Self.prompt(
                for: trimmed, attachments: attachments, context: context,
                proposal: activeProposalText, recent: recentConversation
            )
            var result = try await Self.respond(to: prompt, context: context, proposal: draft)
            // El material adjunto queda guardado con las tareas que salgan de él.
            for index in result.tasks.indices {
                result.tasks[index].attachments = attachments
            }
            respond(to: result, request: trimmed, context: context)
        } catch {
            // La propuesta no se toca: el error solo se cuenta.
            reply(Self.message(for: error) + (active == nil ? "" : " Tu propuesta sigue igual."))
        }
    }

    /// Respuesta a «¿Trabajo o Normal?».
    func chooseMode(_ mode: PlanMode, for messageID: Message.ID, context: ModelContext) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              var result = messages[index].pending else { return }
        messages[index].pending = nil
        result.assign(mode)
        messages.append(Message(role: .user, text: mode.title))
        saveHistory()
        respond(to: result, request: "", context: context)
    }

    /// Respuesta a «¿Cuál quieres mover?» tocando una opción.
    func choose(_ option: ProposalOption, context: ModelContext) {
        guard let clarification = active?.clarification, let edits = clarification.resolved(with: option.id) else { return }
        active?.clarification = nil
        for index in messages.indices { messages[index].options = [] }
        messages.append(Message(role: .user, text: "\(option.title) (\(option.detail))"))
        saveHistory()
        apply(edits, mergeSimilar: false, request: "", context: context)
    }

    private func respond(to result: Interpretation, request: String, context: ModelContext) {
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
                reply(text.isEmpty ? "No he encontrado nada que planificar. Prueba con algo como «Reunión con Marta el jueves a las 10», «Estudiar para el examen del día 20» o «Prioriza el informe»." : text)
            }
            return
        }

        if active != nil {
            let edits = result.proposalEdits
            // Tareas ya guardadas que se quieren adelantar: entran en la propuesta al reorganizar.
            let reorganize = result.reorganize || !result.prioritize.isEmpty
            if result.undo { undo(context: context) }
            apply(edits, mergeSimilar: !ProposalCommand.wantsAnother(request), request: request,
                  reorganize: reorganize, prioritize: result.prioritize, problems: result.problems,
                  question: result.question, context: context)
            return
        }

        guard !result.events.isEmpty || !result.tasks.isEmpty || result.reorganize || !result.prioritize.isEmpty else {
            reply("Primero dime qué quieres planificar; luego aplico esa condición a la propuesta.")
            return
        }
        let draft = result.makeDraft(context: context)
        let id = UUID()
        active = ActiveProposal(history: ProposalHistory(draft), messageID: id)
        let text = [draft.summary, result.question].filter { !$0.isEmpty }.joined(separator: "\n")
        retireProposals()
        messages.append(Message(id: id, role: .assistant, text: text, proposal: .active))
        saveHistory()
        saveProposal()
    }

    // MARK: Editar la propuesta activa

    /// Aplica operaciones a la propuesta activa: resuelve referencias (o pregunta), cambia solo
    /// lo pedido, recoloca lo necesario y guarda una versión nueva.
    private func apply(
        _ edits: [ProposalEdit], mergeSimilar: Bool, request: String, reorganize: Bool = false,
        prioritize: [PersistentIdentifier] = [], problems: [String] = [], question: String = "", context: ModelContext
    ) {
        guard var active else { return }
        let before = active.history.current
        var outcome = ProposalEditOutcome(draft: before, affectedTasks: [], problems: [])
        if !edits.isEmpty {
            switch ProposalEditor.apply(edits, to: before, mergeSimilar: mergeSimilar) {
            case .applied(let result):
                outcome = result
            case .clarify(let clarification):
                active.clarification = clarification
                self.active = active
                messages.append(Message(role: .assistant, text: clarification.question, options: clarification.options))
                saveHistory()
                saveProposal()
                return
            case .failed(let reason):
                reply(reason + " Tu propuesta sigue igual.")
                return
            }
        }

        var next = PlanBuilder.replan(outcome.draft, affected: outcome.affectedTasks, reorganizeAll: reorganize, context: context)
        if !prioritize.isEmpty {
            // Lo elegido va primero, en el orden dicho.
            let chosen = prioritize.compactMap { id in next.tasks.first { $0.existing == id }?.id }
            next.order = chosen + next.orderedTasks.map(\.id).filter { !chosen.contains($0) }
            next = PlanBuilder.replan(next, affected: Set(next.tasks.map(\.id)), context: context)
        }
        next.warnings = outcome.problems + problems + next.warnings

        let changes = ProposalDiff.changes(from: before, to: next)
        guard !changes.isEmpty || reorganize else {
            let text = (outcome.problems + problems + [question]).filter { !$0.isEmpty }.joined(separator: "\n")
            reply(text.isEmpty ? "Eso ya estaba así en la propuesta." : text)
            return
        }
        active.history.commit(next)
        active.clarification = nil
        commit(active, text: updateText(changes: changes, draft: next, extra: outcome.problems + problems + [question]), changes: changes)
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
        for index in messages.indices { messages[index].options = [] }
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

    private func updateText(changes: [ProposalChange], draft: PlanDraft, extra: [String]) -> String {
        let lines = ["He actualizado tu planificación."] + extra.filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
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

    private func dropActive(as state: ProposalState) {
        let id = active?.messageID
        for index in messages.indices where messages[index].id == id {
            messages[index].proposal = state
            messages[index].asksToAccept = false
            messages[index].options = []
        }
        active = nil
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
        guard let base = manualBase, let active, manualCommitted else { return }
        let changes = ProposalDiff.changes(from: base, to: active.history.current)
        guard !changes.isEmpty else { return }
        commit(active, text: "He guardado tus cambios en la propuesta.", changes: changes)
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
        try await respond(to: prompt(for: text, attachments: attachments, context: context), context: context, proposal: nil, session: session)
    }

    /// Una sesión nueva por petición: el contexto va en el mensaje (propuesta, últimos mensajes),
    /// así una conversación larga no llena la memoria del modelo del iPhone.
    private static func respond(
        to prompt: String, context: ModelContext, proposal: PlanDraft?, session: LanguageModelSession? = nil
    ) async throws -> Interpretation {
        let session = session ?? makeSession()
        let response = try await session.respond(to: prompt, generating: ParsedPlan.self, options: GenerationOptions(temperature: 0.2))
        return convert(response.content, context: context, proposal: proposal)
    }

    private static func convert(_ parsed: ParsedPlan, context: ModelContext, proposal: PlanDraft?) -> Interpretation {
        let fallbackMode = ModeController.shared.mode
        var result = Interpretation()

        for event in parsed.events {
            guard let start = ProposalFormat.dateTime(event.start) else {
                result.problems.append("No entendí la fecha de «\(event.title)».")
                continue
            }
            let item = PlanDraft.Item(
                title: event.title, start: start,
                end: start.addingTimeInterval(TimeInterval(event.durationMinutes * 60)),
                mode: PlanMode(rawValue: event.mode) ?? fallbackMode, kind: .event,
                recurrence: Recurrence(rawValue: event.repeats) ?? .none,
                reminderMinutes: event.reminderMinutes > 0 ? event.reminderMinutes : nil
            )
            if PlanMode(rawValue: event.mode) == nil { result.undecidedEvents.insert(item.id) }
            result.events.append(item)
        }

        for task in parsed.tasks {
            guard let deadline = ProposalFormat.dateTime(task.deadline) else {
                result.problems.append("No entendí la fecha límite de «\(task.title)».")
                continue
            }
            let workload = PlanDraft.Workload(
                id: UUID(), title: task.title, mode: PlanMode(rawValue: task.mode) ?? fallbackMode,
                deadline: deadline, estimatedMinutes: task.estimatedMinutes, priority: task.priority,
                difficulty: task.difficulty
            )
            if PlanMode(rawValue: task.mode) == nil { result.undecidedTasks.insert(workload.id) }
            result.tasks.append(workload)
        }

        // Sin propuesta abierta, los cambios no tienen a qué aplicarse.
        if proposal != nil {
            for edit in parsed.edits {
                let fields = ProposalEditFields(
                    action: edit.action, target: edit.target, title: edit.title, day: edit.day, time: edit.time,
                    endTime: edit.endTime, minutes: edit.minutes, deadline: edit.deadline, priority: edit.priority,
                    difficulty: edit.difficulty, mode: edit.mode, repeats: edit.repeats, reminderMinutes: edit.reminderMinutes
                )
                if fields.isUndo {
                    result.undo = true
                } else if let operation = fields.makeEdit() {
                    result.edits.append(operation)
                }
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
            return "No he podido entenderlo. Prueba con algo como «Entregar el informe el viernes, unas 6 horas»."
        }
    }

    // MARK: Contexto para el modelo

    private static func makeSession() -> LanguageModelSession {
        AIProvider.session(instructions: """
            Eres la secretaria personal de Planaby, una app de concentración. Conviertes lo que escribe el usuario en eventos, tareas y cambios.
            - Un evento tiene día y hora fijos. Una tarea es trabajo con fecha límite y duración estimada; Planaby la reparte en bloques, así que no inventes los bloques.
            - Si hay propuesta pendiente, cada elemento tiene un código (E1 evento, T1 tarea). Para cambiar, mover, acortar, priorizar o quitar algo que ya está en ella, usa edits con su código en target, y no lo repitas en events ni en tasks. events y tasks son solo para cosas nuevas.
            - En un edit rellena solo lo que cambia. «Mejor el miércoles a las 12»: day y time. «Me llevará 2 horas»: minutes 120. «Ponlo primero»: action first. «Quita la reunión»: action remove. «Deshaz lo último»: action undo.
            - Si pide que dure más o menos sin decir cuánto, no lo inventes: deja minutes en 0 y pregunta cuánto en question.
            - Si no está claro a cuál se refiere (hay dos reuniones), pon en target sus palabras; Planaby preguntará.
            - Condiciones sobre todo el plan («deja libre el viernes por la tarde», «nada después de las 17», «menos intenso», «lo difícil por la mañana», «primero lo urgente») van en conditions. «Reorganiza todo» pone reorganize a true.
            - Si pide priorizar tareas que ya tiene guardadas, copia sus títulos en prioritize.
            - Si dice una hora de inicio y otra de fin («de 3 a 4»), es un evento con esa duración. Si la de fin queda antes, entiende la misma parte del día.
            - Las horas de comer de cada día («como de 2 a 3») son un evento «Comida» que empieza hoy (o el próximo día laborable), repeats weekdays, mode work.
            - Si nombra varias fechas para lo mismo, crea un evento por fecha con el mismo título.
            - Ignora muletillas del dictado («vale», «bueno»). Calcula fechas absolutas a partir de la fecha actual que se indica.
            - Si a una cita nueva le falta el día o la hora, pregunta en question y no la incluyas.
            - Si dice dónde va (trabajo, personal, normal, casa), úsalo. Si no lo dice y no está claro, mode unknown; Planaby lo preguntará.
            - Usa el material adjunto para estimar duración y dificultad.
            - Planaby ya tiene en cuenta el calendario, el horario de trabajo y los eventos existentes; no preguntes por ellos.
            - Si solo saluda o pregunta otra cosa, deja todo vacío y contesta en question.
            Escribe siempre en español.
            """)
    }

    private static func prompt(
        for text: String, attachments: [ImportedAttachment], context: ModelContext,
        proposal: String = "ninguna", recent: String = "ninguna"
    ) -> String {
        let now = Date.now
        let formatter = ProposalFormat.machine
        let pending = ((try? context.fetch(FetchDescriptor<PlanTask>())) ?? [])
            .filter { !$0.isDone }
            .sorted { $0.deadline < $1.deadline }
            .prefix(10)
            .map { "- \($0.title) (entrega \(formatter.string(from: $0.deadline)), \($0.mode.rawValue))" }
            .joined(separator: "\n")
        let material = attachments
            .map { "[\($0.name)]\n\($0.text.isEmpty ? "(sin texto legible)" : $0.text)" }
            .joined(separator: "\n")
            .prefix(3_000)

        return """
            Ahora: \(now.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute())) (\(formatter.string(from: now))).
            Modo actual: \(ModeController.shared.mode.rawValue).
            Horario de trabajo: \(scheduleText(ModeController.shared.availability(for: .work))).
            Agenda de hoy y mañana: \(agenda(context: context, from: now)).
            Carga ya planificada: \(loadSummary(context: context, from: now)).
            Propuesta pendiente sin aceptar:
            \(proposal)
            Conversación reciente:
            \(recent)
            Tareas guardadas pendientes:
            \(pending.isEmpty ? "ninguna" : pending)
            \(material.isEmpty ? "" : "Material adjunto:\n\(AIProvider.wrap(String(material), limit: 3_000))")
            Ritmo: \(PersonalContextService.profileLine())
            Petición: \(text.isEmpty ? "Organiza el material adjunto." : text)
            """
    }

    /// Lo que hay en el calendario hoy y mañana (propio y externo), para no preguntar por ello.
    private static func agenda(context: ModelContext, from now: Date) -> String {
        let calendar = Calendar.current
        let range = DateInterval(start: now, end: calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now)) ?? now)
        let own = ((try? context.fetch(FetchDescriptor<CalendarEvent>())) ?? []).flatMap { event in
            event.occurrences(in: range).map { (title: event.title, interval: $0) }
        }
        let external = ExternalCalendars.shared.events(in: range)
            .filter { !$0.isAllDay }
            .map { (title: $0.title, interval: $0.interval) }
        let items = (own + external).sorted { $0.interval.start < $1.interval.start }.prefix(16)
        guard !items.isEmpty else { return "nada" }
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US_POSIX")
        time.dateFormat = "EEE HH:mm"
        let end = DateFormatter()
        end.dateFormat = "HH:mm"
        return items.map { "\($0.title) \(time.string(from: $0.interval.start))–\(end.string(from: $0.interval.end))" }
            .joined(separator: "; ")
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
