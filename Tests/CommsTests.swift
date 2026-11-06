import Foundation
import Testing

private func entry(
    _ app: CommApp, _ category: MessageCategory, sender: String = "Jonatan", summary: String = "necesita revisar un documento",
    needsReply: Bool = false, received: Date = Date(timeIntervalSince1970: 1_000_000), priority: Bool = false,
    reviewed: Bool = false, replied: Bool = false, snoozedUntil: Date? = nil, presentedAt: Date? = nil, id: String = UUID().uuidString
) -> CommEntry {
    CommEntry(
        id: id, app: app, appName: app.title, sender: sender, summary: summary, category: category,
        needsReply: needsReply, received: received, isPriority: priority, reviewed: reviewed, replied: replied,
        snoozedUntil: snoozedUntil, presentedAt: presentedAt
    )
}

private let now = Date(timeIntervalSince1970: 1_000_000 + 3_600)

@Suite("Apps y notificaciones")
struct CommAppTests {
    @Test func identifiesAppsByBundleOrName() {
        #expect(CommApp.identify(bundleID: "com.microsoft.skype.teams", appName: nil) == .teams)
        #expect(CommApp.identify(bundleID: "NET.WHATSAPP.WHATSAPP", appName: nil) == .whatsapp)
        #expect(CommApp.identify(bundleID: nil, appName: "Microsoft Outlook") == .outlook)
        #expect(CommApp.identify(bundleID: "", appName: "Mensajes") == .messages)
        #expect(CommApp.identify(bundleID: "com.desconocida.app", appName: "Slack") == .other)
        #expect(CommApp.identify(bundleID: nil, appName: nil) == .other)
    }

    @Test func chatTitleIsTheSender() {
        let note = NotificationPayload(appName: "WhatsApp", title: "Mamá", body: "¿Vienes a cenar?").normalized(now: now)
        #expect(note.app == .whatsapp)
        #expect(note.sender == "Mamá")
        #expect(note.subject.isEmpty)
        #expect(note.body == "¿Vienes a cenar?")
        #expect(note.received == now)
    }

    @Test func mailSubtitleIsTheSubject() {
        let note = NotificationPayload(
            bundleID: "com.microsoft.Office.Outlook", title: "Ana López", subtitle: "Informe trimestral", body: "Te lo paso"
        ).normalized(now: now)
        #expect(note.app == .outlook)
        #expect(note.sender == "Ana López")
        #expect(note.subject == "Informe trimestral")
    }

    @Test func explicitSenderKeepsTheTitleAsSubject() {
        let note = NotificationPayload(appName: "Teams", sender: "Jonatan", title: "Equipo Ventas", body: "Hola").normalized(now: now)
        #expect(note.sender == "Jonatan")
        #expect(note.subject == "Equipo Ventas")
    }

    @Test func missingFieldsDoNotCrash() {
        let note = NotificationPayload().normalized(now: now)
        #expect(note.app == .other)
        #expect(note.appName == "Notificación")
        #expect(note.sender.isEmpty && note.subject.isEmpty && note.body.isEmpty)
    }

    @Test func fingerprintIsStableAndDistinct() {
        let a = NotificationPayload(appName: "Teams", title: "Jonatan", body: "Revisa el doc", date: now)
        #expect(a.normalized().fingerprint == a.normalized().fingerprint)
        var b = a
        b.body = "Otra cosa"
        #expect(a.normalized().fingerprint != b.normalized().fingerprint)
        #expect(a.normalized().fingerprint.hasPrefix("notif:"))
    }

    @Test func noiseIsCalledIrrelevant() {
        #expect(MessageCategory.noise.title == "Irrelevante")
    }
}

@Suite("Necesita respuesta")
struct NeedsReplyTests {
    @Test func questionsAndRequestsNeedReply() {
        #expect(CommPolicy.needsReply(sender: "Jonatan", subject: "", body: "¿Puedes revisar el documento?", category: .important))
        #expect(CommPolicy.needsReply(sender: "Ana", subject: "", body: "Confírmame la hora de mañana", category: .later))
        #expect(CommPolicy.needsReply(sender: "Boss", subject: "", body: "Let me know when it's done", category: .important))
    }

