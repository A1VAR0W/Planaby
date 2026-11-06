import Foundation
import Testing

// Horas de inicio y fin: lo que se elige en los formularios, lo que se pide a la IA y lo que
// se guarda. La duración siempre sale del inicio y el fin.

private let calendar = Calendar.current
/// Lunes 9 de noviembre de 2026, 8:00.
private let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 8))!

private func at(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(byAdding: DateComponents(day: offset, hour: hour - 8, minute: minute), to: monday)!
}

private func times(_ start: Date, _ end: Date) -> EventTimes { EventTimes(start: start, end: end) }

private enum TestError: Error { case notApplied }

private func applied(_ result: ProposalEditResult) throws -> ProposalEditOutcome {
    guard case .applied(let outcome) = result else { throw TestError.notApplied }
    return outcome
}

/// «Subida PRE» el miércoles de 9:00 a 11:30 y «Subida PRO» el jueves de 10:00 a 12:00.
private func uploads() -> PlanDraft {
    PlanDraft(items: [
        PlanDraft.Item(title: "Subida PRE", start: at(2, 9), end: at(2, 11, 30), mode: .work, kind: .event),
        PlanDraft.Item(title: "Subida PRO", start: at(3, 10), end: at(3, 12), mode: .work, kind: .event),
    ], tasks: [], summary: "", warnings: [])
}

private func update(_ target: String, _ change: (inout ProposalChanges) -> Void, in draft: PlanDraft = uploads()) throws -> ProposalEditOutcome {
    var changes = ProposalChanges()
    change(&changes)
    return try applied(ProposalEditor.apply([.update(ProposalTarget(text: target), changes)], to: draft))
}

@Suite("Inicio y fin: reglas")
struct EventScheduleTests {
    @Test func durationComesFromStartAndEnd() {
        #expect(times(at(2, 9), at(2, 11, 30)).minutes == 150)
        #expect(EventSchedule.summary(times(at(2, 9), at(2, 11, 30))) == "09:00–11:30 · 2 h 30 min")
    }

    @Test func endMustBeAfterStart() {
        #expect(EventSchedule.issue(times(at(2, 11), at(2, 9))) == .endNotAfterStart)
        #expect(EventSchedule.issue(times(at(2, 9), at(2, 9))) == .endNotAfterStart)
        #expect(EventSchedule.issue(times(at(2, 9), at(20, 9))) == .tooLong)
        #expect(EventSchedule.issue(times(at(2, 9), at(2, 10))) == nil)
    }

    @Test func movingADayKeepsClockTimesAndSpan() {
        let night = times(at(0, 22), at(1, 1))
        let moved = EventSchedule.moving(night, toDay: at(4, 0))
        #expect(moved.start == at(4, 22) && moved.end == at(5, 1))
        let several = times(at(0, 9), at(2, 18))
        let later = EventSchedule.moving(several, toDay: at(7, 0))
        #expect(later.start == at(7, 9) && later.end == at(9, 18))
    }

    @Test func changingOnlyTheStartKeepsTheEndWhenAsked() {
        let base = times(at(2, 9), at(2, 11, 30))
        let kept = EventSchedule.settingStart(8 * 60 + 30, of: base, keepEnd: true)
        #expect(kept.start == at(2, 8, 30) && kept.end == at(2, 11, 30))
        let moved = EventSchedule.settingStart(10 * 60, of: base, keepEnd: false)
        #expect(moved.start == at(2, 10) && moved.end == at(2, 12, 30))
        // Si el nuevo inicio pasa del fin, se conserva la duración.
        let past = EventSchedule.settingStart(12 * 60, of: base, keepEnd: true)
        #expect(past.end == at(2, 14, 30))
        let earlier = EventSchedule.shiftingStart(by: -30, of: base, keepEnd: true)
        #expect(earlier.start == at(2, 8, 30) && earlier.end == at(2, 11, 30))
    }

    @Test func changingOnlyTheEndKeepsTheStart() throws {
        let base = times(at(2, 9), at(2, 11, 30))
        let later = try #require(EventSchedule.settingEnd(14 * 60 + 30, of: base, nextDay: false))
        #expect(later.start == base.start && later.end == at(2, 14, 30))
        // «De 3 a 4»: la misma parte del día.
        let afternoon = try #require(EventSchedule.settingEnd(4 * 60, of: times(at(2, 15), at(2, 15, 30)), nextDay: false))
        #expect(afternoon.end == at(2, 16))
        // Antes del inicio y sin decir que es al día siguiente: no se acepta.
        #expect(EventSchedule.settingEnd(8 * 60, of: times(at(2, 21), at(2, 22)), nextDay: false) == nil)
    }

