import Foundation

// MARK: - Operaciones

/// A qué elemento de la propuesta se refiere una operación: su código (E1, T2) o cómo lo llamó
/// la persona («la reunión con Jonatan», «eso»). Se resuelve contra la propuesta, nunca a ciegas.
struct ProposalTarget: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case event, task, any }

    var text: String
    var kind: Kind = .any
}

/// Lo que cambia de un evento o de una tarea. Solo cuenta lo que no es nil.
struct ProposalChanges: Codable, Equatable, Sendable {
    var title: String?
    /// Día nuevo, conservando la hora (evento) o la hora límite (tarea).
    var day: Date?
    /// Hora nueva (minutos desde medianoche): inicio de un evento u hora límite de una tarea.
    var startMinute: Int?
    var endMinute: Int?
    /// Duración de un evento, o total estimado de una tarea.
    var minutes: Int?
    /// «Media hora más», «una hora menos».
    var deltaMinutes: Int?
    var deadline: Date?
    var priority: Int?
    var difficulty: Int?
    var mode: PlanMode?
    var recurrence: Recurrence?
    /// 0 = sin aviso.
    var reminderMinutes: Int?
    var notes: String?
    var included: Bool?
    /// Día en que se trabaja una tarea («pásala al viernes»), sin tocar su entrega si da tiempo.
    var workDay: Date?

    var isEmpty: Bool { self == ProposalChanges() }

    /// Es un cambio de horario (para preguntar «¿cuál quieres mover?»).
    var isReschedule: Bool { day != nil || startMinute != nil || deadline != nil || workDay != nil }
}

/// Una modificación concreta de la propuesta. Se aplica de forma determinista: la IA solo dice
/// qué quiere la persona; cómo se cambia la propuesta lo decide este código.
enum ProposalEdit: Codable, Equatable, Sendable {
    case addEvent(PlanDraft.Item)
    case addTask(PlanDraft.Workload)
    case update(ProposalTarget, ProposalChanges)
    /// Quitar de la propuesta (lo guardado no se toca).
    case remove(ProposalTarget)
    /// Borrar del calendario algo guardado (se ve en la propuesta y solo ocurre al aceptarla).
    case delete(ProposalTarget)
    /// Esa tarea se planifica la primera.
    case moveFirst(ProposalTarget)
    /// Primero lo urgente (prioridad y fecha límite).
    case urgentFirst
    case constraints(PlanConstraints)

    var target: ProposalTarget? {
        switch self {
        case .update(let target, _), .remove(let target), .delete(let target), .moveFirst(let target): target
        default: nil
        }
    }

    func with(target: ProposalTarget) -> ProposalEdit {
        switch self {
        case .update(_, let changes): .update(target, changes)
        case .remove: .remove(target)
        case .delete: .delete(target)
        case .moveFirst: .moveFirst(target)
        default: self
        }
    }
}

// MARK: - Resolver referencias

enum ProposalResolution: Equatable {
    case found(UUID)
    case ambiguous([UUID])
    case notFound
}

/// Una opción para resolver una ambigüedad («¿Cuál quieres mover?»).
struct ProposalOption: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let ref: String
    let title: String
    let detail: String
}

/// Una pregunta abierta sobre la propuesta. Mientras tanto la propuesta no cambia; la respuesta
/// completa las operaciones que esperaban.
struct ProposalClarification: Codable, Equatable, Sendable {
    var question: String
    var options: [ProposalOption]
    var edits: [ProposalEdit]
    /// La operación cuya referencia falta por resolver.
    var index: Int

    /// Las mismas operaciones con la referencia ya elegida.
    func resolved(with optionID: UUID) -> [ProposalEdit]? {
        guard let option = options.first(where: { $0.id == optionID }), edits.indices.contains(index),
              let target = edits[index].target else { return nil }
        var result = edits
        result[index] = edits[index].with(target: ProposalTarget(text: option.ref, kind: target.kind))
        return result
    }

    /// La opción que nombra una respuesta escrita («la de Jonatan», «la segunda», «2»).
    func option(matching text: String) -> ProposalOption? {
        let words = ProposalText.words(text)
        let ordinals = [["1", "primera", "primero", "uno", "una"], ["2", "segunda", "segundo", "dos"], ["3", "tercera", "tercero", "tres"]]
        for (index, names) in ordinals.enumerated() where options.indices.contains(index) {
            if words.count <= 3, words.contains(where: names.contains) { return options[index] }
        }
        let scored = options.map { ($0, ProposalText.score(query: words, title: $0.title + " " + $0.ref)) }
        guard let best = scored.map(\.1).max(), best > 0 else { return nil }
        let winners = scored.filter { $0.1 == best }
        return winners.count == 1 ? winners[0].0 : nil
    }
}

/// Texto normalizado para comparar referencias: minúsculas, sin tildes ni signos y sin palabras
/// vacías («la», «de», «eso»).
enum ProposalText {
    static let stopWords: Set<String> = [
        "el", "la", "los", "las", "lo", "un", "una", "unos", "unas", "de", "del", "a", "al", "con", "en", "mi", "mis",
        "tu", "que", "y", "o", "para", "por", "eso", "esa", "ese", "esto", "esta", "este", "aquello", "aquella",
        "le", "se", "me", "su", "sus", "otra", "otro",
    ]

