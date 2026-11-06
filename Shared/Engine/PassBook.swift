import Foundation

/// Pases de «Abrir igualmente»: durante unos minutos una app no vuelve a frenar.
///
/// Reglas (antes un pase de una automatización sin app se convertía en permiso global):
/// - Un aviso con nombre de app («Instagram») solo mira el pase de esa app.
/// - Un aviso sin nombre (una automatización para varias apps no dice cuál se abrió) solo
///   mira el pase «sin nombre». Es una limitación de Atajos: con una acción por app el pase
///   es exacto.
/// - Los pases caducan por fecha, así que siguen valiendo (o no) tras reiniciar la app.
struct PassBook: Codable, Equatable, Sendable {
    /// Clave de la app (minúsculas, sin espacios) → fin del pase.
    private(set) var passes: [String: Date] = [:]

    static let unknownKey = "*"

    static func key(for app: String) -> String {
        let name = app.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return name.isEmpty ? unknownKey : name
    }

    /// Da un pase. `app` es la app que se va a abrir (puede estar vacía si no se sabe);
    /// `fromUnknownTrigger` indica que el aviso llegó sin nombre de app.
    mutating func grant(app: String, fromUnknownTrigger: Bool, minutes: Int, now: Date) {
        prune(now: now)
        let end = now.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        let key = Self.key(for: app)
        passes[key] = max(passes[key] ?? .distantPast, end)
        // Los siguientes avisos de esa automatización también llegarán sin nombre.
        if fromUnknownTrigger, key != Self.unknownKey {
            passes[Self.unknownKey] = max(passes[Self.unknownKey] ?? .distantPast, end)
        }
    }

    func hasPass(for app: String, now: Date) -> Bool {
        (passes[Self.key(for: app)] ?? .distantPast) > now
    }

    /// Minutos que quedan del pase de una app (0 si no hay).
    func remainingMinutes(for app: String, now: Date) -> Int {
        guard let end = passes[Self.key(for: app)], end > now else { return 0 }
        return Int((end.timeIntervalSince(now) / 60).rounded(.up))
    }

    /// Para leer pases guardados con su fecha exacta.
    mutating func setEnd(_ end: Date, forKey key: String) {
        passes[key] = end
    }

    mutating func prune(now: Date) {
        passes = passes.filter { $0.value > now }
    }
}

/// Reparte el tiempo concentrado de una sesión entre las horas reales que ocupó.
enum FocusDistribution {
    struct Slice: Equatable, Sendable {
        /// Inicio de la hora (en el calendario dado).
        let hourStart: Date
        let hour: Int
        /// 1 = domingo … 7 = sábado, como `Calendar`.
        let weekday: Int
        let minutes: Double
    }

    /// El tiempo concentrado se reparte en proporción a lo que la sesión duró en cada hora
    /// (una sesión con descansos no cuenta como concentración todo su tiempo de reloj).
    static func slices(start: Date, end: Date, focusedSeconds: Double, calendar: Calendar) -> [Slice] {
        let total = end.timeIntervalSince(start)
        guard total > 0, focusedSeconds > 0 else { return [] }
        let share = min(1, focusedSeconds / total)
        var result: [Slice] = []
        var cursor = start
        while cursor < end {
            guard let hour = calendar.dateInterval(of: .hour, for: cursor) else { break }
            let pieceEnd = min(hour.end, end)
            let minutes = pieceEnd.timeIntervalSince(cursor) / 60 * share
            result.append(Slice(
                hourStart: hour.start, hour: calendar.component(.hour, from: cursor),
                weekday: calendar.component(.weekday, from: cursor), minutes: minutes
            ))
            cursor = pieceEnd
        }
        return result
    }
}
