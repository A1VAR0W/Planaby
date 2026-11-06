import Foundation
import SwiftData
import Testing

// Pruebas del asistente de planificación sin el modelo: lo que devolvería la IA se simula con
// títulos, fechas y operaciones, y se comprueba lo que hace Planaby con ello.

private let calendar = Calendar.current
/// Viernes 6 de noviembre de 2026, 10:00.
private let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 10))!
/// Lunes 9 de noviembre de 2026, 8:00 (para colocar bloques).
private let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 8))!

private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))!
}

private func at(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(byAdding: DateComponents(day: offset, hour: hour - 8, minute: minute), to: monday)!
}

private let request = "Añade dos eventos, uno Subida PRE para el 25 de noviembre y otro Subida PRO para el 26 de noviembre"

private enum TestError: Error { case notApplied }

private func applied(_ result: ProposalEditResult) throws -> ProposalEditOutcome {
    guard case .applied(let outcome) = result else { throw TestError.notApplied }
    return outcome
}

/// Dos eventos nuevos con hora y duración provisionales, como los deja Planaby cuando la
/// petición no las dice.
private func provisionalPair() -> PlanDraft {
    var pre = PlanDraft.Item(title: "Subida PRE", start: day(2026, 11, 25).addingTimeInterval(9 * 3600),
                             end: day(2026, 11, 25).addingTimeInterval(10 * 3600), mode: .work, kind: .event)
    pre.unconfirmed = [.time, .duration]
    var pro = PlanDraft.Item(title: "Subida PRO", start: day(2026, 11, 26).addingTimeInterval(9 * 3600),
                             end: day(2026, 11, 26).addingTimeInterval(10 * 3600), mode: .work, kind: .event)
    pro.unconfirmed = [.time, .duration]
    return PlanDraft(items: [pre, pro], tasks: [], summary: "", warnings: [])
}

private func savedID(_ key: String) throws -> PersistentIdentifier {
    try PersistentIdentifier.identifier(for: "PlanabyTests", entityName: "CalendarEvent", primaryKey: key)
}

@Suite("Peticiones: que no falte ni sobre nada")
struct RequestCheckTests {
    @Test func countsAnnouncedItems() {
        #expect(RequestCheck.expectedNewItems(in: request) == 2)
        #expect(RequestCheck.expectedNewItems(in: "Añade dos eventos y una tarea para el lunes") == 3)
        #expect(RequestCheck.expectedNewItems(in: "Una reunión el lunes y otra el martes") == 2)
        #expect(RequestCheck.expectedNewItems(in: "Crea 3 tareas: informe, presupuesto y correo") == 3)
    }

    @Test func doesNotCountExistingThingsOrSingleItems() {
        #expect(RequestCheck.expectedNewItems(in: "Mueve las dos tareas al viernes") == nil)
        #expect(RequestCheck.expectedNewItems(in: "Reunión con Marta mañana a las 10") == nil)
        #expect(RequestCheck.expectedNewItems(in: "Está bien, pero cambia la Subida PRE al día 24 y deja la Subida PRO el 26") == nil)
    }

    /// El fallo real: la IA devolvió «Subida PRO» y una «Comida» que nadie pidió.
    @Test func dropsInventedRoutinesAndAgendaCopies() {
        let keep = RequestGrounding.keep(
            titles: ["Subida PRO", "Comida"], sources: [request], agenda: [], expected: 2
        )
        #expect(keep == [true, false])
        let echo = RequestGrounding.keep(
            titles: ["Subida PRE", "Reunión de equipo"], sources: [request], agenda: ["Reunión de equipo"], expected: nil
        )
        #expect(echo == [true, false])
    }

    @Test func keepsWhatTheUserAskedForEvenIfItIsARoutine() {
        let keep = RequestGrounding.keep(
            titles: ["Comida con Ana"], sources: ["Comida con Ana el jueves a las 14"], agenda: [], expected: nil
        )
        #expect(keep == [true])
        // Sinónimos: «almorzar» justifica «Comida».
        #expect(RequestGrounding.isMentioned("Comida", in: ["El jueves almuerzo con Ana"]))
    }

