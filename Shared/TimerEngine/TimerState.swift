import Foundation

struct PhaseTransition: Sendable {
    let date: Date
    let finished: PhaseKind
    let next: PhaseKind
    let nextDuration: TimeInterval?
}

struct CompletedSession: Sendable {
    let start: Date
    let end: Date
    let methodName: String
    let focusedSeconds: TimeInterval
    let completedCycles: Int
}

/// Estado del temporizador basado en fechas, no en ticks: sigue siendo correcto
/// aunque la app esté suspendida, y se puede compartir con widgets y Live Activities.
struct TimerState: Codable, Equatable, Sendable {
    var method: FocusMethod
    var phase: PhaseKind
    var completedCycles: Int
    var phaseStart: Date
    /// nil mientras dura una concentración abierta (Flowtime).
    var phaseEnd: Date?
    /// Momento en que se pausó; nil si está en marcha.
    var pausedAt: Date?
    var sessionStart: Date
    var focusedSeconds: TimeInterval

    init(method: FocusMethod, at now: Date) {
        self.method = method
        phase = .focus
        completedCycles = 0
        phaseStart = now
        phaseEnd = method.duration(of: .focus).map { now.addingTimeInterval($0) }
        pausedAt = nil
        sessionStart = now
        focusedSeconds = 0
    }

    var isPaused: Bool { pausedAt != nil }

    func elapsed(at now: Date) -> TimeInterval {
        max(0, (pausedAt ?? now).timeIntervalSince(phaseStart))
    }

    func remaining(at now: Date) -> TimeInterval? {
        phaseEnd.map { max(0, $0.timeIntervalSince(pausedAt ?? now)) }
    }

    func progress(at now: Date) -> Double {
        guard let phaseEnd else { return 0 }
        let total = phaseEnd.timeIntervalSince(phaseStart)
        return total > 0 ? min(1, elapsed(at: now) / total) : 1
    }

    func totalFocused(at now: Date) -> TimeInterval {
        focusedSeconds + (phase == .focus ? elapsed(at: now) : 0)
    }

    func summary(endingAt now: Date) -> CompletedSession {
        CompletedSession(
            start: sessionStart, end: now, methodName: method.name,
            focusedSeconds: totalFocused(at: now), completedCycles: completedCycles
        )
    }

    mutating func pause(at now: Date) {
        guard pausedAt == nil else { return }
        pausedAt = now
    }

    mutating func resume(at now: Date) {
        guard let pausedAt else { return }
        let shift = now.timeIntervalSince(pausedAt)
        phaseStart.addTimeInterval(shift)
        phaseEnd?.addTimeInterval(shift)
        self.pausedAt = nil
    }

    /// Termina la fase actual ahora mismo ("Saltar", o "Descansar" en Flowtime).
    mutating func skip(at now: Date) {
        resume(at: now)
        completePhase(endingAt: now)
    }

    /// Aplica las transiciones que ocurrieron mientras la app no estaba activa.
    @discardableResult
    mutating func catchUp(to now: Date) -> Int {
        var transitions = 0
        while pausedAt == nil, let end = phaseEnd, end <= now {
            completePhase(endingAt: end)
            transitions += 1
        }
        return transitions
    }

    func upcomingTransitions(limit: Int) -> [PhaseTransition] {
        guard pausedAt == nil else { return [] }
        var copy = self
        var result: [PhaseTransition] = []
        while result.count < limit, let end = copy.phaseEnd {
            let finished = copy.phase
            copy.completePhase(endingAt: end)
            result.append(PhaseTransition(
                date: end, finished: finished, next: copy.phase,
                nextDuration: copy.phaseEnd.map { $0.timeIntervalSince(end) }
            ))
        }
        return result
    }

    private mutating func completePhase(endingAt end: Date) {
        if phase == .focus {
            let worked = end.timeIntervalSince(phaseStart)
            focusedSeconds += worked
            completedCycles += 1
            begin(method.breakKind(afterCompletedCycles: completedCycles), at: end, focusElapsed: worked)
        } else {
            begin(.focus, at: end)
        }
    }

    private mutating func begin(_ kind: PhaseKind, at start: Date, focusElapsed: TimeInterval = 0) {
        phase = kind
        phaseStart = start
        phaseEnd = method.duration(of: kind, focusElapsed: focusElapsed).map { start.addingTimeInterval($0) }
    }
}
