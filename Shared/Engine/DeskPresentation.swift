import Foundation

/// Lo que enseñan el modo escritorio, los widgets (también en StandBy) y la Live Activity.
/// Sale siempre del único `TimerState` (no hay otro motor de tiempo) y de recuentos sin textos de
/// mensajes, así que todas las superficies dicen lo mismo y nada privado llega a la pantalla bloqueada.
struct DeskPresentation: Equatable, Sendable {
    enum Layout: String, Sendable {
        case focus, rest, idle
    }

    var layout: Layout
    var phase: PhaseKind?
    var isPaused: Bool
    var phaseStart: Date?
    var phaseEnd: Date?
    var pausedAt: Date?
    var methodName: String?
    var taskTitle: String?
    /// «Después: Descanso · 5 min» durante la sesión.
    var nextPhaseText: String?
    /// Lo siguiente del plan (sin sesión, o como «Siguiente tarea» durante la sesión).
    var nextItemTitle: String?
    var nextItemStart: Date?
    /// Recuento de comunicaciones para este momento, sin cuerpos de mensaje.
    var commsText: String?
    var commsCount: Int

    init(state: TimerState?, comms: CommsSnapshot, agenda: [AgendaItem], now: Date) {
        if let state {
            layout = state.phase.isBreak ? .rest : .focus
            phase = state.phase
            isPaused = state.isPaused
            phaseStart = state.phaseStart
            phaseEnd = state.phaseEnd
            pausedAt = state.pausedAt
            methodName = state.method.name
            taskTitle = state.taskTitle
            if let next = state.upcomingTransitions(limit: 1).first {
                let minutes = next.nextDuration.map { Int(($0 / 60).rounded()) }
                nextPhaseText = "Después: \(next.next.title)" + (minutes.map { " · \($0) min" } ?? "")
            } else {
                nextPhaseText = state.phase == .focus ? "Después: \(state.nextPhase.title)" : nil
            }
        } else {
            layout = .idle
            phase = nil
            isPaused = false
            phaseStart = nil
            phaseEnd = nil
            pausedAt = nil
            methodName = nil
            taskTitle = nil
            nextPhaseText = nil
        }
        let upcoming = agenda
            .filter { !$0.isAllDay && $0.end > now && $0.title != state?.taskTitle }
            .min { $0.start < $1.start }
        nextItemTitle = upcoming?.title
        nextItemStart = upcoming?.start
        let commPhase: CommPhase = switch layout {
        case .focus: .focus
        case .rest: .rest
        case .idle: .idle
        }
        commsText = comms.text(for: commPhase)
        commsCount = comms.count(for: commPhase)
    }

    /// Lo que hay guardado en el App Group ahora mismo (para widgets y Live Activity).
    static func current(now: Date = .now) -> DeskPresentation {
        var state = TimerState.loadShared()
        state?.catchUp(to: now)
        return DeskPresentation(state: state, comms: .load(), agenda: AgendaSnapshot.load().items, now: now)
    }

    var stateTitle: String {
        if isPaused { return "En pausa" }
        return phase?.title ?? "Sin sesión"
    }

    /// Intervalo para los contadores del sistema; nil si la fase es abierta o está en pausa.
    var range: ClosedRange<Date>? {
        guard !isPaused, let phaseStart, let phaseEnd, phaseEnd > phaseStart else { return nil }
        return phaseStart...phaseEnd
    }

    func progress(at now: Date) -> Double {
        guard let phaseStart, let phaseEnd else { return 0 }
        let total = phaseEnd.timeIntervalSince(phaseStart)
        guard total > 0 else { return 1 }
        return min(1, max(0, (pausedAt ?? now).timeIntervalSince(phaseStart) / total))
    }

    /// Reloj congelado en pausa o para las fases abiertas (los contadores del sistema no se paran).
    func staticClock(at now: Date) -> String? {
        guard let phaseStart else { return nil }
        let reference = pausedAt ?? now
        if let phaseEnd { return isPaused ? TimerState.format(max(0, phaseEnd.timeIntervalSince(reference))) : nil }
        return TimerState.format(max(0, reference.timeIntervalSince(phaseStart)))
    }
}