    @Test func extraUnmentionedItemsGoWhenTheCountIsKnown() {
        let keep = RequestGrounding.keep(
            titles: ["Subida PRE", "Subida PRO", "Revisión final"], sources: [request], agenda: [], expected: 2
        )
        #expect(keep == [true, true, false])
    }

    @Test func titlesKeepTheUsersSpelling() {
        #expect(RequestGrounding.exactTitle("subida pre", in: request) == "Subida PRE")
        #expect(RequestGrounding.exactTitle("Evento Subida PRO", in: request) == "Subida PRO")
        #expect(RequestGrounding.exactTitle("«Subida PRO».", in: request) == "Subida PRO")
        #expect(RequestGrounding.exactTitle("Despliegue", in: request) == "Despliegue")
    }
}

@Suite("Peticiones: fechas escritas")
struct RequestDatesTests {
    @Test func eachTitleGetsItsOwnWrittenDay() {
        let days = RequestDates.days(for: ["Subida PRE", "Subida PRO"], in: request, now: now)
        #expect(days == [day(2026, 11, 25), day(2026, 11, 26)])
    }

    @Test func dayWithoutYearIsTheNextOne() {
        let december = calendar.date(from: DateComponents(year: 2026, month: 12, day: 2, hour: 9))!
        let days = RequestDates.days(for: ["Subida PRE"], in: request, now: december)
        #expect(days == [day(2027, 11, 25)])
    }

    @Test func relativeDaysAndWeekdays() {
        let mentions = RequestDates.mentions(in: "mañana y pasado mañana, y el jueves", now: now).map(\.day)
        #expect(mentions == [day(2026, 11, 7), day(2026, 11, 8), day(2026, 11, 12)])
        // «por la mañana» no es un día.
        #expect(RequestDates.mentions(in: "por la mañana", now: now).isEmpty)
    }

    @Test func bareDayUsesTheReferenceMonth() {
        let mentions = RequestDates.mentions(in: "cambia la Subida PRE al día 24", now: now, reference: day(2026, 11, 25))
        #expect(mentions.map(\.day) == [day(2026, 11, 24)])
    }

    @Test func saysWhen() {
        #expect(RequestDates.saysWhen(request, now: now))
        #expect(RequestDates.saysWhen("la semana que viene", now: now))
        #expect(!RequestDates.saysWhen("Añade una reunión con Marta", now: now))
    }
}

@Suite("Respuestas cortas")
struct AnswerParsingTests {
    @Test func durations() {
        #expect(AnswerParsing.duration("1 h") == 60)
        #expect(AnswerParsing.duration("30 min") == 30)
        #expect(AnswerParsing.duration("2 h") == 120)
        #expect(AnswerParsing.duration("media hora") == 30)
        #expect(AnswerParsing.duration("hora y media") == 90)
        #expect(AnswerParsing.duration("1h30") == 90)
        #expect(AnswerParsing.duration("90 minutos") == 90)
        #expect(AnswerParsing.duration("una hora") == 60)
        #expect(AnswerParsing.duration("2") == 120)
        #expect(AnswerParsing.duration("45") == 45)
        #expect(AnswerParsing.duration("a las 10") == nil)
    }

    @Test func times() {
        #expect(AnswerParsing.time("a las 10") == 10 * 60)
        #expect(AnswerParsing.time("10:30") == 10 * 60 + 30)
        #expect(AnswerParsing.time("5 de la tarde") == 17 * 60)
        #expect(AnswerParsing.time("a las 5") == 17 * 60)
        #expect(AnswerParsing.time("9 de la mañana") == 9 * 60)
        #expect(AnswerParsing.time("a mediodía") == 12 * 60)
        #expect(AnswerParsing.time("1 h") == nil)
    }