    static func words(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    static func keywords(_ text: String) -> [String] {
        words(text).filter { !stopWords.contains($0) }
    }

    /// Cuántas palabras de la consulta aparecen en el título (con plurales y formas cercanas).
    static func score(query: [String], title: String) -> Int {
        let titleWords = keywords(title)
        return query.filter { !stopWords.contains($0) }.reduce(0) { total, word in
            let hit = titleWords.contains { candidate in
                candidate == word || (word.count >= 4 && candidate.count >= 4
                    && (candidate.hasPrefix(String(word.prefix(max(4, word.count - 2))))
                        || word.hasPrefix(String(candidate.prefix(max(4, candidate.count - 2))))))
            }
            return total + (hit ? 1 : 0)
        }
    }

    /// Un código de la propuesta dentro del texto («E1», «t2»).
    static func code(in text: String) -> String? {
        code(in: text, prefixes: ["e", "t"])
    }

    /// Un código de algo guardado («C3» = cita del calendario, «P2» = tarea pendiente).
    static func savedCode(in text: String) -> String? {
        code(in: text, prefixes: ["c", "p"])
    }

    private static func code(in text: String, prefixes: Set<Character>) -> String? {
        for word in words(text) {
            guard let first = word.first, prefixes.contains(first), word.count >= 2,
                  word.dropFirst().allSatisfy(\.isNumber) else { continue }
            return word.uppercased()
        }
        return nil
    }
}

// MARK: - Aplicar operaciones

struct ProposalEditOutcome: Equatable {
    var draft: PlanDraft
    /// Tareas cuyos bloques hay que volver a colocar.
    var affectedTasks: Set<UUID>
    /// Lo que no se pudo hacer, explicado.
    var problems: [String]
}

enum ProposalEditResult: Equatable {
    case applied(ProposalEditOutcome)
    case clarify(ProposalClarification)
    case failed(String)
}

enum ProposalEditor {
    /// Encuentra el elemento al que se refiere `target`. Primero por código; luego por título;
    /// si sigue habiendo varios, es ambiguo (se pregunta, nunca se elige uno al azar).
    static func resolve(_ target: ProposalTarget, in draft: PlanDraft) -> ProposalResolution {
        var candidates: [(id: UUID, title: String, isTask: Bool)] = []
        if target.kind != .task { candidates += draft.newEvents.map { ($0.id, $0.title, false) } }
        if target.kind != .event { candidates += draft.tasks.map { ($0.id, $0.title, true) } }
        guard !candidates.isEmpty else { return .notFound }

        if let code = ProposalText.code(in: target.text),
           let match = candidates.first(where: { draft.ref($0.id) == code }) {
            return .found(match.id)
        }

        let query = ProposalText.keywords(target.text)
        let exact = candidates.filter { ProposalText.keywords($0.title) == query && !query.isEmpty }
        if exact.count == 1 { return .found(exact[0].id) }

        let scored = candidates.map { ($0.id, ProposalText.score(query: query, title: $0.title)) }
        if let best = scored.map(\.1).max(), best > 0 {
            let winners = scored.filter { $0.1 == best }.map(\.0)
            return winners.count == 1 ? .found(winners[0]) : .ambiguous(winners)
        }
        // «Quita eso», «la cita»: si solo hay uno de ese tipo, es ese.
        if candidates.count == 1 { return .found(candidates[0].id) }
        if query.isEmpty { return .ambiguous(candidates.map(\.id)) }
        return .notFound
    }

    /// Aplica todas las operaciones o ninguna: si alguna referencia es ambigua, pregunta primero.
    /// `mergeSimilar`: lo «nuevo» que se llama igual que algo de la propuesta se trata como un
    /// cambio de eso (la IA a veces repite un evento al moverlo); se desactiva con «otra reunión».
    static func apply(
        _ edits: [ProposalEdit], to draft: PlanDraft, mergeSimilar: Bool = true, calendar: Calendar = .current
    ) -> ProposalEditResult {
        var resolved: [Int: UUID] = [:]
        for (index, edit) in edits.enumerated() {
            guard let target = edit.target else { continue }
            switch resolve(target, in: draft) {
            case .found(let id):
                resolved[index] = id
            case .ambiguous(let ids):
                return .clarify(ProposalClarification(
                    question: question(for: edit, draft: draft), options: ids.map { option(for: $0, in: draft) },
                    edits: edits, index: index
                ))
            case .notFound:
                return .failed("No encuentro «\(target.text)» en la propuesta.")
            }
        }

        var result = draft
        var affected: Set<UUID> = []
        var problems: [String] = []
        for (index, edit) in edits.enumerated() {
            switch edit {
            case .addEvent(let item):
                if mergeSimilar, let twin = similarEvent(to: item, in: result) {
                    var changes = ProposalChanges()
                    changes.day = calendar.startOfDay(for: item.start)
                    changes.startMinute = minuteOfDay(item.start, calendar: calendar)
                    changes.minutes = item.durationMinutes
                    update(event: twin, with: changes, in: &result, problems: &problems, calendar: calendar)
                } else {
                    var item = item
                    item.kind = item.kind == .workBlock ? .event : item.kind
                    result.items.append(item)
                }
            case .addTask(let task):
                if mergeSimilar, let twin = result.tasks.first(where: { sameTitle($0.title, task.title) }) {
                    var changes = ProposalChanges()
                    changes.deadline = task.deadline
                    changes.minutes = task.requestedMinutes
                    update(task: twin.id, with: changes, in: &result, affected: &affected, problems: &problems, calendar: calendar)
                } else {
                    result.tasks.append(task)
                    affected.insert(task.id)
                }
            case .update(_, let changes):
                guard let id = resolved[index] else { continue }
                if changes.isEmpty {
                    problems.append("No sé qué cambiar de «\(title(of: id, in: result))». Dime, por ejemplo, la hora o la duración.")
                } else if result.tasks.contains(where: { $0.id == id }) {
                    update(task: id, with: changes, in: &result, affected: &affected, problems: &problems, calendar: calendar)
                } else {
                    update(event: id, with: changes, in: &result, problems: &problems, calendar: calendar)
                }
            case .remove:
                guard let id = resolved[index] else { continue }
                remove(id, from: &result)
                affected.remove(id)
            case .delete:
                guard let id = resolved[index] else { continue }
                delete(id, from: &result)
                affected.remove(id)
            case .moveFirst:
                guard let id = resolved[index] else { continue }
                guard result.tasks.contains(where: { $0.id == id }) else {
                    problems.append("«\(title(of: id, in: result))» es una cita con hora fija: no se puede poner antes que las tareas.")
                    continue
                }
                result.order = [id] + result.orderedTasks.map(\.id).filter { $0 != id }
                affected.formUnion(result.tasks.map(\.id))
            case .urgentFirst:
                result.order = result.tasks
                    .sorted { $0.priority != $1.priority ? $0.priority > $1.priority : $0.deadline < $1.deadline }
                    .map(\.id)
                affected.formUnion(result.tasks.map(\.id))
            case .constraints(let new):
                merge(new, into: &result.constraints)
                // Menos intensidad o lo difícil por la mañana cambian todo el reparto; el resto
                // solo mueve los bloques que ya no encajan (lo decide la colocación).
                if new.lighter || new.hardInMorning { affected.formUnion(result.tasks.map(\.id)) }
            }
        }
        result.assignRefs()
        return .applied(ProposalEditOutcome(draft: result, affectedTasks: affected, problems: problems))
    }

