import SwiftUI

/// Respuesta a «¿Trabajo o Normal?» cuando la IA no sabe en qué plan va algo.
struct ModeChoice: View {
    var tint: Color = Theme.orange
    let onChoose: (PlanMode) -> Void

    var body: some View {
        HStack(spacing: Space.s) {
            ForEach(PlanMode.allCases) { mode in
                Button { onChoose(mode) } label: {
                    Label(mode.title, systemImage: mode.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(minHeight: 32)
                }
                .buttonStyle(.glassProminent)
                .tint(tint)
                .controlSize(.large)
                .accessibilityHint("Lo pone en tu plan \(mode.title)")
            }
        }
    }
}