    @Test func informationAndAutomaticDoNotNeedReply() {
        #expect(!CommPolicy.needsReply(sender: "Ana", subject: "", body: "Ya he llegado a casa", category: .later))
        #expect(!CommPolicy.needsReply(sender: "noreply@banco.es", subject: "¿Conoces nuestras ofertas?", body: "", category: .later))
        #expect(!CommPolicy.needsReply(sender: "Tienda", subject: "", body: "¿Te lo vas a perder?", category: .noise))
    }
}

@Suite("Política de comunicaciones")
struct CommPolicyTests {
    let settings = CommSettings()

    @Test func defaultWorkAppsAreTeamsAndOutlook() {
        #expect(CommSettings().workApps == [.teams, .outlook])
    }

    @Test func focusShowsOnlyImportantWork() {
        #expect(CommPolicy.showsDuringFocus(entry(.teams, .important), settings: settings, now: now))
        #expect(CommPolicy.showsDuringFocus(entry(.outlook, .urgent), settings: settings, now: now))
        #expect(!CommPolicy.showsDuringFocus(entry(.teams, .later, needsReply: true), settings: settings, now: now))
        #expect(!CommPolicy.showsDuringFocus(entry(.whatsapp, .important), settings: settings, now: now))
        #expect(!CommPolicy.showsDuringFocus(entry(.instagram, .urgent), settings: settings, now: now))
    }

    @Test func personalExceptionsAndPriorityUrgent() {
        var custom = settings
        custom.focusExceptions = [.whatsapp]
        #expect(CommPolicy.showsDuringFocus(entry(.whatsapp, .important), settings: custom, now: now))
        #expect(CommPolicy.showsDuringFocus(entry(.messages, .urgent, priority: true), settings: settings, now: now))
        #expect(!CommPolicy.showsDuringFocus(entry(.messages, .important, priority: true), settings: settings, now: now))
        custom.priorityUrgentBypass = false
        #expect(!CommPolicy.showsDuringFocus(entry(.messages, .urgent, priority: true), settings: custom, now: now))
    }

    @Test func reviewedRepliedAndSnoozedAreNotPending() {
        #expect(!CommPolicy.isPending(entry(.teams, .important, reviewed: true), now: now))
        #expect(!CommPolicy.isPending(entry(.teams, .important, replied: true), now: now))
        #expect(!CommPolicy.isPending(entry(.teams, .important, snoozedUntil: now.addingTimeInterval(60)), now: now))
        #expect(CommPolicy.isPending(entry(.teams, .important, snoozedUntil: now.addingTimeInterval(-60)), now: now))
        #expect(!CommPolicy.isPending(entry(.whatsapp, .noise), now: now))
        #expect(CommPolicy.isPending(entry(.whatsapp, .later, needsReply: true), now: now))
        #expect(!CommPolicy.isPending(entry(.whatsapp, .later), now: now))
    }

    @Test func breakShowsWhatWasHeld() {
        let entries = [
            entry(.teams, .important), entry(.whatsapp, .important), entry(.whatsapp, .later, needsReply: true),
            entry(.instagram, .noise),
        ]
        #expect(CommPolicy.visible(entries, phase: .focus, settings: settings, now: now).count == 1)
        #expect(CommPolicy.visible(entries, phase: .rest, settings: settings, now: now).count == 3)
        #expect(CommPolicy.heldForBreak(entries, settings: settings, now: now).count == 2)
        let breakdown = CommPolicy.breakdown(CommPolicy.visible(entries, phase: .rest, settings: settings, now: now))
        #expect(breakdown.map(\.app) == ["WhatsApp", "Teams"])
        #expect(breakdown.map(\.count) == [2, 1])
    }

