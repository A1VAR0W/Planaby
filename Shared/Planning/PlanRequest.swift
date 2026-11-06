import Foundation

// Comprobaciones deterministas sobre lo que pide la persona. La IA entiende la petición; este
// código vigila que la propuesta no pierda ni invente elementos, conserva los nombres tal como
// se escribieron y entiende las respuestas cortas («1 h», «a las 10») sin volver a preguntar al
// modelo. Todo se puede probar sin el modelo.

// MARK: - Cuántas cosas se piden

enum RequestCheck {
    static let numberWords: [String: Int] = [
        "un": 1, "una": 1, "uno": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6,
        "siete": 7, "ocho": 8, "nueve": 9, "diez": 10,
    ]
    /// Palabras que nombran algo que se planifica.
    static let nouns: Set<String> = [
        "evento", "eventos", "cita", "citas", "reunion", "reuniones", "llamada", "llamadas", "clase", "clases",
        "recordatorio", "recordatorios", "tarea", "tareas", "pendiente", "pendientes", "examen", "examenes",
        "entrega", "entregas", "visita", "visitas", "sesion", "sesiones", "bloque", "bloques",
    ]
    /// «Mueve las dos tareas»: se habla de cosas que ya existen, no de nuevas.
    static let determiners: Set<String> = [
        "los", "las", "mis", "tus", "sus", "esos", "esas", "estos", "estas", "ambos", "ambas", "otros", "otras",
    ]
    static let adjectives: Set<String> = ["nuevo", "nueva", "nuevos", "nuevas", "mas", "pequeno", "pequena", "pequenos", "pequenas"]

    /// Elementos nuevos que la petición anuncia: «dos eventos», «3 tareas», «una reunión el lunes
    /// y otra el martes». nil si no dice cuántos o dice uno solo (no hace falta vigilar nada).
    static func expectedNewItems(in text: String) -> Int? {
        let words = ProposalText.words(text)
        var total = 0
        var lastGroup = 0
        var index = 0
        while index < words.count {
            let word = words[index]
            if (word == "otro" || word == "otra"), lastGroup == 1 {
                // «Una reunión el lunes y otra el martes». Tras «dos eventos, uno… y otro…» es
                // una enumeración y no suma.
                total += 1
                index += 1
                continue
            }
            if let count = numberWords[word] ?? Int(word), (1...20).contains(count),
               index == 0 || !determiners.contains(words[index - 1]) {
                var next = index + 1
                if next < words.count, adjectives.contains(words[next]) { next += 1 }
                if next < words.count, nouns.contains(words[next]) {
                    total += count
                    lastGroup = count
                    index = next + 1
                    continue
                }
            }
            index += 1
        }
        return total > 1 ? total : nil
    }
}

// MARK: - Que no se cuele nada

enum RequestGrounding {
    /// Rutinas que el modelo tiende a añadir por su cuenta («Comida»).
    static let routines: [[String]] = [
        ["comida", "comer", "almuerzo", "almorzar"],
        ["cena", "cenar"],
        ["desayuno", "desayunar"],
        ["descanso", "descansar", "pausa"],
        ["merienda", "merendar"],
    ]

    /// El título sale de lo que dijo la persona (o de un adjunto): alguna de sus palabras aparece.
    static func isMentioned(_ title: String, in sources: [String]) -> Bool {
        let keys = ProposalText.keywords(title)
        guard !keys.isEmpty else { return false }
        let text = sources.joined(separator: " ")
        if ProposalText.score(query: keys, title: text) > 0 { return true }
        let words = Set(ProposalText.words(text))
        return routines.contains { group in keys.contains(where: group.contains) && group.contains(where: words.contains) }
    }

    static func isRoutine(_ title: String) -> Bool {
        let keys = ProposalText.keywords(title)
        return routines.contains { group in keys.contains(where: group.contains) }
    }

    /// Qué elementos nuevos se quedan. Se descarta lo que nadie pidió y además es una rutina o la
    /// copia de algo que ya está en la agenda. Si la petición dice cuántos son y sobran, se
    /// descartan primero los que no se mencionan.
    static func keep(titles: [String], sources: [String], agenda: [String], expected: Int?) -> [Bool] {
        var keep = titles.map { title in
            isMentioned(title, in: sources)
                || !(isRoutine(title) || agenda.contains { ProposalEditor.sameTitle($0, title) })
        }
        if let expected, keep.filter({ $0 }).count > expected {
            for index in titles.indices.reversed() where keep[index] && !isMentioned(titles[index], in: sources) {
                keep[index] = false
                if keep.filter({ $0 }).count <= expected { break }
            }
        }
        return keep
    }

