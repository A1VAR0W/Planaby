import Charts
import SwiftData
import SwiftUI

/// Periodo del análisis de Progreso.
enum InsightRange: Int, CaseIterable, Identifiable {
    case week = 7, month = 30, quarter = 90

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .week: "7 días"
        case .month: "30 días"
        case .quarter: "3 meses"
        }
    }
}

/// Cifras del análisis: cuándo rindes, si sigues el plan, cómo estimas, a qué dedicas el tiempo,
/// cuántas distracciones frenas y si entregas a tiempo.
struct Insights {
    struct Cell: Identifiable {
        /// 1 = lunes … 7 = domingo.
        let row: Int
        let hour: Int
        let minutes: Double
        var id: Int { row * 100 + hour }
    }

    struct Share: Identifiable {
        let title: String
        let seconds: TimeInterval
        let tint: Color
        var id: String { title }
    }

    struct MethodLine: Identifiable {
        let name: String
        let sessions: Int
        let completionRate: Double
        let averageMinutes: Double
        var id: String { name }
    }

    static let hours = Array(6...23)

    let range: DateInterval
    let heatmap: [Cell]
    let peak: Cell?
    let totalFocus: TimeInterval
    /// Bloques de trabajo ya pasados y cuántos tuvieron una sesión de concentración.
    let pastBlocks: Int
    let keptBlocks: Int
    /// Tiempo real / tiempo estimado en las tareas terminadas con sesiones (1 = clavado).
    let estimateRatio: Double?
    let estimatedTasks: Int
    let shares: [Share]
    let resisted: Int
    let gaveIn: Int
    let topApps: [(app: String, count: Int)]
    /// Salidas de Planaby concentrándose (no se mezclan con las pausas conscientes).
    let leaves: Int
    let awaySeconds: TimeInterval
    let sessionCount: Int
    /// Sesiones que completaron al menos una concentración (o, sin ciclos, que no se cortaron).
    let completionRate: Double?
    /// Pausas y salidas por sesión.
    let interruptionsPerSession: Double?
    let methods: [MethodLine]
    let tasksDone: Int
    let onTime: Int
    let late: Int
    let overdue: Int

