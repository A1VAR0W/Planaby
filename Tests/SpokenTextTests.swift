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

    @Test func compoundMinutesAreOneNumber() {
        // «cuarenta y cinco» es 45, nunca «40 y 5».
        #expect(SpokenText.tidy("A las diecisiete y cuarenta y cinco") == "A las 17:45")
        #expect(SpokenText.tidy("Reunión a las nueve y treinta y cinco") == "Reunión a las 9:35")
        #expect(SpokenText.tidy("Llamada a las 10 y cincuenta y cinco") == "Llamada a las 10:55")
        #expect(AnswerParsing.time(SpokenText.tidy("a las diecisiete y cuarenta y cinco")) == 17 * 60 + 45)
    }

    @Test func everydayWaysOfSayingTheTime() {
        let cases: [(said: String, written: String)] = [
            ("A las cinco", "A las 5"),
            ("A las cinco y media", "A las 5:30"),
            ("A las cinco y cuarto", "A las 5:15"),
            ("A las cinco menos cuarto", "A las 4:45"),
            ("A las cinco y cinco", "A las 5:05"),
            ("A las nueve y veinte", "A las 9:20"),
            ("De diez a doce", "De 10 a 12"),
            ("Desde las 10:30 hasta las 12", "Desde las 10:30 hasta las 12"),
            ("A las ocho de la tarde", "A las 8 de la tarde"),
            ("Mañana a las nueve", "Mañana a las 9"),
            ("El 25 de noviembre a las diez", "El 25 de noviembre a las 10"),
            ("De las nueve y media a las once y cuarto", "De las 9:30 a las 11:15"),
            ("Cena a las veintiuna", "Cena a las 21"),
        ]
        for (said, written) in cases {
            #expect(SpokenText.tidy(said) == written)
        }
        #expect(AnswerParsing.time("A las 8 de la tarde") == 20 * 60)
        #expect(AnswerParsing.time(SpokenText.tidy("a las seis menos cuarto")) == 17 * 60 + 45)
    }

    @Test func aRangeBetweenTwoHoursIsNotAClock() {
        // «Entre dos y cinco» son dos horas, no las 2:05.
        #expect(SpokenText.tidy("Disponible entre dos y cinco") == "Disponible entre 2 y 5")
        // Una duración no es una hora.
        #expect(SpokenText.tidy("Estudiar dos y media horas") == "Estudiar dos y media horas")
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
