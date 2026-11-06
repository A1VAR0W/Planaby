import Foundation

/// Una sesión tal y como la ve el motor de atención (sin SwiftData, para poder probarlo).
struct SessionSample: Equatable, Sendable {
    var start: Date
    /// "work", "personal" o "" si es anterior a que se guardara el plan.
    var mode: String
    var methodID: String
    /// Minutos de concentración que pedía el método (0 = libre).
    var plannedFocusMinutes: Int
    var focusedMinutes: Double
    var completedCycles: Int
    /// Se terminó en mitad de una concentración, con más de un minuto por delante.
    var endedEarly: Bool
    /// Minutos que llevaba la concentración en la que se terminó.
    var abandonedAfterMinutes: Double
    var pauses = 0
    var leaves = 0
    var skippedBreaks = 0
    /// 0 sin valorar; 1 disperso, 2 normal, 3 muy centrado.
    var focusRating = 0
}

/// Un intento de abrir una app que distrae, o una salida de Planaby concentrándose.
struct AttemptSample: Equatable, Sendable {
    enum Kind: String, Sendable { case pause, leave }
    var date: Date
    var app: String
    var resisted: Bool
    var kind: Kind
}

struct FocusRecommendation: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case shorter, longer, switchMethod, longerBreaks, shorterBreaks, bestHours }

    var kind: Kind
    var mode: String
    var title: String
    /// Por qué se propone, con los datos que lo apoyan.
    var reason: String
    var focusMinutes: Int?
    var breakMinutes: Int?
    var methodID: String?
    var samples: Int

    var id: String { "\(kind.rawValue)|\(mode)|\(focusMinutes ?? 0)|\(breakMinutes ?? 0)|\(methodID ?? "")" }
    /// Se puede aplicar con un toque (las de horario solo informan).
    var isActionable: Bool { kind != .bestHours }
}

struct MethodStat: Identifiable, Equatable, Sendable {
    let methodID: String
    let sessions: Int
    /// Sesiones que completaron al menos una concentración entera.
    let completionRate: Double
    let averageFocusMinutes: Double
    var id: String { methodID }
}

struct AttentionReport: Equatable, Sendable {
    var recommendations: [FocusRecommendation] = []
    /// Hora (0–23) en la que empiezan las franjas de 2 h que mejor terminan.
    var bestHours: [Int] = []
    /// Hora con más intentos de distracción o salidas, si hay datos.
    var interruptionHour: Int?
    var methodStats: [MethodStat] = []
    var sampleCount = 0
}

/// Reglas deterministas sobre el historial. No saca conclusiones con pocas muestras, cambia la
/// duración poco a poco y explica cada propuesta. Una sesión larga no cuenta como buena por ser
/// larga: lo que cuenta es terminarla, cuántas veces se interrumpe y la valoración opcional.
struct AttentionProfileEngine {
    var calendar: Calendar = .current
    /// Mínimo de sesiones antes de proponer un cambio.
    var minimumSamples = 5
    /// Solo se mira el último mes y medio, y como mucho estas sesiones.
    var window: TimeInterval = 45 * 24 * 3600
    var maximumSamples = 30

    func report(
        sessions: [SessionSample], attempts: [AttemptSample], mode: String,
        currentMethodID: String, currentFocusMinutes: Int?, currentBreakMinutes: Int, now: Date
    ) -> AttentionReport {
        let relevant = sessions
            .filter { ($0.mode == mode || $0.mode.isEmpty) && $0.start >= now.addingTimeInterval(-window) && $0.start <= now }
            .sorted { $0.start > $1.start }
            .prefix(maximumSamples)
        let samples = Array(relevant)
        var report = AttentionReport(sampleCount: samples.count)
        report.methodStats = methodStats(samples)
        report.bestHours = bestHours(samples).map { $0.hour }
        report.interruptionHour = interruptionHour(attempts.filter { $0.date >= now.addingTimeInterval(-window) })

        var found: [FocusRecommendation] = []
        if let current = currentFocusMinutes {
            let sameLength = samples.filter { $0.plannedFocusMinutes > 0 && abs($0.plannedFocusMinutes - current) <= 5 }
            if let shorter = shorter(sameLength, current: current, mode: mode) {
                found.append(shorter)
            } else if let longer = longer(sameLength, current: current, mode: mode) {
                found.append(longer)
            }
            if let breaks = breaks(sameLength, currentBreak: currentBreakMinutes, mode: mode) {
                found.append(breaks)
            }
        }
        if let change = switchMethod(report.methodStats, current: currentMethodID, mode: mode) {
            found.append(change)
        }
        if let hours = bestHoursRecommendation(samples, mode: mode) {
            found.append(hours)
        }
        report.recommendations = Array(found.prefix(3))
        return report
    }

