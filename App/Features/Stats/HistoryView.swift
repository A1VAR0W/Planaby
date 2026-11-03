import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \FocusSessionRecord.start, order: .reverse) private var sessions: [FocusSessionRecord]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                LabeledContent("Hoy", value: Self.format(todaySeconds))
                LabeledContent("Sesiones totales", value: "\(sessions.count)")
            }

            Section("Sesiones") {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "Sin sesiones todavía", systemImage: "timer",
                        description: Text("Las sesiones de más de un minuto aparecerán aquí.")
                    )
                }
                ForEach(sessions) { session in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.methodName).font(.headline)
                        Text("\(session.start.formatted(date: .abbreviated, time: .shortened)) · \(Self.format(session.focusedSeconds)) · \(session.completedCycles) ciclos")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Historial")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Listo") { dismiss() }
            }
        }
    }

    private var todaySeconds: Double {
        sessions
            .filter { Calendar.current.isDateInToday($0.start) }
            .reduce(0) { $0 + $1.focusedSeconds }
    }

    private static func format(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
