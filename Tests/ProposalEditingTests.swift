import Foundation
import Testing

private let calendar = Calendar.current
private let base = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 8))! // lunes

private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(byAdding: DateComponents(day: day, hour: hour - 8, minute: minute), to: base)!
}

/// Reunión el jueves a las 10 e informe de 4 h para el viernes.
private func sample() -> PlanDraft {
    let meeting = PlanDraft.Item(title: "Reunión con Jonatan", start: at(3, 10), end: at(3, 11), mode: .work, kind: .event)
    let report = PlanDraft.Workload(id: UUID(), title: "Terminar el informe", mode: .work, deadline: at(4, 23, 59),
                                    estimatedMinutes: 240, priority: 1, notes: "Ver anexo", statedMinutes: 240)
    return PlanDraft(items: [meeting], tasks: [report], summary: "", warnings: [])
}

private func applied(_ result: ProposalEditResult) throws -> ProposalEditOutcome {
    guard case .applied(let outcome) = result else { throw ProposalTestError.notApplied }
    return outcome
}

private enum ProposalTestError: Error { case notApplied }

private var placement: ProposalPlacement { ProposalPlacement(
    busy: [], planner: WorkloadPlanner(), availability: { _ in .work }, now: base)
}

@Suite("Propuestas editables")
struct ProposalEditingTests {
    @Test func codesAreStable() {
        let draft = sample()
        #expect(draft.ref(draft.items[0].id) == "E1")
        #expect(draft.ref(draft.tasks[0].id) == "T1")
    }

    @Test func movingAnEventKeepsOneEvent() throws {
        let draft = sample()
        var changes = ProposalChanges()
        changes.day = calendar.startOfDay(for: at(2, 0))
        changes.startMinute = 12 * 60
        let outcome = try applied(ProposalEditor.apply([.update(ProposalTarget(text: "E1"), changes)], to: draft))
        #expect(outcome.draft.newEvents.count == 1)
        #expect(outcome.draft.newEvents[0].id == draft.items[0].id)
        #expect(outcome.draft.newEvents[0].start == at(2, 12))
        #expect(outcome.draft.newEvents[0].durationMinutes == 60)
    }

    @Test func repeatedEventFromAIIsMergedNotDuplicated() throws {
        let draft = sample()
        let again = PlanDraft.Item(title: "reunión con Jonatan", start: at(2, 12), end: at(2, 13), mode: .work, kind: .event)
        let outcome = try applied(ProposalEditor.apply([.addEvent(again)], to: draft))
        #expect(outcome.draft.newEvents.count == 1)
        #expect(outcome.draft.newEvents[0].start == at(2, 12))
    }

    @Test func taskDurationPriorityAndNotes() throws {
        var changes = ProposalChanges()
        changes.minutes = 120
        changes.priority = 2
        let outcome = try applied(ProposalEditor.apply([.update(ProposalTarget(text: "el informe"), changes)], to: sample()))
        let task = outcome.draft.tasks[0]
        #expect(task.requestedMinutes == 120)
        #expect(task.priority == 2)
        #expect(task.notes == "Ver anexo")
        #expect(outcome.affectedTasks.contains(task.id))
    }

    @Test func removingATaskLeavesNoBlocks() throws {
        var draft = sample()
        draft = placement.replan(draft, affected: Set(draft.tasks.map(\.id))).draft
        #expect(!draft.blocks.isEmpty)
        let outcome = try applied(ProposalEditor.apply([.remove(ProposalTarget(text: "T1"))], to: draft))
        #expect(outcome.draft.tasks.isEmpty)
        #expect(outcome.draft.blocks.isEmpty)
        #expect(outcome.draft.newEvents.count == 1)
    }

    @Test func ambiguousReferenceAsksAndKeepsProposal() throws {
        var draft = sample()
        draft.items.append(PlanDraft.Item(title: "Reunión de equipo", start: at(1, 9), end: at(1, 10), mode: .work, kind: .event))
        draft.assignRefs()
        var changes = ProposalChanges()
        changes.startMinute = 16 * 60
        let result = ProposalEditor.apply([.update(ProposalTarget(text: "la reunión", kind: .event), changes)], to: draft)
        guard case .clarify(let question) = result else { Issue.record("debía preguntar"); return }
        #expect(question.question == "¿Cuál quieres mover?")
        #expect(question.options.count == 2)
        let choice = try #require(question.option(matching: "la de Jonatan"))
        let edits = try #require(question.resolved(with: choice.id))
        let outcome = try applied(ProposalEditor.apply(edits, to: draft))
        #expect(outcome.draft.items.first { $0.id == choice.id }?.start == at(3, 16))
    }

