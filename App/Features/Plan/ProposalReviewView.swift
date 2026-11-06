import SwiftData
import SwiftUI

/// Revisión de una propuesta: citas y tareas editables, lo nuevo destacado sobre lo que ya hay
/// (en gris), carga por día y aceptar. Hasta aceptar no se guarda nada.
///
/// Los cambios se hacen sobre la misma propuesta (mismos identificadores) con `ProposalEditor`,
/// y solo se recoloca lo necesario, así que sobreviven a los cambios que luego pida a la IA.
struct ProposalReviewView: View {
    @Binding var draft: PlanDraft
    let onAccepted: () -> Void
    /// «Pedir cambios a la IA»: vuelve al chat con la misma propuesta.
    var onAskAI: (() -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Query(sort: \CalendarEvent.start) private var existing: [CalendarEvent]
    @State private var editing: Editing?

    enum Editing: Identifiable {
        case event(UUID), task(UUID), block(UUID)

        var id: String {
            switch self {
            case .event(let id): "e\(id)"
            case .task(let id): "t\(id)"
            case .block(let id): "b\(id)"
            }
        }
    }

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
                if let onAskAI {
                    Button(action: onAskAI) {
                        Label("Pedir cambios a la IA", systemImage: "sparkles")
                    }
                }
            }

            if !draft.newEvents.isEmpty {
                Section("Citas") {
                    ForEach(draft.newEvents) { event in
                        ProposalEventRow(event: event, code: draft.ref(event.id)) { editing = .event(event.id) }
                    }
                }
            }

            if !draft.tasks.isEmpty {
                Section {
                    ForEach(draft.orderedTasks) { task in
                        ProposalTaskRow(task: task, code: draft.ref(task.id), blocks: draft.blocks(of: task.id).filter(\.isIncluded)) {
                            editing = .task(task.id)
                        }
                    }
                } header: {
                    Text("Tareas")
                } footer: {
                    Text(draft.order.isEmpty ? "En orden de entrega." : "En el orden que has pedido.")
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
                        DraftRow(item: $draft.items[index]) {
                            let item = draft.items[index]
                            editing = item.kind == .workBlock ? .block(item.id) : .event(item.id)
                        }
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
                // Siempre la última versión: la que se está viendo.
                PlanBuilder.accept(draft, context: context)
                onAccepted()
            } label: {
                Text("Aceptar propuesta")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.orange)
            .controlSize(.large)
            .disabled(draft.includedItems.isEmpty && draft.tasks.isEmpty)
            .accessibilityHint(draft.includedItems.count == 1 ? "Guarda 1 elemento en tu calendario" : "Guarda \(draft.includedItems.count) elementos en tu calendario")
            .padding(.horizontal, Space.m)
            .padding(.bottom, Space.s)
        }
        .sheet(item: $editing) { target in
            NavigationStack { editor(for: target) }
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private func editor(for target: Editing) -> some View {
        switch target {
        case .event(let id):
            if let event = draft.items.first(where: { $0.id == id }) {
                ProposalEventEditor(event: event) { edited in
                    update(event: edited)
                } onRemove: {
                    remove(id)
                }
            }
        case .task(let id):
            if let task = draft.tasks.first(where: { $0.id == id }) {
                ProposalTaskEditor(task: task, blocks: draft.blocks(of: id)) { changes in
                    update(task: ProposalTarget(text: draft.ref(id), kind: .task), changes: changes)
                } onRemove: {
                    remove(id)
                }
            }
        case .block(let id):
            if let index = draft.items.firstIndex(where: { $0.id == id }) {
                DraftItemEditor(item: $draft.items[index])
            }
        }
    }

    // MARK: Cambios

    /// Una cita cambiada a mano: se queda con su identificador y solo se recolocan los bloques
    /// que ahora la pisen.
    private func update(event edited: PlanDraft.Item) {
        guard let index = draft.items.firstIndex(where: { $0.id == edited.id }) else { return }
        var next = draft
        next.items[index] = edited
        draft = PlanBuilder.replan(next, affected: [], context: context)
    }

    private func update(task target: ProposalTarget, changes: ProposalChanges) {
        guard !changes.isEmpty, case .applied(let outcome) = ProposalEditor.apply([.update(target, changes)], to: draft, mergeSimilar: false) else { return }
        draft = PlanBuilder.replan(outcome.draft, affected: outcome.affectedTasks, context: context)
    }

    private func remove(_ id: UUID) {
        var next = draft
        ProposalEditor.remove(id, from: &next)
        draft = PlanBuilder.replan(next, affected: [], context: context)
    }

    // MARK: Agenda

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

// MARK: - Filas

private struct ProposalEventRow: View {
    let event: PlanDraft.Item
    let code: String
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: Space.m) {
                Image(systemName: event.kind.symbol)
                    .foregroundStyle(event.mode.tint)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.body.weight(.medium))
                        .strikethrough(!event.isIncluded)
                    Text(detail)
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
        .opacity(event.isIncluded ? 1 : 0.6)
        .accessibilityHint("Editar la cita")
    }

