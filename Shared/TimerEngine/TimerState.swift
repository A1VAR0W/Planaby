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
    let taskTitle: String?
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
    /// Tarea del plan en la que se está trabajando, si la hay.
    var taskTitle: String?

    init(method: FocusMethod, at now: Date, taskTitle: String? = nil) {
        self.method = method
        phase = .focus
        completedCycles = 0
        phaseStart = now
        phaseEnd = method.duration(of: .focus).map { now.addingTimeInterval($0) }
        pausedAt = nil
        sessionStart = now
        focusedSeconds = 0
        self.taskTitle = taskTitle
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
            focusedSeconds: totalFocused(at: now), completedCycles: completedCycles, taskTitle: taskTitle
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

    /// Cambia de método sin perder la sesión: el bloque de concentración actual conserva lo
    /// trabajado y se ajusta a la nueva duración; un descanso en curso termina como estaba.
    mutating func switchMethod(to newMethod: FocusMethod, at now: Date) {
        method = newMethod
        guard phase == .focus else { return }
        phaseEnd = newMethod.duration(of: .focus).map { phaseStart.addingTimeInterval($0) }
        if let pausedAt, let end = phaseEnd, end < pausedAt {
            phaseEnd = pausedAt
        }
        catchUp(to: now)
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

    /// Fase que viene después de la actual.
    var nextPhase: PhaseKind {
        phase == .focus ? method.breakKind(afterCompletedCycles: completedCycles + 1) : .focus
    }

    func clockText(at date: Date) -> String {
        let seconds = remaining(at: date) ?? elapsed(at: date)
        return Self.format(seconds)
    }

    static func format(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.rounded(.up))
            .formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
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

/// Estado compartido en el App Group: lo escribe la app y lo leen widgets y controles.
extension TimerState {
    private static let storageKey = "timerState"

    static func loadShared() -> TimerState? {
        AppGroup.defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(TimerState.self, from: $0) }
    }

    static func saveShared(_ state: TimerState?) {
        if let state, let data = try? JSONEncoder().encode(state) {
            AppGroup.defaults.set(data, forKey: storageKey)
        } else {
            AppGroup.defaults.removeObject(forKey: storageKey)
        }
    }
}
