import Foundation
import Testing

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// Lunes 2 de noviembre de 2026 a la hora dada (UTC).
private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

// MARK: - Pases

@Suite("PassBook")
struct PassBookTests {
    @Test func passIsOnlyForTheAppThatWasOpened() {
        var book = PassBook()
        book.grant(app: "Instagram", fromUnknownTrigger: false, minutes: 5, now: date(2, 10))
        #expect(book.hasPass(for: "instagram", now: date(2, 10, 2)))
        #expect(!book.hasPass(for: "TikTok", now: date(2, 10, 2)))
        #expect(!book.hasPass(for: "", now: date(2, 10, 2)))
    }

    @Test func unnamedPassDoesNotUnlockNamedApps() {
        var book = PassBook()
        book.grant(app: "", fromUnknownTrigger: true, minutes: 5, now: date(2, 10))
        #expect(book.hasPass(for: "", now: date(2, 10, 1)))
        #expect(!book.hasPass(for: "YouTube", now: date(2, 10, 1)))
    }

    @Test func choosingAnAppFromAnUnnamedTriggerCoversBoth() {
        var book = PassBook()
        book.grant(app: "YouTube", fromUnknownTrigger: true, minutes: 5, now: date(2, 10))
        #expect(book.hasPass(for: "youtube", now: date(2, 10, 1)))
        #expect(book.hasPass(for: "", now: date(2, 10, 1)))
        #expect(!book.hasPass(for: "Instagram", now: date(2, 10, 1)))
    }

    @Test func passesExpireAndArePruned() {
        var book = PassBook()
        book.grant(app: "X", fromUnknownTrigger: false, minutes: 3, now: date(2, 10))
        #expect(book.remainingMinutes(for: "x", now: date(2, 10, 1)) == 2)
        #expect(!book.hasPass(for: "x", now: date(2, 10, 3)))
        book.prune(now: date(2, 10, 4))
        #expect(book.passes.isEmpty)
    }

    @Test func survivesEncoding() throws {
        var book = PassBook()
        book.grant(app: "Reddit", fromUnknownTrigger: false, minutes: 10, now: date(2, 10))
        let copy = try JSONDecoder().decode(PassBook.self, from: JSONEncoder().encode(book))
        #expect(copy.hasPass(for: "reddit", now: date(2, 10, 5)))
    }
}

// MARK: - Pausa consciente

@Suite("FrictionPolicy")
struct FrictionPolicyTests {
    private func attempt(_ minute: Int, app: String = "Instagram", resisted: Bool = true) -> AttemptSample {
        AttemptSample(date: date(2, 10, minute), app: app, resisted: resisted, kind: .pause)
    }

    @Test func outOfScopeNeverPauses() {
        let policy = FrictionPolicy(intensity: .strict, calendar: utc)
        let result = policy.decide(app: "Instagram", inScope: false, focusing: false, onBreak: false,
                                   passes: PassBook(), history: [], now: date(2, 10))
        #expect(!result.pause)
    }

    @Test func passSkipsThePause() {
        var book = PassBook()
        book.grant(app: "Instagram", fromUnknownTrigger: false, minutes: 5, now: date(2, 10))
        let result = FrictionPolicy(intensity: .balanced, calendar: utc)
            .decide(app: "Instagram", inScope: true, focusing: true, onBreak: false, passes: book, history: [], now: date(2, 10, 1))
        #expect(!result.pause)
        #expect(result.skipReason == "pase")
    }

    @Test func repeatedAttemptsLengthenThePause() {
        let policy = FrictionPolicy(intensity: .balanced, calendar: utc)
        let first = policy.decide(app: "Instagram", inScope: true, focusing: true, onBreak: false,
                                  passes: PassBook(), history: [], now: date(2, 10, 20))
        let third = policy.decide(app: "Instagram", inScope: true, focusing: true, onBreak: false,
                                  passes: PassBook(), history: [attempt(5), attempt(15)], now: date(2, 10, 20))
        #expect(first.seconds == 10)
        #expect(third.seconds == 20)
        #expect(third.recentAttempts == 2)
    }

