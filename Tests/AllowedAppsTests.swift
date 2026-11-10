import Foundation
import Testing

// Apps permitidas durante la concentración: salir a una de ellas no cuenta; pasarse del límite, sí.

private let left = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func judge(_ away: TimeInterval, authorized: Bool, limit: TimeInterval = 15 * 60) -> LeaveVerdict {
    LeaveVerdict.judge(leftAt: left, now: left.addingTimeInterval(away), grace: 15, authorized: authorized, limit: limit)
}

@Suite("Apps permitidas")
struct AllowedAppsTests {
    @Test func anAllowedAppDoesNotCount() {
        #expect(judge(10 * 60, authorized: true) == .fine)
        // Con «Sin límite», tampoco tras una hora.
        #expect(judge(3600, authorized: true, limit: 0) == .fine)
    }

    @Test func anyOtherAppCountsAfterTheGrace() {
        #expect(judge(10, authorized: false) == .fine)
        #expect(judge(120, authorized: false) == .distraction(seconds: 120, from: left))
    }

    @Test func onlyWhatGoesOverTheLimitCounts() {
        // 20 min en una app permitida con límite de 15: cuentan 5, desde el minuto 15.
        #expect(judge(20 * 60, authorized: true) == .distraction(seconds: 5 * 60, from: left.addingTimeInterval(15 * 60)))
        // Pasarse por unos segundos entra en el margen.
        #expect(judge(15 * 60 + 5, authorized: true) == .fine)
    }

    @Test func theCatalogIsUsable() {
        #expect(Set(AllowedApps.catalog.map(\.id)).count == AllowedApps.catalog.count)
        #expect(AllowedApps.catalog.allSatisfy { URL(string: $0.url) != nil && !$0.name.isEmpty })
    }

    @Test func appsWrittenByHand() {
        #expect(AllowedApps.normalizedURL("miapp") == "miapp://")
        #expect(AllowedApps.normalizedURL("miapp://abrir") == "miapp://abrir")
        #expect(AllowedApps.normalizedURL("mi app") == "")
        #expect(AllowedApps.normalizedURL("") == "")
        #expect(AllowedApps.makeCustom(name: "  ", scheme: "x") == nil)
        let app = AllowedApps.makeCustom(name: " Banco ", scheme: "")
        #expect(app?.name == "Banco" && app?.url == "")
        #expect(app?.id == AllowedApps.makeCustom(name: "banco", scheme: "otra")?.id)
    }
}
