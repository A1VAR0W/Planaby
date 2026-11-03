import Foundation
import SwiftData

/// Una pausa consciente: alguien iba a abrir una app que distrae y Planaby le frenó.
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

    init(date: Date = .now, app: String, reason: String, resisted: Bool, duringFocus: Bool) {
        self.date = date
        self.app = app
        self.reason = reason
        self.resisted = resisted
        self.duringFocus = duringFocus
    }
}
