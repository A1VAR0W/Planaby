import Foundation

/// Cómo se apuntó una captura.
enum CaptureSource: String, Codable, Sendable, CaseIterable {
    case text, voice, siri

    var title: String {
        switch self {
        case .text: "Escrita"
        case .voice: "Dictada"
        case .siri: "Con Siri"
        }
    }

    var symbol: String {
        switch self {
        case .text: "keyboard"
        case .voice: "mic.fill"
        case .siri: "waveform"
        }
    }
}

/// `pending`: por organizar. `planned`: ya es una tarea del plan. `done`: hecha sin planificarla.
enum CaptureStatus: String, Codable, Sendable {
    case pending, planned, done
}

/// Lo que la lógica necesita de una captura (sin SwiftData, para probarlo aparte).
struct CaptureEntry: Equatable, Sendable, Identifiable {
    var id: UUID
    var text: String
    var created: Date
    var modeRaw: String
    var status: CaptureStatus
    var sessionStart: Date?
    var taskID: UUID?
    var snoozedUntil: Date?
    var presentedAt: Date?
}

/// Reglas de la captura rápida: lógica pura, sin interfaz ni base de datos.
enum CaptureRules {
    static let maxLength = 280

    /// Texto listo para guardar, o nil si no hay nada que apuntar. Quita espacios y saltos de más,
    /// pone la primera letra en mayúscula y recorta lo excesivamente largo.
    static func clean(_ raw: String) -> String? {
        let words = raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        var text = words.joined(separator: " ")
        // Solo puntuación o símbolos («...», «-»): no es una tarea.
        guard text.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        if text.count > maxLength { text = String(text.prefix(maxLength)).trimmingCharacters(in: .whitespaces) + "…" }
        // «iPhone», «eBay»: si la segunda letra ya es mayúscula, se deja como está.
        let second = text.dropFirst().first
        if let first = text.first, first.isLowercase, second?.isUppercase != true {
            text = first.uppercased() + text.dropFirst()
        }
        return text
    }

    /// De qué sesión y fase viene una captura. Solo lee el estado: apuntar algo nunca toca el
    /// temporizador (ni pausa, ni salta, ni cambia la tarea de la sesión).
    static func origin(of state: TimerState?) -> (sessionStart: Date?, phase: String?) {
        guard let state else { return (nil, nil) }
        return (state.sessionStart, state.phase.isBreak ? "break" : "focus")
    }

    /// Por organizar ahora (sin las pospuestas).
    static func isPending(_ entry: CaptureEntry, now: Date) -> Bool {
        entry.status == .pending && (entry.snoozedUntil ?? .distantPast) <= now
    }

    /// Lo apuntado en una sesión que sigue por organizar.
    static func fromSession(_ entries: [CaptureEntry], sessionStart: Date, now: Date) -> [CaptureEntry] {
        entries.filter { isPending($0, now: now) && $0.sessionStart == sessionStart }
    }

    /// Lo apuntado desde `since` (p. ej. el bloque de concentración que acaba de terminar) que aún
    /// no se ha enseñado en un resumen.
    static func toSummarize(_ entries: [CaptureEntry], sessionStart: Date?, since: Date, now: Date) -> [CaptureEntry] {
        entries.filter {
            isPending($0, now: now) && $0.presentedAt == nil && $0.created >= since
                && (sessionStart == nil || $0.sessionStart == sessionStart)
        }
    }

    /// «Has apuntado 3 tareas».
    static func summary(count: Int, duringSession: Bool = false) -> String {
        let what = count == 1 ? "1 tarea" : "\(count) tareas"
        return duringSession ? "Has apuntado \(what) durante tu sesión" : "Has apuntado \(what)"
    }

    /// Enlaza la captura con la tarea creada. Si ya estaba planificada, no hace nada: así una
    /// captura nunca se convierte en dos tareas.
    /// `taskID` es nil si la propuesta aceptada era solo una cita (sin tarea).
    static func markPlanned(_ entry: inout CaptureEntry, taskID: UUID?) -> Bool {
        guard entry.status == .pending, entry.taskID == nil else { return false }
        entry.status = .planned
        entry.taskID = taskID
        return true
    }
}

/// Una captura en la copia de seguridad (opcional en las copias anteriores).
struct CaptureBackup: Codable, Equatable, Sendable {
    var uid: UUID
    var text: String
    var created: Date
    var modeRaw: String
    var statusRaw: String
    var sourceRaw: String
    var sessionStart: Date?
    var phaseRaw: String?
    var reviewedAt: Date?
    var convertedAt: Date?
    var taskID: UUID?
    var snoozedUntil: Date?
    var presentedAt: Date?
}

extension CaptureBackup {
    init(_ capture: CapturedTask) {
        self.init(
            uid: capture.uid, text: capture.text, created: capture.created, modeRaw: capture.modeRaw,
            statusRaw: capture.statusRaw, sourceRaw: capture.sourceRaw, sessionStart: capture.sessionStart,
            phaseRaw: capture.phaseRaw, reviewedAt: capture.reviewedAt, convertedAt: capture.convertedAt,
            taskID: capture.taskID, snoozedUntil: capture.snoozedUntil, presentedAt: capture.presentedAt
        )
    }

    /// Una captura nueva con los mismos datos (y el mismo identificador).
    func makeModel() -> CapturedTask {
        let capture = CapturedTask(
            text: text, mode: PlanMode(rawValue: modeRaw) ?? .personal,
            source: CaptureSource(rawValue: sourceRaw) ?? .text, sessionStart: sessionStart, phase: phaseRaw, created: created
        )
        capture.uid = uid
        capture.statusRaw = statusRaw
        capture.reviewedAt = reviewedAt
        capture.convertedAt = convertedAt
        capture.taskID = taskID
        capture.snoozedUntil = snoozedUntil
        capture.presentedAt = presentedAt
        return capture
    }
}

/// Pide abrir la captura rápida desde un control, un widget o un atajo. En la app se atiende al
/// momento; desde la extensión de widgets queda apuntado en el App Group para cuando se abra.
@MainActor
enum CaptureRequest {
    static var handler: ((Bool) -> Void)?
    private static let key = "captureRequested"

    /// `dictation`: empezar dictando.
    static func post(dictation: Bool = false) {
        if let handler {
            handler(dictation)
        } else {
            AppGroup.defaults.set(Date.now, forKey: key)
        }
    }

    /// Una petición de hace menos de un minuto (y la borra).
    static func consume(now: Date = .now) -> Bool {
        guard let date = AppGroup.defaults.object(forKey: key) as? Date else { return false }
        AppGroup.defaults.removeObject(forKey: key)
        return now.timeIntervalSince(date) < 60
    }
}