    init(
        range kind: InsightRange, sessions: [FocusSessionRecord], events: [CalendarEvent], tasks: [PlanTask],
        distractions: [DistractionRecord], now: Date = .now, calendar: Calendar = .current
    ) {
        let start = calendar.date(byAdding: .day, value: -(kind.rawValue - 1), to: calendar.startOfDay(for: now)) ?? now
        let window = DateInterval(start: start, end: max(start, now))
        range = window
        let inRange = sessions.filter { window.contains($0.start) }

        // Mapa de calor: minutos por día de la semana y hora (lunes arriba). Una sesión de 11:40 a
        // 12:30 suma en las 11 y en las 12, no todo a la hora en la que empezó.
        var grid: [Int: Double] = [:]
        for session in inRange {
            for slice in FocusDistribution.slices(
                start: session.start, end: session.end, focusedSeconds: session.focusedSeconds, calendar: calendar
            ) {
                let row = (slice.weekday + 5) % 7 + 1
                grid[row * 100 + slice.hour, default: 0] += slice.minutes
            }
        }
        let cells = (1...7).flatMap { row in
            Self.hours.map { Cell(row: row, hour: $0, minutes: grid[row * 100 + $0] ?? 0) }
        }
        heatmap = cells
        peak = cells.filter { $0.minutes > 0 }.max { $0.minutes < $1.minutes }
        totalFocus = inRange.reduce(0) { $0 + $1.focusedSeconds }

        // Plan cumplido: un bloque cuenta si alguna sesión lo solapa al menos a la mitad.
        let blocks = events.filter { $0.kind == .workBlock && window.contains($0.start) && $0.end <= now }
        pastBlocks = blocks.count
        keptBlocks = blocks.filter { block in
            let interval = DateInterval(start: block.start, end: max(block.start, block.end))
            let overlap = inRange.reduce(0.0) { total, session in
                let sessionInterval = DateInterval(start: session.start, end: max(session.start, session.end))
                return total + (interval.intersection(with: sessionInterval)?.duration ?? 0)
            }
            return overlap >= interval.duration / 2
        }.count

        // Estimaciones: tiempo concentrado en cada tarea terminada frente a lo estimado. Se une por
        // el identificador de la tarea; las sesiones antiguas, por el título.
        var byID: [UUID: TimeInterval] = [:]
        var byTitle: [String: TimeInterval] = [:]
        for session in sessions {
            if let id = session.taskID {
                byID[id, default: 0] += session.focusedSeconds
            } else if let title = session.taskTitle?.lowercased() {
                byTitle[title, default: 0] += session.focusedSeconds
            }
        }
        let finished = tasks.filter { $0.isDone && ($0.completedAt.map { window.contains($0) } ?? false) }
        tasksDone = finished.count
        let ratios = finished.compactMap { task -> Double? in
            let spent = (task.uid.flatMap { byID[$0] } ?? 0) + (byTitle[task.title.lowercased()] ?? 0)
            guard spent >= 60, task.estimatedMinutes > 0 else { return nil }
            return spent / Double(task.estimatedMinutes * 60)
        }
        estimatedTasks = ratios.count
        estimateRatio = ratios.isEmpty ? nil : ratios.reduce(0, +) / Double(ratios.count)

        // Reparto: por el plan de la tarea de cada sesión.
        let modeByTitle = Dictionary(tasks.map { ($0.title.lowercased(), $0.mode) }, uniquingKeysWith: { first, _ in first })
        var work: TimeInterval = 0, personal: TimeInterval = 0, free: TimeInterval = 0
        let modeByID = Dictionary(tasks.compactMap { task in task.uid.map { ($0, task.mode) } }, uniquingKeysWith: { first, _ in first })
        for session in inRange {
            let mode = session.taskID.flatMap { modeByID[$0] } ?? session.taskTitle.flatMap({ modeByTitle[$0.lowercased()] })
            switch mode {
            case .work?: work += session.focusedSeconds
            case .personal?: personal += session.focusedSeconds
            case nil: free += session.focusedSeconds
            }
        }
        shares = [
            Share(title: "Trabajo", seconds: work, tint: PlanMode.work.tint),
            Share(title: "Normal", seconds: personal, tint: PlanMode.personal.tint),
            Share(title: "Sin tarea", seconds: free, tint: Color.white.opacity(0.35)),
        ].filter { $0.seconds > 0 }

        // Distracciones: pausas conscientes por un lado y salidas de Planaby por otro.
        let inWindow = distractions.filter { window.contains($0.date) }
        let pauses = inWindow.filter { $0.kind == .pause && $0.reason != "Apertura libre" }
        let away = inWindow.filter { $0.kind == .leave || ($0.kind == .pause && $0.app.isEmpty && $0.reason.hasPrefix("Fuera de Planaby")) }
        let realPauses = pauses.filter { !($0.app.isEmpty && $0.reason.hasPrefix("Fuera de Planaby")) }
        resisted = realPauses.filter(\.resisted).count
        gaveIn = realPauses.count - resisted
        leaves = away.count
        awaySeconds = away.reduce(0) { $0 + $1.awaySeconds }

        // Sesiones: cuántas se completan, cuántas interrupciones y qué método funciona mejor.
        let counted = inRange.filter { !$0.isStarter || $0.focusedSeconds >= 300 }
        sessionCount = counted.count
        let completed = counted.filter { $0.completedCycles >= 1 || ($0.plannedFocusMinutes == 0 && !$0.endedEarly) }
        completionRate = counted.isEmpty ? nil : Double(completed.count) / Double(counted.count)
        interruptionsPerSession = counted.isEmpty ? nil
            : Double(counted.reduce(0) { $0 + $1.pauseCount + $1.leaveCount }) / Double(counted.count)
        methods = Dictionary(grouping: counted, by: \.methodName).compactMap { name, list in
            guard list.count >= 2 else { return nil }
            let done = list.filter { $0.completedCycles >= 1 || ($0.plannedFocusMinutes == 0 && !$0.endedEarly) }.count
            return MethodLine(
                name: name, sessions: list.count, completionRate: Double(done) / Double(list.count),
                averageMinutes: list.reduce(0) { $0 + $1.focusedSeconds } / Double(list.count) / 60
            )
        }
        .sorted { $0.sessions > $1.sessions }
        var apps: [String: Int] = [:]
        for pause in pauses where !pause.app.isEmpty { apps[pause.app.capitalized, default: 0] += 1 }
        topApps = apps.sorted { $0.value > $1.value }.prefix(3).map { (app: $0.key, count: $0.value) }

        // Entregas.
        onTime = finished.filter { ($0.completedAt ?? .distantFuture) <= $0.deadline }.count
        late = finished.count - onTime
        overdue = tasks.filter { !$0.isDone && $0.deadline < now }.count
    }
}

