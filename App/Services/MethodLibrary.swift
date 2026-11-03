import Foundation
import Observation

@Observable
@MainActor
final class MethodLibrary {
    private(set) var custom: [FocusMethod]
    var selectedID: String {
        didSet { AppGroup.defaults.set(selectedID, forKey: Keys.selected) }
    }

    var all: [FocusMethod] { FocusMethod.builtIns + custom }
    var selected: FocusMethod { all.first { $0.id == selectedID } ?? .pomodoro }

    private enum Keys {
        static let custom = "customMethods"
        static let selected = "selectedMethodID"
    }

    init() {
        let defaults = AppGroup.defaults
        custom = defaults.data(forKey: Keys.custom)
            .flatMap { try? JSONDecoder().decode([FocusMethod].self, from: $0) } ?? []
        selectedID = defaults.string(forKey: Keys.selected) ?? FocusMethod.pomodoro.id
    }

    func save(_ method: FocusMethod) {
        if let index = custom.firstIndex(where: { $0.id == method.id }) {
            custom[index] = method
        } else {
            custom.append(method)
        }
        persist()
    }

    func delete(_ method: FocusMethod) {
        custom.removeAll { $0.id == method.id }
        if selectedID == method.id { selectedID = FocusMethod.pomodoro.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(custom) {
            AppGroup.defaults.set(data, forKey: Keys.custom)
        }
    }
}