    @Test func changingOnlyTuesdaysMeetingLeavesTheRest() throws {
        // Dos «Reunión» (martes y jueves) y una tarea: «Cambia solamente la reunión del martes a las 12».
        var draft = sample()
        draft.items = [
            PlanDraft.Item(title: "Reunión", start: at(1, 10), end: at(1, 11), mode: .work, kind: .event),
            PlanDraft.Item(title: "Reunión", start: at(3, 10), end: at(3, 11), mode: .work, kind: .event),
        ]
        draft.assignRefs()
        let before = draft
        var changes = ProposalChanges()
        changes.startMinute = 12 * 60
        let outcome = try applied(ProposalEditor.apply([.update(ProposalTarget(text: "la reunión del martes", kind: .event), changes)], to: draft))
        #expect(outcome.draft.items.count == 2)
        #expect(outcome.draft.items[0].id == before.items[0].id)
        #expect(outcome.draft.items[0].start == at(1, 12) && outcome.draft.items[0].durationMinutes == 60)
        #expect(outcome.draft.items[1] == before.items[1])
        #expect(outcome.draft.tasks == before.tasks)
        // Por número de día también: «la del 12» (jueves 12 de noviembre).
        let second = try applied(ProposalEditor.apply([.update(ProposalTarget(text: "la reunión del 12", kind: .event), changes)], to: draft))
        #expect(second.draft.items[1].start == at(3, 12))
        #expect(second.draft.items[0] == before.items[0])
    }

    @Test func startAndEndGiveTheDuration() throws {
        // «Reunión de 10:30 a 12:00»: inicio, fin y 90 min calculados; no hace falta decir la duración.
        let range = try #require(AnswerParsing.range("de 10:30 a 12:00"))
        #expect(range.start == 10 * 60 + 30 && range.end == 12 * 60)
        var changes = ProposalChanges()
        changes.startMinute = range.start
        changes.endMinute = range.end
        let outcome = try applied(ProposalEditor.apply([.update(ProposalTarget(text: "E1"), changes)], to: sample()))
        let meeting = outcome.draft.newEvents[0]
        #expect(meeting.start == at(3, 10, 30) && meeting.end == at(3, 12))
        #expect(meeting.durationMinutes == 90)
    }

    @Test func removingOneEventKeepsTheOthers() throws {
        var draft = sample()
        draft.items.append(PlanDraft.Item(title: "Dentista", start: at(2, 17), end: at(2, 18), mode: .personal, kind: .event))
        draft.assignRefs()
        let outcome = try applied(ProposalEditor.apply([.remove(ProposalTarget(text: "el dentista", kind: .event))], to: draft))
        #expect(outcome.draft.newEvents.map(\.title) == ["Reunión con Jonatan"])
        #expect(outcome.draft.tasks == draft.tasks)
    }

    @Test func undoAndRedo() {
        var history = ProposalHistory(sample())
        var next = sample()
        next.summary = "otra"
        history.commit(next)
        #expect(history.undo()?.summary == "")
        #expect(history.redo()?.summary == "otra")
        #expect(history.canRedo == false)
    }

    @Test func diffDescribesChanges() throws {
        let draft = sample()
        var changes = ProposalChanges()
        changes.day = calendar.startOfDay(for: at(4, 0))
        let outcome = try applied(ProposalEditor.apply([.update(ProposalTarget(text: "E1"), changes)], to: draft))
        let diff = ProposalDiff.changes(from: draft, to: outcome.draft)
        #expect(diff.first?.kind == .modified)
        #expect(diff.first?.fields == [.day])
    }

    @Test func replanKeepsUnaffectedBlocksAndAvoidsEvents() {
        var draft = sample()
        draft = placement.replan(draft, affected: Set(draft.tasks.map(\.id))).draft
        let before = draft.blocks
        let again = placement.replan(draft, affected: []).draft
        #expect(again.blocks.map(\.start) == before.map(\.start))
        let events = draft.newEvents.map { DateInterval(start: $0.start, end: $0.end) }
        #expect(!again.blocks.contains { block in events.contains { $0.start < block.end && block.start < $0.end } })
    }

    @Test func commands() {
        #expect(ProposalCommand.detect("Deshaz lo último") == .undo)
        #expect(ProposalCommand.detect("Ahora sí, guarda el plan") == .accept)
        #expect(ProposalCommand.detect("Pon la reunión como antes a las 10") == nil)
    }