    @Test func choiceLabels() {
        #expect(AnswerParsing.wantsEachSeparately("Duración diferente para cada evento"))
        #expect(AnswerParsing.keepsAsIs("Dejar a las 9:00"))
        #expect(!AnswerParsing.keepsAsIs("1 h"))
    }
}

@Suite("Preguntar solo lo que falta")
struct DetailQuestionTests {
    @Test func asksTheDurationOfBothWithQuickOptions() throws {
        let draft = provisionalPair()
        let question = try #require(DetailQuestion.next(in: draft))
        #expect(question.field == .duration)
        #expect(question.itemIDs == draft.items.map(\.id))
        #expect(question.question.contains("Subida PRE") && question.question.contains("Subida PRO"))
        #expect(question.choices == ["30 min", "1 h", "2 h", "Duración diferente para cada evento"])
    }

    @Test func answeringUpdatesBothAndThenAsksTheTime() throws {
        let draft = provisionalPair()
        let question = try #require(DetailQuestion.next(in: draft))
        guard case .edits(let edits) = question.answer("2 h", in: draft, now: now) else {
            Issue.record("«2 h» debería entenderse sin la IA")
            return
        }
        let outcome = try applied(ProposalEditor.apply(edits, to: draft, mergeSimilar: false))
        #expect(outcome.draft.newEvents.map(\.durationMinutes) == [120, 120])
        #expect(outcome.draft.newEvents.map(\.title) == ["Subida PRE", "Subida PRO"])
        #expect(outcome.draft.newEvents.allSatisfy { !$0.isUnconfirmed(.duration) && $0.isUnconfirmed(.time) })
        #expect(DetailQuestion.next(in: outcome.draft)?.field == .time)
    }

    @Test func differentForEachAndKeepingTheProvisionalTime() throws {
        let draft = provisionalPair()
        let duration = try #require(DetailQuestion.next(in: draft))
        #expect(duration.answer("Duración diferente para cada evento", in: draft, now: now) == .eachSeparately)

        var confirmed = draft
        for index in confirmed.items.indices { confirmed.items[index].confirm(.duration) }
        let time = try #require(DetailQuestion.next(in: confirmed))
        #expect(time.field == .time)
        let keepLabel = "Dejar a las \(ProposalFormat.time.string(from: confirmed.items[0].start))"
        #expect(time.choices.last == keepLabel)
        #expect(time.answer(keepLabel, in: confirmed, now: now) == .keep)
        time.keep(in: &confirmed)
        #expect(DetailQuestion.next(in: confirmed) == nil)
        #expect(!confirmed.hasUnconfirmed)
    }

    @Test func unclearAnswerGoesToTheAI() throws {
        let draft = provisionalPair()
        let question = try #require(DetailQuestion.next(in: draft))
        #expect(question.answer("lo de siempre", in: draft, now: now) == .unknown)
    }

    @Test func narrationListsEveryItem() {
        let text = ProposalNarration.created(events: provisionalPair().items, tasks: []) ?? ""
        #expect(text.hasPrefix("He preparado dos eventos:"))
        #expect(text.contains("• Subida PRE") && text.contains("• Subida PRO"))
        #expect(text.contains("por confirmar"))
    }
}

@Suite("Lo guardado: encontrar el elemento correcto")
struct SavedResolverTests {
    private var refs: [SavedRef] {
        [
            SavedRef(code: "C1", title: "Subida PRE", date: day(2026, 11, 25).addingTimeInterval(9 * 3600), kind: .event),
            SavedRef(code: "C2", title: "Subida PRO", date: day(2026, 11, 26).addingTimeInterval(9 * 3600), kind: .event),
            SavedRef(code: "P1", title: "Revisar documentación", date: day(2026, 11, 12).addingTimeInterval(20 * 3600), kind: .task),
            SavedRef(code: "P2", title: "Revisar documentación", date: day(2026, 11, 13).addingTimeInterval(20 * 3600), kind: .task),
            SavedRef(code: "C3", title: "Subida PRE", date: day(2026, 11, 25).addingTimeInterval(9 * 3600), kind: .event),
            SavedRef(code: "", title: "Comité (Outlook)", date: day(2026, 11, 10).addingTimeInterval(11 * 3600), kind: .external),
        ]
    }