    // MARK: - Reglas

    private func shorter(_ samples: [SessionSample], current: Int, mode: String) -> FocusRecommendation? {
        guard samples.count >= minimumSamples else { return nil }
        let early = samples.filter { $0.endedEarly && $0.completedCycles == 0 && $0.abandonedAfterMinutes >= 2 }
        let rate = Double(early.count) / Double(samples.count)
        guard rate >= 0.4 else { return nil }
        let typical = median(early.map(\.abandonedAfterMinutes))
        // Un poco más de lo que suele aguantar, sin bajar más de un 30 % de golpe ni de 15 min.
        let target = max(15, roundToFive(max(typical * 1.15, Double(current) * 0.7)))
        guard target < current else { return nil }
        return FocusRecommendation(
            kind: .shorter, mode: mode, title: "Prueba sesiones de \(target) min",
            reason: "Has terminado antes de tiempo \(early.count) de tus últimas \(samples.count) sesiones de \(current) min, normalmente hacia el minuto \(Int(typical.rounded())). Es una prueba: si funcionan, iremos alargándolas poco a poco.",
            focusMinutes: target, samples: samples.count
        )
    }

    private func longer(_ samples: [SessionSample], current: Int, mode: String) -> FocusRecommendation? {
        guard samples.count >= minimumSamples + 1, current < 60 else { return nil }
        let completed = samples.filter { $0.completedCycles >= 1 && !($0.endedEarly && $0.completedCycles == 0) }
        let rate = Double(completed.count) / Double(samples.count)
        let pauses = Double(samples.reduce(0) { $0 + $1.pauses + $1.leaves }) / Double(samples.count)
        let rated = samples.filter { $0.focusRating > 0 }
        let feelsGood = rated.count < 3 || Double(rated.reduce(0) { $0 + $1.focusRating }) / Double(rated.count) >= 2
        guard rate >= 0.8, pauses <= 1, feelsGood else { return nil }
        let target = current + 5
        return FocusRecommendation(
            kind: .longer, mode: mode, title: "Puedes probar \(target) min",
            reason: "Has completado \(completed.count) de \(samples.count) sesiones de \(current) min casi sin interrupciones. Subir 5 min es un paso pequeño; si cuesta, vuelve al ritmo anterior.",
            focusMinutes: target, samples: samples.count
        )
    }

    private func breaks(_ samples: [SessionSample], currentBreak: Int, mode: String) -> FocusRecommendation? {
        let withBreaks = samples.filter { $0.completedCycles >= 1 }
        guard withBreaks.count >= minimumSamples else { return nil }
        // Se salta los descansos: le sobran minutos.
        let skipped = withBreaks.filter { $0.skippedBreaks > 0 }.count
        if Double(skipped) / Double(withBreaks.count) >= 0.5, currentBreak > 3 {
            let target = max(3, currentBreak - 2)
            return FocusRecommendation(
                kind: .shorterBreaks, mode: mode, title: "Descansos de \(target) min",
                reason: "Te has saltado el descanso en \(skipped) de \(withBreaks.count) sesiones. Uno algo más corto puede encajarte mejor.",
                breakMinutes: target, samples: withBreaks.count
            )
        }
        // Lo deja justo después de un descanso: quizá no le da para recuperarse.
        let afterBreak = withBreaks.filter { $0.endedEarly }.count
        if Double(afterBreak) / Double(withBreaks.count) >= 0.4, currentBreak < 20 {
            let target = min(20, currentBreak + 2)
            return FocusRecommendation(
                kind: .longerBreaks, mode: mode, title: "Descansos de \(target) min",
                reason: "En \(afterBreak) de \(withBreaks.count) sesiones lo dejaste en la concentración que sigue a un descanso. Un descanso algo más largo puede ayudarte a volver con energía.",
                breakMinutes: target, samples: withBreaks.count
            )
        }
        return nil
    }

