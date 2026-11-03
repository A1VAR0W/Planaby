import SwiftData

@MainActor
enum PlanabyStore {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: FocusSessionRecord.self, CalendarEvent.self, PlanTask.self, TaskAttachment.self)
        } catch {
            fatalError("No se pudo abrir la base de datos: \(error)")
        }
    }()
}