// MARK: - Vista

/// Sección «Análisis» de Progreso.
struct InsightsSection: View {
    @Query(sort: \FocusSessionRecord.start, order: .reverse) private var sessions: [FocusSessionRecord]
    @Query private var events: [CalendarEvent]
    @Query private var tasks: [PlanTask]
    @Query private var distractions: [DistractionRecord]
    @AppStorage("insightRange") private var rangeRaw = InsightRange.week.rawValue

    var body: some View {
        let range = InsightRange(rawValue: rangeRaw) ?? .week
        let insights = Insights(range: range, sessions: sessions, events: events, tasks: tasks, distractions: distractions)

        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text("Análisis").font(.title3.weight(.semibold))
                Spacer()
            }
            .padding(.top, Space.s)
            Picker("Periodo", selection: $rangeRaw) {
                ForEach(InsightRange.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)

            HeatmapCard(insights: insights)

            HStack(alignment: .top, spacing: Space.m) {
                RatioTile(
                    title: "Plan cumplido",
                    value: insights.pastBlocks == 0 ? "—" : percent(Double(insights.keptBlocks) / Double(insights.pastBlocks)),
                    detail: insights.pastBlocks == 0
                        ? "Sin bloques en este periodo"
                        : "\(insights.keptBlocks) de \(insights.pastBlocks) bloques con sesión",
                    systemImage: "checkmark.seal"
                )
                RatioTile(
                    title: "Estimaciones",
                    value: estimateValue(insights.estimateRatio),
                    detail: estimateDetail(insights),
                    systemImage: "ruler"
                )
            }

            if !insights.shares.isEmpty {
                SharesCard(shares: insights.shares)
            }

            HStack(alignment: .top, spacing: Space.m) {
                RatioTile(
                    title: "Sesiones completadas",
                    value: insights.completionRate.map(percent) ?? "—",
                    detail: completionDetail(insights),
                    systemImage: "checkmark.circle"
                )
                RatioTile(
                    title: "Salidas de Planaby",
                    value: insights.sessionCount == 0 ? "—" : "\(insights.leaves)",
                    detail: insights.leaves == 0
                        ? (insights.sessionCount == 0 ? "Sin sesiones en este periodo" : "No te has ido concentrándote")
                        : "\(FocusStats.format(insights.awaySeconds)) fuera en total",
                    systemImage: "rectangle.portrait.and.arrow.right"
                )
            }

            if insights.methods.count >= 2 {
                MethodsCard(methods: insights.methods)
            }

            HStack(alignment: .top, spacing: Space.m) {
                RatioTile(
                    title: "Distracciones frenadas",
                    value: insights.resisted + insights.gaveIn == 0 ? "—" : "\(insights.resisted)",
                    detail: distractionDetail(insights),
                    systemImage: "hand.raised"
                )
                RatioTile(
                    title: "Entregas a tiempo",
                    value: insights.onTime + insights.late == 0 ? "—" : "\(insights.onTime) de \(insights.onTime + insights.late)",
                    detail: (insights.tasksDone == 1 ? "1 tarea terminada · " : "\(insights.tasksDone) tareas terminadas · ")
                        + (insights.overdue == 0
                            ? "nada atrasado"
                            : (insights.overdue == 1 ? "1 atrasada" : "\(insights.overdue) atrasadas")),
                    systemImage: "flag.checkered"
                )
            }
        }
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    private func estimateValue(_ ratio: Double?) -> String {
        guard let ratio else { return "—" }
        let delta = ratio - 1
        if abs(delta) < 0.1 { return "Bien" }
        return (delta > 0 ? "+" : "−") + percent(abs(delta))
    }

    private func estimateDetail(_ insights: Insights) -> String {
        guard let ratio = insights.estimateRatio else { return "Termina tareas con sesiones para medirlo" }
        if abs(ratio - 1) < 0.1 { return "Aciertas con lo que estimas" }
        return ratio > 1 ? "Tardas más de lo que estimas" : "Tardas menos de lo que estimas"
    }

