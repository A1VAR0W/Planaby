import Testing

// La IA del iPhone tiene poco espacio: cada petición se divide por lo que pide y solo se le da
// el contexto que hace falta. Aquí, lo que no depende del modelo.

@Suite("Qué pide la petición")
struct RequestIntentTests {
    @Test func creatingNewItems() {
        let intent = RequestIntent.hints("Añade dos eventos, Subida PRE el 25 de noviembre y Subida PRO el 26")
        #expect(intent.creates && !intent.changes && !intent.conditions && !intent.reorganize)
        #expect(RequestIntent.hints("Tengo que entregar el informe el viernes").creates)
        #expect(RequestIntent.hints("Una reunión el lunes y otra el martes").creates)
    }

    @Test func changingWhatExists() {
        let end = RequestIntent.hints("Cambia la hora de fin de Subida PRE a las 14:30")
        #expect(end.changes && !end.creates)
        #expect(RequestIntent.hints("Haz que Subida PRO termine a las 17:00").changes)
        #expect(RequestIntent.hints("Borra la Subida PRO").changes)
        #expect(RequestIntent.hints("E2 al jueves").changes)
        #expect(RequestIntent.hints("lo de C3, mejor el lunes").changes)
    }

    @Test func conditionsAndReorganizing() {
        #expect(RequestIntent.hints("Nada después de las 17:00").conditions)
        #expect(RequestIntent.hints("Deja dos horas libres mañana por la tarde").conditions)
        #expect(RequestIntent.hints("Primero lo urgente").conditions)
        #expect(RequestIntent.hints("Reorganiza mi semana").reorganize)
        #expect(RequestIntent.hints("Hazme hueco el jueves").reorganize)
    }

    @Test func severalThingsAtOnce() {
        let both = RequestIntent.hints("Mueve la reunión al viernes y añade una llamada el lunes")
        #expect(both.creates && both.changes)
    }

    @Test func unclearIsLeftToTheModel() {
        #expect(RequestIntent.hints("¿Qué tiempo hará mañana?").isEmpty)
        #expect(RequestIntent.hints("y la del jueves?").isEmpty)
    }

    @Test func combining() {
        let words = RequestIntent(changes: true)
        let model = RequestIntent(creates: true)
        #expect(words | model == RequestIntent(creates: true, changes: true))
    }
}

@Suite("Contexto que cabe")
struct ContextBudgetTests {
    private let lines = (1...20).map { "C\($0) evento «Cita \($0)»" }
    private var titles: [String] { (1...20).map { "Cita \($0)" } }

    @Test func keepsWhatTheRequestNamesAndTheNearest() {
        var named = titles
        named[16] = "Subida PRO"
        let chosen = ContextBudget.relevant(lines: lines, titles: named, request: "Borra la Subida PRO", limit: 5)
        #expect(chosen.count == 5)
        #expect(chosen.contains(lines[16]))
        // Las más próximas completan el resto, en su orden (los códigos no cambian).
        #expect(Array(chosen.prefix(4)) == Array(lines.prefix(4)))
    }

    @Test func shortListsStayWhole() {
        #expect(ContextBudget.relevant(lines: Array(lines.prefix(3)), titles: Array(titles.prefix(3)), request: "x", limit: 5).count == 3)
    }

    @Test func clipCutsAtWholeLines() {
        let text = (1...50).map { "línea \($0)" }.joined(separator: "\n")
        let clipped = ContextBudget.clip(text, to: 100)
        #expect(clipped.count <= 102)
        #expect(clipped.hasSuffix("\n…"))
        #expect(!clipped.contains("línea 50"))
        #expect(ContextBudget.clip("corto", to: 100) == "corto")
    }
}
