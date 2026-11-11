import Foundation
import Testing

// Corregir una propuesta que salió mal: «no, un evento cada día, no todos el 19».

private let calendar = Calendar.current
private let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 10))!

private func november(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

private let original = "Añade en trabajo que el día 19,20,23,24 de noviembre estoy de vacaciones (Todo el día, 19 y 24 incluidos)"
private let correction = "Pero tienes que poner un evento cada día no todos el 19"

/// Lo que hizo mal el modelo: cuatro «vacaciones» el 19, sin hora y repitiéndose.
private func wrongDraft(count: Int = 4, recurrence: Recurrence = .weekdays) -> PlanDraft {
    let items = (0..<count).map { _ in
        PlanDraft.Item(title: "Vacaciones", start: november(19, 9), end: november(19, 10), mode: .work, kind: .event,
                       recurrence: recurrence, unconfirmed: [.time, .duration])
    }
    return PlanDraft(items: items, tasks: [], summary: "", warnings: [])
}

private func spread(_ request: String, earlier: [String] = [original], draft: PlanDraft) throws -> PlanDraft {
    let plan = try #require(ProposalSpread.plan(request: request, earlier: earlier, draft: draft, now: now, calendar: calendar))
    guard case .applied(let outcome) = ProposalEditor.apply(plan.edits, to: draft, mergeSimilar: false, calendar: calendar) else {
        throw SpreadTestError.notApplied
    }
    return outcome.draft
}

private enum SpreadTestError: Error { case notApplied }

private func days(_ draft: PlanDraft) -> [Int] {
    draft.newEvents.filter(\.isIncluded).map { calendar.component(.day, from: $0.start) }.sorted()
}

@Suite("Corregir una propuesta: un evento cada día")
struct ProposalSpreadTests {
    @Test func theCorrectionIsUnderstood() {
        #expect(ProposalSpread.asksOnePerDay(correction))
        #expect(ProposalSpread.asksOnePerDay("No, quiero un evento cada día, no todos el 19"))
        #expect(ProposalSpread.asksOnePerDay("uno por día"))
        #expect(ProposalSpread.asksOnePerDay("Cada uno en su día"))
        #expect(ProposalSpread.asksOnePerDay("en días distintos"))
        // No es una corrección: es otra cosa.
        #expect(!ProposalSpread.asksOnePerDay("Estudiar una hora cada día"))
        #expect(!ProposalSpread.asksOnePerDay("Mueve la reunión al viernes"))
    }

    @Test func fourEventsOnTheSameDayGoOnePerDay() throws {
        let draft = wrongDraft()
        let fixed = try spread(correction, draft: draft)
        #expect(days(fixed) == [19, 20, 23, 24])
        // Son los mismos cuatro eventos: ni se duplican ni se pierden.
        #expect(Set(fixed.newEvents.map(\.id)) == Set(draft.newEvents.map(\.id)))
        #expect(fixed.tasks.isEmpty)
    }

    @Test func allDayAndNoInventedRepeat() throws {
        let fixed = try spread(correction, draft: wrongDraft())
        for event in fixed.newEvents {
            #expect(event.recurrence == .none)
            #expect(calendar.component(.hour, from: event.start) == 0)
            #expect(event.durationMinutes == 23 * 60 + 59)
            #expect(!event.isUnconfirmed(.day) && !event.isUnconfirmed(.time))
        }
    }

    @Test func missingEventsAreCreatedAndExtraOnesRemoved() throws {
        // El modelo solo hizo dos: se crean los que faltan, también de todo el día.
        let two = try spread(correction, draft: wrongDraft(count: 2))
        #expect(days(two) == [19, 20, 23, 24])
        #expect(two.newEvents.allSatisfy { $0.durationMinutes == 23 * 60 + 59 && $0.recurrence == .none })
        // El modelo hizo seis: sobran dos.
        let six = try spread(correction, draft: wrongDraft(count: 6))
        #expect(days(six) == [19, 20, 23, 24])
        // Solo uno: también se entiende.
        let one = try spread(correction, draft: wrongDraft(count: 1))
        #expect(days(one) == [19, 20, 23, 24])
    }

    @Test func theDaysCanComeInTheCorrectionItself() throws {
        let fixed = try spread("Ponlos el 19, 20, 23 y 24 de noviembre", earlier: [], draft: wrongDraft())
        #expect(days(fixed) == [19, 20, 23, 24])
    }

    @Test func otherThingsInTheProposalAreNotTouched() throws {
        var draft = wrongDraft()
        let meeting = PlanDraft.Item(title: "Reunión con Marta", start: november(12, 10), end: november(12, 11), mode: .work, kind: .event)
        draft.items.append(meeting)
        draft.assignRefs()
        let fixed = try spread(correction, draft: draft)
        let kept = fixed.newEvents.first(where: { $0.id == meeting.id })
        #expect(kept == meeting)
        #expect(fixed.newEvents.count == 5)
    }

    @Test func aTimeThatWasSaidIsKept() throws {
        var draft = wrongDraft(recurrence: .none)
        for index in draft.items.indices {
            draft.items[index].start = november(19, 17, 45)
            draft.items[index].end = november(19, 20)
            draft.items[index].unconfirmed = nil
        }
        let fixed = try spread(correction, earlier: ["Actuación el 19, 20, 23 y 24 de noviembre de 17:45 a 20:00"], draft: draft)
        #expect(days(fixed) == [19, 20, 23, 24])
        #expect(fixed.newEvents.allSatisfy { calendar.component(.hour, from: $0.start) == 17 && $0.durationMinutes == 135 })
    }

    @Test func nothingIsDoneWithoutKnowingTheDays() {
        // No hay lista de días en ningún mensaje: se deja al modelo o se pregunta.
        #expect(ProposalSpread.plan(request: correction, earlier: ["Estoy de vacaciones"], draft: wrongDraft(), now: now, calendar: calendar) == nil)
        // Ya está bien repartido.
        var good = wrongDraft()
        for (index, day) in [19, 20, 23, 24].enumerated() {
            good.items[index].start = november(day, 9)
            good.items[index].end = november(day, 10)
        }
        #expect(ProposalSpread.plan(request: "Ponlos el 19, 20, 23 y 24 de noviembre", earlier: [], draft: good, now: now, calendar: calendar) == nil)
        // Un mensaje normal no es una corrección de días.
        #expect(ProposalSpread.plan(request: "Mueve la reunión al viernes", earlier: [original], draft: wrongDraft(), now: now, calendar: calendar) == nil)
    }

    @Test func correctingTwiceEndsTheSame() throws {
        let once = try spread(correction, draft: wrongDraft())
        // Repetir la corrección no cambia nada ni duplica.
        #expect(ProposalSpread.plan(request: correction, earlier: [original], draft: once, now: now, calendar: calendar) == nil)
    }
}
