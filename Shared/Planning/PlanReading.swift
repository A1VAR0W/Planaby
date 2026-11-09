import Foundation

// Lo que la IA entiende de una petición, igual venga de Apple Intelligence (formatos @Generable)
// o del modelo local (JSON). Después pasa por las mismas comprobaciones deterministas.

struct ReadEvent: Equatable, Sendable {
    var title = ""
    var day = ""
    var time = ""
    var endTime = ""
    var endsNextDay = false
    var durationMinutes = 0
    var mode = "unknown"
    var reminderMinutes = 15
    var repeats = "none"
}

struct ReadTask: Equatable, Sendable {
    var title = ""
    var deadline = ""
    var estimatedMinutes = 60
    var difficulty = 3
    var mode = "unknown"
    var priority = 1
}

struct PlanReading: Equatable, Sendable {
    var offTopic = false
    var requestedCount = 0
    var events: [ReadEvent] = []
    var tasks: [ReadTask] = []
    var edits: [ProposalEditFields] = []
    var conditions: [ProposalConditionFields] = []
    var reorganize = false
    var prioritize: [String] = []
    var question = ""

    // MARK: JSON del modelo local

    /// Lee la respuesta del modelo local. Tolera lo habitual en modelos pequeños: texto o
    /// razonamiento antes del JSON, bloques ```json, comas sobrantes, números como texto y campos
    /// que faltan. nil si no hay un objeto JSON legible.
    static func parse(json text: String) -> PlanReading? {
        guard let object = jsonObject(in: text) else { return nil }
        var reading = PlanReading()
        reading.offTopic = bool(object["offTopic"]) ?? false
        reading.requestedCount = min(30, max(0, int(object["requestedCount"]) ?? 0))
        reading.reorganize = bool(object["reorganize"]) ?? false
        reading.question = string(object["question"]) ?? ""
        reading.prioritize = (object["prioritize"] as? [Any] ?? []).compactMap(string).filter { !$0.isEmpty }

        for entry in dictionaries(object["events"]) {
            guard let title = string(entry["title"]), !title.isEmpty else { continue }
            var event = ReadEvent(title: title)
            event.day = string(entry["day"]) ?? ""
            event.time = string(entry["time"]) ?? ""
            event.endTime = string(entry["endTime"]) ?? ""
            event.endsNextDay = bool(entry["endsNextDay"]) ?? false
            event.durationMinutes = min(720, max(0, int(entry["durationMinutes"]) ?? 0))
            event.mode = choice(entry["mode"], in: ["work", "personal"]) ?? "unknown"
            event.reminderMinutes = min(1440, max(0, int(entry["reminderMinutes"]) ?? 15))
            event.repeats = choice(entry["repeats"], in: ["none", "weekdays", "daily", "weekly"]) ?? "none"
            reading.events.append(event)
        }
        for entry in dictionaries(object["tasks"]) {
            guard let title = string(entry["title"]), !title.isEmpty else { continue }
            var task = ReadTask(title: title)
            task.deadline = string(entry["deadline"]) ?? ""
            task.estimatedMinutes = min(12000, max(15, int(entry["estimatedMinutes"]) ?? 60))
            task.difficulty = min(5, max(1, int(entry["difficulty"]) ?? 3))
            task.mode = choice(entry["mode"], in: ["work", "personal"]) ?? "unknown"
            task.priority = min(2, max(0, int(entry["priority"]) ?? 1))
            reading.tasks.append(task)
        }
        for entry in dictionaries(object["edits"]) {
            guard let target = string(entry["target"]), !target.isEmpty else { continue }
            var edit = ProposalEditFields()
            edit.action = choice(entry["action"], in: ["update", "delete", "remove", "first", "undo"]) ?? "update"
            edit.target = target
            edit.title = string(entry["title"]) ?? ""
            edit.day = string(entry["day"]) ?? ""
            edit.time = string(entry["time"]) ?? ""
            edit.endTime = string(entry["endTime"]) ?? ""
            edit.minutes = max(0, int(entry["minutes"]) ?? 0)
            edit.deadline = string(entry["deadline"]) ?? ""
            edit.priority = int(entry["priority"]) ?? -1
            edit.difficulty = int(entry["difficulty"]) ?? 0
            edit.mode = choice(entry["mode"], in: ["work", "personal"]) ?? ""
            edit.repeats = choice(entry["repeats"], in: ["none", "weekdays", "daily", "weekly"]) ?? ""
            edit.reminderMinutes = int(entry["reminderMinutes"]) ?? -1
            edit.workDay = string(entry["workDay"]) ?? ""
            edit.startShift = min(720, max(-720, int(entry["startShift"]) ?? 0))
            edit.keepEnd = bool(entry["keepEnd"]) ?? false
            edit.endsNextDay = bool(entry["endsNextDay"]) ?? false
            reading.edits.append(edit)
        }
        for entry in dictionaries(object["conditions"]) {
            guard let kind = choice(entry["kind"], in: ["free", "latestEnd", "earliestStart", "lighter", "hardMorning", "urgentFirst"])
            else { continue }
            reading.conditions.append(ProposalConditionFields(
                kind: kind, day: string(entry["day"]) ?? "", from: string(entry["from"]) ?? "", to: string(entry["to"]) ?? ""
            ))
        }
        return reading
    }

    /// El primer objeto JSON del texto.
    static func jsonObject(in text: String) -> [String: Any]? {
        var value = text
        // Razonamiento de los modelos que «piensan» antes de responder.
        while let open = value.range(of: "<think>") {
            let close = value.range(of: "</think>", range: open.upperBound..<value.endIndex)
            value.removeSubrange(open.lowerBound..<(close?.upperBound ?? value.endIndex))
        }
        guard let start = value.firstIndex(of: "{"), let end = value.lastIndex(of: "}"), start < end else { return nil }
        var candidate = String(value[start...end])
        // Comas antes de cerrar ({"a": 1,} o [1, 2,]).
        candidate = candidate.replacingOccurrences(of: #",\s*([}\]])"#, with: "$1", options: .regularExpression)
        guard let data = candidate.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    private static func dictionaries(_ value: Any?) -> [[String: Any]] {
        (value as? [Any] ?? []).compactMap { $0 as? [String: Any] }
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String: text.trimmingCharacters(in: .whitespacesAndNewlines)
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }

    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: number.intValue
        case let text as String: Int(text.trimmingCharacters(in: .whitespaces))
        default: nil
        }
    }

    private static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let flag as Bool: flag
        case let text as String: ["true", "si", "sí", "yes", "1"].contains(text.lowercased())
        default: nil
        }
    }

    /// El valor si es una de las opciones (sin distinguir mayúsculas); nil si no.
    private static func choice(_ value: Any?, in options: [String]) -> String? {
        guard let text = string(value) else { return nil }
        return options.first { $0.caseInsensitiveCompare(text) == .orderedSame }
    }
}
