import Foundation
import SwiftData
import Testing

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func entry(
    _ text: String = "Llamar a Marta", created: Date = now, status: CaptureStatus = .pending,
    session: Date? = nil, taskID: UUID? = nil, snoozed: Date? = nil, presented: Date? = nil
) -> CaptureEntry {
    CaptureEntry(
        id: UUID(), text: text, created: created, modeRaw: PlanMode.work.rawValue, status: status,
        sessionStart: session, taskID: taskID, snoozedUntil: snoozed, presentedAt: presented
    )
}

@Suite("Captura rápida: texto")
struct CaptureTextTests {
    @Test func trimsAndCollapsesWhitespace() {
        #expect(CaptureRules.clean("   revisar   el\n\ninforme  ") == "Revisar el informe")
    }

    @Test func rejectsEmptyText() {
        #expect(CaptureRules.clean("") == nil)
        #expect(CaptureRules.clean("   \n\t  ") == nil)
    }

    @Test func rejectsPunctuationOnly() {
        #expect(CaptureRules.clean("...") == nil)
        #expect(CaptureRules.clean(" - ") == nil)
    }

    @Test func capitalizesOnlyTheFirstLetter() {
        #expect(CaptureRules.clean("comprar pan para Lucía") == "Comprar pan para Lucía")
        #expect(CaptureRules.clean("iPhone nuevo") == "iPhone nuevo")
        #expect(CaptureRules.clean("Ya en mayúscula") == "Ya en mayúscula")
    }

    @Test func keepsNumbersAccentsAndSymbols() {
        #expect(CaptureRules.clean("3 llamadas · día 12 ✅") == "3 llamadas · día 12 ✅")
        #expect(CaptureRules.clean("ñoquis") == "Ñoquis")
    }

    @Test func truncatesVeryLongText() throws {
        let long = String(repeating: "palabra ", count: 80)
        let cleaned = try #require(CaptureRules.clean(long))
        #expect(cleaned.count <= CaptureRules.maxLength + 1)
        #expect(cleaned.hasSuffix("…"))
    }
}

@Suite("Captura rápida: la sesión no se toca")
struct CaptureSessionTests {
    @Test func originWithoutSession() {
        let origin = CaptureRules.origin(of: nil)
        #expect(origin.sessionStart == nil)
        #expect(origin.phase == nil)
    }

    @Test func originDuringFocus() {
        let state = TimerState(method: .pomodoro, at: now)
        let origin = CaptureRules.origin(of: state)
        #expect(origin.sessionStart == state.sessionStart)
        #expect(origin.phase == "focus")
    }

    @Test func originDuringBreak() {
        var state = TimerState(method: .pomodoro, at: now)
        _ = state.catchUp(to: now.addingTimeInterval(25 * 60 + 5))
        #expect(state.phase.isBreak)
        #expect(CaptureRules.origin(of: state).phase == "break")
    }

    // Apuntar algo no cambia el temporizador: ni fase, ni tarea, ni pausa, ni ciclos.
    @Test func capturingLeavesTheTimerStateIntact() {
        var state = TimerState(method: .pomodoro, at: now)
        state.taskTitle = "Informe trimestral"
        let before = state
        _ = CaptureRules.origin(of: state)
        let capture = CapturedTask(text: "Llamar a Marta", mode: .work, source: .text, sessionStart: state.sessionStart, phase: "focus")
        #expect(state == before)
        #expect(state.taskTitle == "Informe trimestral")
        #expect(capture.sessionStart == state.sessionStart)
    }
}

@Suite("Captura rápida: por organizar")
struct CaptureInboxTests {
    @Test func pendingExcludesSnoozedPlannedAndDone() {
        #expect(CaptureRules.isPending(entry(), now: now))
        #expect(!CaptureRules.isPending(entry(snoozed: now.addingTimeInterval(3600)), now: now))
        #expect(!CaptureRules.isPending(entry(status: .planned), now: now))
        #expect(!CaptureRules.isPending(entry(status: .done), now: now))
    }

    @Test func snoozeExpires() {
        let snoozed = entry(snoozed: now.addingTimeInterval(3600))
        #expect(CaptureRules.isPending(snoozed, now: now.addingTimeInterval(3601)))
    }

    @Test func fromSessionOnlyThatSession() {
        let session = now.addingTimeInterval(-1800)
        let entries = [entry(session: session), entry(session: session), entry(session: now.addingTimeInterval(-9000)), entry()]
        #expect(CaptureRules.fromSession(entries, sessionStart: session, now: now).count == 2)
    }

    @Test func summaryExcludesWhatWasAlreadyShown() {
        let session = now.addingTimeInterval(-1800)
        let entries = [
            entry(session: session), entry(session: session, presented: now),
            entry(status: .planned, session: session), entry(session: nil),
        ]
        #expect(CaptureRules.toSummarize(entries, sessionStart: session, since: .distantPast, now: now).count == 1)
    }

    @Test func summarySinceADate() {
        let entries = [entry(created: now.addingTimeInterval(-600)), entry(created: now.addingTimeInterval(-60))]
        #expect(CaptureRules.toSummarize(entries, sessionStart: nil, since: now.addingTimeInterval(-300), now: now).count == 1)
    }