    @Test func urgentAndRecentFirst() {
        let old = entry(.teams, .important, received: Date(timeIntervalSince1970: 100))
        let recent = entry(.teams, .important, received: Date(timeIntervalSince1970: 200))
        let urgent = entry(.outlook, .urgent, received: Date(timeIntervalSince1970: 50))
        let sorted = CommPolicy.visible([old, recent, urgent], phase: .idle, settings: settings, now: now)
        #expect(sorted.map(\.id) == [urgent.id, recent.id, old.id])
    }

    @Test func awayDigestOnlyNewAndUnpresented() {
        let last = Date(timeIntervalSince1970: 1_000_000)
        let before = entry(.teams, .important, received: last.addingTimeInterval(-10))
        let after = entry(.teams, .important, received: last.addingTimeInterval(10))
        let shown = entry(.outlook, .important, received: last.addingTimeInterval(20), presentedAt: last.addingTimeInterval(30))
        let personal = entry(.whatsapp, .important, received: last.addingTimeInterval(40))
        let entries = [before, after, shown, personal]
        let focus = CommPolicy.awayDigest(entries, lastPresented: last, phase: .focus, settings: settings, now: now)
        #expect(focus.map(\.id) == [after.id])
        let rest = CommPolicy.awayDigest(entries, lastPresented: last, phase: .rest, settings: settings, now: now)
        #expect(Set(rest.map(\.id)) == [after.id, personal.id])
        // Sin presentaciones previas, todo lo pendiente cuenta.
        #expect(CommPolicy.awayDigest(entries, lastPresented: nil, phase: .idle, settings: settings, now: now).count == 3)
    }

    @Test func lineNamesAppAndSender() {
        #expect(CommPolicy.line(entry(.teams, .important, summary: "necesita revisar un documento"))
            == "Teams — Jonatan: necesita revisar un documento.")
        #expect(CommPolicy.line(entry(.teams, .important, summary: "Jonatan necesita que revises un documento"))
            == "Teams — Jonatan necesita que revises un documento.")
        #expect(CommPolicy.line(entry(.whatsapp, .later, sender: "", summary: "", needsReply: true))
            == "WhatsApp — espera respuesta.")
    }

    @Test func settingsRoundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "planaby.tests.\(UUID().uuidString)"))
        var custom = CommSettings()
        custom.workApps = [.gmail]
        custom.focusExceptions = [.whatsapp]
        custom.save(to: defaults)
        #expect(CommSettings.load(from: defaults) == custom)
    }
}

@Suite("Recuento sin textos")
struct CommsSnapshotTests {
    @Test func textsPerPhase() {
        let entries = [entry(.teams, .important), entry(.outlook, .urgent), entry(.whatsapp, .important)]
        let snapshot = CommsSnapshot.make(entries, settings: CommSettings(), now: now)
        #expect(snapshot.focusVisible == 2)
        #expect(snapshot.pending == 3)
        #expect(snapshot.urgent == 1)
        #expect(snapshot.text(for: .focus) == "2 comunicaciones laborales importantes")
        #expect(snapshot.text(for: .rest) == "Mientras trabajabas: 3 pendientes")
        #expect(snapshot.text(for: .idle) == "3 pendientes")
        #expect(CommsSnapshot.empty.text(for: .focus) == nil)
        let one = CommsSnapshot.make([entry(.teams, .important)], settings: CommSettings(), now: now)
        #expect(one.text(for: .focus) == "1 comunicación laboral importante")
    }

    @Test func snapshotNeverCarriesMessageText() throws {
        let secret = "La contraseña del portátil es 1234"
        let snapshot = CommsSnapshot.make([entry(.teams, .urgent, sender: "Jonatan", summary: secret)], settings: CommSettings(), now: now)
        let json = try #require(String(data: JSONEncoder().encode(snapshot), encoding: .utf8))
        #expect(!json.contains("contraseña"))
        #expect(!json.contains("Jonatan"))
        let defaults = try #require(UserDefaults(suiteName: "planaby.tests.\(UUID().uuidString)"))
        snapshot.save(to: defaults)
        #expect(CommsSnapshot.load(from: defaults) == snapshot)
    }
}