    @Test func deadlineAndModeChanges() throws {
        var changes = ProposalChanges()
        changes.deadline = at(3, 18)
        changes.mode = .personal
        let outcome = try applied(ProposalEditor.apply([.update(ProposalTarget(text: "T1"), changes)], to: sample()))
        #expect(outcome.draft.tasks[0].deadline == at(3, 18))
        #expect(outcome.draft.tasks[0].mode == .personal)
    }

    @Test func eventDurationAndEndTime() throws {
        var changes = ProposalChanges()
        changes.endMinute = 11 * 60 + 30
        let outcome = try applied(ProposalEditor.apply([.update(ProposalTarget(text: "E1"), changes)], to: sample()))
        #expect(outcome.draft.items[0].start == at(3, 10))
        #expect(outcome.draft.items[0].durationMinutes == 90)
    }

    @Test func addingKeepsEverythingElse() throws {
        let draft = sample()
        let call = PlanDraft.Item(title: "Llamar a Marta", start: at(1, 17), end: at(1, 17, 30), mode: .personal, kind: .event)
        let outcome = try applied(ProposalEditor.apply([.addEvent(call)], to: draft))
        #expect(outcome.draft.newEvents.count == 2)
        #expect(outcome.draft.tasks == draft.tasks)
        #expect(outcome.draft.ref(call.id) == "E2")
    }

    @Test func latestEndConditionIsRespected() throws {
        var conditions = PlanConstraints()
        conditions.latestEndMinute = 12 * 60
        let outcome = try applied(ProposalEditor.apply([.constraints(conditions)], to: sample()))
        let draft = placement.replan(outcome.draft, affected: Set(outcome.draft.tasks.map(\.id))).draft
        #expect(!draft.blocks.isEmpty)
        #expect(draft.blocks.allSatisfy { ProposalEditor.minuteOfDay($0.end, calendar: calendar) <= 12 * 60 })
    }

    @Test func emptyChangeExplainsInsteadOfGuessing() throws {
        let outcome = try applied(ProposalEditor.apply([.update(ProposalTarget(text: "T1"), ProposalChanges())], to: sample()))
        #expect(outcome.affectedTasks.isEmpty)
        #expect(outcome.draft.tasks[0].requestedMinutes == 240)
        #expect(!outcome.problems.isEmpty)
    }

    /// La conversación completa del encargo, con las operaciones que devolvería la IA.
    @Test func fullConversation() throws {
        var history = ProposalHistory(placement.replan(sample(), affected: Set(sample().tasks.map(\.id))).draft)
        func step(_ edits: [ProposalEdit]) throws {
            let outcome = try applied(ProposalEditor.apply(edits, to: history.current))
            history.commit(placement.replan(outcome.draft, affected: outcome.affectedTasks).draft)
        }
        var move = ProposalChanges()
        move.day = calendar.startOfDay(for: at(2, 0))
        move.startMinute = 12 * 60
        try step([.update(ProposalTarget(text: "E1"), move)])
        var shorter = ProposalChanges()
        shorter.minutes = 120
        try step([.update(ProposalTarget(text: "T1"), shorter)])
        try step([.moveFirst(ProposalTarget(text: "el informe"))])
        try step([.remove(ProposalTarget(text: "la reunión", kind: .event))])
        #expect(history.current.newEvents.isEmpty)
        #expect(history.current.tasks[0].requestedMinutes == 120)

        history.undo()
        let final = history.current
        #expect(final.newEvents.count == 1)
        #expect(final.newEvents[0].start == at(2, 12))
        #expect(final.tasks[0].requestedMinutes == 120)
        #expect(final.blocks.reduce(0) { $0 + $1.durationMinutes } == 120)
        let meeting = DateInterval(start: final.newEvents[0].start, end: final.newEvents[0].end)
        #expect(!final.blocks.contains { $0.start < meeting.end && meeting.start < $0.end })
    }

    @Test func proposalRoundTripsThroughJSON() throws {
        let proposal = ActiveProposal(history: ProposalHistory(sample()), messageID: UUID())
        let data = try JSONEncoder().encode(proposal)
        let back = try JSONDecoder().decode(ActiveProposal.self, from: data)
        #expect(back.history.current.tasks == proposal.history.current.tasks)
        #expect(back.history.current.refs == proposal.history.current.refs)
    }
}
