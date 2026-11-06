import SwiftData
import SwiftUI

/// Resumen del día en Progreso. Sale de las cifras, sin IA; si Apple Intelligence está
/// disponible, se puede pedir un resumen redactado con una sugerencia para mañana. A la IA solo
/// le llegan cifras, nunca títulos de mensajes ni notas.
struct DaySummaryCard: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FocusSessionRecord.start, order: .reverse) private var sessions: [FocusSessionRecord]
    @State private var review: DayReview?
    @State private var loading = false

    var body: some View {
        // Las sesiones de la consulta solo sirven para refrescar al terminar una.
        let _ = sessions.count
        let facts = DayFacts.today(context: context)
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Hoy").font(.headline)
            Text(review?.summary ?? facts.plainSummary)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let suggestion = review?.suggestion, !suggestion.isEmpty {
                Label(suggestion, systemImage: "lightbulb")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            if AIProvider.isAvailable, review == nil, !facts.isEmpty {
                Button {
                    Task {
                        loading = true
                        review = await AIProvider.shared.dailyReview(facts: facts)
                        loading = false
                    }
                } label: {
                    if loading {
                        ProgressView()
                    } else {
                        Label("Resumir con Apple Intelligence", systemImage: "sparkles")
                            .font(.footnote.weight(.medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.orange)
                .frame(minHeight: 44)
                .disabled(loading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
    }
}
