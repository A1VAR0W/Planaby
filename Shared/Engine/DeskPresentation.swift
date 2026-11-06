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

/// Qué ocupa el centro del modo escritorio: la cifra, la música, la cifra con las tareas al lado
/// o música y tareas a la vez, mitad y mitad.
enum DeskPanels: Equatable, Sendable {
    case clock, music, clockAndTasks, musicAndTasks

    init(music: Bool, tasks: Bool) {
        switch (music, tasks) {
        case (true, true): self = .musicAndTasks
        case (true, false): self = .music
        case (false, true): self = .clockAndTasks
        case (false, false): self = .clock
        }
    }

    /// Ancho de cada mitad con música y tareas: el sitio que queda quitando la separación, a partes iguales.
    static func halfWidth(total: Double, spacing: Double) -> Double {
        max(0, (total - spacing) / 2)
    }

    /// Ancho de la lista de tareas junto a la cifra.
    static let taskColumn: Double = 320

    /// Anchos del panel principal (cifra o música) y de las tareas (0 si están cerradas). La
    /// composición es siempre la misma (principal + tareas), así abrir, cerrar o cambiar de
    /// disposición solo cambia anchos: nada se vuelve a crear y la animación es continua.
    static func widths(total: Double, spacing: Double, music: Bool, tasks: Bool) -> (main: Double, tasks: Double) {
        let total = max(0, total)
        guard tasks else { return (total, 0) }
        let half = halfWidth(total: total, spacing: spacing)
        // Con música, mitad y mitad; sin ella, una columna fija que nunca pasa de la mitad
        // (la cifra sigue mandando).
        let side = music ? half : min(taskColumn, half)
        return (max(0, total - spacing - side), side)
    }
}

/// Textos del aviso de cambio de fase (la tarjeta dentro de la app): «¡Sesión completada! Has
/// trabajado durante 25 minutos. Comienza tu descanso de 5 minutos».
enum PhaseAlertText {
    /// Minutos redondeados (al menos 1); nil en una fase abierta.
    static func minutes(_ seconds: TimeInterval?) -> Int? {
        seconds.map { max(1, Int(($0 / 60).rounded())) }
    }

    static func minutesText(_ minutes: Int) -> String {
        minutes == 1 ? "1 minuto" : "\(minutes) minutos"
    }

    static func title(finished: PhaseKind, next: PhaseKind) -> String {
        if next.isBreak { return "¡Sesión completada!" }
        return finished.isBreak ? "Descanso terminado" : "Sigue la concentración"
    }

    static func message(finished: PhaseKind, finishedDuration: TimeInterval?, next: PhaseKind, nextDuration: TimeInterval?) -> String {
        if next.isBreak {
            var parts: [String] = []
            if !finished.isBreak, let worked = minutes(finishedDuration) {
                parts.append("Has trabajado durante \(minutesText(worked)).")
            }
            let kind = next == .longBreak ? "descanso largo" : "descanso"
            parts.append(minutes(nextDuration).map { "Comienza tu \(kind) de \(minutesText($0))." } ?? "Comienza tu \(kind).")
            return parts.joined(separator: " ")
        }
        return minutes(nextDuration).map { "Vuelve la concentración: \(minutesText($0))." } ?? "Vuelve la concentración, sin límite de tiempo."
    }
}

/// Textos de la Live Activity y la Dynamic Island, los mismos que el modo escritorio.
enum ActivityText {
    /// La etiqueta naranja de encima de la cifra.
    static func eyebrow(phase: PhaseKind, isPaused: Bool, isFinished: Bool) -> String {
        if isFinished { return "Fase completada" }
        if isPaused { return "En pausa" }
        return phase.title
    }

    /// «Concentración · 75 %» (o solo la fase si es abierta).
    static func status(phase: PhaseKind, isPaused: Bool, progress: Double?) -> String {
        let title = isPaused ? "En pausa" : phase.title
        guard let progress else { return title }
        return "\(title) · \(Int((min(1, max(0, progress)) * 100).rounded())) %"
    }

    /// La línea de debajo de la cifra: la tarea en concentración; en el descanso, un recordatorio
    /// breve para recuperarse; al acabar, qué viene.
    static func detail(phase: PhaseKind, task: String?, method: String, isFinished: Bool, next: PhaseKind) -> String {
        if isFinished { return next.isBreak ? "Toca para empezar el descanso" : "Toca para volver a concentrarte" }
        if phase.isBreak { return "Levántate, respira y mira lejos" }
        if let task, !task.trimmingCharacters(in: .whitespaces).isEmpty { return task }
        return method
    }

    /// «Luego: Descanso» o «Luego: Concentración».
    static func next(_ next: PhaseKind) -> String { "Luego: \(next.title)" }
}
