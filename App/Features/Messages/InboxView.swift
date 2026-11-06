import SwiftData
import SwiftUI

/// Bandeja de comunicaciones: «Pendientes» (lo que toca ahora según el momento de la sesión) y
/// «Todo» por categorías, con el ruido plegado. Es una copia para decidir qué mirar en la pausa;
/// los mensajes de verdad siguen en sus apps.
struct InboxView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(PlanInbox.self) private var planInbox
    @Environment(FocusTimer.self) private var timer
    @Query(sort: \MessageItem.received, order: .reverse) private var items: [MessageItem]
    @State private var comms = CommsCenter.shared
    @State private var scope = Scope.pending
    @State private var showsNoise = false
    @State private var confirmingClear = false
    @State private var summary: String?
    @State private var summarizing = false
    @State private var addedTask: String?
    private let mail = MailInbox.shared

    enum Scope: String, CaseIterable, Identifiable {
        case pending = "Pendientes"
        case all = "Todo"
        var id: String { rawValue }
    }

    private var phase: CommPhase { CommsCenter.phase(of: timer.state) }

    var body: some View {
        List {
            Section {
                Picker("Ver", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if let error = mail.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.orange)
                    .font(.subheadline)
            }
            if scope == .pending {
                pendingSection
            } else {
                allSections
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    "Bandeja vacía",
                    systemImage: "tray",
                    description: Text("Aquí llegan las comunicaciones filtradas. Actívalo en Ajustes › Filtro de mensajes.")
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
                    Button("Marcar todo como revisado", systemImage: "checkmark.circle") {
                        for item in items where item.isOpen { comms.markReviewed(item) }
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
                comms.refresh()
            }
        } message: {
            Text("Solo se borran las copias de Planaby; los mensajes siguen en sus apps.")
        }
        .alert("Añadido al plan", isPresented: Binding(get: { addedTask != nil }, set: { if !$0 { addedTask = nil } })) {
            Button("Vale", role: .cancel) {}
        } message: {
            Text(addedTask ?? "")
        }
    }

    // MARK: Pendientes

    @ViewBuilder
    private var pendingSection: some View {
        let pending = comms.items(for: phase == .focus ? .focus : .idle, from: items)
        let held = phase == .focus ? comms.items(for: .idle, from: items).count - pending.count : 0
        Section {
            if pending.isEmpty {
                Text(phase == .focus ? "Nada importante de trabajo. Sigue con lo tuyo." : "No tienes nada pendiente.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(pending) { item in
                row(item)
            }
            if held > 0 {
                Label(held == 1 ? "1 personal espera al descanso" : "\(held) personales esperan al descanso", systemImage: "moon.zzz")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        } header: {
            if !pending.isEmpty {
                Text(comms.breakdown(pending).map { "\($0.app) \($0.count)" }.joined(separator: " · "))
            }
        } footer: {
            if !pending.isEmpty {
                VStack(alignment: .leading, spacing: Space.s) {
                    if let summary {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                    Button {
                        summarizing = true
                        Task {
                            summary = await comms.digestSummary(pending)
                            summarizing = false
                        }
                    } label: {
                        Label(summarizing ? "Resumiendo…" : "Resumir lo pendiente", systemImage: "text.badge.star")
                            .font(.subheadline.weight(.semibold))
                    }
                    .disabled(summarizing)
                    .frame(minHeight: 44)
                }
                .padding(.top, Space.s)
            }
        }
    }

    // MARK: Todo

    @ViewBuilder
    private var allSections: some View {
        ForEach(MessageCategory.allCases) { category in
            let list = items.filter { $0.category == category }
            if !list.isEmpty {
                Section {
                    if category != .noise || showsNoise {
                        ForEach(list) { item in row(item) }
                    } else {
                        Button("Mostrar \(list.count == 1 ? "1 mensaje" : "\(list.count) mensajes")") { showsNoise = true }
                    }
                } header: {
                    Label("\(category.title) · \(list.filter(\.isOpen).count)", systemImage: category.symbol)
                }
            }
        }
    }

    // MARK: Fila

    private func row(_ item: MessageItem) -> some View {
        MessageRow(item: item)
            .contentShape(.rect)
            .onTapGesture { item.isOpen ? comms.markReviewed(item) : comms.reopen(item) }
            .swipeActions(edge: .leading) {
                Button("Revisado", systemImage: "checkmark") { comms.markReviewed(item) }
                    .tint(.green)
                Button("Respondido", systemImage: "arrowshape.turn.up.left") { comms.markReplied(item) }
                    .tint(.blue)
            }
            .swipeActions {
                Button("Borrar", systemImage: "trash", role: .destructive) {
                    context.delete(item)
                    try? context.save()
                    comms.refresh()
                }
                Button("Posponer", systemImage: "clock") { comms.snooze(item) }
                    .tint(.gray)
                Button("Al plan", systemImage: "plus.square.on.square") {
                    addedTask = comms.addToPlan(item).title
                }
                .tint(Theme.orange)
            }
            .contextMenu {
                CommActionButtons(item: item)
                Button("Planificar con la IA", systemImage: "sparkles") { planWithAI(item) }
                // Mantener pulsado para corregir a la IA.
                Menu("Mover a…", systemImage: "arrow.right.circle") {
                    ForEach(MessageCategory.allCases.filter { $0 != item.category }) { other in
                        Button(other.title, systemImage: other.symbol) {
                            MessageTriage.learn(item, category: other)
                            comms.refresh()
                        }
                    }
                }
            }
    }

    /// Lo manda al chat del plan para convertirlo en tarea o cita.
    private func planWithAI(_ item: MessageItem) {
        comms.markReviewed(item)
        let what = item.summary.isEmpty ? (item.subject.isEmpty ? item.body : item.subject) : item.summary
        planInbox.pending = "\(item.sender.isEmpty ? "" : "De \(item.sender): ")\(what)"
        dismiss()
    }
}

private struct MessageRow: View {
    let item: MessageItem

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: item.app.symbol)
                .font(.subheadline)
                .foregroundStyle(item.isOpen ? Theme.orange : Theme.secondaryText)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.sender.isEmpty ? item.appTitle : item.sender)
                        .font(.subheadline.weight(item.isOpen ? .semibold : .regular))
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
                HStack(spacing: Space.s) {
                    Text(item.appTitle)
                    if item.needsReply, item.repliedAt == nil {
                        Label("Espera respuesta", systemImage: "arrowshape.turn.up.left.fill")
                            .foregroundStyle(Theme.orange)
                    }
                    if item.repliedAt != nil {
                        Label("Respondido", systemImage: "checkmark")
                    }
                    if let until = item.snoozedUntil, until > .now {
                        Label("Hasta las \(until.formatted(date: .omitted, time: .shortened))", systemImage: "clock")
                    }
                }
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
                .labelStyle(.titleAndIcon)
            }
        }
        .padding(.vertical, Space.xs)
        .opacity(item.isOpen ? 1 : 0.7)
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.isOpen ? "Pendiente" : "Revisado")
        .accessibilityHint("Toca para marcar como revisado o pendiente. Mantén pulsado para más acciones.")
    }
}
