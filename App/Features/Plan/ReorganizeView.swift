import SwiftData
import SwiftUI

/// Reorganizar: ordena las tareas pendientes arrastrándolas (la de arriba sale antes) y, si ha
/// surgido algo, cuéntaselo a la IA. Los bloques que aún no han empezado se vuelven a colocar
/// y todo pasa por la revisión antes de guardarse.
struct ReorganizeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ModeController.self) private var modes
    @Query(filter: #Predicate<PlanTask> { !$0.isDone }, sort: \PlanTask.deadline) private var tasks: [PlanTask]

    @State private var order: [PersistentIdentifier] = []
    @State private var news = ""
    @State private var isThinking = false
    @State private var problem: String?
    @State private var draft: PlanDraft?
    /// Lo que ha surgido, a la espera de saber si va a Trabajo o a Normal.
    @State private var pending: Interpretation?
    @State private var editMode = EditMode.active

    private var ordered: [PlanTask] {
        order.compactMap { id in tasks.first { $0.persistentModelID == id } }
    }

    var body: some View {
        List {
            Section {
                TextField("Ej.: «Me han pedido el presupuesto para mañana a las 12, unas 3 horas»", text: $news, axis: .vertical)
                    .lineLimit(2...5)
                    .disabled(PlanningAssistant.unavailableReason != nil)
            } header: {
                Text("¿Ha surgido algo?")
            } footer: {
                Text(PlanningAssistant.unavailableReason ?? "Opcional. También puedes pedir «Prioriza el informe» o «Hazme hueco el jueves por la tarde».")
            }

            Section {
                if ordered.isEmpty {
                    Text("No tienes tareas pendientes.")
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    ForEach(Array(ordered.enumerated()), id: \.element.persistentModelID) { index, task in
                        HStack(spacing: Space.m) {
                            Text("\(index + 1)")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(index == 0 ? Color.black : Theme.orange)
                                .frame(width: 28, height: 28)
                                .background(index == 0 ? Theme.orange : Theme.surface, in: .circle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title).lineLimit(1)
                                Text("Entrega \(task.deadline.formatted(.relative(presentation: .named))) · \(DifficultyField.label(task.difficulty).lowercased())")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .onMove { source, destination in
                        order.move(fromOffsets: source, toOffset: destination)
                    }
                }
            } header: {
                Text("Orden de prioridad")
            } footer: {
                Text("Arrastra para ordenar: lo de arriba se coloca antes. Lo exigente sigue yendo a tus mejores horas.")
            }

            if let pending {
                Section {
                    VStack(alignment: .leading, spacing: Space.m) {
                        Text(pending.modeQuestion)
                            .font(.body.weight(.semibold))
                        ModeChoice { mode in
                            var result = pending
                            result.assign(mode)
                            self.pending = nil
                            finish(with: result)
                        }
                    }
                    .padding(.vertical, Space.xs)
                }
            }

            if let problem {
                Section {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.orange)
                }
            }
        }
        .environment(\.editMode, $editMode)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle("Reorganizar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cerrar", systemImage: "xmark") { dismiss() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await propose() }
            } label: {
                HStack(spacing: Space.s) {
                    if isThinking { ProgressView().tint(.black) }
                    Text(isThinking ? "Pensando…" : "Proponer nuevo plan")
                }
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.orange)
            .controlSize(.large)
            .disabled(isThinking || (ordered.isEmpty && news.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            .padding(.horizontal, Space.m)
            .padding(.bottom, Space.s)
        }
        .navigationDestination(isPresented: Binding(get: { draft != nil }, set: { if !$0 { draft = nil } })) {
            if let binding = Binding($draft) {
                ProposalReviewView(draft: binding) { dismiss() }
            }
        }
        .onAppear {
            guard order.isEmpty else { return }
            let visible = modes.mode.visibleModes
            order = tasks.filter { visible.contains($0.mode) }.map(\.persistentModelID)
        }
    }

    private func propose() async {
        problem = nil
        pending = nil
        let text = news.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = Interpretation()

        if !text.isEmpty, PlanningAssistant.unavailableReason == nil {
            isThinking = true
            defer { isThinking = false }
            do {
                result = try await PlanningAssistant.interpret(text, context: context)
                if result.isEmpty {
                    problem = ([result.question] + result.problems).first { !$0.isEmpty }
                        ?? "No he entendido qué ha surgido. Reorganizo solo con el orden de la lista."
                } else if !result.problems.isEmpty {
                    problem = result.problems.joined(separator: "\n")
                }
            } catch {
                problem = PlanningAssistant.message(for: error)
                return
            }
        }

        if result.needsMode {
            pending = result
            return
        }
        finish(with: result)
    }

    private func finish(with result: Interpretation) {
        let combined = result.prioritize + order.filter { !result.prioritize.contains($0) }
        draft = PlanBuilder.reorganize(order: combined, newEvents: result.events, newTasks: result.tasks, context: context)
    }
}
