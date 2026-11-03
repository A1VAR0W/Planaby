import Foundation

/// Cifras de progreso calculadas a partir del historial.
struct FocusStats {
    struct Day: Identifiable {
        let date: Date
        let seconds: TimeInterval
        var id: Date { date }
        var minutes: Double { seconds / 60 }
    }

    struct MethodShare: Identifiable {
        let name: String
        let seconds: TimeInterval
        var id: String { name }
    }

    let today: TimeInterval
    let todaySessions: Int
    let lastSevenDays: [Day]
    let weekTotal: TimeInterval
    /// Días seguidos con alguna sesión, contando hasta hoy (o hasta ayer si hoy aún no hay).
    let streak: Int
    let topMethods: [MethodShare]
    let averageSession: TimeInterval

    init(sessions: [FocusSessionRecord], now: Date = .now, calendar: Calendar = .current) {
        var byDay: [Date: TimeInterval] = [:]
        for session in sessions {
            byDay[calendar.startOfDay(for: session.start), default: 0] += session.focusedSeconds
        }

        let todayStart = calendar.startOfDay(for: now)
        today = byDay[todayStart] ?? 0
        todaySessions = sessions.filter { calendar.isDate($0.start, inSameDayAs: now) }.count

        lastSevenDays = (0..<7).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: todayStart).map { Day(date: $0, seconds: byDay[$0] ?? 0) }
        }
        weekTotal = lastSevenDays.reduce(0) { $0 + $1.seconds }

        var streak = 0
        var day: Date? = byDay[todayStart] != nil ? todayStart : calendar.date(byAdding: .day, value: -1, to: todayStart)
        while let current = day, byDay[current] != nil {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: current)
        }
        self.streak = streak

        let weekStart = lastSevenDays.first?.date ?? todayStart
        var byMethod: [String: TimeInterval] = [:]
        for session in sessions where session.start >= weekStart {
            byMethod[session.methodName, default: 0] += session.focusedSeconds
        }
        topMethods = byMethod
            .map { MethodShare(name: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
            .prefix(4)
            .map { $0 }

        averageSession = sessions.isEmpty ? 0 : sessions.reduce(0) { $0 + $1.focusedSeconds } / Double(sessions.count)
    }

    /// "1 h 20 min", "45 min"; por debajo de un minuto, "0 min".
    static func format(_ seconds: TimeInterval) -> String {
        guard seconds >= 60 else { return "0 min" }
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
