import QuickLook
import SwiftData
import SwiftUI

/// Ficha de una tarea: datos, material adjunto, próximos bloques y acciones (estimar de nuevo,
/// replanificar dándole prioridad, marcar como hecha o borrar).
struct TaskDetailView: View {
    @Bindable var task: PlanTask
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var previewURL: URL?
    @State private var estimate: ComplexityEstimate?
    @State private var isEstimating = false
    @State private var estimateError: String?
    @State private var draft: PlanDraft?
    @State private var confirmingDelete = false

    var body: some View {
        let now = Date.now
        let upcoming = task.blocks.filter { $0.end > now }.sorted { $0.start < $1.start }

        Form {
            Section {
                TextField("Título", text: $task.title)
                ModeField(mode: $task.mode)
                DatePicker("Fecha límite", selection: $task.deadline)
                Stepper(value: $task.estimatedMinutes, in: 15...12000, step: task.estimatedMinutes < 60 ? 15 : 30) {
                    LabeledContent("Tiempo estimado", value: FocusStats.format(TimeInterval(task.estimatedMinutes * 60)))
                }
                DifficultyField(difficulty: $task.difficulty)
                PriorityField(priority: $task.priority)
            } footer: {
                Text("Hecho: \(FocusStats.format(TimeInterval(task.completedMinutes * 60))) de \(FocusStats.format(TimeInterval(task.estimatedMinutes * 60))). Si cambias algo, pulsa Replanificar para recolocar los bloques.")
            }

            Section {
                Button {
                    draft = PlanBuilder.reorganize(order: [task.persistentModelID], context: context)
                } label: {
                    Label("Replanificar dándole prioridad", systemImage: "arrow.up.arrow.down")
                }
                Button {
                    Task { await runEstimate() }
                } label: {
                    HStack {
                        Label("Estimar de nuevo con IA", systemImage: "sparkles")
                        Spacer()
                        if isEstimating { ProgressView() }
                    }
                }
                .disabled(isEstimating || PlanningAssistant.unavailableReason != nil)
                if let estimate {
                    EstimateSummary(estimate: estimate)
                }
                if let estimateError {
                    Text(estimateError)
                        .font(.subheadline)
                        .foregroundStyle(Theme.orange)
                }
            }

            Section("Próximos bloques") {
                if upcoming.isEmpty {
                    Text("No tiene bloques pendientes.")
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    ForEach(upcoming) { block in
                        LabeledContent {
                            Text(FocusStats.format(block.duration))
                                .monospacedDigit()
                        } label: {
                            Text(block.start.formatted(.dateTime.weekday(.abbreviated).day().hour().minute()))
                        }
                    }
                }
            }

            Section {
                ForEach(task.attachments.sorted { $0.created < $1.created }) { file in
                    Button {
                        previewURL = AttachmentStore.url(for: file.fileName)
                    } label: {
                        AttachmentLabel(name: file.name, kind: file.kind, text: file.extractedText)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Quitar", systemImage: "trash", role: .destructive) { remove(file) }
                    }
                }
                AttachmentAdder { add($0) }
            } header: {
                Text("Material")
            } footer: {
                Text("Toca un adjunto para verlo.")
            }

            Section("Notas y pasos") {
                TextField("Opcional", text: $task.notes, axis: .vertical)
                    .lineLimit(2...10)
            }

            Section {
                Button("Marcar como hecha", systemImage: "checkmark.circle") {
                    TaskActions.complete(task, context: context)
                    dismiss()
                }
                Button("Borrar tarea", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            }
        }
        .navigationTitle(task.title)
        .navigationBarTitleDisplayMode(.inline)
        .quickLookPreview($previewURL)
        .confirmationDialog("¿Borrar «\(task.title)»?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Borrar tarea, bloques y material", role: .destructive) {
                TaskActions.delete(task, context: context)
                dismiss()
            }
        }
        .navigationDestination(isPresented: Binding(get: { draft != nil }, set: { if !$0 { draft = nil } })) {
            if let binding = Binding($draft) {
                ProposalReviewView(draft: binding) { draft = nil }
            }
        }
        .onDisappear {
            try? context.save()
            ReminderScheduler.shared.reschedule()
        }
    }

    private func add(_ imported: ImportedAttachment) {
        let attachment = TaskAttachment(name: imported.name, kind: imported.kind, fileName: imported.fileName, extractedText: imported.text)
        context.insert(attachment)
        attachment.task = task
        try? context.save()
    }

    private func remove(_ attachment: TaskAttachment) {
        AttachmentStore.delete(attachment.fileName)
        context.delete(attachment)
        try? context.save()
    }

    private func runEstimate() async {
        isEstimating = true
        estimateError = nil
        defer { isEstimating = false }
        do {
            let result = try await PlanningAssistant.estimate(
                title: task.title, notes: task.notes, deadline: task.deadline,
                attachmentTexts: task.attachments.map(\.extractedText)
            )
            withAnimation(Motion.standard) {
                estimate = result
                task.estimatedMinutes = max(15, Int((Double(result.estimatedMinutes) / 15).rounded()) * 15)
                task.difficulty = result.difficulty
                if task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !result.steps.isEmpty {
                    task.notes = result.stepsText
                }
            }
        } catch {
            estimateError = PlanningAssistant.message(for: error)
        }
    }
}
