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

    /// Nombres en singular de lo que se planifica («un único evento»).
    static let singularNouns: Set<String> = [
        "evento", "cita", "reunion", "llamada", "clase", "recordatorio", "tarea", "examen", "entrega", "visita", "sesion",
    ]

    /// «Solo quiero un único evento», «solo una cita»: tiene que quedar una sola cosa. «Solo una
    /// reunión más» añade, no limita.
    static func wantsOnlyOne(_ text: String) -> Bool {
        let words = ProposalText.words(text)
        guard words.contains(where: ["solo", "sola", "solamente", "unicamente", "unico", "unica"].contains) else { return false }
        for index in words.indices where ["un", "una", "1"].contains(words[index]) {
            var next = index + 1
            if next < words.count, ["unico", "unica", "solo", "sola"].contains(words[next]) { next += 1 }
            guard next < words.count, singularNouns.contains(words[next]) else { continue }
            if next + 1 < words.count, words[next + 1] == "mas" { return false }
            return true
        }
        return false
    }

    /// «Nada más», «solo eso», «quita lo demás»: lo que no se nombra sobra.
    static func wantsNothingElse(_ text: String) -> Bool {
        let joined = " " + ProposalText.words(text).joined(separator: " ") + " "
        return [" nada mas ", " solo eso ", " solo ese ", " solo esa ", " unicamente eso ", " quita lo demas ", " quita el resto ",
                " borra lo demas ", " borra el resto ", " lo demas sobra ", " el resto sobra "].contains(where: joined.contains)
    }

    /// El plan que dice la petición: «planifica en normal», «en el plan de trabajo». nil si no lo
    /// dice o nombra los dos. Lo dicho manda sobre lo que deduzca la IA.
    static func statedMode(in text: String) -> PlanMode? {
        let joined = " " + ProposalText.words(text).joined(separator: " ") + " "
        let personal = [" en normal ", " plan normal ", " modo normal ", " en el normal ", " al normal ", " del normal ",
                        " en personal ", " plan personal ", " modo personal ", " en el personal "]
        let work = [" en trabajo ", " plan de trabajo ", " plan trabajo ", " modo trabajo ", " modo de trabajo ",
                    " en el de trabajo ", " al de trabajo "]
        switch (personal.contains(where: joined.contains), work.contains(where: joined.contains)) {
        case (true, false): return .personal
        case (false, true): return .work
        default: return nil
        }
    }

    /// Habla de orden o de prisa («primero», «prioriza», «urgente», «antes que»).
    static func saysPriority(_ text: String) -> Bool {
        ProposalText.words(text).contains {
            ["primero", "primera", "prioriza", "priorizar", "priorizala", "priorizalo", "prioridad", "prioritario", "prioritaria",
             "urgente", "urgentes", "antes", "adelanta", "adelantar", "importante", "importantes"].contains($0)
        }
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

// MARK: - Día y horas de un único evento nuevo

/// Con un solo evento nuevo se sabe de qué habla cada dato de la petición, así que lo escrito
/// manda sobre lo que diga la IA.
enum EventGrounding {
    /// Inicio y fin (minutos desde medianoche). Una franja («de 10 a 12») manda; si no, «empieza
    /// a las 18» y «acabará a las 20». Si la IA da un inicio que nadie escribió («hay que estar
    /// antes» → 16:00), vale la primera hora que sí se escribió.
    static func times(start: Int?, end: Int?, request: String) -> (start: Int?, end: Int?) {
        if let range = AnswerParsing.range(request) { return (range.start, range.end) }
        var start = start
        var end = end
        if let said = AnswerParsing.explicitStart(request) {
            start = said
        } else if let current = start, !AnswerParsing.times(in: request).contains(current), let said = AnswerParsing.startTime(request) {
            start = said
        }
        if let said = AnswerParsing.endTime(request) { end = said }
        return (start, end)
    }

    /// El día, si la petición nombra uno solo («para el día 28 de noviembre», esté donde esté).
    static func onlyDay(in request: String, now: Date, calendar: Calendar = .current) -> Date? {
        let days = Set(RequestDates.mentions(in: request, now: now, calendar: calendar).map(\.day))
        return days.count == 1 ? days.first : nil
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

// MARK: - Lo dictado

/// Lo que se dicta llega con las horas habladas («de cinco y media a siete», «a las seis menos
/// cuarto»). Aquí se pasan a cifras («de 5:30 a 7», «a las 5:45») antes de dárselo a la IA y al
/// repaso, que así leen lo mismo que si se hubiera escrito. Solo toca horas: el resto queda igual.
enum SpokenText {
    private static let hours: [String: Int] = [
        "una": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7, "ocho": 8,
        "nueve": 9, "diez": 10, "once": 11, "doce": 12,
    ]
    private static let minutes: [String: Int] = [
        "cinco": 5, "diez": 10, "cuarto": 15, "veinte": 20, "veinticinco": 25, "media": 30,
        "treinta": 30, "cuarenta": 40, "cuarenta y cinco": 45, "cincuenta": 50,
    ]
    /// Lo que va delante de una hora.
    private static let lead = #"(\b(?:a las|a la|las|la|a|de|desde|hasta|entre|sobre las|y las|y la|y)\s+)"#

    static func tidy(_ text: String) -> String {
        var value = text
        // «las cinco» → «las 5» (solo delante de algo que la convierte en hora).
        let words = hours.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        let tail = #"(?=\s+(?:y\s+(?:media|cuarto|cinco|diez|veinte|veinticinco|treinta|cuarenta|cincuenta|\d)|menos\s|de la\s|en punto|a\s+(?:las?\s+)?(?:\d|"# + words + #")|hasta\s)|\s*[.,;]|\s*$)"#
        value = replace(lead + "(" + words + ")" + #"\b"# + tail, in: value) { match in
            guard let hour = hours[match[2].lowercased()] else { return nil }
            return match[1] + String(hour)
        }
        // «5 menos cuarto» → «4:45»; «5 menos diez» → «4:50».
        value = replace(lead + #"(\d{1,2})\s+menos\s+(cuarto|cinco|diez|veinte|veinticinco)\b"#, in: value) { match in
            guard let hour = Int(match[2]), (1...24).contains(hour), let minute = minutes[match[3].lowercased()] else { return nil }
            return match[1] + clock((hour + 23) % 24, 60 - minute)
        }
        // «5 y media» → «5:30»; «5 y cuarto» → «5:15»; «5 y 20» → «5:20».
        let spoken = minutes.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        value = replace(lead + #"(\d{1,2})\s+y\s+("# + spoken + #"|\d{2})\b(?!\s*(?:horas?|min|de (?:enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre)))"#, in: value) { match in
            guard let hour = Int(match[2]), (0...23).contains(hour),
                  let minute = minutes[match[3].lowercased()] ?? Int(match[3]), (0...59).contains(minute) else { return nil }
            return match[1] + clock(hour, minute)
        }
        return value
    }

    private static func clock(_ hour: Int, _ minute: Int) -> String {
        "\(hour):" + String(format: "%02d", minute)
    }

    /// Sustituye cada coincidencia por lo que diga `change` (nil la deja como está).
    private static func replace(_ pattern: String, in text: String, change: ([String]) -> String?) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        var result = text
        let found = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in found.reversed() {
            guard let whole = Range(match.range, in: result) else { continue }
            let parts = (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
            if let replacement = change(parts) { result.replaceSubrange(whole, with: replacement) }
        }
        return result
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
        return ["asi esta bien", "dejalo", "dejala", "dejalos", "dejalas", "vale asi", "me vale", "esta bien asi", "dejar a las", "dejar de", "dejar hasta"]
            .contains(where: joined.contains)
    }

    /// Una franja con inicio y fin: «de 10 a 12», «de 9:00 a 11:30», «10:00–12:00», «entre las 4 y
    /// las 6», «de 22:00 a 1:00 del día siguiente». Minutos desde medianoche. `nextDay` solo si el
    /// fin queda antes del inicio y se dice que es del día siguiente (o de madrugada).
    static func range(_ text: String) -> (start: Int, end: Int, nextDay: Bool)? {
        let value = normalize(text)
        let hour = #"(\d{1,2})(?:[:.h](\d{2}))?"#
        let notLength = #"(?![\d/])(?!\s*(?:horas?\b|hrs?\b|h\b|min))"#
        let patterns = [
            #"(?:\bde|\bdesde)\s+(?:las?\s+)?"# + hour + #"\s+(?:a|hasta)\s+(?:las?\s+)?"# + hour + notLength,
            #"\bentre\s+(?:las?\s+)?"# + hour + #"\s+y\s+(?:las?\s+)?"# + hour + notLength,
            #"(?<![\d/])"# + hour + #"\s*[-–—]\s*"# + hour + notLength,
        ]
        for pattern in patterns {
            guard let match = groups(pattern, in: value),
                  var startHour = match[1].flatMap({ Int($0) }), var endHour = match[3].flatMap({ Int($0) }),
                  (0...23).contains(startHour), (0...24).contains(endHour) else { continue }
            let startMinute = match[2].flatMap { Int($0) } ?? 0
            let endMinute = match[4].flatMap { Int($0) } ?? 0
            guard (0...59).contains(startMinute), (0...59).contains(endMinute) else { continue }
            let morning = value.contains("de la manana") || value.contains("madrugada") || value.contains(" am")
            let afternoon = value.contains("tarde") || value.contains("noche") || value.contains(" pm")
            let saysNextDay = value.contains("dia siguiente") || value.contains("madrugada") || value.contains("manana siguiente")
            if !morning {
                // «De 3 a 5»: por la tarde. «De 10 a 2»: hasta las 14:00. «De 7 a 9»: por la mañana.
                if endHour < 12, afternoon || (1...7).contains(endHour) { endHour += 12 }
                if (1...7).contains(startHour), startHour + 12 < endHour { startHour += 12 }
                if afternoon, startHour < 12, startHour + 12 < endHour { startHour += 12 }
            }
            if saysNextDay, endHour >= 12, endHour - 12 < startHour, !morning {
                // «De 22 a 1 del día siguiente»: la 1 de la madrugada, no las 13:00.
                endHour -= 12
            }
            let start = startHour * 60 + startMinute
            let end = endHour * 60 + endMinute
            return (start, end, saysNextDay && end <= start)
        }
        return nil
    }

    /// La hora de fin dicha sola: «hasta las 12», «que termine a las 17:00», «acaba a la 1 y media».
    static func endTime(_ text: String) -> Int? {
        let value = normalize(text)
        guard let regex = try? NSRegularExpression(pattern: #"\b(?:hasta|termin\w*|acab\w*|fin|final|finalice|finaliza)\b"#),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range, in: value) else { return nil }
        return time(String(value[range.upperBound...]))
    }

    private static let endWords = #"\b(?:hasta|termin\w*|acab\w*|fin|final|finalice|finaliza)\b"#
    private static let startWords = #"\b(?:empiez\w*|empiec\w*|empez\w*|comienz\w*|comienc\w*|comenz\w*|inicio|inicia\w*|arranca\w*)\b"#

    /// El texto hasta donde se empieza a hablar del final («…acabará a las 20» queda fuera).
    private static func beforeEnd(_ value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: endWords),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range, in: value) else { return value }
        return String(value[..<range.lowerBound])
    }

    /// La hora de inicio dicha con todas las letras: «empieza a las 18», «el inicio es a las 9:30».
    /// nil si no se habla del comienzo.
    static func explicitStart(_ text: String) -> Int? {
        let value = normalize(text)
        guard let regex = try? NSRegularExpression(pattern: startWords),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range, in: value) else { return nil }
        return time(beforeEnd(String(value[range.upperBound...])))
    }

    /// La hora de inicio: la dicha con todas las letras o, si no, la primera hora que no es la de
    /// fin («reunión a las 10 hasta las 12» → 10:00).
    static func startTime(_ text: String) -> Int? {
        explicitStart(text) ?? time(beforeEnd(normalize(text)))
    }

    /// Todas las horas escritas en el texto, en minutos desde medianoche. Las de 1 a 11 valen
    /// también por la tarde («a las 6» puede ser 18:00): sirve para saber si una hora que da la IA
    /// la dijo alguien.
    static func times(in text: String) -> Set<Int> {
        let value = normalize(text)
        var found: Set<Int> = []
        let patterns = [#"(?<!\d)(\d{1,2})[:.](\d{2})(?!\d)"#, #"\b(?:las|la)\s+(\d{1,2})(?!\d)(?:\s+y\s+(media|cuarto))?"#]
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)) {
                let parts = (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: value).map { String(value[$0]) } }
                guard let hour = parts[1].flatMap({ Int($0) }), (0...23).contains(hour) else { continue }
                var minute = 0
                if index == 0 {
                    minute = parts[2].flatMap { Int($0) } ?? 0
                } else if parts.count > 2, parts[2] == "media" {
                    minute = 30
                } else if parts.count > 2, parts[2] == "cuarto" {
                    minute = 15
                }
                guard (0...59).contains(minute) else { continue }
                found.insert(hour * 60 + minute)
                if hour < 12 { found.insert((hour + 12) * 60 + minute) }
            }
        }
        return found
    }

    /// Cuánto se mueve solo el comienzo: «adelanta el comienzo media hora» −30, «que empiece una
    /// hora más tarde» +60. nil si no se habla del comienzo o no se dice cuánto.
    static func startShift(_ text: String) -> Int? {
        let words = Set(ProposalText.words(text))
        let aboutStart = !words.isDisjoint(with: [
            "comienzo", "inicio", "empiece", "empieza", "empezar", "comience", "comienza", "comenzar", "empiecen", "comiencen",
        ])
        guard aboutStart, let minutes = duration(text), minutes > 0 else { return nil }
        let earlier = !words.isDisjoint(with: ["adelanta", "adelantar", "adelantalo", "adelantala", "adelantando", "antes"])
        let later = !words.isDisjoint(with: ["retrasa", "retrasar", "retrasalo", "retrasala", "atrasa", "atrasar", "despues", "tarde"])
        guard earlier != later else { return nil }
        return earlier ? -minutes : minutes
    }

    /// «Conserva la hora de fin», «manteniendo el final», «que termine a la misma hora».
    static func keepsEnd(_ text: String) -> Bool {
        let words = Set(ProposalText.words(text))
        let keep: Set<String> = [
            "conserva", "conservar", "conservando", "conserves", "manten", "mantener", "manteniendo", "mantengas",
            "misma", "mismo", "igual", "sin",
        ]
        let end: Set<String> = ["fin", "final", "termina", "termine", "terminar", "terminando", "acaba", "acabe", "acabar"]
        return !words.isDisjoint(with: keep) && !words.isDisjoint(with: end)
    }

    /// El fin es del día siguiente: «del día siguiente», «de madrugada».
    static func endsNextDay(_ text: String) -> Bool {
        let value = normalize(text)
        return value.contains("dia siguiente") || value.contains("madrugada") || value.contains("manana siguiente")
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

    /// La primera pregunta pendiente: el día, después cuándo empieza (y termina, si tampoco se
    /// sabe) y por último cuándo termina.
    static func next(in draft: PlanDraft, among ids: Set<UUID>? = nil) -> DetailQuestion? {
        for field in [ItemField.day, .time, .duration] {
            let items = draft.newEvents.filter { item in
                item.isIncluded && item.isUnconfirmed(field) && (ids?.contains(item.id) ?? true)
            }
            if !items.isEmpty { return make(field, items: items) }
        }
        return nil
    }

    /// Se pregunta a la vez por el inicio y el fin (ninguno de los dos se sabe).
    static func asksBoth(_ items: [PlanDraft.Item]) -> Bool {
        !items.isEmpty && items.allSatisfy { $0.isUnconfirmed(.time) && $0.isUnconfirmed(.duration) }
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
        case .time where asksBoth(items):
            // Ni inicio ni fin: «¿A qué hora quieres que comiencen y terminen?».
            question = many
                ? "¿A qué hora quieres que comiencen y terminen \(list)?"
                : "¿A qué hora quieres que comience y termine \(list)?"
            choices = ["9:00–10:00", "10:00–12:00", "16:00–17:00"]
            if many { choices.append("Horario diferente para cada evento") }
            if let first = items.first {
                let times = EventTimes(start: first.start, end: first.end)
                choices.append("Dejar de \(ProposalFormat.time.string(from: times.start)) a \(ProposalFormat.time.string(from: times.end))")
            }
        case .time:
            // Se sabe cuánto dura (o cuándo acaba): falta el comienzo.
            let current = items.first.map { ProposalFormat.time.string(from: $0.start) } ?? "9:00"
            let length = items.first.map { ProposalFormat.minutes($0.durationMinutes) } ?? ""
            question = many
                ? "¿A qué hora comienzan \(list)? Duran \(length)."
                : "¿A qué hora comienza \(list)? Dura \(length)."
            choices = ["9:00", "12:00", "17:00"]
            if many { choices.append("Hora diferente para cada evento") }
            choices.append("Dejar a las \(current)")
        case .duration:
            // Se sabe cuándo empieza: falta cuándo termina.
            let starts = Set(items.map { EventSchedule.minuteOfDay($0.start) })
            let first = items.first
            let begins = first.map { ProposalFormat.time.string(from: $0.start) } ?? ""
            question = many
                ? "¿A qué hora terminan \(list)?" + (starts.count == 1 ? " Comienzan a las \(begins)." : "")
                : "¿A qué hora termina \(list)? Comienza a las \(begins)."
            if starts.count == 1, let first {
                choices = [30, 60, 120].map { ProposalFormat.time.string(from: first.start.addingTimeInterval(TimeInterval($0 * 60))) }
            } else {
                choices = ["Dura 30 min", "Dura 1 h", "Dura 2 h"]
            }
            if many { choices.append("Hora de fin diferente para cada evento") }
            if let first, starts.count == 1 { choices.append("Dejar hasta las \(ProposalFormat.time.string(from: first.end))") }
        }
        return DetailQuestion(field: field, itemIDs: items.map(\.id), question: question, choices: choices)
    }

    /// Convierte la respuesta en cambios para los elementos preguntados. También aprovecha otros
    /// datos que vengan en la misma frase («de 10 a 12», «a las 10, una hora»).
    func answer(_ text: String, in draft: PlanDraft, now: Date, calendar: Calendar = .current) -> Answer {
        if AnswerParsing.wantsEachSeparately(text) { return itemIDs.count > 1 ? .eachSeparately : .unknown }
        if AnswerParsing.keepsAsIs(text) { return .keep }
        var changes = ProposalChanges()
        let words = Set(ProposalText.words(text))
        // Solo se toma lo que se pregunta y lo que se dice de forma inequívoca.
        let saysTime = text.contains(":") || !words.isDisjoint(with: ["las", "la", "mediodia", "tarde", "noche"])
        let saysDuration = !words.isDisjoint(with: ["hora", "horas", "h", "min", "mins", "minuto", "minutos", "media", "cuarto", "dura", "duran"])
        if let range = AnswerParsing.range(text) {
            changes.startMinute = range.start
            changes.endMinute = range.end
            if range.nextDay { changes.endsNextDay = true }
        } else {
            switch field {
            case .duration:
                // ¿Cuándo termina? «12:00», «a las 12», «hasta la 1»; o cuánto dura: «dura 2 h».
                if saysDuration, !text.contains(":"), let minutes = AnswerParsing.duration(text) {
                    changes.minutes = max(5, min(minutes, 12 * 60))
                } else if let minute = AnswerParsing.time(text) {
                    changes.endMinute = minute
                    if AnswerParsing.endsNextDay(text) { changes.endsNextDay = true }
                }
            case .time:
                // ¿Cuándo empieza? «a las 10». Si solo se dice cuánto dura, se guarda la duración
                // y se pregunta después el comienzo.
                let pureLength = saysDuration && !saysTime
                if !pureLength, let minute = AnswerParsing.time(text) { changes.startMinute = minute }
                if let end = AnswerParsing.endTime(text), changes.startMinute != nil, end != changes.startMinute { changes.endMinute = end }
                if changes.endMinute == nil, saysDuration, let minutes = AnswerParsing.duration(text) {
                    changes.minutes = max(5, min(minutes, 12 * 60))
                }
            case .day:
                if saysTime, let minute = AnswerParsing.time(text) { changes.startMinute = minute }
            }
        }
        if let day = RequestDates.mentions(in: text, now: now, reference: draft.items.first { itemIDs.contains($0.id) }?.start, calendar: calendar).first?.day {
            changes.day = day
        }
        let answered: Bool = switch field {
        case .day: changes.day != nil
        case .time: changes.startMinute != nil || changes.minutes != nil
        case .duration: changes.endMinute != nil || changes.minutes != nil
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
            let times = EventTimes(start: event.start, end: event.end)
            switch (event.isUnconfirmed(.time), event.isUnconfirmed(.duration)) {
            case (true, true): line += " (horario por confirmar)"
            case (true, false): line += " (hora de inicio por confirmar, dura \(ProposalFormat.minutes(times.minutes)))"
            case (false, true): line += ", empieza a las \(ProposalFormat.time.string(from: event.start)) (hora de fin por confirmar)"
            case (false, false): line += ", \(EventSchedule.summary(times))"
            }
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

// MARK: - Horas dichas en la petición

/// Comprueba con la petición escrita lo que la IA entendió de las horas de un cambio. Solo
/// cuando hay un único cambio (con varios no se sabe a cuál se refiere cada hora).
enum TimeGrounding {
    static func check(_ edits: [ProposalEdit], request: String) -> [ProposalEdit] {
        let updates = edits.indices.filter { index in
            if case .update = edits[index] { return true }
            return false
        }
        guard updates.count == 1, let index = updates.first,
              case .update(let target, var changes) = edits[index] else { return edits }
        // Solo si la IA entendió que se cambian horas (un cambio de nombre no se toca).
        let aboutTime = changes.startMinute != nil || changes.endMinute != nil || changes.minutes != nil
            || changes.startDeltaMinutes != nil || changes.day != nil || changes.workDay != nil || changes.keepEnd == true
        guard aboutTime else { return edits }

        let keepsEnd = AnswerParsing.keepsEnd(request)
        if let range = AnswerParsing.range(request) {
            // «De 9:00 a 11:00»: inicio y fin, tal cual.
            changes.startMinute = range.start
            changes.endMinute = range.end
            changes.endsNextDay = range.nextDay ? true : nil
            changes.minutes = nil
            changes.startDeltaMinutes = nil
        } else if let shift = AnswerParsing.startShift(request) {
            // «Adelanta el comienzo media hora»: se mueve el comienzo, no la duración.
            changes.startDeltaMinutes = shift
            changes.startMinute = nil
            changes.minutes = nil
            changes.deltaMinutes = nil
        } else if let end = AnswerParsing.endTime(request), AnswerParsing.startShift(request) == nil {
            // «Haz que termine a las 17:00»: la hora de fin, sin tocar el inicio.
            changes.endMinute = end
            if changes.startMinute == end { changes.startMinute = nil }
            changes.minutes = nil
        }
        // Conservar el fin solo si se dice.
        changes.keepEnd = keepsEnd && changes.endMinute == nil ? true : nil
        if changes.endsNextDay == true, !AnswerParsing.endsNextDay(request) { changes.endsNextDay = nil }

        var result = edits
        result[index] = .update(target, changes)
        return result
    }
}