    // MARK: Piezas

    private static func update(event id: UUID, with changes: ProposalChanges, in draft: inout PlanDraft, problems: inout [String], calendar: Calendar) {
        guard let index = draft.items.firstIndex(where: { $0.id == id }) else { return }
        var item = draft.items[index]
        let length = item.end.timeIntervalSince(item.start)
        if let title = changes.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty { item.title = title }
        // Lo que se dice ahora deja de ser provisional.
        if changes.day != nil || changes.deadline != nil { item.confirm(.day) }
        if changes.startMinute != nil || changes.deadline != nil { item.confirm(.time) }
        if changes.minutes != nil || changes.deltaMinutes != nil || changes.endMinute != nil { item.confirm(.duration) }
        // Un evento no tiene «día de trabajo»: es su día.
        var changes = changes
        if changes.day == nil, let workDay = changes.workDay {
            changes.day = workDay
            item.confirm(.day)
        }

        var start = item.start
        if let day = changes.day { start = combine(day: day, timeOf: start, calendar: calendar) }
        if let minute = changes.startMinute { start = at(minute: minute, on: start, calendar: calendar) }
        if let deadline = changes.deadline { start = deadline }

        var duration = length
        if let minutes = changes.minutes, minutes > 0 {
            duration = TimeInterval(minutes * 60)
        } else if let delta = changes.deltaMinutes {
            duration = max(5 * 60, length + TimeInterval(delta * 60))
        }
        var end = start.addingTimeInterval(duration)
        if let endMinute = changes.endMinute {
            var candidate = at(minute: endMinute, on: start, calendar: calendar)
            // «De 3 a 4» dicho en la misma parte del día: si queda antes, son 12 h más.
            if candidate <= start, candidate.addingTimeInterval(12 * 3600) > start {
                candidate = candidate.addingTimeInterval(12 * 3600)
            }
            if candidate > start {
                end = candidate
                // Si solo se dijo la hora de fin, se mantiene el inicio.
            } else {
                problems.append("La hora de fin de «\(item.title)» queda antes del inicio; la dejo como estaba.")
            }
        }
        item.start = start
        item.end = end
        if let mode = changes.mode { item.mode = mode }
        if let recurrence = changes.recurrence { item.recurrence = recurrence }
        if let reminder = changes.reminderMinutes { item.reminderMinutes = reminder > 0 ? reminder : nil }
        if let included = changes.included { item.isIncluded = included }
        draft.items[index] = item
    }

    private static func update(
        task id: UUID, with changes: ProposalChanges, in draft: inout PlanDraft, affected: inout Set<UUID>,
        problems: inout [String], calendar: Calendar
    ) {
        guard let index = draft.tasks.firstIndex(where: { $0.id == id }) else { return }
        var task = draft.tasks[index]
        var replan = false
        if let title = changes.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty {
            task.title = title
            for block in draft.items.indices where draft.items[block].taskID == id { draft.items[block].title = title }
        }
        var deadline = task.deadline
        if let day = changes.day { deadline = combine(day: day, timeOf: deadline, calendar: calendar) }
        if let minute = changes.startMinute { deadline = at(minute: minute, on: deadline, calendar: calendar) }
        if let exact = changes.deadline { deadline = exact }
        if deadline != task.deadline {
            task.deadline = deadline
            replan = true
        }
        if let workDay = changes.workDay {
            let day = calendar.startOfDay(for: workDay)
            task.workDay = day
            if task.deadline < day.addingTimeInterval(3600) {
                // Si se pide trabajarla un día después de su entrega, la entrega pasa a ese día.
                let newDeadline = at(minute: 23 * 60 + 59, on: day, calendar: calendar)
                problems.append("«\(task.title)» se entregaba \(ProposalFormat.dayName(task.deadline)); ahora se entrega \(ProposalFormat.dayName(newDeadline)).")
                task.deadline = newDeadline
            }
            replan = true
        }
        if let minutes = changes.minutes, minutes > 0 {
            task.statedMinutes = max(15, minutes)
            task.estimatedMinutes = task.statedMinutes!
            replan = true
        } else if let delta = changes.deltaMinutes {
            task.statedMinutes = max(15, task.requestedMinutes + delta)
            task.estimatedMinutes = task.statedMinutes!
            replan = true
        }
        if let priority = changes.priority {
            task.priority = min(2, max(0, priority))
            replan = true
        }
        if let difficulty = changes.difficulty {
            task.difficulty = min(5, max(1, difficulty))
            replan = true
        }
        if let mode = changes.mode, mode != task.mode {
            task.mode = mode
            replan = true
        }
        if let notes = changes.notes { task.notes = notes }
        draft.tasks[index] = task
        if changes.included == false {
            remove(id, from: &draft)
            affected.remove(id)
            return
        }
        if replan { affected.insert(id) }
    }

