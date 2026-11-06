import SwiftData
import SwiftUI

/// Bandeja del filtro de mensajes: lo urgente arriba, el ruido plegado. Es una copia para decidir
/// qué mirar en la pausa; los mensajes de verdad siguen en Mensajes y en el correo.
struct InboxView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(PlanInbox.self) private var planInbox
    @Query(sort: \MessageItem.received, order: .reverse) private var items: [MessageItem]
    @State private var showsNoise = false
    @State private var confirmingClear = false
    private let mail = MailInbox.shared

    var body: some View {
        List {
            if let error = mail.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.orange)
                    .font(.subheadline)
            }
            ForEach(MessageCategory.allCases) { category in
                let list = items.filter { $0.category == category }
                if !list.isEmpty {
                    Section {
                        if category != .noise || showsNoise {
                            ForEach(list) { item in
                                MessageRow(item: item)
                                    .contentShape(.rect)
                                    .onTapGesture { item.isRead.toggle() }
                                    .swipeActions(edge: .leading) {
                                        Button("Al plan", systemImage: "sparkles") { addToPlan(item) }
                                            .tint(Theme.orange)
                                    }
                                    .swipeActions {
                                        Button("Borrar", systemImage: "trash", role: .destructive) {
                                            context.delete(item)
                                            try? context.save()
                                        }
                                    }
                                    // Mantener pulsado para corregir a la IA.
                                    .contextMenu {
                                        ForEach(MessageCategory.allCases.filter { $0 != item.category }) { other in
                                            Button("Mover a \(other.title)", systemImage: other.symbol) { MessageTriage.learn(item, category: other) }
                                        }
                                    }
                            }
                        } else {
                            Button("Mostrar \(list.count == 1 ? "1 mensaje" : "\(list.count) mensajes")") { showsNoise = true }
                        }
                    } header: {
                        Label("\(category.title) · \(list.filter { !$0.isRead }.count)", systemImage: category.symbol)
                    }
                }
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    "Bandeja vacía",
                    systemImage: "tray",
                    description: Text("Aquí llegan los mensajes y correos filtrados. Actívalo en Ajustes › Filtro de mensajes.")
                )
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .refreshable { await mail.check(context: context) }
        .navigationTitle("Bandeja")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cerrar", systemImage: "xmark") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Marcar todo como leído", systemImage: "checkmark.circle") {
                        for item in items where !item.isRead { item.isRead = true }
                        try? context.save()
                    }
                    Button("Vaciar la bandeja", systemImage: "trash", role: .destructive) { confirmingClear = true }
                } label: {
                    Label("Más", systemImage: "ellipsis")
                }
                .disabled(items.isEmpty)
            }
        }
        .confirmationDialog("¿Vaciar la bandeja?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Vaciar", role: .destructive) {
                for item in items { context.delete(item) }
                try? context.save()
            }
        } message: {
            Text("Solo se borran las copias de Planaby; los mensajes y correos siguen en sus apps.")
        }
    }

    /// Lo manda al chat del plan para convertirlo en tarea o cita.
    private func addToPlan(_ item: MessageItem) {
        item.isRead = true
        let what = item.summary.isEmpty ? (item.subject.isEmpty ? item.body : item.subject) : item.summary
        planInbox.pending = "\(item.sender.isEmpty ? "" : "De \(item.sender): ")\(what)"
        dismiss()
    }
}

private struct MessageRow: View {
    let item: MessageItem

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: item.source.symbol)
                .font(.subheadline)
                .foregroundStyle(item.isRead ? Theme.secondaryText : Theme.orange)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.sender.isEmpty ? item.source.title : item.sender)
                        .font(.subheadline.weight(item.isRead ? .regular : .semibold))
                        .lineLimit(1)
                    Spacer(minLength: Space.s)
                    Text(item.received.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                if !item.subject.isEmpty {
                    Text(item.subject).font(.subheadline).lineLimit(1)
                }
                Text(item.summary.isEmpty ? item.body : item.summary)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, Space.xs)
        .opacity(item.isRead ? 0.7 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.isRead ? "Leído" : "Sin leer")
        .accessibilityHint("Toca para marcar como leído o sin leer")
    }
}
