import Foundation

/// Repaso de lo que devuelve la IA antes de convertirlo en una propuesta. Los modelos pequeños
/// repiten elementos, crean una tarea y un evento para lo mismo, copian títulos y códigos de los
/// ejemplos y, al corregir una propuesta, vuelven a crear lo que ya estaba. Aquí se arregla con
/// reglas fijas que no dependen del modelo y que se pueden probar sin él:
///
/// 1. Fuera los cambios sobre códigos que no existen («P1» de un ejemplo) y los «pon primero» que
///    nadie pidió.
/// 2. Fuera lo que nadie pidió y sale de los ejemplos del modelo.
/// 3. Una cosa pedida es un solo elemento: sin repetidos y sin tarea además de evento.
/// 4. Lo que ya está en la propuesta no se crea otra vez: se cambia.
/// 5. «Solo quiero un único evento»: queda uno y lo demás de la propuesta se quita.
enum PlanReadingCheck {
    /// Lo que existe en este momento: la propuesta abierta y los códigos de lo guardado.
    struct Known: Equatable, Sendable {
        struct Entry: Equatable, Sendable {
            var code: String
            var title: String
            /// Lo crea la propuesta (no es algo guardado que se está cambiando).
            var created = true
        }

        var events: [Entry] = []
        var tasks: [Entry] = []
        var savedCodes: Set<String> = []

        var hasProposal: Bool { !events.isEmpty || !tasks.isEmpty }
        var codes: Set<String> { Set(events.map(\.code) + tasks.map(\.code)).union(savedCodes) }
    }

    static func clean(
        _ reading: PlanReading, request: String, sources: [String], known: Known,
        examples: [String] = LocalPlanningPrompt.exampleTitles, now: Date = .now, calendar: Calendar = .current
    ) -> PlanReading {
        var result = reading
        let another = ProposalCommand.wantsAnother(request) || SavedResolver.wantsDuplicate(request)
        let several = another || (RequestCheck.expectedNewItems(in: request) ?? 1) > 1
        let onlyOne = RequestCheck.wantsOnlyOne(request)
        let saysPriority = RequestCheck.saysPriority(request)
        let days = Set(RequestDates.mentions(in: request, now: now, calendar: calendar).map(\.day))
        let received = reading.events.count + reading.tasks.count

        // 1. Códigos que no existen y «primero» sin que nadie hable de orden.
        let codes = known.codes
        result.edits = result.edits.filter { edit in
            if let code = bareCode(edit.target), !codes.contains(code) { return false }
            return edit.action != "first" || saysPriority
        }
        if !saysPriority { result.prioritize = [] }

        // 2. Títulos que salen de los ejemplos y que la persona no ha nombrado.
        func invented(_ title: String) -> Bool {
            !RequestGrounding.isMentioned(title, in: sources) && isExample(title, examples: examples)
        }
        var events = result.events.filter { !invented($0.title) }
        // Una tarea que nadie ha nombrado y que es un trozo de un ejemplo («Entregar», de «Entregar
        // informe»), o que acompaña a un evento que sí se pidió, es relleno del modelo.
        func filler(_ title: String) -> Bool {
            guard !RequestGrounding.isMentioned(title, in: sources) else { return false }
            let keys = Set(ProposalText.keywords(title))
            let fromExample = !keys.isEmpty && examples.contains { keys.isSubset(of: Set(ProposalText.keywords($0))) }
            return fromExample || !events.isEmpty
        }
        var tasks = result.tasks.filter { !invented($0.title) && !filler($0.title) }

        // 3. Lo mismo dos veces. Varias fechas («clase el lunes y el miércoles») o varias horas
        // («dos reuniones, a las 10 y a las 12») sí son varios, si la petición lo dice.
        var unique: [ReadEvent] = []
        for event in events {
            guard let twin = unique.firstIndex(where: { ProposalEditor.sameTitle($0.title, event.title) && isSame($0, event, several: several, days: days.count) }) else {
                unique.append(event)
                continue
            }
            if completeness(event) > completeness(unique[twin]) { unique[twin] = event }
        }
        events = unique
        // Algo con hora es un evento: no hace falta además una tarea que se llame igual.
        tasks = tasks.filter { task in !events.contains { ProposalEditor.sameTitle($0.title, task.title) } }
        var uniqueTasks: [ReadTask] = []
        for task in tasks where !uniqueTasks.contains(where: {
            ProposalEditor.sameTitle($0.title, task.title) && !(several && $0.deadline != task.deadline)
        }) {
            uniqueTasks.append(task)
        }
        tasks = uniqueTasks

        // 4. Lo que ya está en la propuesta no se vuelve a crear (salvo «otra reunión»): si trae
        // datos que dice la petición, se convierte en un cambio de lo que ya había.
        if known.hasProposal, !another {
            var changes: [ProposalEditFields] = []
            events = events.filter { event in
                let twins = known.events.filter { ProposalEditor.sameTitle($0.title, event.title) }
                guard let twin = twins.first else { return true }
                let edited = result.edits.contains { targets($0, codes: twins.map(\.code), title: twin.title) }
                if !edited, let change = update(of: twin.code, from: event, request: request, now: now, calendar: calendar) {
                    changes.append(change)
                }
                return false
            }
            tasks = tasks.filter { task in
                // Una sola tarea igual: se deja pasar y se funde con ella al aplicar. Varias: es ruido.
                let twins = known.tasks.filter { ProposalEditor.sameTitle($0.title, task.title) }.count
                return twins <= 1 && !known.events.contains { ProposalEditor.sameTitle($0.title, task.title) }
            }
            result.edits += changes
        }

        // 5. «Solo quiero un único evento».
        if onlyOne {
            if known.hasProposal {
                keepOnlyOne(&result, events: &events, tasks: &tasks, request: request, known: known, now: now, calendar: calendar)
            } else if !events.isEmpty {
                events = [events[0]]
                tasks = []
            } else {
                tasks = Array(tasks.prefix(1))
            }
        }

        // «Pon primero» algo que no es una tarea no dice nada.
        let taskTitles = tasks.map(\.title) + known.tasks.map(\.title)
        let taskCodes = Set(known.tasks.map(\.code)).union(known.savedCodes.filter { $0.hasPrefix("P") })
        result.edits = result.edits.filter { edit in
            guard edit.action == "first" else { return true }
            if let code = bareCode(edit.target) { return taskCodes.contains(code) }
            // Algo guardado puede no estar aquí: solo se quita si es claramente un evento.
            let query = ProposalText.keywords(edit.target)
            let isEvent = (events.map(\.title) + known.events.map(\.title)).contains { ProposalText.score(query: query, title: $0) > 0 }
            let isTask = taskTitles.contains { ProposalText.score(query: query, title: $0) > 0 }
            return isTask || !isEvent
        }

        result.events = events
        result.tasks = tasks
        // Si la IA contó sus propios repetidos, su cuenta ya no vale para echar algo en falta.
        let kept = events.count + tasks.count
        if received > kept {
            result.requestedCount = min(result.requestedCount, max(kept, result.requestedCount - (received - kept)))
        }
        if onlyOne { result.requestedCount = min(result.requestedCount, 1) }
        return result
    }

