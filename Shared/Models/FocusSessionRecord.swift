import Foundation
import SwiftData

@Model
final class FocusSessionRecord {
    var start: Date
    var end: Date
    var methodName: String
    var focusedSeconds: Double
    var completedCycles: Int

    init(_ session: CompletedSession) {
        start = session.start
        end = session.end
        methodName = session.methodName
        focusedSeconds = session.focusedSeconds
        completedCycles = session.completedCycles
    }
}
