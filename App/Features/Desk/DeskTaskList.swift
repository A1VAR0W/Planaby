import SwiftData
import SwiftUI

/// Lista de tareas del modo escritorio: un toque en el círculo la marca como hecha (y otro la
/// recupera); las hechas hoy se quedan tachadas con una papelera para borrarlas.
struct DeskTaskList: View {
    let tint: Color
    let ink: Color
    /// Se llama en cada toque para que la barra no se esconda mientras se usa la lista.
    let onInteract: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(ModeController.self) private var modes
    @Query(sort: \PlanTask.deadline) private var tasks: [PlanTask]
    @State private var deleting: PlanTask?

    var body: some View {
        let visible = modes.mode.visibleModes
        let calendar = Calendar.current
        let shown = tasks.filter { task in
            guard visible.contains(task.mode) else { return false }
            guard task.isDone else { return true }
            return task.completedAt.map { calendar.isDateInToday($0) } ?? false
        }
        // Pendientes primero; las hechas, al final.
        let ordered = shown.filter { !$0.isDone } + shown.filter(\.isDone)
        let pending = shown.count { !$0.isDone }

        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text("Tareas")
                    .font(.headline)
                    .foregroundStyle(ink)
                Spacer()
                Text(pending == 0 ? "Todo hecho" : "\(pending) pendientes")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(ink.opacity(0.64))
            }
            .padding(.horizontal, Space.s)

            if ordered.isEmpty {
                Text("Sin tareas en \(modes.mode.title.lowercased()).")
                    .font(.subheadline)
                    .foregroundStyle(ink.opacity(0.64))
                    .padding(Space.s)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: Space.xs) {
                        ForEach(ordered) { task in
                            row(task)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(Space.s)
        .background(Color.white.opacity(0.05), in: .rect(cornerRadius: Theme.cardRadius))
        .animation(.smooth(duration: 0.3), value: ordered.map(\.isDone))
        .sensoryFeedback(.success, trigger: tasks.count { $0.isDone })
        .confirmationDialog(
            "¿Borrar «\(deleting?.title ?? "")»?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { task in
            Button("Borrar tarea y sus bloques", role: .destructive) {
                TaskActions.delete(task, context: context)
            }
        }
    }

    private func row(_ task: PlanTask) -> some View {
        HStack(spacing: Space.xs) {
            Button {
                onInteract()
                if task.isDone {
                    TaskActions.reopen(task, context: context)
                } else {
                    TaskActions.complete(task, context: context)
                }
            } label: {
                HStack(spacing: Space.s) {
                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(task.isDone ? tint : ink.opacity(0.5))
                        .contentTransition(.symbolEffect(.replace))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(task.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(ink.opacity(task.isDone ? 0.45 : 0.95))
                            .strikethrough(task.isDone, color: ink.opacity(0.45))
                            .lineLimit(2)
                        if !task.isDone {
                            Text(task.deadline.formatted(.relative(presentation: .named)))
                                .font(.caption)
                                .foregroundStyle(task.deadline < .now ? tint : ink.opacity(0.55))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.title)
            .accessibilityValue(task.isDone ? "Hecha" : "Pendiente")
            .accessibilityHint(task.isDone ? "Marcar como pendiente" : "Marcar como hecha")

            if task.isDone {
                Button {
                    onInteract()
                    deleting = task
                } label: {
                    Image(systemName: "trash")
                        .font(.subheadline)
                        .foregroundStyle(ink.opacity(0.6))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Borrar \(task.title)")
            }
        }
        .padding(.horizontal, Space.s)
        .contextMenu {
            Button("Borrar", systemImage: "trash", role: .destructive) { deleting = task }
        }
    }
}
