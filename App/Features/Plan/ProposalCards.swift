import SwiftUI

/// Colores de los cambios. Nunca van solos: cada fila lleva también icono y texto.
enum ProposalColors {
    static let added = Color(red: 0.40, green: 0.85, blue: 0.55)
    static let modified = Theme.orange
    static let removed = Color.white.opacity(0.45)
}

/// La tarjeta compacta de la propuesta en el chat: cifras, avisos y acciones. Solo la propuesta
/// activa tiene botones; las sustituidas se quedan como registro.
struct ProposalCard: View {
    let draft: PlanDraft?
    let state: PlanningAssistant.ProposalState
    let isFirst: Bool
    let asksToAccept: Bool
    let canUndo: Bool
    let canRedo: Bool
    let onReview: () -> Void
    let onModify: () -> Void
    let onAccept: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(state == .active ? Color.white : Theme.secondaryText)
                Spacer(minLength: Space.s)
                if state == .active {
                    if canUndo {
                        iconButton("arrow.uturn.backward", label: "Deshacer el último cambio", action: onUndo)
                    }
                    if canRedo {
                        iconButton("arrow.uturn.forward", label: "Rehacer", action: onRedo)
                    }
                }
            }

            if state == .active, let draft {
                counts(draft)
                if asksToAccept {
                    Button(action: onAccept) {
                        Label("Aceptar propuesta", systemImage: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.orange)
                }
                HStack(spacing: Space.s) {
                    Button(action: onReview) {
                        Label("Revisar propuesta", systemImage: "checklist")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(asksToAccept ? Color.white : Color.black)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .modifier(ProminentIf(active: !asksToAccept))
                    Button(action: onModify) {
                        Label("Modificar con IA", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .padding(Space.m)
        .background(Theme.surface, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(state == .active ? Theme.orange.opacity(0.45) : Theme.hairline)
        }
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        switch state {
        case .active: isFirst ? "Tu propuesta está lista" : "Propuesta actualizada"
        case .replaced: "Versión anterior (sustituida)"
        case .accepted: "Guardada en tu calendario"
        }
    }

    private var symbol: String {
        switch state {
        case .active: "sparkles"
        case .replaced: "clock.arrow.circlepath"
        case .accepted: "checkmark.circle"
        }
    }

    private func counts(_ draft: PlanDraft) -> some View {
        let tasks = draft.tasks.count
        let events = draft.newEvents.filter(\.isIncluded).count
        let blocks = draft.blocks.filter(\.isIncluded).count
        let parts = [
            tasks > 0 ? (tasks == 1 ? "1 tarea" : "\(tasks) tareas") : nil,
            events > 0 ? (events == 1 ? "1 cita" : "\(events) citas") : nil,
            blocks > 0 ? (blocks == 1 ? "1 bloque" : "\(blocks) bloques") : nil,
        ].compactMap { $0 }
        return VStack(alignment: .leading, spacing: Space.xs) {
            Text(parts.isEmpty ? "Sin cambios en el calendario" : parts.joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            if !draft.warnings.isEmpty {
                Label(draft.warnings.count == 1 ? "1 aviso" : "\(draft.warnings.count) avisos", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.orange)
            }
        }
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.orange)
        .accessibilityLabel(label)
    }
}

private struct ProminentIf: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.buttonStyle(.glassProminent).tint(Theme.orange)
        } else {
            content.buttonStyle(.glass)
        }
    }
}

/// «Reunión: miércoles → viernes». Añadido en verde, cambiado en naranja, quitado tachado en gris;
/// siempre con icono y palabra, no solo color.
struct ProposalChangeList: View {
    let changes: [ProposalChange]
    var dimmed = false
    private let limit = 6

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(changes.prefix(limit)) { change in
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Image(systemName: symbol(change.kind))
                        .foregroundStyle(color(change.kind))
                        .accessibilityHidden(true)
                    Text(change.text)
                        .font(.footnote)
                        .strikethrough(change.kind == .removed)
                        .foregroundStyle(change.kind == .removed ? ProposalColors.removed : Color.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibility(change))
            }
            if changes.count > limit {
                Text("y \(changes.count - limit) cambios más")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .opacity(dimmed ? 0.6 : 1)
    }

    private func symbol(_ kind: ProposalChange.Kind) -> String {
        switch kind {
        case .added: "plus.circle.fill"
        case .modified: "pencil.circle.fill"
        case .removed: "minus.circle.fill"
        case .moved: "arrow.left.arrow.right.circle.fill"
        }
    }

    private func color(_ kind: ProposalChange.Kind) -> Color {
        switch kind {
        case .added: ProposalColors.added
        case .modified, .moved: ProposalColors.modified
        case .removed: ProposalColors.removed
        }
    }

    private func accessibility(_ change: ProposalChange) -> String {
        switch change.kind {
        case .added, .removed, .moved: change.text
        case .modified: "Cambiado. " + change.text.replacingOccurrences(of: "→", with: "pasa a")
        }
    }
}

/// Atajos para pedir cambios: solo los que tienen sentido con esta propuesta.
struct ProposalChips: View {
    struct Chip: Identifiable {
        let id: String
        let symbol: String
        /// Texto para empezar la petición; nil = acción directa (deshacer).
        let starter: String?
    }

    let draft: PlanDraft
    let canUndo: Bool
    let onStart: (String) -> Void
    let onUndo: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Space.s) {
                ForEach(chips) { chip in
                    Button {
                        if let starter = chip.starter { onStart(starter) } else { onUndo() }
                    } label: {
                        Label(chip.id, systemImage: chip.symbol)
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, Space.m)
                            .frame(minHeight: 36)
                            .background(Theme.surface, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, Space.m)
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Atajos para modificar la propuesta")
    }

    private var chips: [Chip] {
        var chips: [Chip] = []
        let events = draft.newEvents
        let tasks = draft.orderedTasks
        if let event = events.first {
            chips.append(Chip(id: "Cambiar horario", symbol: "calendar", starter: events.count == 1 ? "Mueve «\(event.title)» al " : "Mueve "))
        }
        if let task = tasks.first {
            chips.append(Chip(id: "Ajustar duración", symbol: "timer", starter: tasks.count == 1 ? "Que «\(task.title)» dure " : "Que dure "))
        }
        if tasks.count >= 2 {
            chips.append(Chip(id: "Priorizar", symbol: "arrow.up.to.line", starter: "Pon primero "))
        }
        if !events.isEmpty || !tasks.isEmpty {
            chips.append(Chip(id: "Quitar", symbol: "minus.circle", starter: "Quita "))
        }
        chips.append(Chip(id: "Añadir algo", symbol: "plus", starter: "Añade "))
        if canUndo {
            chips.append(Chip(id: "Deshacer", symbol: "arrow.uturn.backward", starter: nil))
        }
        return chips
    }
}

/// «¿Cuál quieres mover?» con una opción por elemento.
struct ProposalOptionsView: View {
    let options: [ProposalOption]
    let onChoose: (ProposalOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(options) { option in
                Button { onChoose(option) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.title)
                            .font(.subheadline.weight(.semibold))
                        Text(option.detail)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, Space.m)
                    .background(Theme.surface, in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .accessibilityHint("Elige esta opción")
            }
        }
    }
}