    @Test func weekdayPicksTheRightTask() {
        let result = SavedResolver.resolve("la tarea de revisar documentación del jueves", kind: .task, in: refs, now: now)
        #expect(result == .found(2))
    }

    @Test func nameAndCode() {
        #expect(SavedResolver.resolve("Subida PRO", kind: .event, in: refs, now: now) == .found(1))
        #expect(SavedResolver.resolve("C2", kind: .any, in: refs, now: now) == .found(1))
    }

    @Test func sameNameWithoutDetailsIsAskedNotGuessed() {
        #expect(SavedResolver.resolve("revisar documentación", kind: .task, in: refs, now: now) == .ambiguous([2, 3]))
        // Un día que no coincide con ninguna: se pregunta.
        if case .found = SavedResolver.resolve("revisar documentación del lunes", kind: .task, in: refs, now: now) {
            Issue.record("No debe elegir una tarea de otro día")
        }
    }

    @Test func duplicateIsTheLastOne() {
        #expect(SavedResolver.resolve("el duplicado de Subida PRE", kind: .event, in: refs, now: now) == .found(4))
    }

    @Test func unknownNamesAreNotFound() {
        #expect(SavedResolver.resolve("la reunión con Marta", kind: .any, in: refs, now: now) == .notFound)
    }

    @Test func externalEventsAreVisibleButMarked() {
        #expect(SavedResolver.resolve("el comité", kind: .event, in: refs, now: now) == .found(5))
        #expect(refs[5].kind == .external)
    }

    @Test func wholeSeriesOnlyWhenSaid() {
        #expect(SavedResolver.wantsWholeSeries("borra todas las clases de inglés"))
        #expect(!SavedResolver.wantsWholeSeries("borra la clase de inglés del martes"))
    }
}

@Suite("Editar y borrar lo guardado")
struct SavedEditTests {
    @Test func deletingASavedEventIsShownAndNotDoneYet() throws {
        let id = try savedID("1")
        var draft = PlanDraft(items: [], tasks: [], summary: "", warnings: [])
        draft.items.append(PlanDraft.Item(title: "Revisar documentación", start: at(3, 10), end: at(3, 11),
                                          mode: .work, kind: .event, replaces: id))
        draft.assignRefs()
        let outcome = try applied(ProposalEditor.apply([.delete(ProposalTarget(text: "E1"))], to: draft))
        #expect(outcome.draft.items.isEmpty)
        #expect(outcome.draft.deletions.map(\.id) == [id])
        #expect(outcome.draft.replacedSavedIDs.contains(id))
        let changes = ProposalDiff.changes(from: draft, to: outcome.draft)
        #expect(changes.map(\.kind) == [.deleted])
        #expect(changes.first?.text == "Se borrará: Revisar documentación")
    }

    @Test func removingFromTheProposalDoesNotDelete() throws {
        let id = try savedID("2")
        var draft = PlanDraft(items: [], tasks: [], summary: "", warnings: [])
        draft.items.append(PlanDraft.Item(title: "Subida PRE", start: at(1, 10), end: at(1, 11), mode: .work, kind: .event, replaces: id))
        draft.assignRefs()
        let outcome = try applied(ProposalEditor.apply([.remove(ProposalTarget(text: "E1"))], to: draft))
        #expect(outcome.draft.deletions.isEmpty)
    }

