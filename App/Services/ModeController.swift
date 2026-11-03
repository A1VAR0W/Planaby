import Foundation
import Observation
import WidgetKit

/// Modo actual (Trabajo o Normal) y franjas disponibles de cada uno. Se guarda en el App Group.
@Observable
@MainActor
final class ModeController {
    static let shared = ModeController()

    enum Source: String { case manual, focus }

    private(set) var mode: PlanMode
    private(set) var source: Source
    private(set) var schedules: [PlanMode: Availability]

    private enum Keys {
        static let mode = "planMode"
        static let source = "planModeSource"
        static func schedule(_ mode: PlanMode) -> String { "planSchedule.\(mode.rawValue)" }
    }

    private init() {
        let defaults = AppGroup.defaults
        mode = defaults.string(forKey: Keys.mode).flatMap(PlanMode.init(rawValue:)) ?? .personal
        source = defaults.string(forKey: Keys.source).flatMap(Source.init(rawValue:)) ?? .manual
        var schedules: [PlanMode: Availability] = [:]
        for mode in PlanMode.allCases {
            schedules[mode] = defaults.data(forKey: Keys.schedule(mode))
                .flatMap { try? JSONDecoder().decode(Availability.self, from: $0) }
                ?? (mode == .work ? .work : .personal)
        }
        self.schedules = schedules
    }

    func set(_ newMode: PlanMode, source newSource: Source = .manual) {
        source = newSource
        AppGroup.defaults.set(newSource.rawValue, forKey: Keys.source)
        guard newMode != mode else { return }
        mode = newMode
        AppGroup.defaults.set(newMode.rawValue, forKey: Keys.mode)
        ReminderScheduler.shared.reschedule()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func availability(for mode: PlanMode) -> Availability {
        schedules[mode] ?? (mode == .work ? .work : .personal)
    }

    func setAvailability(_ availability: Availability, for mode: PlanMode) {
        schedules[mode] = availability
        if let data = try? JSONEncoder().encode(availability) {
            AppGroup.defaults.set(data, forKey: Keys.schedule(mode))
        }
    }
}
