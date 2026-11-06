import Foundation
import SwiftData

/// Algo apuntado deprisa («Captura rápida») para organizarlo después. No es todavía una tarea:
/// no tiene fecha límite, duración ni bloques, para no inventar nada. Al planificarla se crea la
/// tarea normal y esta captura queda enlazada a ella (`taskID`), así nunca se duplica.
@Model
final class CapturedTask {
    var uid: UUID = UUID()
    /// Lo escrito o dictado, tal cual (ya limpio de espacios).
    var text: String = ""
    var created: Date = Date.now
    /// Plan sugerido (el actual al apuntarlo); se puede cambiar.
    var modeRaw: String = PlanMode.personal.rawValue
    var statusRaw: String = CaptureStatus.pending.rawValue
    var sourceRaw: String = CaptureSource.text.rawValue
    /// Inicio de la sesión de concentración en la que se apuntó (identifica la sesión).
    var sessionStart: Date?
    /// Fase en la que se apuntó: "focus", "break" o nil sin sesión.
    var phaseRaw: String?
    var reviewedAt: Date?
    var convertedAt: Date?
    /// La tarea creada al planificarla (`PlanTask.uid`).
    var taskID: UUID?
    var snoozedUntil: Date?
    /// Cuándo se enseñó el resumen «Has apuntado…», para no repetirlo.
    var presentedAt: Date?

    init(text: String, mode: PlanMode, source: CaptureSource, sessionStart: Date? = nil, phase: String? = nil, created: Date = .now) {
        self.text = text
        modeRaw = mode.rawValue
        sourceRaw = source.rawValue
        self.sessionStart = sessionStart
        phaseRaw = phase
        self.created = created
    }

    var mode: PlanMode {
        get { PlanMode(rawValue: modeRaw) ?? .personal }
        set { modeRaw = newValue.rawValue }
    }

    var status: CaptureStatus {
        get { CaptureStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var source: CaptureSource { CaptureSource(rawValue: sourceRaw) ?? .text }

    var entry: CaptureEntry {
        CaptureEntry(
            id: uid, text: text, created: created, modeRaw: modeRaw, status: status, sessionStart: sessionStart,
            taskID: taskID, snoozedUntil: snoozedUntil, presentedAt: presentedAt
        )
    }
}
