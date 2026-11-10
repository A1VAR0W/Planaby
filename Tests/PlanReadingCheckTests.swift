import Foundation
import Testing

// Lo que la IA devolvió de verdad en el iPhone con «Actuación Natalia» (dos eventos y dos tareas
// para una sola cosa, horas que nadie dijo, un título y un código copiados de los ejemplos) y lo
// que Planaby tiene que hacer con ello.

private let calendar = Calendar.current
private let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 10))!
private let natalia = "Actuación Natalia"
private let firstRequest = "Planifica en normal para el día 28 de noviembre “Actuación Natalia” ponle que empieza a las 18 pero tenemos que estar antes, acabará como a las 20 o así aproximadamente"
private let correction = "Mmmm solo quiero un único evento, de 17:45 a 20:00 el día 28 de noviembre nada más"

private func at(_ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: 28, hour: hour, minute: minute))!
}

private func clean(
    _ reading: PlanReading, _ request: String, sources: [String]? = nil, known: PlanReadingCheck.Known = .init()
) -> PlanReading {
    PlanReadingCheck.clean(reading, request: request, sources: sources ?? [request], known: known, now: now, calendar: calendar)
}

private func known(_ draft: PlanDraft) -> PlanReadingCheck.Known {
    PlanReadingCheck.Known(
        events: draft.newEvents.map { .init(code: draft.ref($0.id), title: $0.title) },
        tasks: draft.tasks.map { .init(code: draft.ref($0.id), title: $0.title) }
    )
}

/// La propuesta que quedó tras la primera respuesta: dos eventos y dos tareas con el mismo nombre.
private func messyDraft() -> PlanDraft {
    PlanDraft(items: [
        PlanDraft.Item(title: natalia, start: at(16), end: at(22), mode: .work, kind: .event),
        PlanDraft.Item(title: natalia, start: at(16), end: at(20), mode: .work, kind: .event),
    ], tasks: [
        PlanDraft.Workload(id: UUID(), title: natalia, mode: .work, deadline: at(23, 59), estimatedMinutes: 600, priority: 1),
        PlanDraft.Workload(id: UUID(), title: natalia, mode: .work, deadline: at(23, 59), estimatedMinutes: 450, priority: 1),
    ], summary: "", warnings: [])
}

private func summary(_ edits: [ProposalEditFields]) -> [String] {
    edits.map { "\($0.action) \($0.target)" }
}

@Suite("Repaso de lo que devuelve la IA")
struct PlanReadingCheckTests {
    // MARK: Las capturas

    @Test func oneThingAskedIsOneEvent() {
        var reading = PlanReading()
        reading.requestedCount = 4
        reading.events = [
            ReadEvent(title: natalia, day: "2026-11-28", time: "16:00", endTime: "22:00", mode: "work"),
            ReadEvent(title: natalia, day: "2026-11-28", time: "16:00", endTime: "20:00", mode: "work"),
        ]
        reading.tasks = [
            ReadTask(title: natalia, deadline: "2026-11-28 23:59", estimatedMinutes: 600),
            ReadTask(title: natalia, deadline: "2026-11-28 23:59", estimatedMinutes: 450),
        ]
        let result = clean(reading, firstRequest)
        #expect(result.events.map(\.title) == [natalia])
        #expect(result.tasks.isEmpty)
        // La cuenta de la IA incluía sus repetidos: ya no sirve para echar nada en falta.
        #expect(result.requestedCount <= 1)
    }

    @Test func writtenHoursDayAndPlanWin() {
        // La IA puso 16:00–22:00 («hay que estar antes») y el plan de Trabajo.
        let times = EventGrounding.times(start: 16 * 60, end: 22 * 60, request: firstRequest)
        #expect(times.start == 18 * 60 && times.end == 20 * 60)
        #expect(EventGrounding.onlyDay(in: firstRequest, now: now, calendar: calendar) == calendar.startOfDay(for: at(0)))
        #expect(RequestCheck.statedMode(in: firstRequest) == .personal)
    }