    /// El nombre tal como lo escribió la persona: «Subida PRE», no «Subida pre» ni «Evento Subida PRE».
    static func exactTitle(_ title: String, in request: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "«»\"'.,;:")))
        guard !trimmed.isEmpty else { return title }
        var candidates = [trimmed]
        let generic = ["evento ", "cita ", "tarea ", "recordatorio "]
        for prefix in generic where trimmed.lowercased().hasPrefix(prefix) {
            candidates.append(String(trimmed.dropFirst(prefix.count)))
        }
        for candidate in candidates where candidate.count >= 2 {
            if let range = request.range(of: candidate, options: [.caseInsensitive, .diacriticInsensitive]),
               isWordBoundary(range, in: request) {
                return String(request[range])
            }
        }
        return trimmed
    }

    private static func isWordBoundary(_ range: Range<String.Index>, in text: String) -> Bool {
        let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
        let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
        return !(before?.isLetter ?? false) && !(after?.isLetter ?? false)
    }
}

// MARK: - Fechas escritas en la petición

enum RequestDates {
    static let months: [String: Int] = [
        "enero": 1, "febrero": 2, "marzo": 3, "abril": 4, "mayo": 5, "junio": 6, "julio": 7, "agosto": 8,
        "septiembre": 9, "setiembre": 9, "octubre": 10, "noviembre": 11, "diciembre": 12,
    ]
    /// Días de la semana como `Calendar` (1 = domingo).
    static let weekdays: [String: Int] = [
        "domingo": 1, "lunes": 2, "martes": 3, "miercoles": 4, "jueves": 5, "viernes": 6, "sabado": 7,
    ]

    struct Mention: Equatable {
        /// Posición (en palabras) dentro del texto.
        let offset: Int
        let day: Date
    }

    /// Los días que se nombran: «25 de noviembre», «el día 24», «mañana», «el jueves».
    /// Sin año, el próximo que no haya pasado. `reference`: mes para «el día 24» (si no, el actual).
    static func mentions(in text: String, now: Date, reference: Date? = nil, calendar: Calendar = .current) -> [Mention] {
        let words = ProposalText.words(text)
        let today = calendar.startOfDay(for: now)
        var result: [Mention] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            let previous = index > 0 ? words[index - 1] : ""
            // «25 de noviembre (de 2027)»
            if let number = Int(word), (1...31).contains(number), index + 2 < words.count, words[index + 1] == "de",
               let month = months[words[index + 2]] {
                var year: Int?
                if index + 4 < words.count, words[index + 3] == "de", let value = Int(words[index + 4]), value > 2000 { year = value }
                if let day = date(day: number, month: month, year: year, today: today, calendar: calendar) {
                    result.append(Mention(offset: index, day: day))
                }
                index += year == nil ? 3 : 5
                continue
            }
            // «el día 24», «al 24»
            if let number = Int(word), (1...31).contains(number), ["dia", "el", "al", "del"].contains(previous),
               !(index + 1 < words.count && ["de", "h", "horas", "hora", "min", "minutos"].contains(words[index + 1])) {
                let base = reference ?? now
                let parts = calendar.dateComponents([.year, .month], from: base)
                if var day = date(day: number, month: parts.month ?? 1, year: parts.year, today: today, calendar: calendar) {
                    if reference == nil, day < today, let next = calendar.date(byAdding: .month, value: 1, to: day) { day = next }
                    result.append(Mention(offset: index, day: day))
                }
                index += 1
                continue
            }
            switch word {
            case "hoy":
                result.append(Mention(offset: index, day: today))
            case "manana" where previous != "la" && previous != "de":
                if previous == "pasado" {
                    result.removeAll { $0.offset == index - 1 }
                    result.append(Mention(offset: index - 1, day: calendar.date(byAdding: .day, value: 2, to: today)!))
                } else {
                    result.append(Mention(offset: index, day: calendar.date(byAdding: .day, value: 1, to: today)!))
                }
            default:
                if let weekday = weekdays[word] {
                    let current = calendar.component(.weekday, from: today)
                    var ahead = (weekday - current + 7) % 7
                    if ahead == 0 { ahead = 7 }
                    result.append(Mention(offset: index, day: calendar.date(byAdding: .day, value: ahead, to: today)!))
                }
            }
            index += 1
        }
        return result
    }

    /// La petición dice cuándo de alguna forma («el 25», «mañana», «la semana que viene»).
    static func saysWhen(_ text: String, now: Date, calendar: Calendar = .current) -> Bool {
        if !mentions(in: text, now: now, calendar: calendar).isEmpty { return true }
        let words = Set(ProposalText.words(text))
        return !words.isDisjoint(with: ["semana", "mes", "finde", "proximo", "proxima", "siguiente", "viene", "dentro", "pasado"])
    }

    /// Días de la semana nombrados («el jueves»), para desempatar entre cosas guardadas.
    static func weekdaysMentioned(in text: String) -> Set<Int> {
        Set(ProposalText.words(text).compactMap { weekdays[$0] })
    }

    /// El día escrito justo después de cada título («Subida PRE para el 25 de noviembre»).
    /// nil donde no se dice o no se encuentra el título.
    static func days(for titles: [String], in request: String, now: Date, calendar: Calendar = .current) -> [Date?] {
        let words = ProposalText.words(request)
        let positions = titles.map { position(of: ProposalText.words($0), in: words) }
        let found = mentions(in: request, now: now, calendar: calendar)
        let sorted = positions.compactMap { $0 }.sorted()
        return positions.map { position in
            guard let position else { return nil }
            let next = sorted.first { $0 > position } ?? Int.max
            return found.first { $0.offset > position && $0.offset < next }?.day
        }
    }

    private static func position(of title: [String], in words: [String]) -> Int? {
        guard !title.isEmpty, title.count <= words.count else { return nil }
        for start in 0...(words.count - title.count) where Array(words[start..<(start + title.count)]) == title {
            return start + title.count - 1
        }
        return nil
    }

    private static func date(day: Int, month: Int, year: Int?, today: Date, calendar: Calendar) -> Date? {
        let currentYear = calendar.component(.year, from: today)
        guard var date = calendar.date(from: DateComponents(year: year ?? currentYear, month: month, day: day)) else { return nil }
        guard calendar.component(.day, from: date) == day else { return nil }
        if year == nil, date < today, let next = calendar.date(byAdding: .year, value: 1, to: date) { date = next }
        return calendar.startOfDay(for: date)
    }
}

