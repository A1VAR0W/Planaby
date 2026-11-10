import Foundation
import Testing

// El final de la concentración: empezar el descanso solo, o esperar a que se elija descansar,
// seguir o finalizar. Todo sale de un único `TimerState`, también lo que pasa en segundo plano.

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private func minute(_ value: Double) -> Date { start.addingTimeInterval(value * 60) }

private func session(asks: Bool) -> TimerState {
    var state = TimerState(method: .pomodoro, at: start)
    state.asksAfterFocus = asks ? true : nil
    return state
}

@Suite("Fin de la concentración")
struct PhaseChoiceTests {
    @Test func byDefaultTheBreakStartsOnItsOwn() {
        var state = session(asks: false)
        #expect(state.catchUp(to: minute(26)) == 1)
        #expect(state.phase == .shortBreak && !state.isPaused && !state.isAwaitingChoice)
        #expect(state.remaining(at: minute(26)) == 4 * 60)
        // Y sigue sola: descanso de 5 y otra concentración.
        #expect(state.catchUp(to: minute(31)) == 1)
        #expect(state.phase == .focus)
    }

    @Test func askingHoldsTheBreakUntilChosen() {
        var state = session(asks: true)
        // Media hora en segundo plano (en Teams, con el iPhone bloqueado…): una sola transición.
        #expect(state.catchUp(to: minute(55)) == 1)
        #expect(state.phase == .shortBreak && state.isAwaitingChoice)
        #expect(state.focusedSeconds == 25 * 60)
        #expect(state.completedCycles == 1)
        // Mirarlo otra vez no cambia nada: no hay transiciones duplicadas.
        let held = state
        #expect(state.catchUp(to: minute(90)) == 0)
        #expect(state == held)
        // No se programan más avisos mientras espera.
        #expect(state.upcomingTransitions(limit: 12).isEmpty)
    }

    @Test func onlyOneAlertIsScheduledWhenAsking() {
        let asking = session(asks: true).upcomingTransitions(limit: 12)
        #expect(asking.count == 1)
        #expect(asking.first?.date == minute(25))
        #expect(asking.first?.next == .shortBreak)
        #expect(session(asks: false).upcomingTransitions(limit: 12).count == 12)
    }

    @Test func restingStartsTheBreakNow() {
        var state = session(asks: true)
        state.catchUp(to: minute(40))
        // «Descansar» a los 40 min: el descanso entero empieza entonces.
        state.resume(at: minute(40))
        #expect(state.phase == .shortBreak && !state.isPaused && !state.isAwaitingChoice)
        #expect(state.remaining(at: minute(40)) == 5 * 60)
        #expect(state.focusedSeconds == 25 * 60)
        // Después vuelve la concentración y, al acabar, se pregunta otra vez.
        #expect(state.catchUp(to: minute(46)) == 1)
        #expect(state.phase == .focus)
        state.catchUp(to: minute(120))
        #expect(state.isAwaitingChoice && state.completedCycles == 2)
    }

    @Test func continuingStartsAnotherFocusBlock() {
        var state = session(asks: true)
        state.catchUp(to: minute(30))
        state.beginFocus(at: minute(30))
        #expect(state.phase == .focus && !state.isPaused && !state.isAwaitingChoice)
        #expect(state.remaining(at: minute(30)) == 25 * 60)
        // No se pierde lo trabajado ni se cuenta dos veces.
        #expect(state.focusedSeconds == 25 * 60)
        #expect(state.totalFocused(at: minute(40)) == 35 * 60)
    }

    @Test func continuingWithoutAskingAlsoWorks() {
        var state = session(asks: false)
        state.catchUp(to: minute(27)) // 2 min de descanso
        state.beginFocus(at: minute(27))
        #expect(state.phase == .focus)
        #expect(state.focusedSeconds == 25 * 60)
    }

    @Test func finishingKeepsTheStatistics() {
        var state = session(asks: true)
        state.catchUp(to: minute(45))
        let summary = state.summary(endingAt: minute(45))
        #expect(summary.focusedSeconds == 25 * 60)
        #expect(!summary.endedEarly)
        #expect(summary.pauses == 0)
    }

    @Test func skippingOnPurposeDoesNotAsk() {
        var state = session(asks: true)
        // «Saltar» a los 10 min: se ha pedido descansar, no hay nada que preguntar.
        state.skip(at: minute(10))
        #expect(state.phase == .shortBreak && !state.isPaused && !state.isAwaitingChoice)
    }

    @Test func skippingAHeldBreakGoesBackToFocus() {
        var state = session(asks: true)
        state.catchUp(to: minute(30))
        state.skip(at: minute(30))
        #expect(state.phase == .focus && !state.isPaused && !state.isAwaitingChoice)
    }

    @Test func theChoiceSurvivesARestart() throws {
        var state = session(asks: true)
        state.catchUp(to: minute(30))
        let data = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(TimerState.self, from: data)
        #expect(restored == state && restored.isAwaitingChoice)
    }

    @Test func aSessionSavedByAnOlderVersionStillLoads() throws {
        // Sin los campos nuevos: se lee igual y se comporta como siempre.
        var old = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(session(asks: true))) as? [String: Any])
        old["asksAfterFocus"] = nil
        old["awaitingChoice"] = nil
        var restored = try JSONDecoder().decode(TimerState.self, from: JSONSerialization.data(withJSONObject: old))
        restored.catchUp(to: minute(26))
        #expect(restored.phase == .shortBreak && !restored.isAwaitingChoice)
    }
}
