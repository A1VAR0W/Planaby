import SwiftData
import SwiftUI

/// Plantilla de evento o hábito (también para editar). Lo escribe el usuario, así que se guarda directamente.
struct EventForm: View {
    let event: CalendarEvent?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var start: Date
    @State private var durationMinutes: Int
    @State private var mode: PlanMode
    @State private var kind: EventKind
    @State private var recurrence: Recurrence
    /// -1 = sin aviso.
    @State private var reminder: Int
    @State private var notes: String

    private static let reminderOptions = [-1, 0, 5, 10, 15, 30, 60, 1440]

    init(event: CalendarEvent?, day: Date, kind: EventKind) {
        self.event = event
        _title = State(initialValue: event?.title ?? "")
        _start = State(initialValue: event?.start ?? Self.defaultStart(on: day))
        _durationMinutes = State(initialValue: event.map { Int($0.duration / 60) } ?? (kind == .habit ? 30 : 60))
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
                DatePicker("Empieza", selection: $start)
                Stepper(value: $durationMinutes, in: 5...720, step: durationMinutes < 30 ? 5 : 15) {
                    LabeledContent("Duración", value: FocusStats.format(TimeInterval(durationMinutes * 60)))
                }
                if kind != .workBlock {
                    Picker("Repetir", selection: $recurrence) {
                        ForEach(Recurrence.allCases) { Text($0.title).tag($0) }
                    }
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
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func save() {
        let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
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
            context.insert(CalendarEvent(
                title: cleanTitle, notes: notes, start: start, end: end, mode: mode,
                kind: kind, recurrence: recurrence, reminderMinutes: reminderMinutes
            ))
        }
        try? context.save()
        ReminderScheduler.shared.reschedule()
        if reminderMinutes != nil {
            Task { await NotificationAccess.requestIfNeeded() }
        }
        dismiss()
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

/// Plantilla de tarea con fecha límite: Planaby la reparte en bloques y enseña la propuesta.
struct TaskForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var mode = ModeController.shared.mode
    @State private var deadline = TaskForm.defaultDeadline()
    @State private var estimatedMinutes = 120
    @State private var priority = 1
    @State private var draft: PlanDraft?

    var body: some View {
        Form {
            Section {
                TextField("Qué hay que hacer", text: $title)
                ModeField(mode: $mode)
            }

            Section {
                DatePicker("Fecha límite", selection: $deadline, in: Date.now...)
                Stepper(value: $estimatedMinutes, in: 30...6000, step: 30) {
                    LabeledContent("Tiempo estimado", value: FocusStats.format(TimeInterval(estimatedMinutes * 60)))
                }
                Picker("Prioridad", selection: $priority) {
                    Text("Baja").tag(0)
                    Text("Media").tag(1)
                    Text("Alta").tag(2)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Planaby lo repartirá en bloques dentro de tu horario de \(mode.title) y te enseñará la propuesta antes de guardar nada.")
            }
        }
        .navigationTitle("Nueva tarea")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar", systemImage: "xmark") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Ver propuesta") {
                    let task = PlanDraft.Workload(
                        id: UUID(), title: title.trimmingCharacters(in: .whitespaces), mode: mode,
                        deadline: deadline, estimatedMinutes: estimatedMinutes, priority: priority
                    )
                    draft = PlanBuilder.draft(events: [], tasks: [task], context: context)
                }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationDestination(isPresented: Binding(get: { draft != nil }, set: { if !$0 { draft = nil } })) {
            if let binding = Binding($draft) {
                ProposalReviewView(draft: binding) { dismiss() }
            }
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
