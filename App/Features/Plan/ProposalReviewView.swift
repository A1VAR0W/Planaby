import SwiftData
import SwiftUI

/// Revisión de una propuesta: lo nuevo destacado sobre lo que ya hay (en gris), carga por día,
/// incluir o quitar bloques, editarlos y aceptar. Hasta aceptar no se guarda nada.
struct ProposalReviewView: View {
    @Binding var draft: PlanDraft
    let onAccepted: () -> Void
    @Environment(\.modelContext) private var context
    @Query(sort: \CalendarEvent.start) private var existing: [CalendarEvent]
    @State private var editingIndex: Int?

    var body: some View {
        let calendar = Calendar.current
        let days = Dictionary(grouping: draft.items.indices) { calendar.startOfDay(for: draft.items[$0].start) }
            .sorted { $0.key < $1.key }

        List {
            Section {
                Text(draft.summary)
                ForEach(draft.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.orange)
                }
                if draft.canMakeRoom {
                    Button {
                        withAnimation(.smooth) { draft = PlanBuilder.makeRoom(for: draft, context: context) }
                    } label: {
                        Label("Hacer hueco moviendo otros bloques", systemImage: "arrow.left.and.right")
                    }
                }
            }

            ForEach(days, id: \.key) { day in
                let current = existingEntries(on: day.key)
                let outside = externalEvents(on: day.key)
                let outsideLoad: TimeInterval = outside.filter { $0.isBusy && !$0.isAllDay }.reduce(0) { $0 + $1.interval.duration }
                Section {
                    ForEach(outside) { event in
                        ExternalAgendaRow(event: event)
                            .opacity(0.6)
                    }
                    ForEach(current) { entry in
                        ExistingRow(entry: entry)
                    }
                    ForEach(day.value, id: \.self) { index in
                        DraftRow(item: $draft.items[index]) { editingIndex = index }
                    }
                } header: {
                    HStack {
                        Text(day.key.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        Spacer()
                        Text(FocusStats.format(load(existing: current, new: day.value) + outsideLoad))
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("Propuesta")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await NotificationAccess.requestIfNeeded() }
                PlanBuilder.accept(draft, context: context)
                onAccepted()
            } label: {
                Text(draft.includedItems.count == 1 ? "Aceptar 1 elemento" : "Aceptar \(draft.includedItems.count) elementos")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.orange)
            .controlSize(.large)
            .disabled(draft.includedItems.isEmpty)
            .padding(.horizontal, Space.m)
            .padding(.bottom, Space.s)
        }
        .sheet(isPresented: Binding(get: { editingIndex != nil }, set: { if !$0 { editingIndex = nil } })) {
            if let index = editingIndex, draft.items.indices.contains(index) {
                NavigationStack { DraftItemEditor(item: $draft.items[index]) }
                    .presentationDetents([.medium])
            }
        }
    }

    private func existingEntries(on day: Date) -> [AgendaEntry] {
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: day) else { return [] }
        let range = DateInterval(start: day, end: end)
        // Los bloques que se recolocan ya aparecen como nuevos.
        let removed = Set(draft.removals)
        return existing
            .filter { !removed.contains($0.persistentModelID) }
            .flatMap { event in event.occurrences(in: range).map { AgendaEntry(event: event, interval: $0) } }
            .sorted { $0.interval.start < $1.interval.start }
    }

    /// Reuniones de Outlook, Teams y otros calendarios (de los dos planes: también ocupan).
    private func externalEvents(on day: Date) -> [ExternalEvent] {
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: day) else { return [] }
        return ExternalCalendars.shared.events(in: DateInterval(start: day, end: end)).sorted { $0.start < $1.start }
    }

    private func load(existing: [AgendaEntry], new indices: [Int]) -> TimeInterval {
        existing.reduce(0) { $0 + $1.interval.duration }
            + indices.map { draft.items[$0] }.filter(\.isIncluded).reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }
}

private struct ExistingRow: View {
    let entry: AgendaEntry

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: "calendar")
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.event.title).foregroundStyle(Theme.secondaryText)
                Text("\(entry.interval.start.formatted(date: .omitted, time: .shortened))–\(entry.interval.end.formatted(date: .omitted, time: .shortened)) · ya en tu calendario")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DraftRow: View {
    @Binding var item: PlanDraft.Item
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: Space.m) {
            Button {
                item.isIncluded.toggle()
            } label: {
                Image(systemName: item.isIncluded ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isIncluded ? item.mode.tint : Theme.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isIncluded ? "Incluido" : "No incluido")
            .accessibilityHint("Incluye o quita \(item.title) de la propuesta")

            Button(action: onEdit) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.body.weight(.medium))
                            .strikethrough(!item.isIncluded)
                        Label {
                            Text("\(item.start.formatted(date: .omitted, time: .shortened))–\(item.end.formatted(date: .omitted, time: .shortened)) · \(item.mode.title)")
                        } icon: {
                            Image(systemName: item.kind.symbol)
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Editar hora y duración")
        }
        .opacity(item.isIncluded ? 1 : 0.6)
        .sensoryFeedback(.selection, trigger: item.isIncluded)
    }
}

private struct DraftItemEditor: View {
    @Binding var item: PlanDraft.Item
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let duration = Binding<Int>(
            get: { Int(item.end.timeIntervalSince(item.start) / 60) },
            set: { item.end = item.start.addingTimeInterval(TimeInterval($0 * 60)) }
        )
        let start = Binding<Date>(
            get: { item.start },
            set: { newStart in
                let length = item.end.timeIntervalSince(item.start)
                item.start = newStart
                item.end = newStart.addingTimeInterval(length)
            }
        )

        Form {
            TextField("Título", text: $item.title)
            DatePicker("Empieza", selection: start)
            Stepper(value: duration, in: 5...480, step: 5) {
                LabeledContent("Duración", value: FocusStats.format(TimeInterval(duration.wrappedValue * 60)))
            }
            Toggle("Incluir en el plan", isOn: $item.isIncluded)
        }
        .navigationTitle("Bloque")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Listo", systemImage: "checkmark") { dismiss() }
            }
        }
    }
}
