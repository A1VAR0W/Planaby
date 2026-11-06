import Foundation
import SwiftData

/// Una sesión terminada. Los campos con valor por defecto se añadieron después: SwiftData los
/// migra solo (las sesiones antiguas los tienen a cero o vacíos).
@Model
final class FocusSessionRecord {
    var start: Date
    var end: Date
    var methodName: String
    var focusedSeconds: Double
    var completedCycles: Int
    /// Tarea en la que se trabajó, si la sesión empezó desde un bloque o un aviso.
    var taskTitle: String? = nil
    /// Identificador estable de la tarea (PlanTask.uid); el título queda para mostrarlo.
    var taskID: UUID? = nil
    var methodID: String = ""
    /// Plan en el que se trabajó ("work" o "personal"); vacío en sesiones antiguas.
    var modeRaw: String = ""
    var plannedFocusMinutes: Int = 0
    /// Se terminó en mitad de una concentración.
    var endedEarly: Bool = false
    var abandonedAfterMinutes: Double = 0
    var pauseCount: Int = 0
    var leaveCount: Int = 0
    var awaySeconds: Double = 0
    var skippedBreaks: Int = 0
    var isStarter: Bool = false
    /// Valoración opcional al terminar: 0 sin valorar; 1 disperso, 2 normal, 3 muy centrado.
    var focusRating: Int = 0

    init(_ session: CompletedSession) {
        start = session.start
        end = session.end
        methodName = session.methodName
        focusedSeconds = session.focusedSeconds
        completedCycles = session.completedCycles
        taskTitle = session.taskTitle
        taskID = session.taskID
        methodID = session.methodID
        modeRaw = session.mode
        plannedFocusMinutes = session.plannedFocusMinutes
        endedEarly = session.endedEarly
        abandonedAfterMinutes = session.abandonedAfterMinutes
        pauseCount = session.pauses
        leaveCount = session.leaves
        awaySeconds = session.awaySeconds
        skippedBreaks = session.skippedBreaks
        isStarter = session.isStarter
    }

    /// Lo que necesita el motor de atención.
    var sample: SessionSample {
        SessionSample(
            start: start, mode: modeRaw, methodID: methodID.isEmpty ? methodName : methodID,
            plannedFocusMinutes: plannedFocusMinutes, focusedMinutes: focusedSeconds / 60,
            completedCycles: completedCycles, endedEarly: endedEarly, abandonedAfterMinutes: abandonedAfterMinutes,
            pauses: pauseCount, leaves: leaveCount, skippedBreaks: skippedBreaks, focusRating: focusRating
        )
    }
}