    // MARK: Piezas

    /// Deja un solo evento en la propuesta: el que la IA cambia, el que nombra la petición o, si
    /// todos se llaman igual, el primero. Los demás eventos creados se quitan, y también las
    /// tareas que se llaman igual o todas si se dice «nada más». Nunca toca lo guardado.
    private static func keepOnlyOne(
        _ result: inout PlanReading, events: inout [ReadEvent], tasks: inout [ReadTask], request: String,
        known: Known, now: Date, calendar: Calendar
    ) {
        let created = known.events.filter(\.created)
        var removals: [String] = []
        var keeperTitle: String?

        if let new = events.first {
            // Lo que se queda es algo nuevo con otro nombre: sobra todo lo creado antes.
            events = [new]
            keeperTitle = new.title
            removals = created.map(\.code)
            result.edits = result.edits.filter { edit in !created.contains { targets(edit, codes: [$0.code], title: $0.title) } }
        } else {
            let updates = result.edits.filter { $0.action == "update" }
            let edited = updates.compactMap { edit in created.first { targets(edit, codes: [$0.code], title: $0.title) } }.first
            let named = created.first { RequestGrounding.isMentioned($0.title, in: [request]) }
            let alike = created.dropFirst().allSatisfy { ProposalEditor.sameTitle($0.title, created[0].title) } ? created.first : nil
            guard let keeper = edited ?? named ?? alike else { return }
            keeperTitle = keeper.title
            removals = created.filter { $0.code != keeper.code }.map(\.code)
            // Los cambios sobre lo que se va a quitar ya no pintan nada.
            result.edits = result.edits.filter { edit in
                !created.contains { $0.code != keeper.code && bareCode(edit.target) == $0.code }
            }
            // Las horas y el día de la petición van al que se queda, aunque la IA no lo dijera.
            let hasUpdate = result.edits.contains { $0.action == "update" && targets($0, codes: [keeper.code], title: keeper.title) }
            if !hasUpdate, let change = update(of: keeper.code, from: ReadEvent(), request: request, now: now, calendar: calendar) {
                result.edits.append(change)
            }
        }
        tasks = []

        let nothingElse = RequestCheck.wantsNothingElse(request)
        let extraTasks = known.tasks.filter { task in
            task.created && (nothingElse || keeperTitle.map { ProposalEditor.sameTitle($0, task.title) } == true)
        }
        // Lo que se quita ya no se cambia ni se borra dos veces.
        let gone = Set(removals + extraTasks.map(\.code))
        result.edits = result.edits.filter { edit in
            guard let code = bareCode(edit.target), gone.contains(code) else { return true }
            return false
        }
        result.edits += gone.sorted(by: codeOrder).map { ProposalEditFields(action: "remove", target: $0) }
    }

