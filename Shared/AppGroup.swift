import Foundation

enum AppGroup {
    static let defaultID = "group.com.alvaro.planaby"

    /// SideStore reescribe los App Groups al firmar con una cuenta gratuita y deja los IDs reales en `ALTAppGroups`.
    /// En la extensión de widgets se busca también en el Info.plist de la app contenedora.
    static var id: String {
        let containingApp = Bundle(url: Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent())
        for bundle in [Bundle.main, containingApp].compactMap({ $0 }) {
            if let groups = bundle.object(forInfoDictionaryKey: "ALTAppGroups") as? [String], let first = groups.first {
                return first
            }
        }
        return defaultID
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }
}
