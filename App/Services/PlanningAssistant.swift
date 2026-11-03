import Foundation
import FoundationModels
import Observation
import SwiftData

// MARK: - Estructura que genera el modelo

@Generable(description: "Lo que el usuario quiere añadir a su plan")
struct ParsedPlan {
    @Guide(description: "Citas con fecha y hora fijas: reuniones, clases, médico, quedadas")
    var events: [ParsedEvent]
    @Guide(description: "Trabajos con fecha límite que hay que repartir en bloques: entregas, informes, estudiar para un examen")
    var tasks: [ParsedTask]
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
    @Guide(description: "Minutos de trabajo estimados en total", .range(15...12000))
    var estimatedMinutes: Int
    @Guide(description: "work si es de trabajo o estudios; personal si es ocio, casa, salud o familia", .anyOf(["work", "personal"]))
    var mode: String
    @Guide(description: "Prioridad: 0 baja, 1 media, 2 alta", .range(0...2))
    var priority: Int
}

// MARK: - Asistente

/// Chat de planificación. Apple Intelligence (en el dispositivo) solo interpreta el texto;
/// el reparto en bloques lo hace `WorkloadPlanner`, y todo acaba en una propuesta que el
/// usuario revisa antes de guardar.
@Observable
@MainActor
final class PlanningAssistant {
    enum Role { case user, assistant }

    struct Message: Identifiable {
        let id = UUID()
        let role: Role
        let text: String
        var draft: PlanDraft?
    }

    private(set) var messages: [Message] = []
    private(set) var isThinking = false
    @ObservationIgnored private var session: LanguageModelSession?

    /// nil si está disponible; si no, el motivo para mostrarlo.
    var unavailableReason: String? {
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

    func send(_ text: String, context: ModelContext) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }
        messages.append(Message(role: .user, text: trimmed))
        isThinking = true
        defer { isThinking = false }

        do {
            let session = self.session ?? Self.makeSession()
            self.session = session
            let response = try await session.respond(
                to: Self.prompt(for: trimmed, context: context),
                generating: ParsedPlan.self,
                options: GenerationOptions(temperature: 0.2)
            )
            handle(response.content, context: context)
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize:
                session = nil
                reply("La conversación se ha hecho muy larga y he empezado de cero. Repíteme la última petición.")
            case .guardrailViolation:
                reply("No puedo ayudarte con eso. Prueba a describir solo lo que quieres planificar.")
            default:
                reply("No he podido entenderlo. Prueba con algo como «Entregar el informe el viernes, unas 6 horas».")
            }
        } catch {
            reply("Algo ha fallado: \(error.localizedDescription)")
        }
    }

    func updateDraft(_ draft: PlanDraft, in messageID: Message.ID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].draft = draft
    }

    func markAccepted(_ messageID: Message.ID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].draft = nil
        reply("Hecho: añadido a tu calendario.")
    }

    // MARK: - Interpretación

    private func handle(_ parsed: ParsedPlan, context: ModelContext) {
        let fallbackMode = ModeController.shared.mode
        var problems: [String] = []

        let events: [PlanDraft.Item] = parsed.events.compactMap { event in
            guard let start = Self.date(from: event.start) else {
                problems.append("No entendí la fecha de «\(event.title)».")
                return nil
            }
            return PlanDraft.Item(
                title: event.title, start: start,
                end: start.addingTimeInterval(TimeInterval(event.durationMinutes * 60)),
                mode: PlanMode(rawValue: event.mode) ?? fallbackMode, kind: .event,
                reminderMinutes: event.reminderMinutes
            )
        }

        let tasks: [PlanDraft.Workload] = parsed.tasks.compactMap { task in
            guard let deadline = Self.date(from: task.deadline) else {
                problems.append("No entendí la fecha límite de «\(task.title)».")
                return nil
            }
            return PlanDraft.Workload(
                id: UUID(), title: task.title, mode: PlanMode(rawValue: task.mode) ?? fallbackMode,
                deadline: deadline, estimatedMinutes: task.estimatedMinutes, priority: task.priority
            )
        }

        let question = parsed.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !events.isEmpty || !tasks.isEmpty else {
            let text = ([question] + problems).filter { !$0.isEmpty }.joined(separator: "\n")
            reply(text.isEmpty ? "No he encontrado nada que planificar. Prueba con algo como «Reunión con Marta el jueves a las 10» o «Estudiar para el examen del día 20, unas 8 horas»." : text)
            return
        }

        var draft = PlanBuilder.draft(events: events, tasks: tasks, context: context)
        draft.warnings = problems + draft.warnings
        let text = [draft.summary, question].filter { !$0.isEmpty }.joined(separator: "\n")
        messages.append(Message(role: .assistant, text: text, draft: draft))
    }

    private func reply(_ text: String) {
        messages.append(Message(role: .assistant, text: text))
    }

    // MARK: - Contexto para el modelo

    private static func makeSession() -> LanguageModelSession {
        LanguageModelSession(instructions: """
            Eres el planificador de Planaby, una app de concentración. Conviertes lo que escribe el usuario en eventos y tareas.
            - Un evento tiene día y hora fijos. Una tarea es trabajo con fecha límite y duración estimada; Planaby la repartirá en bloques, así que no inventes los bloques.
            - Calcula fechas absolutas a partir de la fecha actual que se indica en cada mensaje ("mañana", "el jueves", "en dos semanas").
            - Si a una cita le falta el día o la hora, pregunta en question y no la incluyas.
            - Si una tarea no dice cuánto lleva, estima una duración razonable.
            - Si el usuario solo saluda o pregunta otra cosa, deja events y tasks vacíos y contesta en question.
            Escribe siempre en español.
            """)
    }

    private static func prompt(for text: String, context: ModelContext) -> String {
        let now = Date.now
        let mode = ModeController.shared.mode
        return """
            Ahora: \(now.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute())) (\(formatter.string(from: now))).
            Modo actual: \(mode.rawValue).
            Carga ya planificada: \(loadSummary(context: context, from: now)).
            Petición: \(text)
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
