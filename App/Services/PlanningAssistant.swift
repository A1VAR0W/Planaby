import Foundation
import FoundationModels
import Observation
import SwiftData

// MARK: - Estructuras que genera el modelo

@Generable(description: "Lo que el usuario quiere añadir o cambiar en su plan")
struct ParsedPlan {
    @Guide(description: "Citas con fecha y hora fijas: reuniones, clases, médico, quedadas")
    var events: [ParsedEvent]
    @Guide(description: "Trabajos nuevos con fecha límite que hay que repartir en bloques: entregas, informes, estudiar para un examen")
    var tasks: [ParsedTask]
    @Guide(description: "true si el usuario pide reorganizar, replanificar, priorizar algo, adelantar trabajo o hacer hueco")
    var reorganize: Bool
    @Guide(description: "Títulos exactos de tareas pendientes que el usuario quiere adelantar o priorizar, en orden")
    var prioritize: [String]
    @Guide(description: "Pregunta breve solo si falta un dato imprescindible, como el día de una cita. Vacía si ya se puede planificar, si el usuario dio dos opciones (usa la primera) o si ya lo respondió antes")
    var question: String
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

/// Lo que se entendió de una petición, ya convertido a borradores.
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

    var isEmpty: Bool { events.isEmpty && tasks.isEmpty && !reorganize && prioritize.isEmpty }

    /// Une lo nuevo con una propuesta aún sin aceptar: lo que se llama igual (y, si es un
    /// evento, cae el mismo día) se sustituye; el resto se suma y se vuelve a repartir todo.
    func merged(with new: Interpretation) -> Interpretation {
        var result = self
        let calendar = Calendar.current
        for event in new.events {
            result.events.removeAll {
                $0.title.lowercased() == event.title.lowercased()
                    && ($0.recurrence != .none || calendar.isDate($0.start, inSameDayAs: event.start))
            }
        }
        result.events += new.events
        for task in new.tasks {
            result.tasks.removeAll { $0.title.lowercased() == task.title.lowercased() }
        }
        result.tasks += new.tasks
        result.reorganize = reorganize || new.reorganize
        result.prioritize += new.prioritize.filter { !prioritize.contains($0) }
        result.question = new.question
        result.problems = new.problems
        result.undecidedEvents = new.undecidedEvents
        result.undecidedTasks = new.undecidedTasks
        return result
    }
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
        draft.warnings = problems + draft.warnings
        return draft
    }
}

// MARK: - Asistente

/// La secretaria de Planaby. Apple Intelligence (en el dispositivo) interpreta el texto y el
/// material adjunto; el reparto lo hace `WorkloadPlanner` con el perfil personal, y todo acaba
/// en una propuesta que la persona revisa antes de guardar.
@Observable
@MainActor
final class PlanningAssistant {
    enum Role: String, Codable { case user, assistant }

    struct Message: Identifiable {
        let id = UUID()
        let role: Role
        let text: String
        var attachmentNames: [String] = []
        var draft: PlanDraft?
        /// Lo entendido que dio lugar a `draft`: los siguientes mensajes lo completan.
        var request: Interpretation?
        /// Lo entendido, a la espera de saber si va a Trabajo o a Normal.
        var pending: Interpretation?
    }

    /// Lo que se guarda de cada mensaje (las propuestas sin aceptar no se guardan).
    private struct StoredMessage: Codable {
        let role: Role
        let text: String
        let attachmentNames: [String]
    }

    private(set) var messages: [Message] = []
    private(set) var isThinking = false
    @ObservationIgnored private var session: LanguageModelSession?

    /// La conversación se guarda en el iPhone y sigue ahí al cerrar o actualizar la app.
    private static var historyURL: URL { URL.applicationSupportDirectory.appending(path: "chat.json") }
    private static let historyLimit = 100

    init() {
        let stored = (try? Data(contentsOf: Self.historyURL))
            .flatMap { try? JSONDecoder().decode([StoredMessage].self, from: $0) } ?? []
        messages = stored.map { Message(role: $0.role, text: $0.text, attachmentNames: $0.attachmentNames) }
    }

    func clearHistory() {
        messages = []
        session = nil
        saveHistory()
    }