    private var detail: String {
        var parts = [
            event.start.formatted(.dateTime.weekday(.wide).day().hour().minute()),
            ProposalFormat.minutes(event.durationMinutes),
            event.recurrence == .none ? event.mode.title : event.recurrence.title,
        ]
        if !event.isIncluded { parts.append("sin incluir") }
        return parts.joined(separator: " · ")
    }
}

private struct ProposalTaskRow: View {
    let task: PlanDraft.Workload
    let code: String
    let blocks: [PlanDraft.Item]
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: Space.m) {
                Image(systemName: "square.stack.3d.up")
                    .foregroundStyle(task.mode.tint)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.body.weight(.medium))
                    Text("\(ProposalFormat.minutes(task.requestedMinutes)) · entrega \(task.deadline.formatted(.dateTime.weekday(.abbreviated).day().hour().minute())) · prioridad \(ProposalFormat.priority(task.priority))")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    Text(blocks.count == 1 ? "1 bloque" : "\(blocks.count) bloques")
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
        .accessibilityHint("Editar la tarea")
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
                            Text("\(item.start.formatted(date: .omitted, time: .shortened))–\(item.end.formatted(date: .omitted, time: .shortened)) · \(item.recurrence == .none ? item.mode.title : item.recurrence.title)")
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
            .accessibilityHint(item.kind == .workBlock ? "Editar hora y duración del bloque" : "Editar la cita")
        }
        .opacity(item.isIncluded ? 1 : 0.6)
        .sensoryFeedback(.selection, trigger: item.isIncluded)
    }
}

// MARK: - Editores

/// Un bloque de trabajo suelto: moverlo a mano lo deja fijo (no se recoloca si no choca).
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

/// Una cita de la propuesta: título, día, hora, duración, repetición, plan y aviso.
private struct ProposalEventEditor: View {
    @State var event: PlanDraft.Item
    let onSave: (PlanDraft.Item) -> Void
    let onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let duration = Binding<Int>(
            get: { event.durationMinutes },
            set: { event.end = event.start.addingTimeInterval(TimeInterval($0 * 60)) }
        )
        let start = Binding<Date>(
            get: { event.start },
            set: { newStart in
                let length = event.end.timeIntervalSince(event.start)
                event.start = newStart
                event.end = newStart.addingTimeInterval(length)
            }
        )
        let reminder = Binding<Int>(
            get: { event.reminderMinutes ?? 0 },
            set: { event.reminderMinutes = $0 > 0 ? $0 : nil }
        )

