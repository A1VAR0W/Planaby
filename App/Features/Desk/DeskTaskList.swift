import SwiftData
import SwiftUI

/// Lista de tareas del modo escritorio: un toque en el círculo la marca como hecha (y otro la
/// recupera); las hechas hoy se quedan tachadas con una papelera para borrarlas. La tarea de la
/// sesión va arriba marcada como «Ahora», y el lápiz apunta una nueva sin salir.
struct DeskTaskList: View {
    let tint: Color
    let ink: Color
    /// Abierta en el escritorio: al abrirse, el contenido entra escalonado; al cerrarse, se va a la vez.
    var isOpen = true
    /// Se llama en cada toque para que la barra no se esconda mientras se usa la lista.
    let onInteract: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var context
    @Environment(ModeController.self) private var modes
    @Environment(FocusTimer.self) private var timer
    @Query(sort: \PlanTask.deadline) private var tasks: [PlanTask]
    @State private var deleting: PlanTask?
    @Query(filter: #Predicate<CapturedTask> { $0.statusRaw == "pending" }) private var captures: [CapturedTask]

    var body: some View {
        let visible = modes.mode.visibleModes
        let calendar = Calendar.current
        let shown = tasks.filter { task in
            guard visible.contains(task.mode) else { return false }
            guard task.isDone else { return true }
            return task.completedAt.map { calendar.isDateInToday($0) } ?? false
        }
        // La de la sesión arriba; luego pendientes, y las hechas al final.
        let current = timer.state?.taskID
        let isCurrent = { (task: PlanTask) in current != nil && task.uid == current && !task.isDone }
        let ordered = shown.filter(isCurrent) + shown.filter { !$0.isDone && !isCurrent($0) } + shown.filter(\.isDone)
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
                Button {
                    onInteract()
                    CaptureCenter.shared.open()
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Añadir tarea")
                .accessibilityHint("Captura rápida sin salir de la sesión")
            }
            .padding(.leading, Space.s)
            .modifier(OpenStagger(isOpen: isOpen, index: 0, reduceMotion: reduceMotion))

            // Lo apuntado con la captura rápida: se organiza después, sin salir del escritorio.
            let unsorted = captures.count { CaptureRules.isPending($0.entry, now: .now) }
            if unsorted > 0 {
                Button {
                    onInteract()
                    CaptureCenter.shared.inboxRequested = true
                } label: {
                    HStack(spacing: Space.s) {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(tint)
                            .accessibilityHidden(true)
                        Text("\(unsorted) por organizar")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ink.opacity(0.85))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ink.opacity(0.45))
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, Space.s)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Abre «Por organizar»")
                .modifier(OpenStagger(isOpen: isOpen, index: 1, reduceMotion: reduceMotion))
            }

            if ordered.isEmpty {
                Text("Sin tareas en \(modes.mode.title.lowercased()).")
                    .font(.subheadline)
                    .foregroundStyle(ink.opacity(0.64))
                    .padding(Space.s)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: Space.xs) {
                        ForEach(Array(ordered.enumerated()), id: \.element.id) { index, task in
                            row(task, isCurrent: isCurrent(task))
                                .modifier(OpenStagger(isOpen: isOpen, index: index + 2, reduceMotion: reduceMotion))
                                .transition(.rise(reduceMotion: reduceMotion))
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(Space.s)
        .background(Color.white.opacity(0.05), in: .rect(cornerRadius: Theme.cardRadius))
        // Completar o reabrir recoloca la fila con un muelle suave (sin saltos).
        .animation(Motion.adaptive(Motion.emphasized, reduceMotion: reduceMotion), value: ordered.map(\.id))
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: ordered.map(\.isDone))
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

    private func row(_ task: PlanTask, isCurrent: Bool) -> some View {
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
                        if isCurrent {
                            Text("Ahora · en esta sesión")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(tint)
                        } else if !task.isDone {
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
        .background(isCurrent ? tint.opacity(0.12) : .clear, in: .rect(cornerRadius: 14))
        .contextMenu {
            Button("Borrar", systemImage: "trash", role: .destructive) { deleting = task }
        }
    }
}

/// Al abrir la lista, cada fila entra un poco después de la anterior; al cerrarla, todas se van
/// a la vez y más rápido. Con «Reducir movimiento», solo un fundido.
private struct OpenStagger: ViewModifier {
    let isOpen: Bool
    let index: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isOpen ? 1 : 0)
            .offset(x: isOpen || reduceMotion ? 0 : 18)
            .animation(isOpen ? Motion.stagger(index, reduceMotion: reduceMotion) : Motion.adaptive(Motion.exit, reduceMotion: reduceMotion), value: isOpen)
    }
}
