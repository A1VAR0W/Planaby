import Foundation
import SwiftData

@Model
final class FocusSessionRecord {
    var start: Date
    var end: Date
    var methodName: String
    var focusedSeconds: Double
    var completedCycles: Int
    /// Tarea en la que se trabajó, si la sesión empezó desde un bloque o un aviso.
    var taskTitle: String? = nil

    init(_ session: CompletedSession) {
        start = session.start
        end = session.end
        methodName = session.methodName
        focusedSeconds = session.focusedSeconds
        completedCycles = session.completedCycles
        taskTitle = session.taskTitle
    }
}