    @Test func crossingMidnightOnlyWhenSaid() throws {
        let base = times(at(2, 22), at(2, 23))
        let night = try #require(EventSchedule.settingEnd(60, of: base, nextDay: true))
        #expect(night.start == at(2, 22) && night.end == at(3, 1))
        #expect(EventSchedule.daySpan(night) == 1)
        #expect(EventSchedule.rangeText(night).contains("01:00"))
    }

    @Test func daylightSavingKeepsWallClockTimes() throws {
        var madrid = Calendar(identifier: .gregorian)
        madrid.timeZone = try #require(TimeZone(identifier: "Europe/Madrid"))
        // El 29 de marzo de 2026 a las 2:00 pasan a ser las 3:00.
        let before = madrid.date(from: DateComponents(year: 2026, month: 3, day: 28, hour: 1))!
        let event = EventTimes(start: before, end: before.addingTimeInterval(3 * 3600))
        let moved = EventSchedule.moving(event, toDay: madrid.date(from: DateComponents(year: 2026, month: 3, day: 29))!, calendar: madrid)
        #expect(madrid.component(.hour, from: moved.start) == 1)
        #expect(madrid.component(.hour, from: moved.end) == 4)
        // Ese día de 1:00 a 4:00 son dos horas reales.
        #expect(moved.minutes == 120)
        // Una hora que no existe (2:30) pasa a la siguiente que sí.
        let gap = EventSchedule.at(2 * 60 + 30, on: moved.start, calendar: madrid)
        #expect(madrid.component(.hour, from: gap) == 3)
    }

    @Test func conflictsIgnoreTouchingEdges() {
        let meeting = EventConflict(title: "Comité", interval: DateInterval(start: at(2, 11, 30), end: at(2, 12, 30)))
        let lunch = EventConflict(title: "Comida", interval: DateInterval(start: at(2, 10), end: at(2, 11)))
        let found = EventSchedule.conflicts(times(at(2, 9), at(2, 11, 30)), with: [meeting, lunch])
        #expect(found.map(\.title) == ["Comida"])
    }
}

@Suite("Inicio y fin: lo que se escribe")
struct TimeRangeParsingTests {
    @Test func ranges() {
        #expect(AnswerParsing.range("de 10:00 a 12:00")?.start == 10 * 60)
        #expect(AnswerParsing.range("de 10:00 a 12:00")?.end == 12 * 60)
        #expect(AnswerParsing.range("Añade una reunión mañana de 10 a 12").map { [$0.start, $0.end] } == [600, 720])
        #expect(AnswerParsing.range("9:00–11:30").map { [$0.start, $0.end] } == [540, 690])
        #expect(AnswerParsing.range("entre las 4 y las 6").map { [$0.start, $0.end] } == [16 * 60, 18 * 60])
        #expect(AnswerParsing.range("de 3 a 5 de la tarde").map { [$0.start, $0.end] } == [15 * 60, 17 * 60])
        #expect(AnswerParsing.range("de 10 a 2").map { [$0.start, $0.end] } == [600, 14 * 60])
        #expect(AnswerParsing.range("de 7 a 9 de la mañana").map { [$0.start, $0.end] } == [420, 540])
    }

    @Test func notRanges() {
        #expect(AnswerParsing.range("Añade dos eventos, Subida PRE el 25 de noviembre y Subida PRO el 26") == nil)
        #expect(AnswerParsing.range("tarda 3-4 horas") == nil)
        #expect(AnswerParsing.range("del 25 al 26 de noviembre") == nil)
        #expect(AnswerParsing.range("una reunión de 2 horas") == nil)
    }

    @Test func crossingMidnight() throws {
        let night = try #require(AnswerParsing.range("de 22:00 a 1:00 del día siguiente"))
        #expect(night.start == 22 * 60 && night.end == 60 && night.nextDay)
        let late = try #require(AnswerParsing.range("de 23 a 2 de la madrugada"))
        #expect(late.end == 2 * 60 && late.nextDay)
        // Sin decirlo, no cruza la medianoche.
        #expect(AnswerParsing.range("de 22:00 a 1:00")?.nextDay == false)
    }