    /// Quita un evento, o una tarea con sus bloques, su orden y los bloques guardados que iba a
    /// sustituir (que así se conservan). No quedan restos.
    static func remove(_ id: UUID, from draft: inout PlanDraft) {
        if let task = draft.tasks.first(where: { $0.id == id }) {
            draft.tasks.removeAll { $0.id == id }
            draft.items.removeAll { $0.taskID == id }
            draft.order.removeAll { $0 == id }
            let kept = Set(task.replacedBlocks)
            draft.removals.removeAll { kept.contains($0) }
        } else {
            draft.items.removeAll { $0.id == id }
        }
        draft.refs[id] = nil
    }

    /// Borra algo guardado: queda apuntado en la propuesta y desaparece del calendario solo al
    /// aceptarla. Si no estaba guardado (solo era una propuesta), basta con quitarlo.
    static func delete(_ id: UUID, from draft: inout PlanDraft) {
        if let task = draft.tasks.first(where: { $0.id == id }), let saved = task.existing {
            if !draft.deletions.contains(where: { $0.id == saved }) {
                draft.deletions.append(SavedDeletion(
                    id: saved, title: task.title, detail: "entrega " + ProposalFormat.dayTime.string(from: task.deadline), isTask: true
                ))
            }
        } else if let item = draft.items.first(where: { $0.id == id }), let saved = item.replaces {
            if !draft.deletions.contains(where: { $0.id == saved }) {
                draft.deletions.append(SavedDeletion(
                    id: saved, title: item.title, detail: ProposalFormat.dayTime.string(from: item.start),
                    isTask: false, isSeries: item.recurrence != .none
                ))
            }
        }
        remove(id, from: &draft)
    }

    private static func merge(_ new: PlanConstraints, into current: inout PlanConstraints) {
        if let latest = new.latestEndMinute { current.latestEndMinute = latest }
        if let earliest = new.earliestStartMinute { current.earliestStartMinute = earliest }
        current.freeIntervals += new.freeIntervals.filter { !current.freeIntervals.contains($0) }
        current.lighter = current.lighter || new.lighter
        current.hardInMorning = current.hardInMorning || new.hardInMorning
    }

    private static func similarEvent(to item: PlanDraft.Item, in draft: PlanDraft) -> UUID? {
        let matches = draft.newEvents.filter { sameTitle($0.title, item.title) }
        return matches.count == 1 ? matches[0].id : nil
    }

    static func sameTitle(_ a: String, _ b: String) -> Bool {
        let left = ProposalText.keywords(a)
        return !left.isEmpty && left == ProposalText.keywords(b)
    }

    private static func question(for edit: ProposalEdit, draft: PlanDraft) -> String {
        switch edit {
        case .remove: "¿Cuál quieres quitar?"
        case .delete: "¿Cuál quieres borrar?"
        case .moveFirst: "¿Cuál va primero?"
        case .update(_, let changes): changes.isReschedule ? "¿Cuál quieres mover?" : "¿Cuál quieres cambiar?"
        default: "¿A cuál te refieres?"
        }
    }

    static func option(for id: UUID, in draft: PlanDraft) -> ProposalOption {
        let formatter = ProposalFormat.dayTime
        if let task = draft.tasks.first(where: { $0.id == id }) {
            return ProposalOption(id: id, ref: draft.ref(id), title: task.title,
                                  detail: "\(ProposalFormat.minutes(task.requestedMinutes)) · entrega \(formatter.string(from: task.deadline))")
        }
        let item = draft.items.first { $0.id == id }
        return ProposalOption(id: id, ref: draft.ref(id), title: item?.title ?? "",
                              detail: item.map { formatter.string(from: $0.start) } ?? "")
    }

    private static func title(of id: UUID, in draft: PlanDraft) -> String {
        draft.tasks.first { $0.id == id }?.title ?? draft.items.first { $0.id == id }?.title ?? ""
    }

    static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func at(minute: Int, on date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        return calendar.date(bySettingHour: min(23, minute / 60), minute: minute % 60, second: 0, of: day) ?? date
    }

    static func combine(day: Date, timeOf time: Date, calendar: Calendar) -> Date {
        at(minute: minuteOfDay(time, calendar: calendar), on: day, calendar: calendar)
    }
}

// MARK: - De lo que entiende la IA a operaciones

/// Los campos de una modificación tal como los devuelve el modelo (texto y números; vacío, 0 o
/// -1 = sin cambio). Se convierten aquí para poder probarlo sin el modelo.
struct ProposalEditFields: Equatable, Sendable {
    var action = "update"
    var target = ""
    var title = ""
    var day = ""
    var time = ""
    var endTime = ""
    var minutes = 0
    var deadline = ""
    var priority = -1
    var difficulty = 0
    var mode = ""
    var repeats = ""
    var reminderMinutes = -1
    /// Día en que se trabaja una tarea (no su entrega).
    var workDay = ""