// MARK: - Respuestas cortas

/// «1 h», «media hora», «a las 10», «5 de la tarde»: se entiende sin el modelo.
enum AnswerParsing {
    static func normalize(_ text: String) -> String {
        var value = " " + text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es")).lowercased() + " "
        let numbers: [(String, String)] = [
            (" un par de ", " 2 "), (" una ", " 1 "), (" un ", " 1 "), (" dos ", " 2 "), (" tres ", " 3 "), (" cuatro ", " 4 "),
            (" cinco ", " 5 "), (" seis ", " 6 "), (" siete ", " 7 "), (" ocho ", " 8 "), (" nueve ", " 9 "), (" diez ", " 10 "),
            (" once ", " 11 "), (" doce ", " 12 "), (" quince ", " 15 "), (" veinte ", " 20 "), (" treinta ", " 30 "),
            (" cuarenta y cinco ", " 45 "), (" noventa ", " 90 "),
        ]
        for (word, digit) in numbers {
            while value.contains(word) { value = value.replacingOccurrences(of: word, with: digit) }
        }
        return value
    }

    /// Minutos de duración, o nil si no se dice.
    static func duration(_ text: String) -> Int? {
        let value = normalize(text)
        if let match = groups(#"(\d+)?\s*horas?\s+y\s+media"#, in: value) {
            return (match[1].flatMap { Int($0) } ?? 1) * 60 + 30
        }
        if value.contains("media hora") { return 30 }
        if value.contains("3 cuartos de hora") { return 45 }
        if value.contains("cuarto de hora") { return 15 }
        if let match = groups(#"(\d+)[,.](\d)\s*(?:horas?|hrs?|h)(?![a-z])"#, in: value),
           let hours = Int(match[1] ?? ""), let tenth = Int(match[2] ?? "") {
            return hours * 60 + tenth * 6
        }
        if let match = groups(#"(\d+)\s*(?:horas?|hrs?|h)(?![a-z])\s*(?:y\s*)?(?:(\d+)(?![:\d])\s*(?:minutos?|mins?|m)?(?![a-z]))?"#, in: value),
           let hours = Int(match[1] ?? "") {
            return hours * 60 + (match[2].flatMap { Int($0) } ?? 0)
        }
        if let match = groups(#"(\d+)\s*(?:minutos?|mins?|m)(?![a-z])"#, in: value), let minutes = Int(match[1] ?? "") {
            return minutes
        }
        // Solo un número: horas si es pequeño, minutos si no.
        if let match = groups(#"^\s*(\d+)\s*$"#, in: value), let number = Int(match[1] ?? "") {
            return number <= 8 ? number * 60 : number
        }
        return nil
    }

    /// Minutos desde medianoche, o nil si no se dice ninguna hora.
    static func time(_ text: String) -> Int? {
        let value = normalize(text)
        if value.contains("mediodia") { return 12 * 60 }
        var hour: Int?
        var minute = 0
        if let match = groups(#"(?<!\d)(\d{1,2})[:.](\d{2})(?!\d)"#, in: value) {
            hour = Int(match[1] ?? "")
            minute = Int(match[2] ?? "") ?? 0
        } else if let match = groups(#"(?:a las|las|a la|la)\s+(\d{1,2})(?!\d)(?:\s+y\s+(media|cuarto)|\s+(menos)\s+cuarto)?"#, in: value) {
            hour = Int(match[1] ?? "")
            if match[2] == "media" { minute = 30 } else if match[2] == "cuarto" { minute = 15 }
            if match[3] != nil, let current = hour { hour = current - 1; minute = 45 }
        } else if let match = groups(#"(?<!\d)(\d{1,2})\s*(?:de la (?:manana|tarde|noche|madrugada)|am|pm)"#, in: value) {
            hour = Int(match[1] ?? "")
        } else if let match = groups(#"^\s*(\d{1,2})\s*$"#, in: value) {
            hour = Int(match[1] ?? "")
        }
        guard var hour, (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        let afternoon = value.contains("tarde") || value.contains("noche") || value.contains(" pm")
        let morning = value.contains("de la manana") || value.contains("madrugada") || value.contains(" am")
        if hour < 12, afternoon { hour += 12 } else if !morning, (1...7).contains(hour) { hour += 12 }
        return hour * 60 + minute
    }

    /// «Distinta para cada uno», «cada uno diferente».
    static func wantsEachSeparately(_ text: String) -> Bool {
        let words = Set(ProposalText.words(text))
        return (words.contains("distinta") || words.contains("distinto") || words.contains("diferente") || words.contains("diferentes"))
            && (words.contains("cada") || words.contains("uno") || words.contains("evento"))
    }

    /// «Así está bien», «déjalo»: se acepta lo provisional.
    static func keepsAsIs(_ text: String) -> Bool {
        let joined = ProposalText.words(text).joined(separator: " ")
        return ["asi esta bien", "dejalo", "dejala", "dejalos", "dejalas", "vale asi", "me vale", "esta bien asi", "dejar a las"]
            .contains(where: joined.contains)
    }

    private static func groups(_ pattern: String, in text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }
}

// MARK: - Lo que falta por saber

/// Una pregunta sobre un dato que la persona no dijo (día, hora o duración). Se construye sin la
/// IA, con opciones rápidas, y se responde sin la IA cuando la respuesta es corta.
struct DetailQuestion: Codable, Equatable, Sendable {
    var field: ItemField
    var itemIDs: [UUID]
    var question: String
    var choices: [String]
    /// Se pregunta de uno en uno («duración diferente para cada evento»).
    var oneByOne = false

    enum Answer: Equatable {
        case edits([ProposalEdit])
        /// Cada uno con un valor distinto: se pregunta de uno en uno.
        case eachSeparately
        /// Lo provisional vale.
        case keep
        case unknown
    }

    /// La primera pregunta pendiente: el día, después la duración y por último la hora.
    static func next(in draft: PlanDraft, among ids: Set<UUID>? = nil) -> DetailQuestion? {
        for field in [ItemField.day, .duration, .time] {
            let items = draft.newEvents.filter { item in
                item.isIncluded && item.isUnconfirmed(field) && (ids?.contains(item.id) ?? true)
            }
            if !items.isEmpty { return make(field, items: items) }
        }
        return nil
    }

    static func make(_ field: ItemField, items: [PlanDraft.Item]) -> DetailQuestion {
        let names = items.map { "«\($0.title)»" }
        let list = items.count <= 3 ? ProposalNarration.join(names) : "cada uno de los \(items.count) eventos"
        let many = items.count > 1
        let question: String
        var choices: [String]
        switch field {
        case .day:
            question = many ? "Me falta un dato: ¿qué día son \(list)?" : "Me falta un dato: ¿qué día es \(list)?"
            choices = ["Hoy", "Mañana"]
            if many { choices.append("Día diferente para cada evento") }
        case .duration:
            question = many ? "Me falta un dato: ¿cuánto duran \(list)?" : "Me falta un dato: ¿cuánto dura \(list)?"
            choices = ["30 min", "1 h", "2 h"]
            if many { choices.append("Duración diferente para cada evento") }
        case .time:
            let current = items.first.map { ProposalFormat.time.string(from: $0.start) } ?? "9:00"
            question = many ? "¿A qué hora son \(list)? Por ahora están a las \(current)." : "¿A qué hora es \(list)? Por ahora está a las \(current)."
            choices = ["9:00", "12:00", "17:00"]
            if many { choices.append("Hora diferente para cada evento") }
            choices.append("Dejar a las \(current)")
        }
        return DetailQuestion(field: field, itemIDs: items.map(\.id), question: question, choices: choices)
    }

    /// Convierte la respuesta en cambios para los elementos preguntados. También aprovecha otros
    /// datos que vengan en la misma frase («a las 10, una hora»).
    func answer(_ text: String, in draft: PlanDraft, now: Date, calendar: Calendar = .current) -> Answer {
        if AnswerParsing.wantsEachSeparately(text) { return itemIDs.count > 1 ? .eachSeparately : .unknown }
        if AnswerParsing.keepsAsIs(text) { return .keep }
        var changes = ProposalChanges()
        let words = Set(ProposalText.words(text))
        // Solo se toma lo que se pregunta y lo que se dice de forma inequívoca: «2» en una
        // pregunta de duración son dos horas, no las 14:00.
        let saysTime = text.contains(":") || !words.isDisjoint(with: ["las", "mediodia", "tarde", "noche"])
        let saysDuration = !words.isDisjoint(with: ["hora", "horas", "h", "min", "mins", "minuto", "minutos", "media", "cuarto"])
        if field == .duration || saysDuration, let minutes = AnswerParsing.duration(text) {
            changes.minutes = max(5, min(minutes, 12 * 60))
        }
        if field == .time || saysTime, let minute = AnswerParsing.time(text) {
            changes.startMinute = minute
        }
        if let day = RequestDates.mentions(in: text, now: now, reference: draft.items.first { itemIDs.contains($0.id) }?.start, calendar: calendar).first?.day {
            changes.day = day
        }
        let answered: Bool = switch field {
        case .day: changes.day != nil
        case .time: changes.startMinute != nil
        case .duration: changes.minutes != nil
        }
        guard answered else { return .unknown }
        let edits = itemIDs.compactMap { id -> ProposalEdit? in
            guard draft.items.contains(where: { $0.id == id }) else { return nil }
            return .update(ProposalTarget(text: draft.ref(id), kind: .event), changes)
        }
        return edits.isEmpty ? .unknown : .edits(edits)
    }

    /// Da por buenos los valores provisionales preguntados.
    func keep(in draft: inout PlanDraft) {
        for index in draft.items.indices where itemIDs.contains(draft.items[index].id) {
            draft.items[index].confirm(field)
        }
    }
}

// MARK: - Contar la propuesta

enum ProposalNarration {
    static func count(_ number: Int, _ singular: String, _ plural: String, feminine: Bool = false) -> String {
        let words = ["", feminine ? "una" : "un", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve", "diez"]
        let amount = number < words.count ? words[number] : "\(number)"
        return "\(amount) \(number == 1 ? singular : plural)"
    }

    static func join(_ parts: [String]) -> String {
        switch parts.count {
        case 0: ""
        case 1: parts[0]
        default: parts.dropLast().joined(separator: ", ") + " y " + parts.last!
        }
    }

    /// «He preparado dos eventos:» y una línea por elemento, con lo que falta por confirmar.
    static func created(events: [PlanDraft.Item], tasks: [PlanDraft.Workload]) -> String? {
        guard !events.isEmpty || !tasks.isEmpty else { return nil }
        var heads: [String] = []
        if !events.isEmpty { heads.append(count(events.count, "evento", "eventos")) }
        if !tasks.isEmpty { heads.append(count(tasks.count, "tarea", "tareas", feminine: true)) }
        var lines = ["He preparado \(join(heads)):"]
        for event in events {
            var line = "• \(event.title) — \(ProposalFormat.dayMonth.string(from: event.start))"
            line += event.isUnconfirmed(.time) ? " (hora por confirmar)" : ", \(ProposalFormat.time.string(from: event.start))"
            line += event.isUnconfirmed(.duration) ? " · duración por confirmar" : " · \(ProposalFormat.minutes(event.durationMinutes))"
            lines.append(line)
        }
        for task in tasks {
            lines.append("• \(task.title) — \(ProposalFormat.minutes(task.requestedMinutes)), entrega \(ProposalFormat.dayMonth.string(from: task.deadline))")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Lo que ya está guardado

/// Algo del calendario o de las tareas guardadas, tal como se le enseña a la IA: C1, C2… para
/// eventos de Planaby, P1, P2… para tareas pendientes. Los eventos de otros calendarios no tienen
/// código: solo se leen.
struct SavedRef: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case event, task, external }

    var code: String
    var title: String
    /// Inicio de un evento o entrega de una tarea.
    var date: Date
    var kind: Kind
    var isRecurring = false
}

enum SavedResolution: Equatable {
    case found(Int)
    case ambiguous([Int])
    case notFound
}

enum SavedResolver {
    /// Palabras que sitúan algo pero no forman parte de su nombre.
    static let contextWords: Set<String> = [
        "hoy", "manana", "pasado", "lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo",
        "tarea", "evento", "cita", "duplicada", "duplicado", "repetida", "repetido", "guardada", "guardado",
        "semana", "dia", "proximo", "proxima",
    ]

    /// A qué elemento guardado se refiere `text`. Primero el código; después el nombre; si varios
    /// se llaman igual, el día que se diga; si aun así hay varios, se pregunta.
    static func resolve(_ text: String, kind: ProposalTarget.Kind, in refs: [SavedRef], now: Date, calendar: Calendar = .current) -> SavedResolution {
        let candidates = refs.indices.filter { index in
            switch kind {
            case .event: refs[index].kind != .task
            case .task: refs[index].kind == .task
            case .any: true
            }
        }
        if let code = ProposalText.savedCode(in: text), let match = candidates.first(where: { refs[$0].code == code }) {
            return .found(match)
        }
        let query = ProposalText.keywords(text).filter { !contextWords.contains($0) && Int($0) == nil }
        guard !query.isEmpty else { return .notFound }
        let scored = candidates.map { ($0, ProposalText.score(query: query, title: refs[$0].title)) }
        guard let best = scored.map(\.1).max(), best > 0 else { return .notFound }
        // Al menos la mitad de lo que se dice tiene que estar en el nombre.
        guard best * 2 >= query.count else { return .notFound }
        var winners = scored.filter { $0.1 == best }.map(\.0)

        let days = RequestDates.mentions(in: text, now: now, calendar: calendar).map(\.day)
        let weekdays = RequestDates.weekdaysMentioned(in: text)
        if !days.isEmpty || !weekdays.isEmpty {
            let onDay = winners.filter { index in
                let date = refs[index].date
                return days.contains { calendar.isDate($0, inSameDayAs: date) }
                    || weekdays.contains(calendar.component(.weekday, from: date))
            }
            // Si el día dicho no coincide con nada, se pregunta en vez de adivinar.
            if onDay.isEmpty { return .ambiguous(winners) }
            winners = onDay
        }
        if winners.count > 1, wantsDuplicate(text), winners.dropFirst().allSatisfy({ ProposalEditor.sameTitle(refs[$0].title, refs[winners[0]].title) }) {
            // «Borra el duplicado»: el último de los que se llaman igual.
            return .found(winners.max { refs[$0].code.count != refs[$1].code.count ? refs[$0].code.count < refs[$1].code.count : refs[$0].code < refs[$1].code }!)
        }
        return winners.count == 1 ? .found(winners[0]) : .ambiguous(winners)
    }

    static func wantsDuplicate(_ text: String) -> Bool {
        ProposalText.words(text).contains { $0.hasPrefix("duplicad") || $0.hasPrefix("repetid") }
    }

    /// Pide la serie entera («todas las clases», «siempre»), no una sola vez.
    static func wantsWholeSeries(_ text: String) -> Bool {
        let words = Set(ProposalText.words(text))
        return !words.isDisjoint(with: ["todas", "todos", "serie", "siempre", "cada", "semanal", "semanales", "diaria", "diarias"])
    }
}
