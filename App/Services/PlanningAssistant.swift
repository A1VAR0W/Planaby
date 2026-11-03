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
    @Guide(description: "Pregunta breve si falta un dato imprescindible, como el día o la hora de una cita; vacía si no hace falta")
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
    @Guide(description: "work si es de trabajo o estudios; personal si es ocio, casa, salud o familia", .anyOf(["work", "personal"]))
    var mode: String
    @Guide(description: "Minutos de antelación del aviso; 15 si no se indica", .range(0...1440))
    var reminderMinutes: Int
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
    @Guide(description: "work si es de trabajo o estudios; personal si es ocio, casa, salud o familia", .anyOf(["work", "personal"]))
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

    var isEmpty: Bool { events.isEmpty && tasks.isEmpty && !reorganize && prioritize.isEmpty }
}

// MARK: - Asistente

/// La secretaria de Planaby. Apple Intelligence (en el dispositivo) interpreta el texto y el
/// material adjunto; el reparto lo hace `WorkloadPlanner` con el perfil personal, y todo acaba
/// en una propuesta que la persona revisa antes de guardar.
@Observable
@MainActor
final class PlanningAssistant {
    enum Role { case user, assistant }

    struct Message: Identifiable {
        let id = UUID()
        let role: Role
        let text: String
        var attachmentNames: [String] = []
        var draft: PlanDraft?
    }

    private(set) var messages: [Message] = []
    private(set) var isThinking = false
    @ObservationIgnored private var session: LanguageModelSession?

    /// nil si está disponible; si no, el motivo para mostrarlo.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            nil
        case .unavailable(.deviceNotEligible):
            "Este iPhone no es compatible con Apple Intelligence. Puedes usar las plantillas."
        case .unavailable(.appleIntelligenceNotEnabled):
            "Activa Apple Intelligence en Ajustes de iOS para planificar con IA. Mientras, puedes usar las plantillas."
        case .unavailable(.modelNotReady):
            "Apple Intelligence se está preparando. Vuelve a intentarlo en un rato o usa las plantillas."
        case .unavailable:
            "Apple Intelligence no está disponible ahora mismo. Puedes usar las plantillas."
        @unknown default:
            "Apple Intelligence no está disponible ahora mismo. Puedes usar las plantillas."
        }
    }

    var unavailableReason: String? { Self.unavailableReason }

    // MARK: Chat

    func send(_ text: String, attachments: [ImportedAttachment] = [], context: ModelContext) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty, !isThinking else { return }
        messages.append(Message(role: .user, text: trimmed.isEmpty ? "Organiza esto" : trimmed, attachmentNames: attachments.map(\.name)))
        isThinking = true
        defer { isThinking = false }

        do {
            let session = self.session ?? Self.makeSession()
            self.session = session
            var result = try await Self.interpret(trimmed, attachments: attachments, session: session, context: context)
            // El material adjunto queda guardado con las tareas que salgan de él.
            for index in result.tasks.indices {
                result.tasks[index].attachments = attachments
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

    func markAccepted(_ messageID: Message.ID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].draft = nil
        reply("Hecho: tu calendario está actualizado.")
    }

    private func respond(to result: Interpretation, context: ModelContext) {
        guard !result.isEmpty else {
            let text = ([result.question] + result.problems).filter { !$0.isEmpty }.joined(separator: "\n")
            reply(text.isEmpty ? "No he encontrado nada que planificar. Prueba con algo como «Reunión con Marta el jueves a las 10», «Estudiar para el examen del día 20» o «Prioriza el informe»." : text)
            return
        }

        var draft = result.reorganize || !result.prioritize.isEmpty
            ? PlanBuilder.reorganize(order: result.prioritize, newEvents: result.events, newTasks: result.tasks, context: context)
            : PlanBuilder.draft(events: result.events, tasks: result.tasks, context: context)
        draft.warnings = result.problems + draft.warnings
        let text = [draft.summary, result.question].filter { !$0.isEmpty }.joined(separator: "\n")
        messages.append(Message(role: .assistant, text: text, draft: draft))
    }

    private func reply(_ text: String) {
        messages.append(Message(role: .assistant, text: text))
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
            result.events.append(PlanDraft.Item(
                title: event.title, start: start,
                end: start.addingTimeInterval(TimeInterval(event.durationMinutes * 60)),
                mode: PlanMode(rawValue: event.mode) ?? fallbackMode, kind: .event,
                reminderMinutes: event.reminderMinutes
            ))
        }

        for task in parsed.tasks {
            guard let deadline = date(from: task.deadline) else {
                result.problems.append("No entendí la fecha límite de «\(task.title)».")
                continue
            }
            result.tasks.append(PlanDraft.Workload(
                id: UUID(), title: task.title, mode: PlanMode(rawValue: task.mode) ?? fallbackMode,
                deadline: deadline, estimatedMinutes: task.estimatedMinutes, priority: task.priority,
                difficulty: task.difficulty
            ))
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
        let session = LanguageModelSession(instructions: """
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
            \(material.isEmpty ? "ninguno" : String(material))
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
        LanguageModelSession(instructions: """
            Eres la secretaria personal de Planaby, una app de concentración. Conviertes lo que escribe el usuario en eventos y tareas, o detectas que quiere reorganizar su plan.
            - Un evento tiene día y hora fijos. Una tarea es trabajo nuevo con fecha límite y duración estimada; Planaby la repartirá en bloques, así que no inventes los bloques.
            - Si el usuario pide priorizar o adelantar tareas que ya tiene, pon reorganize a true y copia sus títulos en prioritize; no las repitas en tasks.
            - Si le ha surgido algo con hora (una reunión), es un evento; si además pide hacer hueco, reorganize es true.
            - Calcula fechas absolutas a partir de la fecha actual que se indica en cada mensaje ("mañana", "el jueves", "en dos semanas").
            - Si a una cita le falta el día o la hora, pregunta en question y no la incluyas.
            - Usa el material adjunto para estimar duración y dificultad.
            - Si el usuario solo saluda o pregunta otra cosa, deja todo vacío y contesta en question.
            Escribe siempre en español.
            """)
    }

    private static func prompt(for text: String, attachments: [ImportedAttachment], context: ModelContext) -> String {
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
            Carga ya planificada: \(loadSummary(context: context, from: now)).
            Tareas pendientes:
            \(pending.isEmpty ? "ninguna" : pending)
            \(material.isEmpty ? "" : "Material adjunto:\n\(material)")
            Petición: \(text.isEmpty ? "Organiza el material adjunto." : text)
            """
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