    @Test func oldAttemptsAndOtherAppsDoNotEscalate() {
        let policy = FrictionPolicy(intensity: .balanced, calendar: utc)
        let history = [AttemptSample(date: date(2, 8), app: "Instagram", resisted: true, kind: .pause), attempt(15, app: "TikTok")]
        let result = policy.decide(app: "Instagram", inScope: true, focusing: true, onBreak: false,
                                   passes: PassBook(), history: history, now: date(2, 10, 20))
        #expect(result.recentAttempts == 0)
        #expect(result.seconds == 10)
    }

    @Test func breaksAreGentler() {
        let policy = FrictionPolicy(intensity: .strict, calendar: utc)
        let result = policy.decide(app: "Instagram", inScope: true, focusing: false, onBreak: true,
                                   passes: PassBook(), history: [], now: date(2, 10))
        #expect(result.seconds == 10)
        #expect(!result.asksMotive)
    }

    @Test func freeOpensOnlyOutsideFocus() {
        let rules = [FrictionRule(app: "instagram", passMinutes: 15, freeOpensPerDay: 1)]
        let policy = FrictionPolicy(intensity: .balanced, rules: rules, calendar: utc)
        let free = policy.decide(app: "Instagram", inScope: true, focusing: false, onBreak: false,
                                 passes: PassBook(), history: [], now: date(2, 10))
        #expect(!free.pause)
        #expect(free.skipReason == "apertura libre")
        let used = policy.decide(app: "Instagram", inScope: true, focusing: false, onBreak: false,
                                 passes: PassBook(), history: [attempt(0, resisted: false)], now: date(2, 11))
        #expect(used.pause)
        let focusing = policy.decide(app: "Instagram", inScope: true, focusing: true, onBreak: false,
                                     passes: PassBook(), history: [], now: date(2, 10))
        #expect(focusing.pause)
        #expect(focusing.passMinutes == 15)
    }
}

// MARK: - Temporizador

@Suite("TimerState")
struct TimerStateTests {
    @Test func countsPausesOnlyDuringFocus() {
        var state = TimerState(method: .pomodoro, at: date(2, 10), taskTitle: "Informe", taskID: UUID(), mode: "work")
        state.pause(at: date(2, 10, 5))
        state.resume(at: date(2, 10, 6))
        state.skip(at: date(2, 10, 7)) // a descanso
        state.pause(at: date(2, 10, 8))
        let summary = state.summary(endingAt: date(2, 10, 9))
        #expect(summary.pauses == 1)
        #expect(summary.mode == "work")
        #expect(summary.methodID == "pomodoro")
    }

    @Test func skippingABreakIsCounted() {
        var state = TimerState(method: .pomodoro, at: date(2, 10))
        state.catchUp(to: date(2, 10, 26)) // terminó la concentración, en descanso
        #expect(state.phase == .shortBreak)
        state.skip(at: date(2, 10, 27))
        #expect(state.phase == .focus)
        #expect(state.summary(endingAt: date(2, 10, 28)).skippedBreaks == 1)
    }

    @Test func endingMidFocusIsEarly() {
        var state = TimerState(method: .pomodoro, at: date(2, 10))
        let early = state.summary(endingAt: date(2, 10, 12))
        #expect(early.endedEarly)
        #expect(early.abandonedAfterMinutes == 12)
        state.catchUp(to: date(2, 10, 26))
        #expect(!state.summary(endingAt: date(2, 10, 27)).endedEarly)
    }

    @Test func leavesAccumulate() {
        var state = TimerState(method: .pomodoro, at: date(2, 10))
        state.noteLeave(seconds: 40)
        state.noteLeave(seconds: 80)
        let summary = state.summary(endingAt: date(2, 10, 20))
        #expect(summary.leaves == 2)
        #expect(summary.awaySeconds == 120)
    }

    @Test func refocusStartsAShortBlockKeepingWork() {
        var state = TimerState(method: .pomodoro, at: date(2, 10))
        state.beginFocus(at: date(2, 10, 10), minutes: 10)
        #expect(state.focusedSeconds == 600)
        #expect(state.remaining(at: date(2, 10, 10)) == 600)
        #expect(state.totalFocused(at: date(2, 10, 15)) == 900)
    }

