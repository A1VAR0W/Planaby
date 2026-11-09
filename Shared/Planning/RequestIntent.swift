import Foundation

// La IA del iPhone tiene muy poco espacio (unos 4.000 tokens entre instrucciones, formato,
// contexto y respuesta). Por eso cada petición se divide: primero se decide qué pide (crear,
// cambiar, condiciones o reorganizar) y luego se le pregunta solo eso, con un formato pequeño y
// solo el contexto que hace falta.

/// Qué pide una petición. Varias cosas a la vez son posibles («cambia X y añade Y»).
struct RequestIntent: Equatable, Sendable {
    var creates = false
    var changes = false
    var conditions = false
    var reorganize = false

    var isEmpty: Bool { !creates && !changes && !conditions && !reorganize }

    static func | (lhs: RequestIntent, rhs: RequestIntent) -> RequestIntent {
        RequestIntent(
            creates: lhs.creates || rhs.creates, changes: lhs.changes || rhs.changes,
            conditions: lhs.conditions || rhs.conditions, reorganize: lhs.reorganize || rhs.reorganize
        )
    }

    private static let createWords: Set<String> = [
        "anade", "anadir", "anademe", "anadelo", "anadela", "crea", "crear", "creame", "nueva", "nuevo", "nuevas", "nuevos",
        "apunta", "apuntar", "apuntame", "agenda", "agendar", "agendame", "programa", "programar", "programame",
        "tengo", "incluye", "incluir", "organiza", "planifica", "planificar",
    ]
    private static let changeWords: Set<String> = [
        "cambia", "cambiar", "cambiala", "cambialo", "mueve", "mover", "muevela", "muevelo", "pasa", "pasar", "pasala", "pasalo",
        "adelanta", "adelantar", "adelantala", "adelantalo", "retrasa", "retrasar", "retrasala", "retrasalo", "atrasa", "atrasar",
        "borra", "borrar", "borrala", "borralo", "elimina", "eliminar", "eliminala", "eliminalo", "quita", "quitar", "quitala",
        "quitalo", "cancela", "cancelar", "renombra", "renombrar", "termine", "terminen", "empiece", "empiecen",
        "comience", "comiencen", "acabe", "dure", "duren", "prioriza", "priorizar", "deshaz", "deshacer", "mejor", "ponla",
        "ponlo", "dejala", "dejalo", "duplicado", "conserva", "manten", "alarga", "acorta", "amplia", "reduce",
    ]
    private static let conditionPhrases = [
        "nada despues", "nada antes", "nada a partir", "libre", "libres", "menos intens", "mas ligero", "mas tranquil",
        "mas relajad", "lo dificil", "lo mas dificil", "lo urgente", "primero lo urgente", "sin trabajar",
    ]
    private static let reorganizePhrases = [
        "reorganiza", "replanifica", "reparte de nuevo", "vuelve a repartir", "haz hueco", "hacer hueco", "hazme hueco",
        "adelanta trabajo", "adelantar trabajo", "ordena mi semana", "organiza mi semana", "organiza la semana",
    ]

    /// Lo que se deduce de las palabras, sin la IA. Vacío si no está claro.
    static func hints(_ text: String) -> RequestIntent {
        let words = ProposalText.words(text)
        let set = Set(words)
        let joined = " " + words.joined(separator: " ") + " "
        var intent = RequestIntent()
        intent.creates = !set.isDisjoint(with: createWords) || RequestCheck.expectedNewItems(in: text) != nil
        intent.changes = !set.isDisjoint(with: changeWords) || ProposalText.code(in: text) != nil
            || ProposalText.savedCode(in: text) != nil
        intent.conditions = conditionPhrases.contains { joined.contains(" " + $0) }
        intent.reorganize = reorganizePhrases.contains { joined.contains(" " + $0) }
        return intent
    }
}

/// Recortes para que el contexto quepa.
enum ContextBudget {
    /// Las líneas de lo guardado que hacen falta para esta petición: las que nombra (por
    /// título) y, hasta `limit`, las más próximas. Conserva el orden (y por tanto los códigos).
    static func relevant(lines: [String], titles: [String], request: String, limit: Int) -> [String] {
        guard lines.count > limit else { return lines }
        let query = ProposalText.keywords(request)
        let named = Set(titles.indices.filter { ProposalText.score(query: query, title: titles[$0]) > 0 })
        var chosen = named
        for index in lines.indices where chosen.count < limit && !chosen.contains(index) {
            chosen.insert(index)
        }
        return lines.indices.filter { chosen.contains($0) }.map { lines[$0] }
    }

    /// Como mucho `limit` caracteres, cortando por una línea entera si se puede.
    static func clip(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let cut = String(text.prefix(limit))
        if let newline = cut.lastIndex(of: "\n"), cut.distance(from: cut.startIndex, to: newline) > limit / 2 {
            return String(cut[..<newline]) + "\n…"
        }
        return cut + "…"
    }
}