        Form {
            TextField("Título", text: $event.title)
            DatePicker("Empieza", selection: start)
            Stepper(value: duration, in: 5...720, step: 5) {
                LabeledContent("Duración", value: ProposalFormat.minutes(duration.wrappedValue))
            }
            Picker("Se repite", selection: $event.recurrence) {
                ForEach(Recurrence.allCases) { Text($0.title).tag($0) }
            }
            Picker("Plan", selection: $event.mode) {
                ForEach(PlanMode.allCases) { Text($0.title).tag($0) }
            }
            Picker("Aviso", selection: reminder) {
                Text("Sin aviso").tag(0)
                ForEach([5, 10, 15, 30, 60], id: \.self) { Text("\($0) min antes").tag($0) }
            }
            Toggle("Incluir en el plan", isOn: $event.isIncluded)
            Section {
                Button("Quitar de la propuesta", systemImage: "trash", role: .destructive) {
                    onRemove()
                    dismiss()
                }
            }
        }
        .navigationTitle("Cita")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar", systemImage: "xmark") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Listo", systemImage: "checkmark") {
                    onSave(event)
                    dismiss()
                }
            }
        }
    }
}

/// Una tarea de la propuesta. Al terminar, los cambios se aplican como una operación más
/// (igual que si se pidieran a la IA) y solo se recolocan sus bloques.
private struct ProposalTaskEditor: View {
    let original: PlanDraft.Workload
    let blocks: [PlanDraft.Item]
    let onSave: (ProposalChanges) -> Void
    let onRemove: () -> Void
    @State private var task: PlanDraft.Workload
    @State private var minutes: Int
    @Environment(\.dismiss) private var dismiss

    init(task: PlanDraft.Workload, blocks: [PlanDraft.Item], onSave: @escaping (ProposalChanges) -> Void, onRemove: @escaping () -> Void) {
        original = task
        self.blocks = blocks
        self.onSave = onSave
        self.onRemove = onRemove
        _task = State(initialValue: task)
        _minutes = State(initialValue: task.requestedMinutes)
    }

    var body: some View {
        Form {
            TextField("Título", text: $task.title)
            DatePicker("Entrega", selection: $task.deadline)
            Stepper(value: $minutes, in: 15...12000, step: 15) {
                LabeledContent("Tiempo total", value: ProposalFormat.minutes(minutes))
            }
            Picker("Prioridad", selection: $task.priority) {
                Text("Baja").tag(0)
                Text("Media").tag(1)
                Text("Alta").tag(2)
            }
            Stepper(value: $task.difficulty, in: 1...5) {
                LabeledContent("Dificultad", value: "\(task.difficulty) de 5")
            }
            Picker("Plan", selection: $task.mode) {
                ForEach(PlanMode.allCases) { Text($0.title).tag($0) }
            }
            Section("Notas") {
                TextField("Notas", text: $task.notes, axis: .vertical)
                    .lineLimit(2...6)
                if !task.attachments.isEmpty {
                    Label(task.attachments.map(\.name).joined(separator: ", "), systemImage: "paperclip")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Section(blocks.isEmpty ? "Sin bloques" : "Bloques") {
                ForEach(blocks) { block in
                    LabeledContent(
                        block.start.formatted(.dateTime.weekday(.wide).day().hour().minute()),
                        value: ProposalFormat.minutes(block.durationMinutes)
                    )
                    .opacity(block.isIncluded ? 1 : 0.5)
                }
            }
            Section {
                Button("Quitar de la propuesta", systemImage: "trash", role: .destructive) {
                    onRemove()
                    dismiss()
                }
            }
        }
        .navigationTitle("Tarea")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar", systemImage: "xmark") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Listo", systemImage: "checkmark") {
                    onSave(changes)
                    dismiss()
                }
            }
        }
    }

    private var changes: ProposalChanges {
        var changes = ProposalChanges()
        if task.title != original.title { changes.title = task.title }
        if task.deadline != original.deadline { changes.deadline = task.deadline }
        if minutes != original.requestedMinutes { changes.minutes = minutes }
        if task.priority != original.priority { changes.priority = task.priority }
        if task.difficulty != original.difficulty { changes.difficulty = task.difficulty }
        if task.mode != original.mode { changes.mode = task.mode }
        if task.notes != original.notes { changes.notes = task.notes }
        return changes
    }
}