    /// «Está bien, pero cambia la Subida PRE al día 24 y deja la Subida PRO el 26»: un cambio
    /// parcial; la otra no se toca y nada se duplica.
    @Test func partialChangeKeepsTheRest() throws {
        let draft = provisionalPair()
        var changes = ProposalChanges()
        changes.day = day(2026, 11, 24)
        let outcome = try applied(ProposalEditor.apply([.update(ProposalTarget(text: "Subida PRE", kind: .event), changes)], to: draft))
        #expect(outcome.draft.newEvents.count == 2)
        #expect(calendar.isDate(outcome.draft.newEvents[0].start, inSameDayAs: day(2026, 11, 24)))
        #expect(outcome.draft.newEvents[1] == draft.items[1])
        let diff = ProposalDiff.changes(from: draft, to: outcome.draft)
        #expect(diff.count == 1 && diff[0].kind == .modified && diff[0].title == "Subida PRE")
    }

    @Test func editingASavedEventIsAChangeNotANewEvent() throws {
        let id = try savedID("3")
        var draft = PlanDraft(items: [], tasks: [], summary: "", warnings: [])
        draft.items.append(PlanDraft.Item(title: "Subida PRO", start: at(2, 10), end: at(2, 11), mode: .work, kind: .event, replaces: id))
        draft.assignRefs()
        var changes = ProposalChanges()
        changes.startMinute = 16 * 60
        let outcome = try applied(ProposalEditor.apply([.update(ProposalTarget(text: "E1"), changes)], to: draft))
        #expect(outcome.draft.editedEvents.count == 1)
        #expect(outcome.draft.createdEvents.isEmpty)
        #expect(outcome.draft.newEvents[0].replaces == id)
        #expect(ProposalDiff.changes(from: draft, to: outcome.draft).map(\.kind) == [.modified])
    }

    @Test func workDayPutsEveryBlockOnThatDay() throws {
        let report = PlanDraft.Workload(id: UUID(), title: "Revisar documentación", mode: .work, deadline: at(4, 23, 59),
                                        estimatedMinutes: 180, priority: 0, statedMinutes: 180)
        let draft = PlanDraft(items: [], tasks: [report], summary: "", warnings: [])
        var changes = ProposalChanges()
        changes.workDay = at(2, 0)
        let outcome = try applied(ProposalEditor.apply([.update(ProposalTarget(text: "T1"), changes)], to: draft))
        #expect(outcome.affectedTasks == [report.id])
        let placement = ProposalPlacement(busy: [], planner: WorkloadPlanner(), availability: { _ in .work }, now: monday)
        let result = placement.replan(outcome.draft, affected: outcome.affectedTasks)
        #expect(!result.draft.blocks.isEmpty)
        #expect(result.draft.blocks.allSatisfy { calendar.isDate($0.start, inSameDayAs: at(2, 0)) })
        #expect(result.shortfalls.isEmpty)
    }

    @Test func workDayAfterTheDeadlineMovesTheDeadlineAndSaysSo() throws {
        let report = PlanDraft.Workload(id: UUID(), title: "Informe", mode: .work, deadline: at(1, 23, 59),
                                        estimatedMinutes: 60, priority: 0, statedMinutes: 60)
        let draft = PlanDraft(items: [], tasks: [report], summary: "", warnings: [])
        var changes = ProposalChanges()
        changes.workDay = at(4, 0)
        let outcome = try applied(ProposalEditor.apply([.update(ProposalTarget(text: "T1"), changes)], to: draft))
        #expect(calendar.isDate(outcome.draft.tasks[0].deadline, inSameDayAs: at(4, 0)))
        #expect(!outcome.problems.isEmpty)
    }

    @Test func freeAfternoonIsRespected() throws {
        let report = PlanDraft.Workload(id: UUID(), title: "Informe", mode: .work, deadline: at(0, 23, 59),
                                        estimatedMinutes: 300, priority: 1, statedMinutes: 300)
        var draft = PlanDraft(items: [], tasks: [report], summary: "", warnings: [])
        draft.constraints.freeIntervals = [DateInterval(start: at(0, 15), end: at(0, 17))]
        let placement = ProposalPlacement(busy: [], planner: WorkloadPlanner(), availability: { _ in .work }, now: monday)
        let result = placement.replan(draft, affected: [report.id])
        let free = draft.constraints.freeIntervals[0]
        #expect(result.draft.blocks.allSatisfy { $0.end <= free.start || $0.start >= free.end })
    }
}

