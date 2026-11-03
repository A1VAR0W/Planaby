import Foundation

/// Claves de los ajustes del usuario. Las del App Group también las leen los widgets y los intents.
enum Preferences {
    // App Group
    static let dailyGoalMinutes = "dailyGoalMinutes"
    static let phaseAlerts = "phaseAlerts"

    // Solo la app: modo escritorio
    static let deskDimmed = "deskDimmed"
    static let deskNightMode = "deskNightMode"
    static let deskNightStart = "deskNightStart"
    static let deskNightEnd = "deskNightEnd"
    static let deskKeepAwake = "deskKeepAwake"

    static let defaultDailyGoal = 120

    static var phaseAlertsEnabled: Bool {
        AppGroup.defaults.object(forKey: phaseAlerts) as? Bool ?? true
    }
}