    /// nil si la acción es «deshacer» (se atiende aparte) o no dice nada.
    func makeEdit(calendar: Calendar = .current) -> ProposalEdit? {
        let target = ProposalTarget(text: self.target, kind: inferredKind)
        switch action {
        case "remove": return .remove(target)
        case "delete": return .delete(target)
        case "first": return .moveFirst(target)
        case "undo": return nil
        default:
            var changes = ProposalChanges()
            let title = self.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { changes.title = title }
            changes.day = ProposalFormat.day(day, calendar: calendar)
            changes.startMinute = ProposalFormat.minute(time)
            changes.endMinute = ProposalFormat.minute(endTime)
            if minutes > 0 { changes.minutes = minutes }
            changes.deadline = ProposalFormat.dateTime(deadline, calendar: calendar)
            if (0...2).contains(priority) { changes.priority = priority }
            if (1...5).contains(difficulty) { changes.difficulty = difficulty }
            changes.mode = PlanMode(rawValue: mode)
            changes.recurrence = repeats.isEmpty ? nil : Recurrence(rawValue: repeats)
            if reminderMinutes >= 0 { changes.reminderMinutes = reminderMinutes }
            changes.workDay = ProposalFormat.day(workDay, calendar: calendar)
            return .update(target, changes)
        }
    }

    var isUndo: Bool { action == "undo" }

    /// Una hora de fin o una hora de inicio es de un evento; una fecha límite, prioridad o
    /// dificultad, de una tarea. Si no, vale cualquiera (y el código, si lo hay, manda).
    private var inferredKind: ProposalTarget.Kind {
        if let code = ProposalText.code(in: target) { return code.hasPrefix("E") ? .event : .task }
        if let code = ProposalText.savedCode(in: target) { return code.hasPrefix("C") ? .event : .task }
        if !deadline.isEmpty || priority >= 0 || difficulty > 0 || !workDay.isEmpty { return .task }
        if !time.isEmpty || !endTime.isEmpty || !repeats.isEmpty { return .event }
        return .any
    }
}

/// Una condición general tal como la devuelve el modelo.
struct ProposalConditionFields: Equatable, Sendable {
    var kind = ""
    var day = ""
    var from = ""
    var to = ""

    func makeEdit(calendar: Calendar = .current) -> ProposalEdit? {
        var constraints = PlanConstraints()
        switch kind {
        case "latestEnd":
            guard let minute = ProposalFormat.minute(from) else { return nil }
            constraints.latestEndMinute = minute
        case "earliestStart":
            guard let minute = ProposalFormat.minute(from) else { return nil }
            constraints.earliestStartMinute = minute
        case "free":
            guard let day = ProposalFormat.day(self.day, calendar: calendar) else { return nil }
            let start = ProposalFormat.minute(from).map { ProposalEditor.at(minute: $0, on: day, calendar: calendar) } ?? day
            let end = ProposalFormat.minute(to).map { ProposalEditor.at(minute: $0, on: day, calendar: calendar) }
                ?? calendar.date(byAdding: .day, value: 1, to: day) ?? day
            guard end > start else { return nil }
            constraints.freeIntervals = [DateInterval(start: start, end: end)]
        case "lighter": constraints.lighter = true
        case "hardMorning": constraints.hardInMorning = true
        case "urgentFirst": return .urgentFirst
        default: return nil
        }
        return .constraints(constraints)
    }
}

// MARK: - Órdenes directas

/// Lo que se entiende sin IA: deshacer, rehacer y aceptar. Solo frases cortas y claras, para no
/// confundir «ponla como antes a las 10» con deshacer.
enum ProposalCommand: Equatable {
    case undo, redo, accept

    static func detect(_ text: String) -> ProposalCommand? {
        let words = ProposalText.words(text)
        guard !words.isEmpty, words.count <= 8 else { return nil }
        let joined = words.joined(separator: " ")
        let editVerbs: Set<String> = [
            "cambia", "cambiala", "cambialo", "mueve", "muevela", "muevelo", "quita", "quitala", "quitalo", "pon", "ponla", "ponlo",
            "anade", "elimina", "borra", "pasa", "pasala", "pasalo", "reduce", "aumenta", "dura", "adelanta", "retrasa", "organiza",
        ]
        let hasEdit = words.contains(where: editVerbs.contains) || words.contains { $0.contains(where: \.isNumber) }

        if words.contains(where: ["rehaz", "rehazlo", "rehacer"].contains) { return .redo }
        if words.contains(where: ["deshaz", "deshazlo", "deshacer", "deshace"].contains) { return .undo }
        if !hasEdit, words.count <= 5,
           ["como estaba", "como antes", "vuelve atras", "anula lo ultimo", "anula el ultimo cambio"].contains(where: joined.contains) {
            return .undo
        }
        let acceptWords: Set<String> = [
            "acepta", "aceptala", "aceptalo", "aceptar", "acepto", "guarda", "guardala", "guardalo", "guardar",
            "confirma", "confirmala", "confirmalo", "confirmar", "aplica", "aplicalo", "aplicala",
        ]
        if !hasEdit, words.contains(where: acceptWords.contains) { return .accept }
        return nil
    }

    /// «Otra reunión», «también»: algo nuevo aunque se llame como algo de la propuesta.
    static func wantsAnother(_ text: String) -> Bool {
        ProposalText.words(text).contains { ["otra", "otro", "tambien", "ademas", "segunda", "segundo"].contains($0) }
    }
}

// MARK: - Versiones

/// Versiones de la propuesta mientras se edita, para deshacer y rehacer sin pedírselo a la IA.
/// Es distinto del historial de la conversación.
struct ProposalHistory: Codable, Equatable, Sendable {
    static let limit = 20

