import Foundation
import Testing

// La respuesta del modelo local (JSON) se lee con tolerancia y acaba en los mismos cambios que
// la de Apple Intelligence.

@Suite("Respuesta del modelo local")
struct PlanReadingTests {
    @Test func everyExampleShownToTheModelIsReadable() throws {
        for example in LocalPlanningPrompt.examples {
            let reading = try #require(PlanReading.parse(json: example.json), "\(example.request)")
            #expect(!reading.offTopic)
            #expect(reading.events.count + reading.tasks.count + reading.edits.count + reading.conditions.count > 0)
        }
        #expect(LocalPlanningPrompt.instructions.contains("Subida PRE"))
    }

    @Test func newEventsWithoutHoursKeepBoth() throws {
        let reading = try #require(PlanReading.parse(json: LocalPlanningPrompt.examples[0].json))
        #expect(reading.requestedCount == 2)
        #expect(reading.events.map(\.title) == ["Subida PRE", "Subida PRO"])
        #expect(reading.events.map(\.day) == ["2026-11-25", "2026-11-26"])
        #expect(reading.events.allSatisfy { $0.time.isEmpty && $0.endTime.isEmpty && $0.durationMinutes == 0 })
        // Lo que no viene toma el valor de siempre.
        #expect(reading.events[0].reminderMinutes == 15 && reading.events[0].repeats == "none")
    }

    @Test func editsOnlyCarryWhatChanges() throws {
        let reading = try #require(PlanReading.parse(json: LocalPlanningPrompt.examples[2].json))
        #expect(reading.edits.count == 2)
        let end = reading.edits[0]
        #expect(end.action == "update" && end.target == "E1" && end.endTime == "14:30")
        #expect(end.time.isEmpty && end.minutes == 0 && end.priority == -1 && end.reminderMinutes == -1)
        #expect(reading.edits[1].action == "delete" && reading.edits[1].target == "C1")

        guard case .update(_, let changes) = end.makeEdit() else {
            Issue.record("Debe ser un cambio")
            return
        }
        #expect(changes.endMinute == 14 * 60 + 30 && changes.startMinute == nil && changes.minutes == nil)
    }

    @Test func keepingTheEndAndAConditionTogether() throws {
        let reading = try #require(PlanReading.parse(json: LocalPlanningPrompt.examples[3].json))
        #expect(reading.edits[0].startShift == -30 && reading.edits[0].keepEnd)
        #expect(reading.conditions.first?.kind == "latestEnd")
        #expect(reading.conditions.first?.makeEdit() != nil)
    }

    @Test func toleratesWhatSmallModelsDo() throws {
        let messy = """
            <think>El usuario quiere una reunión.</think>
            Claro, aquí tienes:
            ```json
            {"requestedCount": "1", "events": [{"title": "Reunión", "day": "2026-11-10", "time": "10:00", "durationMinutes": "45", "mode": "Work", "repeats": "cada día",},], "reorganize": "true"}
            ```
            """
        let reading = try #require(PlanReading.parse(json: messy))
        #expect(reading.requestedCount == 1)
        #expect(reading.events.count == 1)
        #expect(reading.events[0].durationMinutes == 45)
        #expect(reading.events[0].mode == "work")
        // Un valor que no es una de las opciones se queda en el de siempre.
        #expect(reading.events[0].repeats == "none")
        #expect(reading.reorganize)
        #expect(reading.tasks.isEmpty && reading.edits.isEmpty)
    }

    @Test func dropsWhatCannotBeUsed() throws {
        let json = #"{"events": [{"day": "2026-11-10"}], "edits": [{"action": "update", "title": "Sin destino"}], "conditions": [{"kind": "otra"}], "tasks": [{"title": "Informe", "estimatedMinutes": 99999, "priority": 7}]}"#
        let reading = try #require(PlanReading.parse(json: json))
        #expect(reading.events.isEmpty && reading.edits.isEmpty && reading.conditions.isEmpty)
        #expect(reading.tasks.first?.estimatedMinutes == 12000 && reading.tasks.first?.priority == 2)
    }

    @Test func notJSONIsNil() {
        #expect(PlanReading.parse(json: "No puedo ayudarte con eso.") == nil)
        #expect(PlanReading.parse(json: "{roto") == nil)
    }
}