    @Test func pausedTimerSchedulesNothing() {
        var state = TimerState(method: .pomodoro, at: date(2, 10))
        #expect(!state.upcomingTransitions(limit: 4).isEmpty)
        state.pause(at: date(2, 10, 1))
        #expect(state.upcomingTransitions(limit: 4).isEmpty)
    }

    @Test func switchingMethodKeepsTheSession() {
        var state = TimerState(method: .pomodoro, at: date(2, 10))
        let other = FocusMethod.builtIns.first { $0.id == "52-17" }!
        state.switchMethod(to: other, at: date(2, 10, 20))
        #expect(state.phase == .focus)
        #expect(state.sessionStart == date(2, 10))
        #expect(state.remaining(at: date(2, 10, 20)) == 32 * 60)
    }

    @Test func starterMethodMarksTheSession() {
        let state = TimerState(method: .starter, at: date(2, 10))
        #expect(state.summary(endingAt: date(2, 10, 3)).isStarter)
    }

    @Test func oldSavedStateStillDecodes() throws {
        // Un estado guardado por la versión anterior no tiene los campos nuevos.
        let state = TimerState(method: .pomodoro, at: date(2, 10))
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        for key in ["taskID", "modeRaw", "pauseCount", "leaveCount", "awaySeconds", "skippedBreaks", "isStarter"] {
            json.removeValue(forKey: key)
        }
        let decoded = try JSONDecoder().decode(TimerState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.summary(endingAt: date(2, 10, 5)).pauses == 0)
    }
}

// MARK: - Reparto por horas

@Suite("FocusDistribution")
struct FocusDistributionTests {
    @Test func splitsAcrossHours() {
        let slices = FocusDistribution.slices(start: date(2, 11, 40), end: date(2, 12, 30), focusedSeconds: 50 * 60, calendar: utc)
        #expect(slices.map(\.hour) == [11, 12])
        #expect(abs(slices[0].minutes - 20) < 0.01)
        #expect(abs(slices[1].minutes - 30) < 0.01)
    }

    @Test func breaksDoNotCountAsFocus() {
        // 60 min de reloj con 30 de concentración: cada hora recibe la mitad.
        let slices = FocusDistribution.slices(start: date(2, 9, 30), end: date(2, 10, 30), focusedSeconds: 30 * 60, calendar: utc)
        #expect(abs(slices.reduce(0) { $0 + $1.minutes } - 30) < 0.01)
    }

    @Test func emptySessionHasNoSlices() {
        #expect(FocusDistribution.slices(start: date(2, 9), end: date(2, 9), focusedSeconds: 0, calendar: utc).isEmpty)
    }
}

// MARK: - Motor de recomendaciones

@Suite("AttentionProfileEngine")
struct AttentionEngineTests {
    private let engine = AttentionProfileEngine(calendar: utc)
    private let now = date(30, 20)

    private func session(
        day: Int, hour: Int = 10, mode: String = "work", method: String = "pomodoro", planned: Int = 25,
        focused: Double = 25, cycles: Int = 1, early: Bool = false, after: Double = 0,
        pauses: Int = 0, skipped: Int = 0, rating: Int = 0
    ) -> SessionSample {
        SessionSample(
            start: date(day, hour), mode: mode, methodID: method, plannedFocusMinutes: planned,
            focusedMinutes: focused, completedCycles: cycles, endedEarly: early, abandonedAfterMinutes: after,
            pauses: pauses, skippedBreaks: skipped, focusRating: rating
        )
    }

    private func report(_ sessions: [SessionSample], mode: String = "work", method: String = "pomodoro", focus: Int? = 25, rest: Int = 5) -> AttentionReport {
        engine.report(sessions: sessions, attempts: [], mode: mode, currentMethodID: method,
                      currentFocusMinutes: focus, currentBreakMinutes: rest, now: now)
    }

    @Test func notEnoughSamplesMeansNoRecommendation() {
        let few = (1...4).map { session(day: $0 + 10, focused: 12, cycles: 0, early: true, after: 12) }
        #expect(report(few).recommendations.isEmpty)
    }

