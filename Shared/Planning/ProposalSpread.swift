import Foundation

/// Corregir una propuesta que ha puesto en el mismo día varios eventos iguales: «no, uno cada
/// día, no todos el 19». No hace falta el modelo: los días ya se dijeron (en este mensaje o en
/// uno anterior) y solo hay que repartirlos. Sirve igual con Apple Intelligence, con el modelo
/// local y sin ninguno de los dos.
enum ProposalSpread {
    struct Plan: Equatable {
        var edits: [ProposalEdit]
        var title: String
        var days: [Date]
    }

    /// «Un evento cada día», «uno por día», «cada uno en su día», «no todos el 19».
    static func asksOnePerDay(_ text: String) -> Bool {
        let joined = " " + ProposalText.words(text).joined(separator: " ") + " "
        let direct = [
            " uno cada dia ", " una cada dia ", " uno por dia ", " una por dia ", " uno en cada dia ", " una en cada dia ",
            " uno para cada dia ", " una para cada dia ", " un evento cada dia ", " un evento por dia ", " un evento en cada dia ",
            " un evento para cada dia ", " una cita cada dia ", " una cita por dia ", " evento cada dia ", " evento por dia ",
            " cada uno en su dia ", " cada una en su dia ", " cada uno su dia ", " cada evento en su dia ", " cada uno en un dia ",
            " cada una en un dia ", " cada evento en un dia ", " un dia cada uno ", " un dia cada una ",
            " dias distintos ", " dias diferentes ", " dias separados ", " dia distinto ", " dia diferente ",
            " no todos el ", " no todas el ", " no todos en el ", " no todas en el ", " no todos juntos ", " no todas juntas ",
            " todos el mismo dia ", " todas el mismo dia ", " todos en el mismo dia ", " todas en el mismo dia ",
            " no el mismo dia ", " no en el mismo dia ",
        ]
        return direct.contains(where: joined.contains)
    }

    /// «Ponlos el 19, 20, 23 y 24»: los días se dan en el propio mensaje.
    private static func asksToPlace(_ text: String) -> Bool {
        let verbs: Set<String> = [
            "ponlos", "ponlas", "muevelos", "muevelas", "pasalos", "pasalas", "repartelos", "repartelas", "reparte",
            "distribuye", "distribuyelos", "distribuyelas", "separalos", "separalas", "separa", "colocalos", "colocalas",
        ]
        return ProposalText.words(text).contains(where: verbs.contains)
    }

    /// Las operaciones que dejan un evento por día, o nil si el mensaje no pide eso o no se
    /// sabe con seguridad qué días ni qué eventos son (entonces decide el modelo, o se pregunta).
    /// `earlier`: mensajes anteriores de la persona, del más reciente al más antiguo.
    static func plan(
        request: String, earlier: [String], draft: PlanDraft, now: Date, calendar: Calendar = .current
    ) -> Plan? {
        let perDay = asksOnePerDay(request)
        let own = PlanReadingCheck.orderedDays(in: request, now: now, calendar: calendar)
        guard perDay || (own.count >= 2 && asksToPlace(request) && !ProposalCommand.wantsAnother(request)) else { return nil }

        // Los días: los de este mensaje si trae la lista; si no, los de la petición original.
        var days = own.count >= 2 ? own : []
        if days.isEmpty {
            for text in earlier {
                let listed = PlanReadingCheck.orderedDays(in: text, now: now, calendar: calendar)
                if listed.count >= 2 {
                    days = listed
                    break
                }
            }
        }
        guard days.count >= 2 else { return nil }

        // Los eventos: un grupo con el mismo nombre. Si hay varios grupos, el que se nombra.
        let events = draft.newEvents.filter { $0.isIncluded && $0.replaces == nil }
        var groups: [[PlanDraft.Item]] = []
        for event in events {
            if let index = groups.firstIndex(where: { ProposalEditor.sameTitle($0[0].title, event.title) }) {
                groups[index].append(event)
            } else {
                groups.append([event])
            }
        }
        var candidates = groups.filter { $0.count >= 2 }
        if candidates.isEmpty, groups.count == 1 { candidates = groups }
        if candidates.count > 1 {
            let query = ProposalText.keywords(request)
            let named = candidates.filter { ProposalText.score(query: query, title: $0[0].title) > 0 }
            let sameCount = candidates.filter { $0.count == days.count }
            candidates = named.count == 1 ? named : (sameCount.count == 1 ? sameCount : candidates)
        }
        guard candidates.count == 1 else { return nil }
        let group = candidates[0].sorted { $0.start < $1.start }

        // Ya está bien repartido: no hay nada que corregir.
        let current = group.map { calendar.startOfDay(for: $0.start) }
        guard current != days else { return nil }

        // Lo que se dijo antes sobre el horario sigue valiendo.
        let sources = [request] + earlier
        let allDay = sources.contains(where: RequestCheck.saysAllDay)
        let repeats = sources.contains(where: RequestCheck.saysRepeat) && !perDay
        let template = group.first { !$0.isUnconfirmed(.time) } ?? group[0]

        var edits: [ProposalEdit] = []
        for (index, day) in days.enumerated() {
            if index < group.count {
                let event = group[index]
                var changes = ProposalChanges()
                if calendar.startOfDay(for: event.start) != day || event.isUnconfirmed(.day) { changes.day = day }
                if allDay, event.isUnconfirmed(.time) || event.isUnconfirmed(.duration) {
                    changes.startMinute = 0
                    changes.endMinute = 23 * 60 + 59
                }
                if !repeats, event.recurrence != .none { changes.recurrence = Recurrence.none }
                if !changes.isEmpty {
                    edits.append(.update(ProposalTarget(text: draft.ref(event.id), kind: .event), changes))
                }
            } else {
                var copy = template
                copy.id = UUID()
                let times = EventSchedule.moving(EventTimes(start: copy.start, end: copy.end), toDay: day, calendar: calendar)
                copy.start = times.start
                copy.end = times.end
                copy.confirm(.day)
                if allDay, copy.isUnconfirmed(.time) || copy.isUnconfirmed(.duration) {
                    copy.start = EventSchedule.at(0, on: day, calendar: calendar)
                    copy.end = EventSchedule.at(23 * 60 + 59, on: day, calendar: calendar)
                    copy.confirm(.time)
                    copy.confirm(.duration)
                }
                if !repeats { copy.recurrence = .none }
                edits.append(.addEvent(copy))
            }
        }
        // Si sobraban eventos iguales, se quitan de la propuesta.
        for extra in group.dropFirst(days.count) {
            edits.append(.remove(ProposalTarget(text: draft.ref(extra.id), kind: .event)))
        }
        guard !edits.isEmpty else { return nil }
        return Plan(edits: edits, title: group[0].title, days: days)
    }
}