    @Test func summaryTexts() {
        #expect(CaptureRules.summary(count: 1) == "Has apuntado 1 tarea")
        #expect(CaptureRules.summary(count: 3) == "Has apuntado 3 tareas")
        #expect(CaptureRules.summary(count: 4, duringSession: true) == "Has apuntado 4 tareas durante tu sesión")
    }

    // Una captura se convierte en tarea una sola vez.
    @Test func plannedOnlyOnce() {
        var item = entry()
        let task = UUID()
        #expect(CaptureRules.markPlanned(&item, taskID: task))
        #expect(item.status == .planned)
        #expect(item.taskID == task)
        #expect(!CaptureRules.markPlanned(&item, taskID: UUID()))
        #expect(item.taskID == task)
    }

    @Test func plannedAsAnEventHasNoTask() {
        var item = entry()
        #expect(CaptureRules.markPlanned(&item, taskID: nil))
        #expect(item.status == .planned)
        #expect(item.taskID == nil)
        #expect(!CaptureRules.markPlanned(&item, taskID: UUID()))
    }

    @Test func doneIsNotPlanned() {
        var item = entry(status: .done)
        #expect(!CaptureRules.markPlanned(&item, taskID: UUID()))
        #expect(item.status == .done)
    }
}

@Suite("Captura rápida: datos y copias")
struct CaptureStorageTests {
    @Test func newCaptureDefaults() {
        let capture = CapturedTask(text: "Revisar contrato", mode: .work, source: .voice)
        #expect(capture.status == .pending)
        #expect(capture.mode == .work)
        #expect(capture.source == .voice)
        #expect(capture.taskID == nil)
        #expect(capture.entry.id == capture.uid)
        #expect(capture.entry.text == "Revisar contrato")
    }

    @Test func unknownRawValuesFallBack() {
        let capture = CapturedTask(text: "x", mode: .work, source: .text)
        capture.statusRaw = "???"
        capture.modeRaw = "???"
        capture.sourceRaw = "???"
        #expect(capture.status == .pending)
        #expect(capture.mode == .personal)
        #expect(capture.source == .text)
    }

    @Test func backupRoundTripKeepsEverything() throws {
        let capture = CapturedTask(text: "Pedir cita", mode: .personal, source: .siri, sessionStart: now, phase: "break", created: now)
        capture.status = .planned
        capture.taskID = UUID()
        capture.snoozedUntil = now.addingTimeInterval(60)
        capture.reviewedAt = now
        capture.convertedAt = now
        capture.presentedAt = now
        let backup = CaptureBackup(capture)
        let decoded = try JSONDecoder().decode(CaptureBackup.self, from: JSONEncoder().encode(backup))
        #expect(decoded == backup)

        let restored = decoded.makeModel()
        #expect(restored.uid == capture.uid)
        #expect(restored.text == "Pedir cita")
        #expect(restored.status == .planned)
        #expect(restored.source == .siri)
        #expect(restored.mode == .personal)
        #expect(restored.taskID == capture.taskID)
        #expect(restored.phaseRaw == "break")
        #expect(restored.sessionStart == now)
        #expect(restored.snoozedUntil == capture.snoozedUntil)
    }

    // Las copias de antes de la captura rápida no traen el campo: se leen igual.
    @Test func oldBackupsWithoutCapturesStillDecode() throws {
        struct Wrapper: Codable { var format: Int; var captures: [CaptureBackup]? }
        let decoded = try JSONDecoder().decode(Wrapper.self, from: Data(#"{"format":1}"#.utf8))
        #expect(decoded.captures == nil)
    }

    // Lo apuntado sigue ahí al cerrar y volver a abrir la base de datos.
    @Test func survivesReopeningTheStore() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "capture-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "store.sqlite")
        let schema = Schema([CapturedTask.self])
        var id: UUID?

        do {
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let context = ModelContext(container)
            let capture = CapturedTask(text: "Enviar factura", mode: .work, source: .text, sessionStart: now, phase: "focus")
            context.insert(capture)
            try context.save()
            id = capture.uid
        }

        let reopened = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let fetched = try ModelContext(reopened).fetch(FetchDescriptor<CapturedTask>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.uid == id)
        #expect(fetched.first?.text == "Enviar factura")
        #expect(fetched.first?.status == .pending)
    }

    @MainActor
    @Test func requestFromAControlIsConsumedOnce() {
        CaptureRequest.handler = nil
        _ = CaptureRequest.consume()
        CaptureRequest.post()
        #expect(CaptureRequest.consume())
        #expect(!CaptureRequest.consume())
    }

    @MainActor
    @Test func staleRequestIsIgnored() {
        CaptureRequest.handler = nil
        CaptureRequest.post()
        #expect(!CaptureRequest.consume(now: .now.addingTimeInterval(120)))
    }

    @MainActor
    @Test func requestGoesStraightToTheAppWhenOpen() {
        var opened: Bool?
        CaptureRequest.handler = { opened = $0 }
        defer { CaptureRequest.handler = nil }
        CaptureRequest.post(dictation: true)
        #expect(opened == true)
        #expect(!CaptureRequest.consume())
    }
}
