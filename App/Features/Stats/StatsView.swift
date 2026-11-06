import Charts
import SwiftData
import SwiftUI

/// Pestaña Progreso: hoy frente al objetivo, racha, últimos 7 días, métodos, sesiones recientes
/// y el análisis (cuándo rindes, plan cumplido, estimaciones, distracciones y entregas).
struct StatsView: View {
    let onStartFocus: () -> Void
    @Query(sort: \FocusSessionRecord.start, order: .reverse) private var sessions: [FocusSessionRecord]
    @AppStorage(Preferences.dailyGoalMinutes, store: AppGroup.defaults) private var goalMinutes = Preferences.defaultDailyGoal

    private enum Route: Hashable { case history }

    var body: some View {
        let stats = FocusStats(sessions: sessions)
        let goal = TimeInterval(goalMinutes * 60)

        ScrollView {
            if sessions.isEmpty {
                ContentUnavailableView {
                    Label("Aún no hay sesiones", systemImage: "chart.bar")
                } description: {
                    Text("Cada sesión de más de un minuto suma a tu progreso, tu racha y tu objetivo diario.")
                } actions: {
                    Button(action: onStartFocus) {
                        Text("Empezar a concentrarme")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .padding(.horizontal, Space.s)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.orange)
                }
                .padding(.top, Space.xxl)
            } else {
                VStack(spacing: Space.m) {
                    TodayCard(stats: stats, goal: goal)

                    DaySummaryCard()

                    HStack(spacing: Space.m) {
                        StatTile(
                            title: "Racha", value: stats.streak == 1 ? "1 día" : "\(stats.streak) días",
                            systemImage: "flame.fill"
                        )
                        StatTile(
                            title: "Media por sesión", value: FocusStats.format(stats.averageSession),
                            systemImage: "timer"
                        )
                    }

                    WeekCard(days: stats.lastSevenDays, total: stats.weekTotal, goalMinutes: goalMinutes)

                    if !stats.topMethods.isEmpty {
                        MethodsCard(methods: stats.topMethods)
                    }

                    RecentCard(sessions: Array(sessions.prefix(4)))

                    InsightsSection()
                }
                .padding(.horizontal, Space.m)
                .padding(.bottom, Space.l)
            }
        }
        .background(Color.black)
        .navigationTitle("Progreso")
        .navigationDestination(for: Route.self) { _ in SessionHistoryView() }
    }

    // MARK: - Tarjetas

    private struct TodayCard: View {
        let stats: FocusStats
        let goal: TimeInterval

        var body: some View {
            let progress = goal > 0 ? min(1, stats.today / goal) : 0
            HStack(spacing: Space.l) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Eyebrow(text: "Hoy", color: Theme.orange)
                    Text(FocusStats.format(stats.today))
                        .font(.system(.largeTitle, design: .rounded).weight(.light).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(progress >= 1
                         ? "Objetivo cumplido"
                         : "Te quedan \(FocusStats.format(goal - stats.today)) para tu objetivo")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                    Text(stats.todaySessions == 1 ? "1 sesión" : "\(stats.todaySessions) sesiones")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 0)
                ZStack {
                    ProgressRing(progress: progress, tint: Theme.orange, lineWidth: 8)
                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(.headline, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                }
                .frame(width: 92, height: 92)
            }
            .card(padding: Space.l)
            .accessibilityElement(children: .combine)
        }
    }

    private struct StatTile: View {
        let title: String
        let value: String
        let systemImage: String

        var body: some View {
            VStack(alignment: .leading, spacing: Space.s) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(Theme.orange)
                    .accessibilityHidden(true)
                Text(value)
                    .font(.system(.title2, design: .rounded).weight(.medium).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .card()
            .accessibilityElement(children: .combine)
        }
    }

    private struct WeekCard: View {
        let days: [FocusStats.Day]
        let total: TimeInterval
        let goalMinutes: Int

        var body: some View {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Últimos 7 días").font(.headline)
                    Spacer()
                    Text(FocusStats.format(total))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                }

