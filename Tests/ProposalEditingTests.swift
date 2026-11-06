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

private let placement = ProposalPlacement(
    busy: [], planner: WorkloadPlanner(), availability: { _ in .work }, now: base
)

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

    @Test func proposalRoundTripsThroughJSON() throws {
        let proposal = ActiveProposal(history: ProposalHistory(sample()), messageID: UUID())
        let data = try JSONEncoder().encode(proposal)
        let back = try JSONDecoder().decode(ActiveProposal.self, from: data)
        #expect(back.history.current.tasks == proposal.history.current.tasks)
        #expect(back.history.current.refs == proposal.history.current.refs)
    }
}
