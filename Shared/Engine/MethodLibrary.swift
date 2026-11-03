import Foundation
import Observation
import WidgetKit

@Observable
@MainActor
final class MethodLibrary {
    static let shared = MethodLibrary()

    private(set) var custom: [FocusMethod]
    var selectedID: String {
        didSet {
            AppGroup.defaults.set(selectedID, forKey: Keys.selected)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    var all: [FocusMethod] { FocusMethod.builtIns + custom }
    var selected: FocusMethod { all.first { $0.id == selectedID } ?? .pomodoro }

    private enum Keys {
        static let custom = "customMethods"
        static let selected = "selectedMethodID"
    }

    private init() {
        custom = Self.loadCustom()
        selectedID = AppGroup.defaults.string(forKey: Keys.selected) ?? FocusMethod.pomodoro.id
    }

    /// Método seleccionado leído directamente del App Group, para widgets y extensiones.
    nonisolated static func storedSelection() -> FocusMethod {
        let id = AppGroup.defaults.string(forKey: Keys.selected)
        return (FocusMethod.builtIns + loadCustom()).first { $0.id == id } ?? .pomodoro
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

    private nonisolated static func loadCustom() -> [FocusMethod] {
        AppGroup.defaults.data(forKey: Keys.custom)
            .flatMap { try? JSONDecoder().decode([FocusMethod].self, from: $0) } ?? []
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(custom) {
            AppGroup.defaults.set(data, forKey: Keys.custom)
        }
    }
}
