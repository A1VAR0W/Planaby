import SwiftUI
import WidgetKit

struct AgendaEntry: TimelineEntry {
    let date: Date
    let mode: PlanMode
    /// Lo que está en curso ahora, si hay algo.
    let current: AgendaItem?
    /// Lo siguiente, en orden.
    let upcoming: [AgendaItem]
}

/// Se adelanta a cada inicio y final de los próximos eventos, así el widget pasa de «Próximo»
/// a «Ahora» y al siguiente sin abrir la app.
struct AgendaProvider: TimelineProvider {
    func placeholder(in context: Context) -> AgendaEntry {
        let start = Date.now.addingTimeInterval(25 * 60)
        let sample = AgendaItem(
            title: "Preparar la presentación", start: start, end: start.addingTimeInterval(3600),
            modeRaw: PlanMode.work.rawValue, kindRaw: EventKind.workBlock.rawValue, isAllDay: false
        )
        return AgendaEntry(date: .now, mode: .work, current: nil, upcoming: [sample])
    }

    func getSnapshot(in context: Context, completion: @escaping (AgendaEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entries()[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AgendaEntry>) -> Void) {
        // Si no hay más cambios a la vista, se vuelve a mirar en una hora.
        completion(Timeline(entries: entries(), policy: .after(.now.addingTimeInterval(3600))))
    }

    private func entries() -> [AgendaEntry] {
        let now = Date.now
        let (mode, items) = AgendaSnapshot.load()
        let pending = items.filter { $0.end > now }
        let changes = Set(pending.flatMap { [$0.start, $0.end] }.filter { $0 > now }).sorted().prefix(20)
        return ([now] + changes).map { date in
            let live = pending.filter { $0.end > date }
            let current = live.first { !$0.isAllDay && $0.start <= date }
            return AgendaEntry(
                date: date, mode: mode, current: current,
                upcoming: live.filter { $0 != current && $0.start > date }
            )
        }
    }
}

struct AgendaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AgendaWidget", provider: AgendaProvider()) { entry in
            AgendaWidgetView(entry: entry)
                .widgetURL(PlanabyLinks.desk)
                .containerBackground(for: .widget) {
                    ZStack {
                        Color.black
                        RadialGradient(
                            colors: [entry.mode.tint.opacity(0.24), .clear],
                            center: .topLeading, startRadius: 0, endRadius: 220
                        )
                    }
                }
        }
        .configurationDisplayName("Plan")
        .description("Lo que tienes ahora y lo siguiente de tu plan.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct AgendaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AgendaEntry

    /// Lo destacado: lo que está en curso o, si no hay nada, lo siguiente.
    private var main: AgendaItem? { entry.current ?? entry.upcoming.first }
    private var rest: [AgendaItem] { Array(entry.upcoming.drop { $0 == main }) }

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        default: system
        }
    }

    // MARK: - Inicio

    private var system: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Eyebrow(text: entry.current != nil ? "Ahora" : "Próximo", color: main?.mode.tint ?? entry.mode.tint)
                Spacer(minLength: 0)
                Image(systemName: entry.mode.symbol)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityLabel("Modo \(entry.mode.title)")
            }
            if let main {
                Text(main.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(family == .systemSmall ? 3 : 2)
                when(main)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                if family == .systemMedium, !rest.isEmpty {
                    Divider().overlay(Theme.hairline)
                    ForEach(rest.prefix(2), id: \.self) { item in
                        HStack(spacing: 6) {
                            Image(systemName: item.kind.symbol)
                                .foregroundStyle(item.mode.tint)
                                .frame(width: 16)
                                .accessibilityHidden(true)
                            Text(item.title)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(item.isAllDay ? "Todo el día" : item.start.formatted(.dateTime.hour().minute()))
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .font(.caption)
                        .foregroundStyle(.white)
                    }
                }
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Text("Nada más en tu plan")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Planifica desde la pestaña Plan.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// «Hasta las 11:00», «En 25 min» o «Mañana, 9:00».
    @ViewBuilder
    private func when(_ item: AgendaItem) -> some View {
        if item.isAllDay {
            Text("Todo el día")
        } else if item.start <= entry.date {
            Text("Hasta las \(item.end.formatted(.dateTime.hour().minute()))")
        } else if item.start.timeIntervalSince(entry.date) < 3600 {
            Text("En \(Text(timerInterval: entry.date...item.start, countsDown: true))")
        } else if Calendar.current.isDate(item.start, inSameDayAs: entry.date) {
            Text("A las \(item.start.formatted(.dateTime.hour().minute()))")
        } else {
            Text(item.start.formatted(.dateTime.weekday(.wide).hour().minute()))
        }
    }

    // MARK: - Pantalla bloqueada

    @ViewBuilder
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let main {
                Label(entry.current != nil ? "Ahora" : "Próximo", systemImage: main.kind.symbol)
                    .font(.caption.weight(.semibold))
                Text(main.title)
                    .font(.headline)
                    .lineLimit(1)
                when(main)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Plan", systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                Text("Nada más en tu plan")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var inline: some View {
        if let main {
            if main.isAllDay || main.start <= entry.date {
                Text(main.title)
            } else {
                Text("\(main.start.formatted(.dateTime.hour().minute())) · \(main.title)")
            }
        } else {
            Text("Plan libre")
        }
    }
}
