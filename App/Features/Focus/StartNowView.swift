import SwiftData
import SwiftUI

/// Qué tarea toca ahora: la del bloque en curso; si no, la más importante y urgente del plan
/// actual que no esté atascada.
enum MainTask {
    static func pick(from tasks: [PlanTask], events: [CalendarEvent], mode: PlanMode, now: Date = .now) -> PlanTask? {
        let pending = tasks.filter { !$0.isDone && !$0.isBlocked }
        if let current = events.first(where: { $0.kind == .workBlock && $0.start <= now && $0.end > now })?.task,
           !current.isDone, !current.isBlocked {
            return current
        }
        let sorted = pending.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.deadline < $1.deadline
        }
        return sorted.first { $0.mode == mode } ?? sorted.first
    }
}

/// «Empezar ahora»: para cuando no apetece. Una tarea, un primer paso pequeño y solo cinco
/// minutos; al terminarlos, Planaby pregunta si seguir con un bloque normal.
struct StartNowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(FocusTimer.self) private var timer
    @Environment(ModeController.self) private var modes
    @Query(filter: #Predicate<PlanTask> { !$0.isDone }, sort: \PlanTask.deadline) private var tasks: [PlanTask]
    @Query private var events: [CalendarEvent]

    @State private var selectedID: UUID?
    @State private var step = ""
    @State private var suggesting = false
    @FocusState private var stepFocused: Bool

    private var available: [PlanTask] { tasks.filter { !$0.isBlocked } }

    private var selected: PlanTask? {
        available.first { $0.uid == selectedID } ?? MainTask.pick(from: tasks, events: events, mode: modes.mode)
    }

    var body: some View {
        Form {
            Section {
                Text("Solo cinco minutos. No hace falta tener ganas: basta con dar el primer paso.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }

            if available.isEmpty {
                Section {
                    Text("No hay tareas pendientes. Empieza igualmente cinco minutos con lo que tengas delante.")
                        .font(.subheadline)
                }
            } else {
                Section("Tarea") {
                    Picker("Tarea", selection: Binding(get: { selected?.uid }, set: { selectedID = $0; loadStep() })) {
                        ForEach(available) { task in
                            Text(task.title).tag(task.uid)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.inline)
                }
            }

            Section {
                TextField("Por ejemplo: abrir el documento y escribir el título", text: $step, axis: .vertical)
                    .focused($stepFocused)
                    .lineLimit(1...3)
                if AIProvider.isAvailable, let task = selected {
                    Button {
                        Task { await suggest(for: task) }
                    } label: {
                        if suggesting {
                            ProgressView()
                        } else {
                            Label("Proponer un primer paso", systemImage: "sparkles")
                        }
                    }
                    .disabled(suggesting)
                }
            } header: {
                Text("Primer paso")
            } footer: {
                Text("Algo que se pueda hacer en menos de cinco minutos.")
            }
        }
        .navigationTitle("Empezar ahora")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                start()
            } label: {
                Text("Empezar 5 minutos")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.orange)
            .controlSize(.large)
            .padding(.horizontal, Space.l)
            .padding(.bottom, Space.s)
        }
        .onAppear(perform: loadStep)
    }

    private func loadStep() {
        step = selected?.firstStep ?? ""
    }

    private func suggest(for task: PlanTask) async {
        suggesting = true
        defer { suggesting = false }
        if let proposal = await AIProvider.shared.firstStep(title: task.title, notes: task.notes) {
            step = proposal
        }
    }

    private func start() {
        stepFocused = false
        let task = selected
        let clean = step.trimmingCharacters(in: .whitespacesAndNewlines)
        if let task, !clean.isEmpty, clean != task.nextStep {
            task.nextStep = clean
            try? context.save()
        }
        Task {
            await NotificationAccess.requestIfNeeded()
            timer.start(.starter, task: task?.title, taskID: task?.stableID)
            if let state = timer.state, !clean.isEmpty {
                SessionContext.save(SessionContext(sessionStart: state.sessionStart, nextStep: clean))
                timer.sync()
            }
            dismiss()
        }
    }
}
