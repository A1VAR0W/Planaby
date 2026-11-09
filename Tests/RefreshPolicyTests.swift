import Foundation
import Testing

// Cada cuánto despierta Planaby: solo lo necesario para lo que se ve.

@Suite("Ahorro de batería")
struct RefreshPolicyTests {
    @Test func ticksEverySecondOnlyWhileSomethingRuns() {
        #expect(RefreshPolicy.tickInterval(sessionRunning: true) == 1)
        #expect(RefreshPolicy.tickInterval(sessionRunning: false, musicPlaying: true) == 1)
        // Sin sesión, en pausa o sin música: el reloj solo cambia cada minuto.
        #expect(RefreshPolicy.tickInterval(sessionRunning: false) == 60)
    }

    @Test func minuteTicksStartOnTheMinute() {
        let now = Date(timeIntervalSinceReferenceDate: 3_600 * 1_000 + 754.3)
        let start = RefreshPolicy.tickStart(interval: 60, now: now)
        #expect(start.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60) == 0)
        #expect(start <= now && now.timeIntervalSince(start) < 60)
        // Con ticks de un segundo se empieza ya.
        #expect(RefreshPolicy.tickStart(interval: 1, now: now) == now)
    }

    @Test func phasesAdvanceExactlyWhenTheyEnd() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let delay = RefreshPolicy.reconcileDelay(phaseEnd: now.addingTimeInterval(25 * 60), isPaused: false, now: now)
        #expect(delay.map { $0 > 25 * 60 && $0 < 25 * 60 + 1 } == true)
        // Nada que esperar: sin sesión, en pausa o sin final.
        #expect(RefreshPolicy.reconcileDelay(phaseEnd: nil, isPaused: false, now: now) == nil)
        #expect(RefreshPolicy.reconcileDelay(phaseEnd: now.addingTimeInterval(60), isPaused: true, now: now) == nil)
        // Ya pasó y no se ha puesto al día: otra vez en un segundo, nunca sin pausa.
        #expect(RefreshPolicy.reconcileDelay(phaseEnd: now.addingTimeInterval(-5), isPaused: false, now: now) == 1)
    }

    @Test func musicIsCheckedLessWhenNothingPlays() {
        let playing = RefreshPolicy.musicPoll(isPlaying: true, remoteConnected: false)
        let idle = RefreshPolicy.musicPoll(isPlaying: false, remoteConnected: false)
        let remote = RefreshPolicy.musicPoll(isPlaying: true, remoteConnected: true)
        #expect(playing < idle && idle < remote)
        #expect(playing >= 3)
    }

    @Test func reconnectionBacksOff() {
        let delays = (1...8).map { RefreshPolicy.reconnectDelay(failures: $0) }
        #expect(delays.prefix(4) == [6, 12, 24, 48])
        #expect(delays.dropFirst(4).allSatisfy { $0 == 60 })
        #expect(zip(delays, delays.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(RefreshPolicy.reconnectDelay(failures: 0) == 6)
    }
}