    @Test func abandoningEarlySuggestsShorterBlocksGradually() throws {
        let sessions = (1...6).map { session(day: $0 + 10, focused: 12, cycles: 0, early: true, after: 12) }
        let shorter = try #require(report(sessions).recommendations.first { $0.kind == .shorter })
        // Nunca baja más de un 30 % de golpe: de 25 a 20 (25 × 0,7 = 17,5 → 20), no a 12.
        #expect(shorter.focusMinutes == 20)
        #expect(shorter.reason.contains("6"))
    }

    @Test func completingConsistentlySuggestsLongerBlocks() throws {
        let sessions = (1...7).map { session(day: $0 + 10, focused: 50, cycles: 2) }
        let longer = try #require(report(sessions).recommendations.first { $0.kind == .longer })
        #expect(longer.focusMinutes == 30)
    }

    @Test func longButInterruptedSessionsAreNotRewarded() {
        let sessions = (1...7).map { session(day: $0 + 10, focused: 90, cycles: 3, pauses: 3) }
        #expect(!report(sessions).recommendations.contains { $0.kind == .longer })
    }

    @Test func lowRatingsBlockLongerBlocks() {
        let sessions = (1...7).map { session(day: $0 + 10, focused: 50, cycles: 2, rating: 1) }
        #expect(!report(sessions).recommendations.contains { $0.kind == .longer })
    }

    @Test func modesAreSeparated() {
        let personal = (1...8).map { session(day: $0 + 10, mode: "personal", focused: 12, cycles: 0, early: true, after: 12) }
        let work = report(personal, mode: "work")
        #expect(work.sampleCount == 0)
        #expect(work.recommendations.isEmpty)
        #expect(report(personal, mode: "personal").recommendations.contains { $0.kind == .shorter })
    }

    @Test func oldSessionsAreIgnored() {
        let old = (1...8).map { session(day: $0, focused: 12, cycles: 0, early: true, after: 12) }
            .map { var copy = $0; copy.start = copy.start.addingTimeInterval(-60 * 24 * 3600); return copy }
        #expect(report(old).sampleCount == 0)
    }

    @Test func skippingBreaksSuggestsShorterBreaks() throws {
        let sessions = (1...6).map { session(day: $0 + 10, focused: 50, cycles: 2, pauses: 2, skipped: 1) }
        let breaks = try #require(report(sessions).recommendations.first { $0.kind == .shorterBreaks })
        #expect(breaks.breakMinutes == 3)
    }

    @Test func suggestsAMethodThatWorksBetter() throws {
        let bad = (1...6).map { session(day: $0 + 10, method: "ultradian", planned: 90, focused: 30, cycles: 0, early: true, after: 30) }
        let good = (1...4).map { session(day: $0 + 20, method: "pomodoro", focused: 50, cycles: 2) }
        let change = try #require(report(bad + good, method: "ultradian", focus: 90).recommendations.first { $0.kind == .switchMethod })
        #expect(change.methodID == "pomodoro")
    }

    @Test func freeMethodGetsNoLengthChange() {
        let sessions = (1...8).map { session(day: $0 + 10, method: "flow", planned: 0, focused: 40, cycles: 1) }
        let result = report(sessions, method: "flow", focus: nil)
        #expect(!result.recommendations.contains { $0.kind == .shorter || $0.kind == .longer })
    }

    @Test func findsTheHourWithMostInterruptions() {
        let attempts = (0..<4).map { AttemptSample(date: date(20 + $0, 17, 10), app: "Instagram", resisted: false, kind: .pause) }
        let result = engine.report(sessions: [], attempts: attempts, mode: "work", currentMethodID: "pomodoro",
                                   currentFocusMinutes: 25, currentBreakMinutes: 5, now: now)
        #expect(result.interruptionHour == 17)
    }

    @Test func bestHoursNeedEnoughEvidence() {
        let morning = (1...5).map { session(day: $0 + 10, hour: 9, focused: 25, cycles: 1) }
        let evening = (1...5).map { session(day: $0 + 15, hour: 19, focused: 8, cycles: 0, early: true, after: 8) }
        let result = report(morning + evening)
        #expect(result.bestHours.first == 8)
        #expect(result.recommendations.contains { $0.kind == .bestHours })
    }
}