    @Test func correctingKeepsOneAndRemovesTheRest() throws {
        let draft = messyDraft()
        var reading = PlanReading()
        reading.edits = [
            ProposalEditFields(action: "update", target: "E1", time: "17:45", minutes: 135),
            ProposalEditFields(action: "first", target: natalia),
        ]
        reading.events = [ReadEvent(title: natalia, day: "2026-11-28", time: "17:45"), ReadEvent(title: natalia, day: "2026-11-28")]
        reading.tasks = [ReadTask(title: "Entregar informe", deadline: "2026-11-13 23:59")]

        let result = clean(reading, correction, sources: [correction, firstRequest], known: known(draft))
        #expect(result.events.isEmpty && result.tasks.isEmpty)
        #expect(summary(result.edits) == ["update E1", "remove E2", "remove T1", "remove T2"])

        // Aplicado a la propuesta: un solo evento, de 17:45 a 20:00, y nada más.
        let edits = TimeGrounding.check(result.edits.compactMap { $0.makeEdit(calendar: calendar) }, request: correction)
        guard case .applied(let outcome) = ProposalEditor.apply(edits, to: draft, calendar: calendar) else {
            Issue.record("Debe aplicarse sin preguntar")
            return
        }
        let event = try #require(outcome.draft.newEvents.first)
        #expect(outcome.draft.newEvents.count == 1 && outcome.draft.tasks.isEmpty)
        #expect(ProposalEditor.minuteOfDay(event.start, calendar: calendar) == 17 * 60 + 45)
        #expect(ProposalEditor.minuteOfDay(event.end, calendar: calendar) == 20 * 60)
        #expect(calendar.isDate(event.start, inSameDayAs: at(0)))
    }

    @Test func correctingWorksWhenTheModelCreatesInsteadOfEditing() {
        // La otra forma de equivocarse: no cambia nada y vuelve a crear el evento.
        var reading = PlanReading()
        reading.events = [ReadEvent(title: natalia, day: "2026-11-28", time: "17:45", endTime: "20:00")]
        let result = clean(reading, correction, sources: [correction, firstRequest], known: known(messyDraft()))
        #expect(result.events.isEmpty)
        #expect(summary(result.edits) == ["update E1", "remove E2", "remove T1", "remove T2"])
        #expect(result.edits[0].day == "2026-11-28" && result.edits[0].time == "17:45" && result.edits[0].endTime == "20:00")
    }

    @Test func codesThatDoNotExistAreDropped() {
        var reading = PlanReading()
        reading.edits = [
            ProposalEditFields(action: "update", target: "P1", time: "09:00", workDay: "2026-11-13"),
            ProposalEditFields(action: "update", target: "la reunión", time: "10:00"),
            ProposalEditFields(action: "delete", target: "c2"),
        ]
        let result = clean(reading, "Mueve la reunión a las 10 y borra la comida", known: .init(savedCodes: ["C2"]))
        #expect(summary(result.edits) == ["update la reunión", "delete c2"])
        #expect(PlanReadingCheck.bareCode(" e12 ") == "E12" && PlanReadingCheck.bareCode("la E1") == nil)
    }

    // MARK: Lo que sale de los ejemplos

    @Test func titlesCopiedFromTheExamplesAreDropped() {
        var reading = PlanReading()
        reading.events = [ReadEvent(title: "Dentista", day: "2026-11-12", time: "17:00"), ReadEvent(title: "Subida PRE", day: "2026-11-25")]
        reading.tasks = [ReadTask(title: "Entregar el informe", deadline: "2026-11-13 23:59")]
        let result = clean(reading, "Cita con el dentista el jueves a las 5")
        #expect(result.events.map(\.title) == ["Dentista"] && result.tasks.isEmpty)
    }

