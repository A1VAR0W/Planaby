import Foundation
import Testing

// Lo dictado llega con las horas habladas: se pasan a cifras y lo demás no se toca.

@Suite("Horas dictadas")
struct SpokenTextTests {
    @Test func halfAndQuarterInsideARange() {
        let text = SpokenText.tidy("Ensayo de cinco y media a siete")
        #expect(text == "Ensayo de 5:30 a 7")
        #expect(AnswerParsing.range(text).map { [$0.start, $0.end] } == [17 * 60 + 30, 19 * 60])
    }

    @Test func quarterTo() {
        let text = SpokenText.tidy("Dentista el jueves a las seis menos cuarto")
        #expect(text == "Dentista el jueves a las 5:45")
        #expect(AnswerParsing.time(text) == 17 * 60 + 45)
        #expect(SpokenText.tidy("Comida a la una y cuarto") == "Comida a la 1:15")
    }

    @Test func minutesSaidAsNumbers() {
        #expect(SpokenText.tidy("Actuación Natalia el 28 de noviembre desde las 17 y cuarenta y cinco hasta las 20")
            == "Actuación Natalia el 28 de noviembre desde las 17:45 hasta las 20")
        #expect(SpokenText.tidy("Reunión a las 10 y 20") == "Reunión a las 10:20")
    }

    @Test func whatIsNotAnHourStaysAsItIs() {
        for text in [
            "Preparar la presentación para el viernes, unas 3 horas y media",
            "Comprar dos barras de pan y una tarta",
            "Clases el 27 y 28 de noviembre",
            "Pon un evento que se llame Actuación Natalia para el 28 de noviembre desde las 17:45 a las 20:00",
        ] {
            #expect(SpokenText.tidy(text) == text)
        }
    }
}
