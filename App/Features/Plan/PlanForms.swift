import SwiftData
import SwiftUI

/// Plantilla de evento o hábito (también para editar). Lo escribe el usuario, así que se guarda directamente.
struct EventForm: View {
    let event: CalendarEvent?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Para avisar si coincide con otra cita.
    @Query(sort: \CalendarEvent.start) private var saved: [CalendarEvent]

    @State private var title: String
    @State private var start: Date
    /// La hora de fin se elige directamente; la duración sale de ahí.
    @State private var end: Date
    @State private var mode: PlanMode
    @State private var kind: EventKind
    @State private var recurrence: Recurrence
    /// -1 = sin aviso.
    @State private var reminder: Int
    @State private var notes: String
    /// Más días con lo mismo a la misma hora (solo al crear y si no se repite).
    @State private var otherDays: Set<DateComponents> = []

    private static let reminderOptions = [-1, 0, 5, 10, 15, 30, 60, 1440]

    init(event: CalendarEvent?, day: Date, kind: EventKind) {
        self.event = event
        _title = State(initialValue: event?.title ?? "")
        let start = event?.start ?? Self.defaultStart(on: day)
        _start = State(initialValue: start)
        _end = State(initialValue: event?.end ?? start.addingTimeInterval(TimeInterval((kind == .habit ? 30 : 60) * 60)))
        _mode = State(initialValue: event?.mode ?? ModeController.shared.mode)
        _kind = State(initialValue: kind)
        _recurrence = State(initialValue: event?.recurrence ?? (kind == .habit ? .daily : .none))
        _reminder = State(initialValue: event.map { $0.reminderMinutes ?? -1 } ?? 15)
        _notes = State(initialValue: event?.notes ?? "")
    }

    var body: some View {
        Form {
            Section {
                TextField(kind == .habit ? "Hábito, p. ej. «Leer 30 min»" : "Título", text: $title)
                ModeField(mode: $mode)
            }

            Section {
                EventTimeFields(start: $start, end: $end, conflicts: conflicts, allowsSeveralDays: kind != .workBlock)
                if kind != .workBlock {
                    Picker("Repetir", selection: $recurrence) {
                        ForEach(Recurrence.allCases) { Text($0.title).tag($0) }
                    }
                }
            }

            if event == nil, recurrence == .none {
                Section {
                    MultiDatePicker("Otros días", selection: $otherDays, in: Calendar.current.startOfDay(for: .now)...)
                } header: {
                    Text(otherDays.isEmpty ? "Otros días" : "Otros días · \(otherDays.count)")
                } footer: {
                    Text("Marca más días para crear lo mismo, con el mismo inicio y fin, en cada uno (por ejemplo, varias clases o turnos).")
                }
            }

            Section {
                Picker("Aviso", selection: $reminder) {
                    ForEach(Self.reminderOptions, id: \.self) { Text(Self.reminderLabel($0)).tag($0) }
                }
            } footer: {
                if mode == .work && reminder >= 0 {
                    Text("Los avisos de Trabajo no suenan en modo Normal.")
                }
            }

            Section("Notas") {
                TextField("Opcional", text: $notes, axis: .vertical)
                    .lineLimit(2...6)
            }
        }
        .navigationTitle(event == nil ? (kind == .habit ? "Nuevo hábito" : "Nuevo evento") : "Editar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar", systemImage: "xmark") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", systemImage: "checkmark", action: save)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || EventSchedule.issue(times) != nil)
            }
        }
    }

    private var times: EventTimes { EventTimes(start: start, end: end) }

    /// Citas guardadas y de otros calendarios que coinciden con estas horas (sin contar esta).
    private var conflicts: [EventConflict] {
        guard EventSchedule.issue(times) == nil else { return [] }
        let candidates = PlanBuilder.conflictCandidates(
            saved: saved, range: DateInterval(start: start, end: end),
            excluding: Set([event?.persistentModelID].compactMap { $0 })
        )
        return EventSchedule.conflicts(times, with: candidates)
    }

    private func save() {
        guard EventSchedule.issue(times) == nil else { return }
        let reminderMinutes = reminder >= 0 ? reminder : nil
        let cleanTitle = title.trimmingCharacters(in: .whitespaces)
        if let event {
            event.title = cleanTitle
            event.start = start
            event.end = end
            event.mode = mode
            event.recurrence = kind == .workBlock ? .none : recurrence
            event.reminderMinutes = reminderMinutes
            event.notes = notes
        } else {
            // Cada día marcado, con las mismas horas de inicio y fin.
            for copy in [times] + extraDays.map({ EventSchedule.moving(times, toDay: $0) }) {
                context.insert(CalendarEvent(
                    title: cleanTitle, notes: notes, start: copy.start, end: copy.end,
                    mode: mode, kind: kind, recurrence: recurrence, reminderMinutes: reminderMinutes
                ))
            }
        }
        try? context.save()
        ReminderScheduler.shared.reschedule()
        if reminderMinutes != nil {
            Task { await NotificationAccess.requestIfNeeded() }
        }
        dismiss()
    }

    /// Los otros días marcados (sin repetir el primero).
    private var extraDays: [Date] {
        guard recurrence == .none else { return [] }
        let calendar = Calendar.current
        return otherDays
            .compactMap { calendar.date(from: $0) }
            .filter { !calendar.isDate($0, inSameDayAs: start) }
            .map { calendar.startOfDay(for: $0) }
            .sorted()
    }

    /// Hoy, a la siguiente hora en punto; otro día, a las 9.
    private static func defaultStart(on day: Date) -> Date {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) {
            let next = calendar.date(byAdding: .hour, value: 1, to: .now) ?? .now
            return calendar.date(bySetting: .minute, value: 0, of: next) ?? next
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }

    private static func reminderLabel(_ minutes: Int) -> String {
        switch minutes {
        case -1: "Sin aviso"
        case 0: "A la hora"
        case 1440: "1 día antes"
        case 60: "1 hora antes"
        default: "\(minutes) min antes"
        }
    }
}

