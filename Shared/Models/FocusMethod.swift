import Foundation

enum PhaseKind: String, Codable, Sendable {
    case focus, shortBreak, longBreak

    var isBreak: Bool { self != .focus }

    var title: String {
        switch self {
        case .focus: "Concentración"
        case .shortBreak: "Descanso"
        case .longBreak: "Descanso largo"
        }
    }
}

struct FocusMethod: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var summary: String
    /// nil = concentración abierta (Flowtime): el usuario decide cuándo parar.
    var focusMinutes: Int?
    var shortBreakMinutes: Int
    var longBreakMinutes: Int
    /// Ciclos de concentración antes de un descanso largo; 0 = nunca.
    var cyclesBeforeLongBreak: Int
    /// Solo Flowtime: el descanso dura esta fracción del tiempo concentrado.
    var flowBreakRatio: Double?
    var isBuiltIn: Bool

    var isOpenEnded: Bool { focusMinutes == nil }

    var detail: String {
        var parts = [focusMinutes.map { "\($0) min" } ?? "Libre"]
        if let flowBreakRatio {
            parts.append("descanso \(Int((flowBreakRatio * 100).rounded())) %")
        } else {
            parts.append("descanso \(shortBreakMinutes)")
        }
        if cyclesBeforeLongBreak > 0 {
            parts.append("largo \(longBreakMinutes) cada \(cyclesBeforeLongBreak)")
        }
        return parts.joined(separator: " · ")
    }

    func breakKind(afterCompletedCycles cycles: Int) -> PhaseKind {
        guard cyclesBeforeLongBreak > 0, cycles > 0, cycles % cyclesBeforeLongBreak == 0 else { return .shortBreak }
        return .longBreak
    }

    /// Duración de una fase; nil si la concentración es abierta. Nunca menos de un minuto.
    func duration(of kind: PhaseKind, focusElapsed: TimeInterval = 0) -> TimeInterval? {
        let seconds: TimeInterval? = switch kind {
        case .focus: focusMinutes.map { TimeInterval($0 * 60) }
        case .shortBreak: flowBreakRatio.map { focusElapsed * $0 } ?? TimeInterval(shortBreakMinutes * 60)
        case .longBreak: TimeInterval(longBreakMinutes * 60)
        }
        return seconds.map { max(60, $0.rounded()) }
    }
}

extension FocusMethod {
    static let pomodoro = FocusMethod(
        id: "pomodoro", name: "Pomodoro",
        summary: "25 min de foco con descansos cortos y uno largo cada 4 ciclos.",
        focusMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15, cyclesBeforeLongBreak: 4,
        flowBreakRatio: nil, isBuiltIn: true
    )

    static let builtIns: [FocusMethod] = [
        pomodoro,
        FocusMethod(
            id: "52-17", name: "52/17",
            summary: "El ritmo de los trabajadores más productivos según DeskTime.",
            focusMinutes: 52, shortBreakMinutes: 17, longBreakMinutes: 17, cyclesBeforeLongBreak: 0,
            flowBreakRatio: nil, isBuiltIn: true
        ),
        FocusMethod(
            id: "ultradian", name: "Ultradiano 90/20",
            summary: "Sigue el ciclo natural de energía de unos 90 minutos.",
            focusMinutes: 90, shortBreakMinutes: 20, longBreakMinutes: 20, cyclesBeforeLongBreak: 0,
            flowBreakRatio: nil, isBuiltIn: true
        ),
        FocusMethod(
            id: "112-26", name: "112/26",
            summary: "Bloques largos de trabajo profundo (estudio DeskTime 2021).",
            focusMinutes: 112, shortBreakMinutes: 26, longBreakMinutes: 26, cyclesBeforeLongBreak: 0,
            flowBreakRatio: nil, isBuiltIn: true
        ),
        FocusMethod(
            id: "50-10", name: "Hora redonda 50/10",
            summary: "50 min de trabajo y 10 de pausa; descanso largo cada 3 horas.",
            focusMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 30, cyclesBeforeLongBreak: 3,
            flowBreakRatio: nil, isBuiltIn: true
        ),
        FocusMethod(
            id: "flowtime", name: "Flowtime",
            summary: "Trabaja sin reloj y para cuando pierdas el foco. El descanso es el 20 % de lo trabajado.",
            focusMinutes: nil, shortBreakMinutes: 5, longBreakMinutes: 0, cyclesBeforeLongBreak: 0,
            flowBreakRatio: 0.2, isBuiltIn: true
        ),
    ]

    static func newCustom() -> FocusMethod {
        FocusMethod(
            id: UUID().uuidString, name: "", summary: "Plantilla personalizada",
            focusMinutes: 30, shortBreakMinutes: 5, longBreakMinutes: 15, cyclesBeforeLongBreak: 4,
            flowBreakRatio: nil, isBuiltIn: false
        )
    }
}