    private(set) var versions: [PlanDraft]
    private(set) var index: Int

    init(_ first: PlanDraft) {
        versions = [first]
        index = 0
    }

    var current: PlanDraft { versions[index] }
    var canUndo: Bool { index > 0 }
    var canRedo: Bool { index < versions.count - 1 }

    /// Una versión nueva; lo que se había deshecho deja de poder rehacerse.
    mutating func commit(_ draft: PlanDraft) {
        versions = Array(versions.prefix(index + 1)) + [draft]
        if versions.count > Self.limit { versions.removeFirst(versions.count - Self.limit) }
        index = versions.count - 1
    }

    /// Cambios a mano sobre la versión actual (se agrupan en una sola versión al terminar).
    mutating func replaceCurrent(_ draft: PlanDraft) {
        versions[index] = draft
    }

    @discardableResult
    mutating func undo() -> PlanDraft? {
        guard canUndo else { return nil }
        index -= 1
        return current
    }

    @discardableResult
    mutating func redo() -> PlanDraft? {
        guard canRedo else { return nil }
        index += 1
        return current
    }
}

/// La propuesta activa del chat: una sola, con sus versiones y, si la hay, la pregunta abierta.
/// Se guarda en el iPhone para seguir editándola después de cerrar Planaby.
struct ActiveProposal: Codable, Equatable, Sendable {
    var history: ProposalHistory
    /// El mensaje del chat que la enseña (los anteriores quedan como sustituidos).
    var messageID: UUID
    var clarification: ProposalClarification?
    var updated: Date = .now
    /// Pregunta pendiente sobre un dato que falta (día, hora o duración), con respuestas rápidas.
    var detail: DetailQuestion?
}

// MARK: - Qué ha cambiado

struct ProposalChange: Codable, Equatable, Sendable, Identifiable {
    /// `deleted`: algo guardado que se borrará al aceptar; `kept`: ya no se borra.
    enum Kind: String, Codable, Sendable { case added, modified, removed, moved, deleted, kept }
    enum Field: String, Codable, Sendable {
        case title, day, time, duration, deadline, minutes, priority, difficulty, mode, recurrence, reminder, notes, included, order
    }

    struct Detail: Codable, Equatable, Sendable {
        var field: Field
        var before: String
        var after: String
    }

    var id = UUID()
    var kind: Kind
    var title: String
    var details: [Detail] = []

    var fields: [Field] { details.map(\.field) }

    /// «Reunión: miércoles → viernes, 10:00 → 11:00».
    var text: String {
        switch kind {
        case .added: return "Nuevo: \(title)"
        case .removed: return "Quitado: \(title)"
        case .deleted: return "Se borrará: \(title)"
        case .kept: return "Se conserva: \(title)"
        case .moved: return title
        case .modified:
            let parts = details.map { detail in
                switch detail.field {
                case .order: return detail.after
                case .notes: return "notas"
                case .included: return detail.after
                default: return detail.before.isEmpty ? detail.after : "\(detail.before) → \(detail.after)"
                }
            }
            return "\(title): " + parts.joined(separator: ", ")
        }
    }
}

enum ProposalDiff {
    /// Lo que ha cambiado entre dos versiones, comparando por identificador (no por título).
    static func changes(from old: PlanDraft, to new: PlanDraft) -> [ProposalChange] {
        var result: [ProposalChange] = []
        let oldEvents = Dictionary(uniqueKeysWithValues: old.newEvents.map { ($0.id, $0) })
        let newEvents = Dictionary(uniqueKeysWithValues: new.newEvents.map { ($0.id, $0) })
        for event in new.newEvents {
            guard let before = oldEvents[event.id] else {
                result.append(ProposalChange(kind: .added, title: event.title))
                continue
            }
            let details = eventDetails(before, event)
            if !details.isEmpty { result.append(ProposalChange(kind: .modified, title: event.title, details: details)) }
        }
        let deleted = Set(new.deletions.map(\.id))
        for event in old.newEvents where newEvents[event.id] == nil {
            // Un evento guardado que se borra ya sale como «Se borrará».
            if let saved = event.replaces, deleted.contains(saved) { continue }
            result.append(ProposalChange(kind: .removed, title: event.title))
        }

        let oldTasks = Dictionary(uniqueKeysWithValues: old.tasks.map { ($0.id, $0) })
        let newIDs = Set(new.tasks.map(\.id))
        let oldOrder = old.orderedTasks.map(\.id)
        let newOrder = new.orderedTasks.map(\.id)
        for task in new.tasks {
            guard let before = oldTasks[task.id] else {
                result.append(ProposalChange(kind: .added, title: task.title))
                continue
            }
            var details = taskDetails(before, task)
            if newOrder.first == task.id, oldOrder.first != task.id, new.tasks.count > 1, !new.order.isEmpty {
                details.append(.init(field: .order, before: "", after: "primero"))
            }
            if !details.isEmpty { result.append(ProposalChange(kind: .modified, title: task.title, details: details)) }
        }
        for task in old.tasks where !newIDs.contains(task.id) {
            if let saved = task.existing, deleted.contains(saved) { continue }
            result.append(ProposalChange(kind: .removed, title: task.title))
        }
        let wasDeleted = Set(old.deletions.map(\.id))
        for deletion in new.deletions where !wasDeleted.contains(deletion.id) {
            result.append(ProposalChange(kind: .deleted, title: deletion.title))
        }
        for deletion in old.deletions where !deleted.contains(deletion.id) {
            result.append(ProposalChange(kind: .kept, title: deletion.title))
        }

        // Bloques de tareas que siguen en la propuesta y han cambiado de sitio.
        let kept = Set(old.tasks.map(\.id)).intersection(newIDs)
        let oldSlots = Set(old.blocks.filter { kept.contains($0.taskID ?? UUID()) }.map { Slot($0) })
        let newSlots = Set(new.blocks.filter { kept.contains($0.taskID ?? UUID()) }.map { Slot($0) })
        let moved = newSlots.subtracting(oldSlots).count
        if moved > 0 {
            result.append(ProposalChange(kind: .moved, title: moved == 1 ? "1 bloque recolocado" : "\(moved) bloques recolocados"))
        }
        return result
    }

