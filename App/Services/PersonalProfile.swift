import Foundation
import Observation
import SwiftData

/// Franjas del día que se usan en el test de ritmo.
enum DayPeriod: String, Codable, CaseIterable, Identifiable, Sendable {
    case earlyMorning, morning, midday, afternoon, evening

    var id: String { rawValue }

    var title: String {
        switch self {
        case .earlyMorning: "Primera hora"
        case .morning: "Mañana"
        case .midday: "Mediodía"
        case .afternoon: "Tarde"
        case .evening: "Noche"
        }
    }

    var hours: Range<Int> {
        switch self {
        case .earlyMorning: 6..<9
        case .morning: 9..<12
        case .midday: 12..<15
        case .afternoon: 15..<19
        case .evening: 19..<23
        }
    }

    var rangeText: String { "\(hours.lowerBound):00–\(hours.upperBound):00" }

    var symbol: String {
        switch self {
        case .earlyMorning: "sunrise.fill"
        case .morning: "sun.max.fill"
        case .midday: "sun.min.fill"
        case .afternoon: "sun.haze.fill"
        case .evening: "moon.stars.fill"
        }
    }
}

/// Respuestas del test de ritmo de concentración.
struct FocusProfile: Codable, Equatable, Sendable {
    var peaks: Set<DayPeriod> = [.morning]
    var lows: Set<DayPeriod> = [.midday]
    /// Cuánto aguanta concentrada la persona de un tirón.
    var blockMinutes = 50
    /// Prefiere empezar por lo difícil (o calentar con lo fácil).
    var hardFirst = true
    /// Ha terminado el test.
    var isCompleted = false
    /// Ya se le ofreció al abrir la app (aunque lo dejara para luego).
    var wasOffered = false

    /// Energía por hora según las respuestas: alta en los picos, baja en los valles y de madrugada.
    var energyByHour: [Double] {
        (0..<24).map { hour in
            if peaks.contains(where: { $0.hours.contains(hour) }) { return 1.0 }
            if lows.contains(where: { $0.hours.contains(hour) }) { return 0.2 }
            return (6..<23).contains(hour) ? 0.55 : 0.1
        }
    }
}

/// Lo que Planaby sabe de la persona: el test y lo aprendido de su historial. Ajusta el
/// planificador (horas de energía) y las estimaciones (si suele tardar más de lo previsto).
@Observable
@MainActor
final class PersonalProfile {
    static let shared = PersonalProfile()

    private(set) var profile: FocusProfile
    /// Minutos concentrados por hora del día en los últimos 30 días.
    private(set) var learnedMinutesByHour = Array(repeating: 0.0, count: 24)
    private(set) var learnedSessions = 0
    /// Tiempo real / estimado en tareas terminadas (1 = acierta).
    private(set) var estimateRatio = 1.0
    private(set) var estimateSamples = 0

    private static let key = "focusProfile"

    private init() {
        profile = AppGroup.defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(FocusProfile.self, from: $0) } ?? FocusProfile()
    }

    var shouldOfferTest: Bool { !profile.isCompleted && !profile.wasOffered }

    func save(_ newProfile: FocusProfile) {
        profile = newProfile
        if let data = try? JSONEncoder().encode(newProfile) {
            AppGroup.defaults.set(data, forKey: Self.key)
        }
    }

    func markOffered() {
        var copy = profile
        copy.wasOffered = true
        save(copy)
    }

    /// Mezcla las respuestas con lo aprendido: cuantas más sesiones, más pesa el historial (hasta la mitad).
    var energyByHour: [Double] {
        let base = profile.energyByHour
        let peak = learnedMinutesByHour.max() ?? 0
        guard peak > 0 else { return base }
        let weight = min(0.5, Double(learnedSessions) / 40)
        return (0..<24).map { hour in
            (1 - weight) * base[hour] + weight * learnedMinutesByHour[hour] / peak
        }
    }

    /// Las mejores horas, para explicarlas ("9–12 y 16–18").
    var bestHoursText: String {
        let energy = energyByHour
        let threshold = (energy.max() ?? 1) * 0.85
        var ranges: [Range<Int>] = []
        for hour in 0..<24 where energy[hour] >= threshold {
            if let last = ranges.last, last.upperBound == hour {
                ranges[ranges.count - 1] = last.lowerBound..<(hour + 1)
            } else {
                ranges.append(hour..<(hour + 1))
            }
        }
        return ranges.map { "\($0.lowerBound)–\($0.upperBound)" }.joined(separator: " y ")
    }

    /// Estimación corregida con lo que suele tardar de verdad, redondeada a 15 min.
    func adjustedEstimate(_ minutes: Int) -> Int {
        guard estimateSamples >= 2, abs(estimateRatio - 1) >= 0.1 else { return minutes }
        return max(15, Int((Double(minutes) * estimateRatio / 15).rounded()) * 15)
    }

    var estimateNote: String? {
        guard estimateSamples >= 2, abs(estimateRatio - 1) >= 0.1 else { return nil }
        let percent = Int((abs(estimateRatio - 1) * 100).rounded())
        return estimateRatio > 1
            ? "He sumado un \(percent) % a la estimación: sueles necesitar más tiempo del previsto."
            : "He restado un \(percent) % a la estimación: sueles terminar antes de lo previsto."
    }

    func planner() -> WorkloadPlanner {
        var planner = WorkloadPlanner()
        planner.energyByHour = energyByHour
        planner.hardFirst = profile.hardFirst
        return planner
    }

    /// Recalcula lo aprendido a partir de las sesiones y las tareas terminadas.
    func refresh(context: ModelContext, now: Date = .now) {
        let calendar = Calendar.current
        let sessions = (try? context.fetch(FetchDescriptor<FocusSessionRecord>())) ?? []

        let monthAgo = now.addingTimeInterval(-30 * 24 * 3600)
        var minutes = Array(repeating: 0.0, count: 24)
        var count = 0
        for session in sessions where session.start >= monthAgo {
            count += 1
            // Reparte la sesión por las horas que ocupó.
            var cursor = session.start
            while cursor < session.end {
                let hourEnd = calendar.dateInterval(of: .hour, for: cursor)?.end ?? session.end
                let pieceEnd = min(hourEnd, session.end)
                minutes[calendar.component(.hour, from: cursor)] += pieceEnd.timeIntervalSince(cursor) / 60
                cursor = pieceEnd
            }
        }
        learnedMinutesByHour = minutes
        learnedSessions = count

        let done = ((try? context.fetch(FetchDescriptor<PlanTask>())) ?? [])
            .filter { $0.isDone && $0.estimatedMinutes > 0 }
        let ratios: [Double] = done.compactMap { task in
            let actual = sessions
                .filter { $0.taskTitle == task.title && $0.start >= task.created }
                .reduce(0) { $0 + $1.focusedSeconds } / 60
            return actual >= 15 ? actual / Double(task.estimatedMinutes) : nil
        }.sorted()
        estimateSamples = ratios.count
        estimateRatio = ratios.isEmpty ? 1 : min(1.75, max(0.75, ratios[ratios.count / 2]))
    }
}
