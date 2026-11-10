import Foundation
import Testing

// Dos cosas a la misma hora están permitidas: solo se avisa de lo que ya hay ahí.

private let calendar = Calendar.current
/// Jueves 26 de noviembre de 2026, 10:00 (el sábado 28 es de esta semana: «sábado»).
private let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 10))!

/// El sábado 28 a esa hora.
private func saturday(_ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: 28, hour: hour, minute: minute))!
}

private func span(_ start: Date, _ end: Date) -> DateInterval { DateInterval(start: start, end: end) }

private func slot(_ title: String, _ intervals: DateInterval...) -> OverlapNotice.Slot {
    OverlapNotice.Slot(title: title, intervals: intervals)
}

private func saved(_ title: String, _ interval: DateInterval) -> EventConflict {
    EventConflict(title: title, interval: interval)
}

@Suite("Dos cosas a la vez")
struct OverlapNoticeTests {
    @Test func whatIsAlreadyThereIsNamed() {
        let found = OverlapNotice.clashes(
            [slot("Ensayo", span(saturday(18), saturday(20)))],
            outside: [saved("Cena", span(saturday(19), saturday(21)))]
        )
        #expect(found.count == 1)
        #expect(OverlapNotice.line(found[0], now: now) == "«Ensayo» coincide con «Cena» (sábado 19:00–21:00).")
    }

    @Test func touchingEdgesIsNotAtTheSameTime() {
        let found = OverlapNotice.clashes(
            [slot("Ensayo", span(saturday(18), saturday(20)))],
            outside: [saved("Merienda", span(saturday(17), saturday(18))), saved("Cena", span(saturday(20), saturday(21)))]
        )
        #expect(found.isEmpty)
    }

    /// Lo de la captura: dos «Actuación Natalia» a la vez se avisa una vez, no «X coincide con X» dos veces.
    @Test func twoNewOnesAtTheSameTimeAreToldOnce() {
        let found = OverlapNotice.clashes([
            slot("Actuación Natalia", span(saturday(18), saturday(20))),
            slot("Actuación Natalia", span(saturday(17, 45), saturday(20))),
        ], outside: [])
        #expect(found.count == 1)
        #expect(OverlapNotice.line(found[0], now: now) == "Hay dos «Actuación Natalia» a la vez (sábado 17:45–20:00).")
    }

    @Test func aTwinAndSomethingElse() {
        let found = OverlapNotice.clashes(
            [slot("Actuación Natalia", span(saturday(18), saturday(20)))],
            outside: [saved("Cena", span(saturday(19), saturday(21))), saved("actuacion natalia", span(saturday(18), saturday(20)))]
        )
        #expect(OverlapNotice.line(found[0], now: now) == "«Actuación Natalia» coincide con «Cena» y otro «Actuación Natalia» (sábado 19:00–21:00).")
    }

    @Test func manyThingsAreSummed() {
        let found = OverlapNotice.clashes(
            [slot("Ensayo", span(saturday(9), saturday(14)))],
            outside: [
                saved("Café", span(saturday(9), saturday(10))), saved("Llamada", span(saturday(10), saturday(11))),
                saved("Compra", span(saturday(11), saturday(12))), saved("Comida", span(saturday(13), saturday(14))),
            ]
        )
        #expect(OverlapNotice.line(found[0], now: now) == "«Ensayo» coincide con «Café», «Llamada» y 2 más (sábado 09:00–10:00).")
    }

    /// Un hábito diario que coincide todos los días avisa una vez.
    @Test func somethingThatRepeatsIsToldOnce() {
        let days = (0..<3).map { offset in
            span(saturday(18).addingTimeInterval(Double(offset) * 86_400), saturday(19).addingTimeInterval(Double(offset) * 86_400))
        }
        let others = days.map { saved("Cena", $0) }
        let found = OverlapNotice.clashes([OverlapNotice.Slot(title: "Leer", intervals: days)], outside: others)
        #expect(found.count == 1)
    }

    @Test func theAlertSaysItCanBeSavedAnyway() {
        let found = OverlapNotice.clashes(
            [slot("Ensayo", span(saturday(18), saturday(20)))],
            outside: [saved("Cena", span(saturday(19), saturday(21)))]
        )
        let message = OverlapNotice.alertMessage(found, now: now)
        #expect(message == "«Ensayo» coincide con «Cena» (sábado 19:00–21:00).\nPuedes guardarlo igualmente: los dos se quedan en tu calendario.")
        #expect(OverlapNotice.alertTitle == "Ya tienes algo a esa hora")
    }

    @Test func theAlertShowsAtMostFour() {
        let slots = (0..<6).map { index in slot("Cosa \(index)", span(saturday(9 + index), saturday(10 + index))) }
        let outside = [saved("Todo el día fuera", span(saturday(8), saturday(20)))]
        let message = OverlapNotice.alertMessage(OverlapNotice.clashes(slots, outside: outside), now: now)
        let lines = message.components(separatedBy: "\n")
        #expect(lines.count == 6)
        #expect(lines[4] == "Y 2 más.")
        #expect(lines[5] == "Puedes guardarlo igualmente: todo se queda en tu calendario.")
    }

    @Test func theAgendaMarksWhatIsAtTheSameTime() {
        let together = OverlapNotice.alongside([
            OverlapNotice.Entry(id: "a", title: "Actuación Natalia", interval: span(saturday(17, 45), saturday(20))),
            OverlapNotice.Entry(id: "b", title: "Cena", interval: span(saturday(19), saturday(21))),
            OverlapNotice.Entry(id: "c", title: "Copas", interval: span(saturday(21), saturday(23))),
        ])
        #expect(together["a"] == ["Cena"])
        #expect(together["b"] == ["Actuación Natalia"])
        #expect(together["c"] == nil)
        #expect(OverlapNotice.alongsideText(["Cena", "Cine"]) == "A la vez que «Cena» y «Cine»")
    }
}