/// Plantilla de tarea con fecha límite: se le pueden adjuntar capturas y archivos para que la IA
/// estime tiempo y dificultad; Planaby la reparte en bloques y enseña la propuesta.
struct TaskForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var mode = ModeController.shared.mode
    @State private var deadline = TaskForm.defaultDeadline()
    @State private var estimatedMinutes = 120
    @State private var priority = 1
    @State private var difficulty = 3
    @State private var notes = ""
    @State private var attachments: [ImportedAttachment] = []
    @State private var estimate: ComplexityEstimate?
    @State private var isEstimating = false
    @State private var estimateError: String?
    @State private var draft: PlanDraft?

    private var cleanTitle: String { title.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Form {
            Section {
                TextField("Qué hay que hacer", text: $title)
                ModeField(mode: $mode)
            }

            Section {
                ForEach(attachments) { file in
                    AttachmentLabel(name: file.name, kind: file.kind, text: file.text)
                }
                .onDelete { offsets in
                    for index in offsets { AttachmentStore.delete(attachments[index].fileName) }
                    attachments.remove(atOffsets: offsets)
                }
                AttachmentAdder { attachments.append($0) }
            } header: {
                Text("Material")
            } footer: {
                Text("Enunciados, capturas, apuntes… Se leen en el iPhone para estimar mejor la tarea.")
            }

            Section {
                Button {
                    Task { await runEstimate() }
                } label: {
                    HStack {
                        Label("Estimar con IA", systemImage: "sparkles")
                        Spacer()
                        if isEstimating { ProgressView() }
                    }
                }
                .disabled(cleanTitle.isEmpty || isEstimating || AIProvider.unavailableReason != nil)
                if let estimate {
                    EstimateSummary(estimate: estimate)
                }
                if let estimateError {
                    Text(estimateError)
                        .font(.subheadline)
                        .foregroundStyle(Theme.orange)
                }
            } footer: {
                if let reason = AIProvider.unavailableReason {
                    Text(reason)
                }
            }

            Section {
                DatePicker("Fecha límite", selection: $deadline, in: Date.now...)
                Stepper(value: $estimatedMinutes, in: 15...12000, step: estimatedMinutes < 60 ? 15 : 30) {
                    LabeledContent("Tiempo estimado", value: FocusStats.format(TimeInterval(estimatedMinutes * 60)))
                }
                DifficultyField(difficulty: $difficulty)
                PriorityField(priority: $priority)
            } footer: {
                Text("Planaby lo repartirá en bloques dentro de tu horario de \(mode.title), con lo más exigente en tus mejores horas, y te enseñará la propuesta antes de guardar nada.")
            }

            Section("Notas y pasos") {
                TextField("Opcional", text: $notes, axis: .vertical)
                    .lineLimit(2...8)
            }
        }
        .navigationTitle("Nueva tarea")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(!attachments.isEmpty)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar", systemImage: "xmark") {
                    attachments.forEach { AttachmentStore.delete($0.fileName) }
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Ver propuesta") {
                    let task = PlanDraft.Workload(
                        id: UUID(), title: cleanTitle, mode: mode, deadline: deadline,
                        estimatedMinutes: estimatedMinutes, priority: priority, difficulty: difficulty,
                        notes: notes, attachments: attachments
                    )
                    draft = PlanBuilder.draft(events: [], tasks: [task], context: context)
                }
                .disabled(cleanTitle.isEmpty)
            }
        }
        .navigationDestination(isPresented: Binding(get: { draft != nil }, set: { if !$0 { draft = nil } })) {
            if let binding = Binding($draft) {
                ProposalReviewView(draft: binding) { dismiss() }
            }
        }
    }

    private func runEstimate() async {
        isEstimating = true
        estimateError = nil
        defer { isEstimating = false }
        do {
            let result = try await PlanningAssistant.estimate(
                title: cleanTitle, notes: notes, deadline: deadline, attachmentTexts: attachments.map(\.text)
            )
            withAnimation(Motion.standard) {
                estimate = result
                estimatedMinutes = max(15, Int((Double(result.estimatedMinutes) / 15).rounded()) * 15)
                difficulty = result.difficulty
                if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !result.steps.isEmpty {
                    notes = result.stepsText
                }
            }
        } catch {
            estimateError = PlanningAssistant.message(for: error)
        }
    }

    private static func defaultDeadline() -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: 3, to: .now) ?? .now
        return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? day
    }
}

/// Selector de plan del elemento.
struct ModeField: View {
    @Binding var mode: PlanMode

    var body: some View {
        Picker("Plan", selection: $mode) {
            ForEach(PlanMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }
}