    /// Un cambio sobre `code` con lo que la petición dice de día y horas (lo demás no se toca).
    /// nil si no hay nada que cambiar.
    private static func update(of code: String, from event: ReadEvent, request: String, now: Date, calendar: Calendar) -> ProposalEditFields? {
        var fields = ProposalEditFields(action: "update", target: code)
        let mentions = Set(RequestDates.mentions(in: request, now: now, calendar: calendar).map(\.day))
        if mentions.count == 1, let day = mentions.first {
            fields.day = dayText(day, calendar: calendar)
        } else if !event.day.isEmpty, RequestDates.saysWhen(request, now: now, calendar: calendar) {
            fields.day = event.day
        }
        if let range = AnswerParsing.range(request) {
            fields.time = clock(range.start)
            fields.endTime = clock(range.end)
        } else {
            if let start = AnswerParsing.explicitStart(request) {
                fields.time = clock(start)
            } else if !event.time.isEmpty, AnswerParsing.time(request) != nil {
                fields.time = event.time
            }
            if let end = AnswerParsing.endTime(request) {
                fields.endTime = clock(end)
            } else if event.durationMinutes > 0, AnswerParsing.duration(request) != nil {
                fields.minutes = event.durationMinutes
            }
        }
        return fields == ProposalEditFields(action: "update", target: code) ? nil : fields
    }

    /// Dos eventos con el mismo nombre son el mismo salvo que la petición hable de varios días
    /// (y estos lo sean) o de varias cosas (y cambie la hora).
    private static func isSame(_ a: ReadEvent, _ b: ReadEvent, several: Bool, days: Int) -> Bool {
        let differentDay = !a.day.isEmpty && !b.day.isEmpty && a.day != b.day
        if differentDay { return !(several || days > 1) }
        let differentTime = !a.time.isEmpty && !b.time.isEmpty && a.time != b.time
        return !(differentTime && several)
    }

    private static func completeness(_ event: ReadEvent) -> Int {
        (event.day.isEmpty ? 0 : 1) + (event.time.isEmpty ? 0 : 1) + (event.endTime.isEmpty && event.durationMinutes == 0 ? 0 : 1)
    }

    /// El título es uno de los ejemplos que se le enseñan al modelo, o un trozo de al menos dos
    /// palabras («Entregar informe»). Una sola palabra corriente («Reunión») no basta.
    static func isExample(_ title: String, examples: [String]) -> Bool {
        let keys = Set(ProposalText.keywords(title))
        guard !keys.isEmpty else { return false }
        return examples.contains { example in
            let other = Set(ProposalText.keywords(example))
            return keys == other || (keys.count >= 2 && keys.isSubset(of: other))
        }
    }

    /// El destino es solo un código («E1», «p2»). nil si es un nombre.
    static func bareCode(_ target: String) -> String? {
        let text = target.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "«»\"'.,:"))).uppercased()
        guard let first = text.first, "ETCP".contains(first), text.count >= 2, text.dropFirst().allSatisfy(\.isNumber) else { return nil }
        return text
    }

    /// El cambio va a uno de estos elementos: por código o, si usa palabras, por el nombre.
    private static func targets(_ edit: ProposalEditFields, codes: [String], title: String) -> Bool {
        if let code = bareCode(edit.target) { return codes.contains(code) }
        return ProposalText.score(query: ProposalText.keywords(edit.target), title: title) > 0
    }

    /// E1, E2, E10… y luego T1, T2…
    private static func codeOrder(_ a: String, _ b: String) -> Bool {
        if a.prefix(1) != b.prefix(1) { return a.prefix(1) < b.prefix(1) }
        return (Int(a.dropFirst()) ?? 0) < (Int(b.dropFirst()) ?? 0)
    }

    private static func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", min(23, minute / 60), minute % 60)
    }

    private static func dayText(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 1, parts.day ?? 1)
    }
}