    @Test func endTimesShiftsAndKeepingTheEnd() {
        #expect(AnswerParsing.endTime("Cambia la hora de fin de Subida PRE a las 14:30") == 14 * 60 + 30)
        #expect(AnswerParsing.endTime("Haz que Subida PRO termine a las 17:00") == 17 * 60)
        #expect(AnswerParsing.endTime("Mueve la reunión a las 10") == nil)
        #expect(AnswerParsing.startShift("Adelanta el comienzo media hora, pero conserva la hora de fin") == -30)
        #expect(AnswerParsing.startShift("Retrasa el inicio 15 minutos") == 15)
        #expect(AnswerParsing.startShift("Que empiece a las 10") == nil)
        #expect(AnswerParsing.keepsEnd("Adelanta el comienzo media hora, pero conserva la hora de fin"))
        #expect(!AnswerParsing.keepsEnd("deja la Subida PRO el 26"))
    }
}

@Suite("Inicio y fin: cambios pedidos")
struct EventTimeEditTests {
    @Test func onlyTheEnd() throws {
        let outcome = try update("Subida PRE") { $0.endMinute = 14 * 60 + 30 }
        let pre = outcome.draft.newEvents[0]
        #expect(pre.start == at(2, 9) && pre.end == at(2, 14, 30))
        // El otro evento no se toca.
        let pro = outcome.draft.newEvents[1]
        #expect(pro.title == "Subida PRO" && pro.start == at(3, 10) && pro.end == at(3, 12))
    }

    @Test func onlyTheStartMovesTheWholeEvent() throws {
        let outcome = try update("Subida PRO") { $0.startMinute = 11 * 60 }
        let pro = outcome.draft.newEvents[1]
        #expect(pro.start == at(3, 11) && pro.end == at(3, 13))
    }

    @Test func earlierStartKeepingTheEnd() throws {
        let outcome = try update("Subida PRE") {
            $0.startDeltaMinutes = -30
            $0.keepEnd = true
        }
        let pre = outcome.draft.newEvents[0]
        #expect(pre.start == at(2, 8, 30) && pre.end == at(2, 11, 30))
        #expect(outcome.problems.isEmpty)
    }

    @Test func newDayWithStartAndEnd() throws {
        let outcome = try update("Subida PRO") {
            $0.day = at(4, 0)
            $0.startMinute = 9 * 60
            $0.endMinute = 11 * 60
        }
        let pro = outcome.draft.newEvents[1]
        #expect(pro.start == at(4, 9) && pro.end == at(4, 11))
    }

    @Test func endBeforeStartIsRefusedAndExplained() throws {
        // Empieza a las 21:00 y «termina a las 8»: ni las 8:00 ni las 20:00 quedan después.
        let outcome = try update("Subida PRE") {
            $0.startMinute = 21 * 60
            $0.endMinute = 8 * 60
        }
        let pre = outcome.draft.newEvents[0]
        #expect(pre.start == at(2, 21) && pre.end == at(2, 23, 30))
        #expect(outcome.problems.first?.contains("día siguiente") == true)
    }

    @Test func nightEventEndsTheNextDay() throws {
        let outcome = try update("Subida PRE") {
            $0.startMinute = 22 * 60
            $0.endMinute = 60
            $0.endsNextDay = true
        }
        let pre = outcome.draft.newEvents[0]
        #expect(pre.start == at(2, 22) && pre.end == at(3, 1))
    }

    /// Lo que entendió la IA se corrige con lo escrito: «conserva la hora de fin» y el comienzo
    /// media hora antes, aunque el modelo lo pusiera como duración.
    @Test func groundingFixesWhatTheModelGotWrong() {
        var changes = ProposalChanges()
        changes.minutes = 30
        let fixed = TimeGrounding.check(
            [.update(ProposalTarget(text: "E1"), changes)],
            request: "Adelanta el comienzo media hora, pero conserva la hora de fin"
        )
        guard case .update(_, let result) = fixed.first else {
            Issue.record("Debe seguir siendo un cambio")
            return
        }
        #expect(result.startDeltaMinutes == -30 && result.keepEnd == true && result.minutes == nil)

        var end = ProposalChanges()
        end.startMinute = 17 * 60
        let ending = TimeGrounding.check([.update(ProposalTarget(text: "Subida PRO"), end)], request: "Haz que Subida PRO termine a las 17:00")
        guard case .update(_, let endResult) = ending.first else { return }
        #expect(endResult.endMinute == 17 * 60 && endResult.startMinute == nil)
    }

    @Test func groundingLeavesRenamesAlone() {
        var changes = ProposalChanges()
        changes.title = "Revisión"
        let edits: [ProposalEdit] = [.update(ProposalTarget(text: "E1"), changes)]
        #expect(TimeGrounding.check(edits, request: "Cambia el nombre de la reunión de 10 a 12 por Revisión") == edits)
    }

