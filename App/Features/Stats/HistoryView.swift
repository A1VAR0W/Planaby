import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \FocusSessionRecord.start, order: .reverse) private var sessions: [FocusSessionRecord]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Hoy")
                    Text(Self.format(todaySeconds))
                        .font(Theme.clock(56))
                    Text(sessions.count == 1 ? "1 sesión en total" : "\(sessions.count) sesiones en total")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section("Sesiones") {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "Sin sesiones todavía", systemImage: "circle.dashed",
                        description: Text("Las sesiones de más de un minuto aparecerán aquí.")
                    )
                }
                ForEach(sessions) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.methodName).font(.body.weight(.medium))
                            Text(session.start.formatted(date: .abbreviated, time: .shortened))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Self.format(session.focusedSeconds))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Historial")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Listo", systemImage: "checkmark") { dismiss() }
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
