import SwiftData
import SwiftUI

/// Una sola sugerencia, discreta, en Enfoque sin sesión. Explica por qué y se puede probar,
/// dejar para más adelante o desactivar.
struct AdaptiveSuggestionCard: View {
    @Environment(ModeController.self) private var modes
    @Query(sort: \FocusSessionRecord.start, order: .reverse) private var sessions: [FocusSessionRecord]
    @Query(sort: \DistractionRecord.date, order: .reverse) private var distractions: [DistractionRecord]
    @State private var coordinator = AdaptiveFocusCoordinator.shared
    @State private var showsReason = false

    var body: some View {
        if let recommendation = coordinator.suggestion(
            sessions: Array(sessions.prefix(200)), distractions: Array(distractions.prefix(300)), mode: modes.mode
        ) {
            VStack(alignment: .leading, spacing: Space.s) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showsReason.toggle() }
                } label: {
                    HStack(spacing: Space.s) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Theme.orange)
                            .accessibilityHidden(true)
                        Text(recommendation.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.secondaryText)
                            .rotationEffect(.degrees(showsReason ? 180 : 0))
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 32)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(showsReason ? "Oculta el motivo" : "Muestra por qué te lo propongo")

                if showsReason {
                    Text(recommendation.reason)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }

                HStack(spacing: Space.s) {
                    Button(recommendation.isActionable ? "Probar" : "Entendido") {
                        withAnimation(.easeOut(duration: 0.2)) { coordinator.accept(recommendation) }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.orange)
                    .foregroundStyle(.black)
                    Button("Ahora no") {
                        withAnimation(.easeOut(duration: 0.2)) { coordinator.dismiss(recommendation) }
                    }
                    .buttonStyle(.glass)
                    Spacer(minLength: 0)
                    Menu {
                        Button("No sugerir más", systemImage: "bell.slash") { coordinator.isEnabled = false }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityLabel("Más opciones")
                }
                .font(.subheadline.weight(.medium))
            }
            .padding(Space.m)
            .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardRadius))
            .transition(.opacity)
        }
    }
}
