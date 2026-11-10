import Foundation
import Testing

// Apps permitidas durante la concentración: salir con un pase no cuenta; lo que pase de él, sí.
// iOS no dice qué app se abre: lo que se prueba es la salida autorizada, no la app usada.

private let session = Date(timeIntervalSinceReferenceDate: 800_000_000)
/// Se toca la app a los 10 min de sesión y se sale 2 s después.
private let granted = session.addingTimeInterval(600)
private let left = granted.addingTimeInterval(2)

private func pass(_ minutes: Int = 15, app: String = "Teams") -> AllowedPass {
    AllowedPass(app: app, grantedAt: granted, minutes: minutes, session: session)
}

private func judge(_ away: TimeInterval, pass: AllowedPass?) -> LeaveVerdict {
    LeaveVerdict.judge(leftAt: left, now: left.addingTimeInterval(away), grace: 15, pass: pass)
}

private func scratch() -> UserDefaults {
    let name = "allowed-apps-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Suite("Apps permitidas")
struct AllowedAppsTests {
    @Test func openingTeamsOrOutlookDoesNotCount() {
        #expect(judge(10 * 60, pass: pass(app: "Teams")) == .fine)
        #expect(judge(10 * 60, pass: pass(app: "Outlook")) == .fine)
        // Volver antes de que acabe el pase: nada.
        #expect(judge(60, pass: pass(5)) == .fine)
    }

    @Test func anAppThatIsNotAllowedCountsAfterTheGrace() {
        #expect(judge(10, pass: nil) == .fine)
        #expect(judge(120, pass: nil) == .distraction(seconds: 120, from: left))
    }

    @Test func onlyWhatGoesOverThePassCounts() {
        // Pase de 15 min y 20 min fuera: cuenta lo que pasa del final del pase, desde ese momento.
        let expiry = granted.addingTimeInterval(15 * 60)
        let now = left.addingTimeInterval(20 * 60)
        #expect(judge(20 * 60, pass: pass(15)) == .distraction(seconds: now.timeIntervalSince(expiry), from: expiry))
        // Pasarse por unos segundos entra en el margen.
        #expect(judge(15 * 60 + 5, pass: pass(15)) == .fine)
    }

    @Test func theDurationOfThePassCanBeChanged() {
        #expect(AllowedApps.limitOptions == [5, 15, 30, 0])
        #expect(judge(10 * 60, pass: pass(5)) != .fine)
        #expect(judge(10 * 60, pass: pass(15)) == .fine)
        #expect(judge(25 * 60, pass: pass(30)) == .fine)
        // «Hasta terminar la sesión»: no caduca.
        #expect(pass(0).expiry == nil)
        #expect(judge(3 * 3600, pass: pass(0)) == .fine)
        #expect(AllowedApps.limitTitle(0) == "Hasta terminar la sesión")
        #expect(AllowedApps.limitTitle(15) == "15 min")
    }

    @Test func aPassDoesNotCoverALeaveAfterItExpired() {
        // Se sale cuando el pase de 5 min ya ha caducado: es una salida normal.
        let late = granted.addingTimeInterval(6 * 60)
        let verdict = LeaveVerdict.judge(leftAt: late, now: late.addingTimeInterval(120), grace: 15, pass: pass(5))
        #expect(verdict == .distraction(seconds: 120, from: late))
    }

    @Test func thePassEndsWithTheSession() {
        let now = granted.addingTimeInterval(60)
        #expect(pass(0).isValid(at: now, session: session))
        // La sesión terminó estando fuera, o es otra sesión: ya no vale.
        #expect(!pass(0).isValid(at: now, session: nil))
        #expect(!pass(0).isValid(at: now, session: session.addingTimeInterval(3600)))
        // Caducado.
        #expect(!pass(5).isValid(at: granted.addingTimeInterval(301), session: session))
        #expect(pass(5).remaining(at: granted.addingTimeInterval(60)) == 240)
    }

    @Test func thePassSurvivesARestart() {
        let defaults = scratch()
        #expect(AllowedPass.load(defaults: defaults) == nil)
        AllowedPass.save(pass(30, app: "Outlook"), defaults: defaults)
        #expect(AllowedPass.load(defaults: defaults) == pass(30, app: "Outlook"))
        AllowedPass.save(nil, defaults: defaults)
        #expect(AllowedPass.load(defaults: defaults) == nil)
    }

    @Test func eachPlanHasItsOwnApps() {
        let defaults = scratch()
        // Trabajo trae las de trabajar; Normal, ninguna.
        #expect(AllowedApps.chosen(.work, defaults: defaults).map(\.id) == ["teams", "outlook", "notes", "safari", "word"])
        #expect(AllowedApps.chosen(.personal, defaults: defaults).isEmpty)
        // Quitar y añadir en un plan no toca el otro.
        AllowedApps.setChosen(["teams", "slack"], for: .work, defaults: defaults)
        AllowedApps.setChosen(["notes"], for: .personal, defaults: defaults)
        #expect(AllowedApps.chosen(.work, defaults: defaults).map(\.id) == ["teams", "slack"])
        #expect(AllowedApps.chosen(.personal, defaults: defaults).map(\.id) == ["notes"])
        // Se pueden quitar todas.
        AllowedApps.setChosen([], for: .work, defaults: defaults)
        #expect(AllowedApps.chosen(.work, defaults: defaults).isEmpty)
    }

    @Test func aDurationThatNoLongerExistsFallsBackToTheDefault() {
        let defaults = scratch()
        #expect(AllowedApps.limit(defaults: defaults) == 15)
        defaults.set(30, forKey: AllowedApps.Keys.limit)
        #expect(AllowedApps.limit(defaults: defaults) == 30)
        defaults.set(60, forKey: AllowedApps.Keys.limit)
        #expect(AllowedApps.limit(defaults: defaults) == 15)
    }

    @Test func theCatalogIsUsable() {
        #expect(Set(AllowedApps.catalog.map(\.id)).count == AllowedApps.catalog.count)
        #expect(AllowedApps.catalog.allSatisfy { URL(string: $0.url) != nil && !$0.name.isEmpty })
        #expect(AllowedApps.workDefaults.allSatisfy { id in AllowedApps.catalog.contains { $0.id == id } })
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
        // Una app añadida a mano se elige en un plan como las demás.
        let defaults = scratch()
        if let app {
            AllowedApps.saveCustom([app], defaults: defaults)
            AllowedApps.setChosen([app.id, "teams"], for: .personal, defaults: defaults)
            #expect(AllowedApps.chosen(.personal, defaults: defaults).map(\.name) == ["Teams", "Banco"])
        }
    }
}