    private struct Slot: Hashable {
        let task: UUID?
        let start: Date
        let end: Date
        init(_ item: PlanDraft.Item) { task = item.taskID; start = item.start; end = item.end }
    }

    private static func eventDetails(_ a: PlanDraft.Item, _ b: PlanDraft.Item) -> [ProposalChange.Detail] {
        var details: [ProposalChange.Detail] = []
        let calendar = Calendar.current
        if a.title != b.title { details.append(.init(field: .title, before: a.title, after: b.title)) }
        if !calendar.isDate(a.start, inSameDayAs: b.start) {
            details.append(.init(field: .day, before: ProposalFormat.dayName(a.start), after: ProposalFormat.dayName(b.start)))
        }
        if ProposalEditor.minuteOfDay(a.start, calendar: calendar) != ProposalEditor.minuteOfDay(b.start, calendar: calendar) {
            details.append(.init(field: .time, before: ProposalFormat.time.string(from: a.start), after: ProposalFormat.time.string(from: b.start)))
        }
        if a.durationMinutes != b.durationMinutes {
            details.append(.init(field: .duration, before: ProposalFormat.minutes(a.durationMinutes), after: ProposalFormat.minutes(b.durationMinutes)))
        }
        if a.mode != b.mode { details.append(.init(field: .mode, before: a.mode.title, after: b.mode.title)) }
        if a.recurrence != b.recurrence { details.append(.init(field: .recurrence, before: a.recurrence.title, after: b.recurrence.title)) }
        if a.reminderMinutes != b.reminderMinutes {
            details.append(.init(field: .reminder, before: reminder(a.reminderMinutes), after: reminder(b.reminderMinutes)))
        }
        if a.isIncluded != b.isIncluded {
            details.append(.init(field: .included, before: "", after: b.isIncluded ? "incluido" : "sin incluir"))
        }
        return details
    }

    private static func taskDetails(_ a: PlanDraft.Workload, _ b: PlanDraft.Workload) -> [ProposalChange.Detail] {
        var details: [ProposalChange.Detail] = []
        if a.title != b.title { details.append(.init(field: .title, before: a.title, after: b.title)) }
        if a.deadline != b.deadline {
            details.append(.init(field: .deadline, before: ProposalFormat.dayTime.string(from: a.deadline), after: ProposalFormat.dayTime.string(from: b.deadline)))
        }
        if a.requestedMinutes != b.requestedMinutes {
            details.append(.init(field: .minutes, before: ProposalFormat.minutes(a.requestedMinutes), after: ProposalFormat.minutes(b.requestedMinutes)))
        }
        if a.priority != b.priority {
            details.append(.init(field: .priority, before: "prioridad " + ProposalFormat.priority(a.priority), after: ProposalFormat.priority(b.priority)))
        }
        if a.difficulty != b.difficulty {
            details.append(.init(field: .difficulty, before: "dificultad \(a.difficulty)", after: "\(b.difficulty)"))
        }
        if a.mode != b.mode { details.append(.init(field: .mode, before: a.mode.title, after: b.mode.title)) }
        if a.notes != b.notes { details.append(.init(field: .notes, before: "", after: "")) }
        if a.workDay != b.workDay, let day = b.workDay {
            details.append(.init(field: .day, before: a.workDay.map { ProposalFormat.dayName($0) } ?? "", after: ProposalFormat.dayName(day)))
        }
        return details
    }

    private static func reminder(_ minutes: Int?) -> String {
        minutes.map { "aviso \($0) min antes" } ?? "sin aviso"
    }
}

// MARK: - Formatos

enum ProposalFormat {
    static let spanish = Locale(identifier: "es_ES")

    static let time: DateFormatter = make("HH:mm")
    static let dayTime: DateFormatter = make("EEE d HH:mm")
    static let weekday: DateFormatter = make("EEEE")
    static let dayMonth: DateFormatter = make("EEEE d MMM")
    /// Lo que se le pasa a la IA (sin idioma).
    static let machine: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static func make(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = spanish
        formatter.dateFormat = format
        return formatter
    }

    /// «miércoles», o «miércoles 19 nov» si no es de esta semana.
    static func dayName(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        return (0..<7).contains(days) ? weekday.string(from: date) : dayMonth.string(from: date)
    }

    /// «45 min», «2 h», «2 h 30 min».
    static func minutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) min"
        case (_, 0): return "\(hours) h"
        default: return "\(hours) h \(rest) min"
        }
    }

    /// «17:00».
    static func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    static func priority(_ value: Int) -> String {
        switch value {
        case 2: "alta"
        case 0: "baja"
        default: "media"
        }
    }

    static func minute(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    static func day(_ text: String, calendar: Calendar = .current) -> Date? {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
        guard cleaned.count >= 10 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(cleaned.prefix(10))).map { calendar.startOfDay(for: $0) }
    }

    /// «yyyy-MM-dd HH:mm»; si solo hay día, a las 23:59.
    static func dateTime(_ text: String, calendar: Calendar = .current) -> Date? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "T", with: " ")
        guard let day = day(cleaned, calendar: calendar) else { return nil }
        let time = cleaned.count > 10 ? minute(String(cleaned.dropFirst(11).prefix(5))) : nil
        return ProposalEditor.at(minute: time ?? (23 * 60 + 59), on: day, calendar: calendar)
    }
}