    @Test func aiEditFieldsCarryTheNewOptions() {
        let fields = ProposalEditFields(action: "update", target: "E1", startShift: -30, keepEnd: true, endsNextDay: true)
        guard case .update(_, let changes) = fields.makeEdit() else {
            Issue.record("Debe ser un cambio")
            return
        }
        #expect(changes.startDeltaMinutes == -30 && changes.keepEnd == true && changes.endsNextDay == true)
    }
}

@Suite("Inicio y fin: tareas")
struct TaskSlotTests {
    private func report(minutes: Int = 120) -> PlanDraft {
        PlanDraft(items: [], tasks: [
            PlanDraft.Workload(id: UUID(), title: "Revisar documentación", mode: .work, deadline: at(4, 23, 59),
                               estimatedMinutes: minutes, priority: 0, statedMinutes: minutes),
        ], summary: "", warnings: [])
    }

    private var placement: ProposalPlacement {
        ProposalPlacement(busy: [], planner: WorkloadPlanner(), availability: { _ in .work }, now: monday)
    }

    /// «Mueve esta tarea al viernes de 9:00 a 11:00».
    @Test func slotBecomesExactlyThatBlock() throws {
        let outcome = try update("T1", {
            $0.workDay = at(4, 0)
            $0.startMinute = 9 * 60
            $0.endMinute = 11 * 60
        }, in: report())
        let task = outcome.draft.tasks[0]
        #expect(task.workFrom == 9 * 60 && task.workTo == 11 * 60)
        #expect(task.deadline == at(4, 23, 59))
        let result = placement.replan(outcome.draft, affected: outcome.affectedTasks)
        #expect(result.draft.blocks.map { [$0.start, $0.end] } == [[at(4, 9), at(4, 11)]])
        #expect(result.shortfalls.isEmpty)
    }

    @Test func dayGivenAsDayIsTheWorkDayNotTheDeadline() throws {
        let outcome = try update("T1", {
            $0.day = at(4, 0)
            $0.startMinute = 9 * 60
            $0.endMinute = 11 * 60
        }, in: report())
        #expect(outcome.draft.tasks[0].deadline == at(4, 23, 59))
        #expect(outcome.draft.tasks[0].workSlot()?.start == at(4, 9))
    }

    @Test func shortSlotSaysWhatIsLeft() throws {
        let outcome = try update("T1", {
            $0.workDay = at(4, 0)
            $0.startMinute = 9 * 60
            $0.endMinute = 10 * 60
        }, in: report(minutes: 180))
        let result = placement.replan(outcome.draft, affected: outcome.affectedTasks)
        #expect(result.draft.blocks.count == 1)
        #expect(result.shortfalls[outcome.draft.tasks[0].id] == 120)
    }

    @Test func slotAfterTheDeadlineMovesTheDeadline() throws {
        var draft = report()
        draft.tasks[0].deadline = at(2, 18)
        let outcome = try update("T1", {
            $0.workDay = at(4, 0)
            $0.startMinute = 9 * 60
            $0.endMinute = 11 * 60
        }, in: draft)
        #expect(calendar.isDate(outcome.draft.tasks[0].deadline, inSameDayAs: at(4, 0)))
        #expect(!outcome.problems.isEmpty)
    }
}

@Suite("Inicio y fin: compatibilidad")
struct EventTimesCompatibilityTests {
    /// Propuestas y cambios guardados antes de esta versión (sin los campos nuevos).
    @Test func oldChangesAndTasksStillDecode() throws {
        let oldChanges = Data(#"{"startMinute": 600, "minutes": 60}"#.utf8)
        let changes = try JSONDecoder().decode(ProposalChanges.self, from: oldChanges)
        #expect(changes.startMinute == 600 && changes.keepEnd == nil && changes.startDeltaMinutes == nil)

        let task = report()
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(task)) as? [String: Any])
        object.removeValue(forKey: "workFrom")
        object.removeValue(forKey: "workTo")
        let decoded = try JSONDecoder().decode(PlanDraft.Workload.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded == task)
    }

    @Test func existingEventsKeepTheirTimes() throws {
        let draft = uploads()
        let decoded = try JSONDecoder().decode(PlanDraft.self, from: JSONEncoder().encode(draft))
        #expect(decoded.items.map { [$0.start, $0.end] } == draft.items.map { [$0.start, $0.end] })
        #expect(decoded.items.map(\.durationMinutes) == [150, 120])
    }

    private func report() -> PlanDraft.Workload {
        PlanDraft.Workload(id: UUID(), title: "Informe", mode: .work, deadline: at(4, 20), estimatedMinutes: 90, priority: 1)
    }
}
