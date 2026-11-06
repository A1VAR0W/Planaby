import Foundation

/// Reglas del filtro de mensajes que no dependen de la IA: remitentes prioritarios, lo aprendido
/// de las correcciones a mano y el criterio de «urgente». Lógica pura para poder probarla.
struct TriageRules: Equatable, Sendable {
    /// Nombres, teléfonos o correos (en minúsculas) que siempre merecen al menos «Importante».
    var prioritySenders: [String] = []
    /// Remitente → categoría elegida a mano («Mover a…» en la bandeja).
    var overrides: [String: String] = [:]

    /// Clave de un remitente: el correo si lo hay («Ana <ana@x.com>» → «ana@x.com»); si no, el nombre.
    static func senderKey(_ sender: String) -> String {
        let text = sender.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let open = text.lastIndex(of: "<"), let close = text.lastIndex(of: ">"), open < close {
            let email = text[text.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
            if !email.isEmpty { return email }
        }
        return text
    }

    func isPriority(_ sender: String) -> Bool {
        let key = Self.senderKey(sender)
        let full = sender.lowercased()
        guard !key.isEmpty else { return false }
        return prioritySenders.contains { wanted in
            let clean = wanted.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !clean.isEmpty && (key == clean || full.contains(clean))
        }
    }

    func override(for sender: String) -> MessageCategory? {
        overrides[Self.senderKey(sender)].flatMap(MessageCategory.init(rawValue:))
    }

    mutating func learn(sender: String, category: MessageCategory) {
        let key = Self.senderKey(sender)
        guard !key.isEmpty else { return }
        overrides[key] = category.rawValue
    }

    /// Hay un motivo concreto o un plazo de horas (no basta con escribir «urgente»).
    static func hasConcreteUrgency(_ text: String) -> Bool {
        let lower = text.lowercased()
        let cues = [
            "emergencia", "hospital", "accidente", "llámame", "llamame", "llama ya", "ahora mismo",
            "en una hora", "en media hora", "antes de las", "hoy antes", "esta mañana", "esta tarde", "esta noche",
            "se ha caído", "no funciona", "bloqueado", "te estoy esperando", "estoy esperando", "vence hoy", "hoy a las",
        ]
        return cues.contains { lower.contains($0) }
    }

    /// Corrige lo que dice la IA con las reglas de la persona.
    func adjust(_ category: MessageCategory, sender: String, text: String) -> MessageCategory {
        if let chosen = override(for: sender) { return chosen }
        let priority = isPriority(sender)
        if category == .urgent, !priority, !Self.hasConcreteUrgency(text) { return .important }
        if priority, category == .later || category == .noise { return .important }
        return category
    }

    /// Sin IA: reglas sencillas.
    func heuristic(fromMessages: Bool, sender: String, subject: String, body: String) -> MessageCategory {
        if let chosen = override(for: sender) { return chosen }
        let text = "\(sender) \(subject) \(body)".lowercased()
        let noise = ["noreply", "no-reply", "newsletter", "unsubscribe", "darse de baja", "oferta", "promo", "código de verificación", "verification code"]
        if noise.contains(where: { text.contains($0) }), !isPriority(sender) { return .noise }
        if Self.hasConcreteUrgency(text) { return .urgent }
        let urgentWord = ["urgente", "urgent", "asap", "cuanto antes"].contains { text.contains($0) }
        if urgentWord { return isPriority(sender) ? .urgent : .important }
        if isPriority(sender) { return .important }
        return fromMessages ? .important : .later
    }
}