// MARK: - Colocar de nuevo

/// Vuelve a colocar los bloques tras una modificación, con el planificador de siempre. Solo se
/// recolocan las tareas afectadas y las que ya no encajan (pisan una cita, se salen de una
/// condición nueva o pasan la fecha límite); los demás bloques se quedan donde estaban,
/// incluidos los movidos a mano.
struct ProposalPlacement {
    /// Lo ocupado fuera de la propuesta: calendario guardado (sin lo que se sustituye) y externos.
    var busy: [DateInterval]
    var planner: WorkloadPlanner
    var availability: (PlanMode) -> Availability
    /// Corrige una estimación con el desvío habitual de la persona.
    var adjust: (Int) -> Int = { $0 }
    var now: Date
    var blockReminder = 5
    var calendar: Calendar = .current

    struct Result {
        var draft: PlanDraft
        /// Minutos que no caben antes de la fecha límite, por tarea.
        var shortfalls: [UUID: Int]
        /// Tareas recolocadas.
        var replanned: Set<UUID>
    }

    func replan(_ draft: PlanDraft, affected: Set<UUID>) -> Result {
        var draft = draft
        let horizon = max(draft.tasks.map(\.deadline).max() ?? now, now.addingTimeInterval(24 * 3600))
        let range = DateInterval(start: now, end: max(horizon, now.addingTimeInterval(3600)))
        let events = draft.newEvents.filter(\.isIncluded).flatMap { $0.occurrences(in: range) }
        let fixed = busy + events + draft.constraints.freeIntervals

        var replan = affected.intersection(draft.tasks.map(\.id))
        for task in draft.tasks where !replan.contains(task.id) {
            let blocks = draft.blocks(of: task.id)
            if blocks.isEmpty || !blocks.allSatisfy({ fits($0, task: task, fixed: fixed, constraints: draft.constraints) }) {
                replan.insert(task.id)
            }
        }

        let pinned = draft.blocks.filter { block in block.taskID.map { !replan.contains($0) } ?? false }
        let ranked = draft.orderedTasks.map(\.id)
        var work: [WorkItem] = []
        for index in draft.tasks.indices where replan.contains(draft.tasks[index].id) {
            if let stated = draft.tasks[index].statedMinutes { draft.tasks[index].estimatedMinutes = adjust(stated) }
            let task = draft.tasks[index]
            let window = workWindow(task)
            work.append(WorkItem(
                id: task.id, deadline: window.end, minutes: task.estimatedMinutes, priority: task.priority,
                availability: draft.constraints.apply(to: availability(task.mode)), capGroup: task.mode.rawValue,
                difficulty: task.difficulty, rank: draft.order.isEmpty ? nil : ranked.firstIndex(of: task.id),
                notBefore: window.start
            ))
        }

        var planner = planner
        planner.energyByHour = draft.constraints.energy(planner.energyByHour)
        // Lo que se queda cuenta para el tope diario de su plan.
        var used: [String: Int] = [:]
        for block in pinned where block.isIncluded {
            used[WorkloadPlanner.capKey(group: block.mode.rawValue, day: calendar.startOfDay(for: block.start)), default: 0] += block.durationMinutes
        }
        let result = planner.plan(
            work, busy: fixed + pinned.filter(\.isIncluded).map { DateInterval(start: $0.start, end: $0.end) },
            from: now, used: used
        )

        var items = draft.newEvents + pinned
        for block in result.blocks {
            guard let task = draft.tasks.first(where: { $0.id == block.itemID }) else { continue }
            items.append(PlanDraft.Item(
                title: task.title, start: block.start, end: block.end, mode: task.mode,
                kind: .workBlock, reminderMinutes: blockReminder, taskID: task.id
            ))
        }
        items.sort { $0.start < $1.start }
        draft.items = items
        return Result(draft: draft, shortfalls: result.shortfalls, replanned: replan)
    }

    /// Un bloque sigue valiendo si no ha empezado, acaba antes de la fecha límite, no pisa nada
    /// fijo y respeta las condiciones de horario.
    /// Cuándo se puede trabajar una tarea: hasta su entrega o, si tiene día de trabajo, solo ese día.
    func workWindow(_ task: PlanDraft.Workload) -> (start: Date?, end: Date) {
        guard let day = task.workDay.map({ calendar.startOfDay(for: $0) }),
              let next = calendar.date(byAdding: .day, value: 1, to: day) else { return (nil, task.deadline) }
        return (day, min(task.deadline, next))
    }

    private func fits(_ block: PlanDraft.Item, task: PlanDraft.Workload, fixed: [DateInterval], constraints: PlanConstraints) -> Bool {
        let window = workWindow(task)
        guard block.start >= now, block.end <= window.end else { return false }
        if let start = window.start, block.start < start { return false }
        if fixed.contains(where: { $0.start < block.end && block.start < $0.end }) { return false }
        if let latest = constraints.latestEndMinute, endMinute(of: block) > latest { return false }
        if let earliest = constraints.earliestStartMinute, ProposalEditor.minuteOfDay(block.start, calendar: calendar) < earliest { return false }
        return true
    }

    private func endMinute(of block: PlanDraft.Item) -> Int {
        let minute = ProposalEditor.minuteOfDay(block.end, calendar: calendar)
        // Un bloque que acaba a medianoche cuenta como las 24:00.
        return minute == 0 && !calendar.isDate(block.start, inSameDayAs: block.end) ? 24 * 60 : minute
    }
}