                Chart {
                    ForEach(days) { day in
                        BarMark(
                            x: .value("Día", day.date, unit: .day),
                            y: .value("Minutos", day.minutes),
                            width: .ratio(0.55)
                        )
                        .cornerRadius(6)
                        .foregroundStyle(Calendar.current.isDateInToday(day.date) ? Theme.orange : Theme.orange.opacity(0.45))
                        .accessibilityLabel(Text(day.date.formatted(.dateTime.weekday(.wide))))
                        .accessibilityValue(Text(FocusStats.format(day.seconds)))
                    }
                    RuleMark(y: .value("Objetivo", Double(goalMinutes)))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .annotation(position: .top, alignment: .leading, spacing: 2) {
                            Text("Objetivo")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .accessibilityLabel(Text("Objetivo diario"))
                        .accessibilityValue(Text("\(goalMinutes) min"))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel()
                    }
                }
                .chartYAxisLabel("min")
                .frame(height: 180)
            }
            .card()
        }
    }

    private struct MethodsCard: View {
        let methods: [FocusStats.MethodShare]

        var body: some View {
            let maximum = methods.first?.seconds ?? 1
            VStack(alignment: .leading, spacing: Space.m) {
                Text("Métodos esta semana").font(.headline)
                ForEach(methods) { method in
                    VStack(alignment: .leading, spacing: Space.xs + 2) {
                        HStack {
                            Text(method.name).font(.subheadline)
                            Spacer()
                            Text(FocusStats.format(method.seconds))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Theme.secondaryText)
                        }
                        ProgressView(value: method.seconds, total: maximum)
                            .tint(Theme.orange)
                            .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .card()
        }
    }

    private struct RecentCard: View {
        let sessions: [FocusSessionRecord]

        var body: some View {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Recientes").font(.headline)
                ForEach(sessions) { session in
                    SessionRow(session: session, showsDay: true)
                    if session.id != sessions.last?.id {
                        Divider().overlay(Theme.hairline)
                    }
                }
                NavigationLink(value: Route.history) {
                    HStack {
                        Text("Ver todo el historial")
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.orange)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .card()
        }
    }
}

/// Fila de una sesión: método, hora y tiempo concentrado.
struct SessionRow: View {
    let session: FocusSessionRecord
    var showsDay = false

    var body: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.methodName).font(.body.weight(.medium))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Text(FocusStats.format(session.focusedSeconds))
                .font(.body.monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.vertical, Space.xs)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let time = "\(session.start.formatted(date: .omitted, time: .shortened))–\(session.end.formatted(date: .omitted, time: .shortened))"
        let cycles = session.completedCycles == 1 ? "1 ciclo" : "\(session.completedCycles) ciclos"
        guard showsDay else { return "\(time) · \(cycles)" }
        let day = Calendar.current.isDateInToday(session.start)
            ? "Hoy"
            : session.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return "\(day), \(time)"
    }
}

/// Historial completo agrupado por días, con borrado confirmado.
struct SessionHistoryView: View {
    @Query(sort: \FocusSessionRecord.start, order: .reverse) private var sessions: [FocusSessionRecord]
    @Environment(\.modelContext) private var context
    @State private var deleting: FocusSessionRecord?

    var body: some View {
        let days = Dictionary(grouping: sessions) { Calendar.current.startOfDay(for: $0.start) }
            .sorted { $0.key > $1.key }

        List {
            ForEach(days, id: \.key) { entry in
                Section {
                    ForEach(entry.value) { session in
                        SessionRow(session: session)
                            .swipeActions {
                                Button("Borrar", systemImage: "trash", role: .destructive) { deleting = session }
                            }
                    }
                } header: {
                    HStack {
                        Text(entry.key.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        Spacer()
                        Text(FocusStats.format(entry.value.reduce(0) { $0 + $1.focusedSeconds }))
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("Historial")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if sessions.isEmpty {
                ContentUnavailableView("Sin sesiones", systemImage: "clock", description: Text("Tu historial está vacío."))
            }
        }
        .confirmationDialog(
            "¿Borrar esta sesión?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { session in
            Button("Borrar sesión", role: .destructive) {
                context.delete(session)
                try? context.save()
            }
        } message: { session in
            Text("Se restarán \(FocusStats.format(session.focusedSeconds)) de tu progreso.")
        }
    }
}
