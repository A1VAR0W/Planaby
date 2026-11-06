import Foundation
import SwiftData

/// Por qué se iba a abrir una app que distrae (opcional, se elige en la pausa consciente).
enum DistractionMotive: String, CaseIterable, Identifiable, Sendable {
    case boredom, habit, hardTask, tired, realNeed, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .boredom: "Aburrimiento"
        case .habit: "Costumbre"
        case .hardTask: "Tarea difícil"
        case .tired: "Cansancio"
        case .realNeed: "Lo necesito"
        case .other: "Otro"
        }
    }

    var symbol: String {
        switch self {
        case .boredom: "cloud"
        case .habit: "repeat"
        case .hardTask: "mountain.2"
        case .tired: "battery.25percent"
        case .realNeed: "checkmark.circle"
        case .other: "ellipsis"
        }
    }
}

/// Un intento de distracción. Son cosas distintas y no se mezclan en las estadísticas:
/// - `pause`: pausa consciente al abrir una app (Atajos).
/// - `leave`: se salió de Planaby concentrándose más del margen (bloquear el iPhone no cuenta).
@Model
final class DistractionRecord {
    var date: Date
    /// Nombre de la app tal y como se puso en el atajo (puede estar vacío).
    var app: String
    /// Para qué la iba a abrir, si lo escribió.
    var reason: String
    /// true si volvió a lo suyo; false si la abrió igualmente.
    var resisted: Bool
    /// Había una sesión de concentración en marcha.
    var duringFocus: Bool
    /// "pause" o "leave" (los registros antiguos son pausas).
    var kindRaw: String = "pause"
    /// DistractionMotive elegido (vacío si no se eligió).
    var motiveRaw: String = ""
    /// Segundos fuera de Planaby (solo `leave`).
    var awaySeconds: Double = 0

    init(
        date: Date = .now, app: String, reason: String, resisted: Bool, duringFocus: Bool,
        kind: AttemptSample.Kind = .pause, motive: DistractionMotive? = nil, awaySeconds: Double = 0
    ) {
        self.date = date
        self.app = app
        self.reason = reason
        self.resisted = resisted
        self.duringFocus = duringFocus
        kindRaw = kind.rawValue
        motiveRaw = motive?.rawValue ?? ""
        self.awaySeconds = awaySeconds
    }

    var kind: AttemptSample.Kind { AttemptSample.Kind(rawValue: kindRaw) ?? .pause }
    var motive: DistractionMotive? { DistractionMotive(rawValue: motiveRaw) }

    var sample: AttemptSample { AttemptSample(date: date, app: app, resisted: resisted, kind: kind) }
}