    private func switchMethod(_ stats: [MethodStat], current: String, mode: String) -> FocusRecommendation? {
        guard let mine = stats.first(where: { $0.methodID == current }), mine.sessions >= minimumSamples, mine.completionRate < 0.5 else { return nil }
        guard let better = stats
            .filter({ $0.methodID != current && $0.sessions >= 3 && $0.completionRate >= mine.completionRate + 0.25 })
            .max(by: { $0.completionRate < $1.completionRate }) else { return nil }
        return FocusRecommendation(
            kind: .switchMethod, mode: mode, title: "Vuelve a un método que te funciona",
            reason: "Con el método actual terminas el \(percent(mine.completionRate)) de las sesiones; con otro que ya has usado, el \(percent(better.completionRate)) (\(better.sessions) sesiones).",
            methodID: better.methodID, samples: mine.sessions + better.sessions
        )
    }

    private func bestHoursRecommendation(_ samples: [SessionSample], mode: String) -> FocusRecommendation? {
        guard samples.count >= minimumSamples * 2 else { return nil }
        let overall = completionRate(samples)
        guard let best = bestHours(samples).first, best.rate >= overall + 0.15 else { return nil }
        return FocusRecommendation(
            kind: .bestHours, mode: mode, title: "Tu mejor franja: \(best.hour)–\(best.hour + 2) h",
            reason: "Las sesiones que empiezas entre las \(best.hour) y las \(best.hour + 2) terminan bien el \(percent(best.rate)) de las veces, frente al \(percent(overall)) de media (\(best.count) sesiones). Es una tendencia, no una garantía: Planaby pondrá ahí lo más exigente.",
            samples: best.count
        )
    }

    // MARK: - Cifras

    func methodStats(_ samples: [SessionSample]) -> [MethodStat] {
        Dictionary(grouping: samples, by: \.methodID).map { id, list in
            MethodStat(
                methodID: id, sessions: list.count, completionRate: completionRate(list),
                averageFocusMinutes: list.reduce(0) { $0 + $1.focusedMinutes } / Double(list.count)
            )
        }
        .sorted { $0.sessions > $1.sessions }
    }

    private func bestHours(_ samples: [SessionSample]) -> [(hour: Int, rate: Double, count: Int)] {
        let groups = Dictionary(grouping: samples) { calendar.component(.hour, from: $0.start) / 2 * 2 }
        return groups.compactMap { (hour: Int, list: [SessionSample]) -> (hour: Int, rate: Double, count: Int)? in
            guard list.count >= 3 else { return nil }
            return (hour: hour, rate: completionRate(list), count: list.count)
        }
        .sorted { $0.rate != $1.rate ? $0.rate > $1.rate : $0.count > $1.count }
    }

    private func interruptionHour(_ attempts: [AttemptSample]) -> Int? {
        let counts = Dictionary(grouping: attempts) { calendar.component(.hour, from: $0.date) }.mapValues(\.count)
        guard let top = counts.max(by: { $0.value < $1.value }), top.value >= 3 else { return nil }
        return top.key
    }

    func completionRate(_ samples: [SessionSample]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let completed = samples.filter { $0.completedCycles >= 1 || ($0.plannedFocusMinutes == 0 && !$0.endedEarly) }
        return Double(completed.count) / Double(samples.count)
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted.count.isMultiple(of: 2)
            ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
            : sorted[sorted.count / 2]
    }

    private func roundToFive(_ value: Double) -> Int { Int((value / 5).rounded()) * 5 }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded())) %" }
}
