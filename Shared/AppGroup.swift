import Foundation

enum AppGroup {
    static let defaultID = "group.com.alvaro.planaby"

    /// SideStore reescribe los App Groups al firmar con una cuenta gratuita y deja los IDs reales en `ALTAppGroups`.
    static var id: String {
        (Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String])?.first ?? defaultID
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }
}