    private func saveHistory() {
        let stored = messages.suffix(Self.historyLimit).map {
            StoredMessage(role: $0.role, text: $0.text, attachmentNames: $0.attachmentNames)
        }
        if let data = try? JSONEncoder().encode(Array(stored)) {
            try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
            try? data.write(to: Self.historyURL, options: .atomic)
        }
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
        isThinking = true
        defer { isThinking = false }

        do {
            let session = self.session ?? Self.makeSession()
            self.session = session
            let response = try await session.respond(
                to: Self.prompt(for: trimmed, attachments: attachments, context: context, proposal: openProposalText),
                generating: ParsedPlan.self,
                options: GenerationOptions(temperature: 0.2)
            )
            var result = Self.convert(response.content, context: context)
            // El material adjunto queda guardado con las tareas que salgan de él.
            for index in result.tasks.indices {
                result.tasks[index].attachments = attachments
            }
            // Si hay una propuesta sin aceptar, lo nuevo la completa o la corrige y se
            // reorganiza todo junto (por ejemplo, la hora de comer después de pedir una tarea).
            if !result.isEmpty, let index = openProposalIndex, let previous = messages[index].request {
                result = previous.merged(with: result)
                messages[index].draft = nil
                messages[index].request = nil
            }
            respond(to: result, context: context)
        } catch {
            if case LanguageModelSession.GenerationError.exceededContextWindowSize = error {
                session = nil
            }
            reply(Self.message(for: error))
        }
    }