    @Test func whatThePersonNamesStaysEvenIfAnExampleHasIt() {
        var reading = PlanReading()
        reading.tasks = [ReadTask(title: "Entregar el informe", deadline: "2026-11-13 23:59", estimatedMinutes: 360)]
        #expect(clean(reading, "Tengo que entregar el informe el viernes, unas 6 horas").tasks.count == 1)
        // Un nombre que la IA cambia por otro («gym» → «Gimnasio») no se toma por inventado.
        var gym = PlanReading()
        gym.events = [ReadEvent(title: "Gimnasio", day: "2026-11-11", time: "07:00")]
        #expect(clean(gym, "Mañana gym a las 7 de la mañana").events.count == 1)
        #expect(!PlanReadingCheck.isExample("Reunión", examples: LocalPlanningPrompt.exampleTitles))
        #expect(PlanReadingCheck.isExample("Entregar informe", examples: LocalPlanningPrompt.exampleTitles))
    }

    // MARK: Lo que sí son varias cosas

    @Test func severalThingsStaySeveral() {
        // Los dos eventos del caso PRE/PRO.
        let prePro = PlanReading.parse(json: LocalPlanningPrompt.examples[0].json)!
        #expect(clean(prePro, LocalPlanningPrompt.examples[0].request).events.count == 2)

        var twoDays = PlanReading()
        twoDays.events = [ReadEvent(title: "Reunión", day: "2026-11-16", time: "10:00"), ReadEvent(title: "Reunión", day: "2026-11-17", time: "10:00")]
        #expect(clean(twoDays, "Añade una reunión el lunes y otra el martes, a las 10").events.count == 2)

        var yoga = PlanReading()
        yoga.events = [ReadEvent(title: "Clase de yoga", day: "2026-11-16"), ReadEvent(title: "Clase de yoga", day: "2026-11-18")]
        #expect(clean(yoga, "Clase de yoga el lunes y el miércoles").events.count == 2)

        var sameDay = PlanReading()
        sameDay.events = [ReadEvent(title: "Reunión", day: "2026-11-11", time: "10:00"), ReadEvent(title: "Reunión", day: "2026-11-11", time: "12:00")]
        #expect(clean(sameDay, "Dos reuniones mañana, una a las 10 y otra a las 12").events.count == 2)

        var examAndStudy = PlanReading()
        examAndStudy.events = [ReadEvent(title: "Examen de mates", day: "2026-11-13", time: "09:00")]
        examAndStudy.tasks = [ReadTask(title: "Estudiar para el examen de mates", deadline: "2026-11-12 23:59", estimatedMinutes: 480)]
        let both = clean(examAndStudy, "Examen de mates el viernes a las 9 y estudiar para el examen de mates, unas 8 horas")
        #expect(both.events.count == 1 && both.tasks.count == 1)
    }

    // MARK: Con una propuesta abierta

    @Test func whatIsAlreadyProposedIsChangedNotCreatedAgain() {
        let draft = PlanDraft(items: [
            PlanDraft.Item(title: "Reunión con Marta", start: at(10), end: at(11), mode: .work, kind: .event),
        ], tasks: [], summary: "", warnings: [])

        var moved = PlanReading()
        moved.events = [ReadEvent(title: "Reunión con Marta", day: "2026-11-13", time: "09:00")]
        let result = clean(moved, "Mueve la reunión con Marta al viernes", known: known(draft))
        #expect(result.events.isEmpty)
        #expect(summary(result.edits) == ["update E1"])
        // Solo lo que dice la petición: el día. La hora que añadió la IA no se toca.
        #expect(result.edits[0].day == "2026-11-13" && result.edits[0].time.isEmpty)

        // «Otra» sí es algo nuevo.
        var another = PlanReading()
        another.events = [ReadEvent(title: "Reunión con Marta", day: "2026-11-12", time: "10:00")]
        #expect(clean(another, "Añade otra reunión con Marta el jueves a las 10", known: known(draft)).events.count == 1)
    }