@Suite("Propuestas guardadas en el iPhone")
struct ProposalStorageTests {
    @Test func oldProposalWithoutNewFieldsStillOpens() throws {
        let draft = provisionalPair()
        let data = try JSONEncoder().encode(draft)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "deletions")
        var items = try #require(object["items"] as? [[String: Any]])
        for index in items.indices {
            items[index].removeValue(forKey: "unconfirmed")
            items[index].removeValue(forKey: "replaces")
        }
        object["items"] = items
        let old = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(PlanDraft.self, from: old)
        #expect(decoded.deletions.isEmpty)
        #expect(decoded.items.map(\.title) == draft.items.map(\.title))
        #expect(decoded.ref(decoded.items[0].id) == draft.ref(draft.items[0].id))
        #expect(decoded.items.allSatisfy { $0.unconfirmed == nil })
    }

    @Test func deletionsAndPendingQuestionsSurviveARestart() throws {
        let id = try savedID("4")
        var draft = provisionalPair()
        draft.deletions = [SavedDeletion(id: id, title: "Revisar documentación", detail: "jue 12 20:00", isTask: true)]
        var active = ActiveProposal(history: ProposalHistory(draft), messageID: UUID())
        active.detail = DetailQuestion.next(in: draft)
        let decoded = try JSONDecoder().decode(ActiveProposal.self, from: JSONEncoder().encode(active))
        #expect(decoded.history.current.deletions == draft.deletions)
        #expect(decoded.detail == active.detail)
        #expect(decoded.history.current.items == draft.items)
    }
}

@Suite("Movimiento, volumen y paneles")
struct MotionAndVolumeTests {
    @Test func exitsAreFasterAndStaggerIsCapped() {
        #expect(MotionTiming.exit(for: MotionTiming.emphasized) < MotionTiming.emphasized)
        #expect(MotionTiming.staggerDelay(0) == 0)
        #expect(MotionTiming.staggerDelay(100) == MotionTiming.staggerDelay(MotionTiming.staggerLimit))
        #expect(MotionTiming.duration(MotionTiming.panel, reduceMotion: true) <= MotionTiming.reduced)
        #expect(MotionTiming.press < MotionTiming.quick && MotionTiming.quick < MotionTiming.panel)
    }

    @Test func volumeLevels() {
        #expect(VolumeLevel.symbol(for: 0) == "speaker.slash.fill")
        #expect(VolumeLevel.symbol(for: 0.2) == "speaker.wave.1.fill")
        #expect(VolumeLevel.symbol(for: 0.5) == "speaker.wave.2.fill")
        #expect(VolumeLevel.symbol(for: 1) == "speaker.wave.3.fill")
        #expect(VolumeLevel.text(for: 0.456) == "46 %")
        #expect(VolumeLevel.text(for: 0) == "Sin sonido")
        #expect(VolumeLevel.isMuted(.nan))
        #expect(VolumeLevel.clamped(1.4) == 1)
    }

    @Test func panelWidthsShareTheSpaceWithoutOverflow() {
        let total = 780.0, spacing = 16.0
        #expect(DeskPanels.widths(total: total, spacing: spacing, music: true, tasks: false) == (total, 0))
        let both = DeskPanels.widths(total: total, spacing: spacing, music: true, tasks: true)
        #expect(both.main == both.tasks && both.main + both.tasks + spacing == total)
        let clock = DeskPanels.widths(total: total, spacing: spacing, music: false, tasks: true)
        #expect(clock.tasks == DeskPanels.taskColumn && clock.main > clock.tasks)
        #expect(clock.main + clock.tasks + spacing == total)
        // En pantallas estrechas la lista nunca pasa de la mitad.
        let narrow = DeskPanels.widths(total: 500, spacing: spacing, music: false, tasks: true)
        #expect(narrow.tasks <= narrow.main)
    }
}