    private func completionDetail(_ insights: Insights) -> String {
        guard insights.sessionCount > 0, let interruptions = insights.interruptionsPerSession else {
            return "Sin sesiones en este periodo"
        }
        let rounded = (interruptions * 10).rounded() / 10
        return "\(insights.sessionCount) sesiones · \(rounded.formatted(.number.precision(.fractionLength(0...1)))) interrupciones de media"
    }

    private func distractionDetail(_ insights: Insights) -> String {
        let total = insights.resisted + insights.gaveIn
        guard total > 0 else { return "Opcional: Ajustes › Bloqueo › Frenar apps" }
        var text = "de \(total) pausas conscientes"
        if let top = insights.topApps.first { text += " · más: \(top.app)" }
        return text
    }
}

private struct HeatmapCard: View {
    let insights: Insights

    var body: some View {
        let maximum = max(1, insights.heatmap.map(\.minutes).max() ?? 1)
        let weekdays = ["L", "M", "X", "J", "V", "S", "D"]
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Cuándo te concentras").font(.headline)
                Spacer()
                Text(FocusStats.format(insights.totalFocus))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                ForEach(1...7, id: \.self) { row in
                    GridRow {
                        Text(weekdays[row - 1])
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 14)
                        ForEach(Insights.hours, id: \.self) { hour in
                            let minutes = insights.heatmap.first { $0.row == row && $0.hour == hour }?.minutes ?? 0
                            RoundedRectangle(cornerRadius: 3)
                                .fill(minutes == 0 ? Theme.surface : Theme.orange.opacity(0.2 + 0.8 * minutes / maximum))
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
                GridRow {
                    Color.clear.frame(width: 14, height: 1)
                    ForEach(Insights.hours, id: \.self) { hour in
                        Text(hour % 3 == 0 ? "\(hour)" : "")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize()
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Mapa de calor de concentración por día y hora")
            .accessibilityValue(peakText ?? "Sin sesiones en este periodo")

            Text(peakText.map { "Tu mejor franja: \($0)." } ?? "Aún no hay sesiones en este periodo.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
    }

    private var peakText: String? {
        guard let peak = insights.peak else { return nil }
        let names = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]
        return "\(names[peak.row - 1]) de \(peak.hour):00 a \(peak.hour + 1):00"
    }
}

/// Qué método te deja terminar más sesiones (solo con dos o más métodos usados).
private struct MethodsCard: View {
    let methods: [Insights.MethodLine]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Qué método te funciona").font(.headline)
            ForEach(methods) { method in
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(method.name).font(.subheadline.weight(.medium))
                        Spacer()
                        Text(method.completionRate.formatted(.percent.precision(.fractionLength(0))))
                            .font(.subheadline.monospacedDigit())
                    }
                    ProgressView(value: method.completionRate)
                        .tint(Theme.orange)
                    Text("\(method.sessions) sesiones · \(Int(method.averageMinutes.rounded())) min de media")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .accessibilityElement(children: .combine)
            }
            Text("Porcentaje de sesiones que completan al menos una concentración entera.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
    }
}

private struct SharesCard: View {
    let shares: [Insights.Share]

    var body: some View {
        let total = max(1, shares.reduce(0) { $0 + $1.seconds })
        VStack(alignment: .leading, spacing: Space.m) {
            Text("A qué dedicas la concentración").font(.headline)
            Chart(shares) { share in
                BarMark(x: .value("Tiempo", share.seconds / 60))
                    .foregroundStyle(share.tint)
                    .accessibilityLabel(Text(share.title))
                    .accessibilityValue(Text(FocusStats.format(share.seconds)))
            }
            .chartXAxis(.hidden)
            .frame(height: 20)
            .clipShape(.capsule)
            HStack(spacing: Space.m) {
                ForEach(shares) { share in
                    HStack(spacing: Space.xs) {
                        Circle().fill(share.tint).frame(width: 8, height: 8)
                        Text("\(share.title) \((share.seconds / total).formatted(.percent.precision(.fractionLength(0))))")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
        .card()
    }
}

private struct RatioTile: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(Theme.orange)
                .accessibilityHidden(true)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.medium).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.footnote.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }
}