    func updateDraft(_ draft: PlanDraft, in messageID: Message.ID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].draft = draft
    }

    /// La última propuesta que sigue abierta (sin aceptar ni sustituir).
    private var openProposalIndex: Int? {
        messages.lastIndex { $0.draft != nil && $0.request != nil }
    }

    func markAccepted(_ messageID: Message.ID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].draft = nil
        messages[index].request = nil
        reply("Hecho: tu calendario está actualizado.")
    }

    /// Respuesta a «¿Trabajo o Normal?».
    func chooseMode(_ mode: PlanMode, for messageID: Message.ID, context: ModelContext) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              var result = messages[index].pending else { return }
        messages[index].pending = nil
        result.assign(mode)
        messages.append(Message(role: .user, text: mode.title))
        saveHistory()
        respond(to: result, context: context)
    }

    private func respond(to result: Interpretation, context: ModelContext) {
        if result.needsMode {
            messages.append(Message(role: .assistant, text: result.modeQuestion, pending: result))
            saveHistory()
            return
        }
        guard !result.isEmpty else {
            let text = ([result.question] + result.problems).filter { !$0.isEmpty }.joined(separator: "\n")
            reply(text.isEmpty ? "No he encontrado nada que planificar. Prueba con algo como «Reunión con Marta el jueves a las 10», «Estudiar para el examen del día 20» o «Prioriza el informe»." : text)
            return
        }

        let draft = result.makeDraft(context: context)
        // No se repite una pregunta que ya se hizo.
        let asked = messages.contains { $0.role == .assistant && !result.question.isEmpty && $0.text.contains(result.question) }
        let text = [draft.summary, asked ? "" : result.question].filter { !$0.isEmpty }.joined(separator: "\n")
        messages.append(Message(role: .assistant, text: text, draft: draft, request: result))
        saveHistory()
    }

    private func reply(_ text: String) {
        messages.append(Message(role: .assistant, text: text))
        saveHistory()
    }

    // MARK: Interpretación

    /// Interpreta una petición suelta (también la usa Reorganizar).
    static func interpret(
        _ text: String, attachments: [ImportedAttachment] = [], session: LanguageModelSession? = nil, context: ModelContext
    ) async throws -> Interpretation {
        let session = session ?? makeSession()
        let response = try await session.respond(
            to: prompt(for: text, attachments: attachments, context: context),
            generating: ParsedPlan.self,
            options: GenerationOptions(temperature: 0.2)
        )
        return convert(response.content, context: context)
    }

    private static func convert(_ parsed: ParsedPlan, context: ModelContext) -> Interpretation {
        let fallbackMode = ModeController.shared.mode
        var result = Interpretation()

        for event in parsed.events {
            guard let start = date(from: event.start) else {
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
            guard let deadline = date(from: task.deadline) else {
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

        // Los títulos que da el modelo se buscan entre las tareas pendientes.
        let pending = ((try? context.fetch(FetchDescriptor<PlanTask>())) ?? []).filter { !$0.isDone }
        for title in parsed.prioritize {
            let needle = title.lowercased()
            if let match = pending.first(where: { $0.title.lowercased().contains(needle) || needle.contains($0.title.lowercased()) }),
               !result.prioritize.contains(match.persistentModelID) {
                result.prioritize.append(match.persistentModelID)
            }
        }
        result.reorganize = parsed.reorganize
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
            Eres la secretaria personal de Planaby, una app de concentración. Conviertes lo que escribe el usuario en eventos y tareas, o detectas que quiere reorganizar su plan.
            - Un evento tiene día y hora fijos. Una tarea es trabajo nuevo con fecha límite y duración estimada; Planaby la repartirá en bloques, así que no inventes los bloques.
            - Si el usuario pide priorizar o adelantar tareas que ya tiene, pon reorganize a true y copia sus títulos en prioritize; no las repitas en tasks.
            - Si le ha surgido algo con hora (una reunión), es un evento; si además pide hacer hueco, reorganize es true.
            - Si dice una hora de inicio y otra de fin («a las 3 de la tarde hasta las 4», «que acabe a las 4»), es un evento con esa duración aunque lo llame tarea. Si la hora de fin queda antes que la de inicio, es un error al hablar: entiende la misma parte del día (de 15:00 a 16:00).
            - Las horas de comer o descansos de cada día («como de 2 a 3», «mi hora de comida es de 1:30 a 2:30») son un evento titulado «Comida» que empieza hoy (o el próximo día laborable), con repeats weekdays y mode work. Si da dos opciones, usa la primera y no preguntes.
            - Cada mensaje puede completar o corregir la propuesta pendiente que se indica: devuelve solo lo nuevo o lo que cambia (con el mismo título si es un cambio). Planaby lo junta con lo anterior y lo reparte todo de nuevo. No repitas lo que ya está en la propuesta.
            - Planaby ya tiene en cuenta el calendario, el horario de trabajo y los eventos existentes al repartir los bloques; no preguntes por ellos.
            - Si nombra varias fechas para lo mismo («el lunes y el miércoles», «los días 5, 12 y 19»), crea un evento por cada fecha con el mismo título.
            - Ignora muletillas y frases a medias del dictado («vale», «bueno», «necesito que me hagas»).
            - Calcula fechas absolutas a partir de la fecha actual que se indica en cada mensaje ("mañana", "el jueves", "en dos semanas").
            - Si a una cita le falta el día o la hora, pregunta en question y no la incluyas.
            - Si el usuario dice dónde va (trabajo, personal, normal, casa), usa eso. Si no lo dice y el contenido no deja claro si es de trabajo o personal (por ejemplo «llamar a Juan» o «revisar el documento»), pon mode a unknown y Planaby se lo preguntará. No decidas por el modo actual.
            - Usa el material adjunto para estimar duración y dificultad.
            - Si el usuario solo saluda o pregunta otra cosa, deja todo vacío y contesta en question.
            Escribe siempre en español.
            """)
    }

    private static func prompt(
        for text: String, attachments: [ImportedAttachment], context: ModelContext, proposal: String = "ninguna"
    ) -> String {
        let now = Date.now
        let pending = ((try? context.fetch(FetchDescriptor<PlanTask>())) ?? [])
            .filter { !$0.isDone }
            .sorted { $0.deadline < $1.deadline }
            .prefix(12)
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
            Propuesta pendiente sin aceptar: \(proposal).
            Tareas pendientes:
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

    /// Resumen de la propuesta abierta, para que el modelo no la repita.
    private var openProposalText: String {
        guard let index = openProposalIndex, let request = messages[index].request else { return "ninguna" }
        let tasks = request.tasks.map { "tarea «\($0.title)» (\($0.estimatedMinutes) min, entrega \(Self.formatter.string(from: $0.deadline)))" }
        let events = request.events.map { "evento «\($0.title)» \(Self.formatter.string(from: $0.start))\($0.recurrence == .none ? "" : " (\($0.recurrence.title))")" }
        let all = tasks + events
        return all.isEmpty ? "ninguna" : all.joined(separator: "; ")
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
            .map { "\(formatter.string(from: $0.key).prefix(10)) \(FocusStats.format($0.value))" }
            .joined(separator: ", ")
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static func date(from text: String) -> Date? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "T", with: " ")
        if let date = formatter.date(from: cleaned) { return date }
        let dayOnly = DateFormatter()
        dayOnly.locale = Locale(identifier: "en_US_POSIX")
        dayOnly.dateFormat = "yyyy-MM-dd"
        return dayOnly.date(from: String(cleaned.prefix(10)))
            .flatMap { Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: $0) }
    }
}