    @Test func firstNeedsSomeoneAskingForIt() {
        let draft = PlanDraft(items: [
            PlanDraft.Item(title: "Reunión", start: at(10), end: at(11), mode: .work, kind: .event),
        ], tasks: [
            PlanDraft.Workload(id: UUID(), title: "Informe", mode: .work, deadline: at(20), estimatedMinutes: 90, priority: 1),
        ], summary: "", warnings: [])
        var reading = PlanReading()
        reading.edits = [ProposalEditFields(action: "first", target: "T1"), ProposalEditFields(action: "first", target: "E1")]
        reading.prioritize = ["Informe"]
        // Poner primero solo vale para tareas.
        let asked = clean(reading, "Pon el informe primero", known: known(draft))
        #expect(summary(asked.edits) == ["first T1"] && asked.prioritize == ["Informe"])
        let notAsked = clean(reading, "Que la reunión dure media hora", known: known(draft))
        #expect(notAsked.edits.isEmpty && notAsked.prioritize.isEmpty)
    }

    // MARK: Lo que se entiende de la petición sin la IA

    @Test func startAndEndSaidInWords() {
        #expect(AnswerParsing.explicitStart(firstRequest) == 18 * 60)
        #expect(AnswerParsing.endTime(firstRequest) == 20 * 60)
        #expect(AnswerParsing.explicitStart("Reunión mañana a las 10") == nil)
        #expect(AnswerParsing.startTime("Reunión a las 10 hasta las 12") == 10 * 60)
        #expect(AnswerParsing.startTime("Acabará a las 20 y empieza a las 18") == 18 * 60)
        let times = AnswerParsing.times(in: "A las 6 y a las 18:30")
        #expect(times.isSuperset(of: [6 * 60, 18 * 60, 18 * 60 + 30]))
    }

    @Test func theModelHourStaysWhenSomeoneWroteIt() {
        // La hora de la IA es la escrita: se queda.
        let same = EventGrounding.times(start: 10 * 60, end: nil, request: "Reunión mañana a las 10")
        #expect(same.start == 10 * 60 && same.end == nil)
        // La IA da una hora que nadie escribió: vale la escrita.
        #expect(EventGrounding.times(start: 9 * 60, end: nil, request: "Reunión mañana a las 10").start == 10 * 60)
        // Sin hora en la petición no se inventa ninguna.
        #expect(EventGrounding.times(start: nil, end: nil, request: "Reunión mañana").start == nil)
        // Una franja manda siempre.
        let range = EventGrounding.times(start: 8 * 60, end: nil, request: "Reunión mañana de 9 a 11")
        #expect(range.start == 9 * 60 && range.end == 11 * 60)
    }

    @Test func planAndOnlyOne() {
        #expect(RequestCheck.statedMode(in: "Añádelo al plan de trabajo") == .work)
        #expect(RequestCheck.statedMode(in: "Una reunión normal y corriente") == nil)
        #expect(RequestCheck.statedMode(in: "Ponlo en normal, no en trabajo") == nil)

        #expect(RequestCheck.wantsOnlyOne(correction) && RequestCheck.wantsNothingElse(correction))
        #expect(RequestCheck.wantsOnlyOne("Solo una cita el lunes"))
        #expect(!RequestCheck.wantsOnlyOne("Solo quiero una reunión más"))
        #expect(!RequestCheck.wantsOnlyOne("Añade un evento el lunes"))
        #expect(!RequestCheck.wantsNothingElse("Añade una reunión el lunes"))
    }

    @Test func onlyOneWithoutProposalKeepsTheFirst() {
        var reading = PlanReading()
        reading.requestedCount = 3
        reading.events = [ReadEvent(title: "Cena", day: "2026-11-14", time: "21:00"), ReadEvent(title: "Compra", day: "2026-11-14")]
        reading.tasks = [ReadTask(title: "Reservar mesa", deadline: "2026-11-13 23:59")]
        let result = clean(reading, "Solo quiero un evento: cena, compra y reservar mesa el sábado a las 9 de la noche")
        #expect(result.events.map(\.title) == ["Cena"] && result.tasks.isEmpty && result.requestedCount <= 1)
    }
}
