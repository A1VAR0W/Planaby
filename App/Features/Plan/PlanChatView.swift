import SwiftData
import SwiftUI

/// Chat de planificación con Apple Intelligence. Hay una sola propuesta activa: cada mensaje la
/// modifica (sin duplicar ni empezar de cero) y nada se guarda hasta «Aceptar propuesta».
struct PlanChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(PlanInbox.self) private var inbox
    @State private var assistant = PlanningAssistant()
    @State private var input = ""
    @State private var reviewing = false
    @State private var modifying = false
    @State private var confirmingClear = false
    @State private var attachments: [ImportedAttachment] = []
    @State private var showsPhotos = false
    @State private var showsFiles = false
    @State private var importing = 0
    @State private var confirmingDiscard = false
    /// La petición en curso, para poder cancelarla.
    @State private var sending: Task<Void, Never>?
    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let suggestions = [
        "Entregar el informe el viernes, unas 6 horas",
        "Reunión con el equipo mañana a las 10",
        "Estudiar para el examen del día 20, unas 8 horas",
        "Cena con Lucía el sábado a las 21:30",
    ]

    var body: some View {
        Group {
            if let reason = assistant.unavailableReason {
                ContentUnavailableView {
                    Label("Planificar con IA", systemImage: "sparkles")
                } description: {
                    Text(reason)
                } actions: {
                    Button("Cerrar") { dismiss() }
                }
            } else {
                conversation
            }
        }
        .background(Color.black)
        .navigationTitle("Planificar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cerrar", systemImage: "xmark") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Borrar conversación", systemImage: "trash") { confirmingClear = true }
                    .disabled(assistant.messages.isEmpty || assistant.isThinking)
            }
        }
        .confirmationDialog("¿Borrar la conversación?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Borrar", role: .destructive) { assistant.clearHistory() }
        } message: {
            Text("Lo que ya está en tu plan no cambia.")
        }
        .confirmationDialog("¿Descartar la propuesta?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Descartar", role: .destructive) { assistant.discardActive() }
        } message: {
            Text("No se guardará nada en tu calendario.")
        }
        .navigationDestination(isPresented: $reviewing) {
            ProposalReviewView(draft: draftBinding, onAccepted: {
                assistant.markAccepted()
                reviewing = false
            }, onAskAI: {
                reviewing = false
                startModifying()
            })
            .onAppear { assistant.beginManualEdits() }
            .onDisappear { assistant.endManualEdits() }
        }
        .task {
            assistant.restore(context: context)
            if let pending = inbox.pending {
                inbox.pending = nil
                await assistant.send(pending, context: context)
            }
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.m) {
                    if assistant.messages.isEmpty {
                        intro
                    }
                    ForEach(assistant.messages) { message in
                        MessageBubble(
                            message: message, assistant: assistant,
                            onReview: { reviewing = true },
                            onModify: startModifying,
                            onAccept: { assistant.acceptActive(context: context) },
                            onUndo: { assistant.undo(context: context) },
                            onRedo: { assistant.redo(context: context) },
                            onChooseMode: { mode in assistant.chooseMode(mode, for: message.id, context: context) },
                            onChoose: { option in assistant.choose(option, context: context) },
                            onAnswer: { choice in sendQuick(choice) },
                            onRetry: { sending = Task { await assistant.retry(context: context); sending = nil } },
                            onDiscard: { confirmingDiscard = true }
                        )
                        .id(message.id)
                        .transition(.rise(reduceMotion: reduceMotion))
                    }
                    if assistant.isThinking {
                        HStack(spacing: Space.s) {
                            ProgressView()
                            Text("Organizando…")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                            Spacer(minLength: Space.s)
                            Button("Cancelar") { sending?.cancel() }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.orange)
                                .frame(minHeight: 44)
                                .buttonStyle(.pressable)
                        }
                        .padding(.vertical, Space.s)
                        .id("thinking")
                        .transition(.opacity)
                    }
                }
                .padding(Space.m)
                .animation(Motion.adaptive(Motion.emphasized, reduceMotion: reduceMotion), value: assistant.messages.count)
                .animation(Motion.adaptive(Motion.quick, reduceMotion: reduceMotion), value: assistant.isThinking)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: assistant.messages.count) {
                if let last = assistant.messages.last?.id {
                    withAnimation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion)) { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Image(systemName: "sparkles")
                .font(.title)
                .foregroundStyle(Theme.orange)
                .accessibilityHidden(true)
            Text("Cuéntame qué tienes por delante")
                .font(.title3.weight(.semibold))
            Text("Citas con hora, trabajos con fecha límite o cosas que han surgido. Puedes adjuntar capturas o archivos para que estime mejor. Repartiré la carga en tus mejores horas y no guardaré nada sin que lo confirmes.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    Button {
                        sendQuick(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, Space.m)
                            .frame(minHeight: 44)
                            .background(Theme.surface, in: .capsule)
                    }
                    .buttonStyle(.pressable)
                    .staggeredAppear(Self.suggestions.firstIndex(of: suggestion) ?? 0)
                }
            }
        }
        .padding(.top, Space.l)
    }

    private var composer: some View {
        let hasContent = !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
        let canSend = hasContent && !assistant.isThinking && importing == 0
        return VStack(alignment: .leading, spacing: Space.s) {
            if let draft = assistant.draft, modifying || inputFocused, !assistant.isThinking {
                ProposalChips(draft: draft, canUndo: assistant.canUndo) { starter in
                    input = starter
                    inputFocused = true
                } onUndo: {
                    assistant.undo(context: context)
                }
                .padding(.horizontal, -Space.m)
            }
            if !attachments.isEmpty || importing > 0 {
                ScrollView(.horizontal) {
                    HStack(spacing: Space.s) {
                        ForEach(attachments) { file in
                            AttachmentChip(name: file.name, kind: file.kind) {
                                AttachmentStore.delete(file.fileName)
                                attachments.removeAll { $0.id == file.id }
                            }
                        }
                        if importing > 0 {
                            ProgressView().padding(.horizontal, Space.s)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            HStack(alignment: .bottom, spacing: Space.s) {
                Menu {
                    Button("Capturas o fotos", systemImage: "photo.on.rectangle") { showsPhotos = true }
                    Button("Archivo", systemImage: "doc.badge.plus") { showsFiles = true }
                } label: {
                    Image(systemName: "paperclip")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Adjuntar")
                .attachmentImporters(photos: $showsPhotos, files: $showsFiles, importing: $importing) { attachments.append($0) }
                TextField(assistant.draft == nil ? "Escribe qué quieres planificar" : "¿Qué quieres cambiar?", text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.s + 2)
                    .frame(minHeight: 44)
                    .background(Theme.surface, in: .rect(cornerRadius: 22))
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(Theme.orange)
                .foregroundStyle(.black)
                .disabled(!canSend)
                .accessibilityLabel("Enviar")
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .background(.black)
    }

    /// Envía lo escrito. Si falla (sin IA, error o cancelación), el texto y los adjuntos vuelven
    /// al campo para no tener que escribirlo otra vez.
    private func send() {
        let text = input
        let files = attachments
        input = ""
        attachments = []
        modifying = false
        sending = Task {
            let handled = await assistant.send(text, attachments: files, context: context)
            if !handled, input.isEmpty, attachments.isEmpty {
                input = text
                attachments = files
            }
            sending = nil
        }
    }

    /// Una respuesta rápida o una sugerencia: se envía tal cual.
    private func sendQuick(_ text: String) {
        guard !assistant.isThinking else { return }
        sending = Task {
            await assistant.send(text, context: context)
            sending = nil
        }
    }

    /// «Modificar con IA»: la propuesta se queda y el cursor va al campo.
    private func startModifying() {
        modifying = true
        inputFocused = true
    }

    /// La revisión edita siempre la última versión de la propuesta activa.
    private var draftBinding: Binding<PlanDraft> {
        Binding(
            get: { assistant.draft ?? PlanDraft(items: [], tasks: [], summary: "", warnings: []) },
            set: { assistant.updateManually($0) }
        )
    }
}

private struct MessageBubble: View {
    let message: PlanningAssistant.Message
    let assistant: PlanningAssistant
    let onReview: () -> Void
    let onModify: () -> Void
    let onAccept: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onChooseMode: (PlanMode) -> Void
    let onChoose: (ProposalOption) -> Void
    let onAnswer: (String) -> Void
    let onRetry: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        let isUser = message.role == .user
        let isActive = assistant.isActive(message)
        VStack(alignment: isUser ? .trailing : .leading, spacing: Space.s) {
            if !message.attachmentNames.isEmpty {
                Label(message.attachmentNames.joined(separator: ", "), systemImage: "paperclip")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
            }
            Text(message.text)
                .font(.body)
                .foregroundStyle(isUser ? Color.black : Color.white)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s + 2)
                .background(isUser ? Theme.orange : Theme.surface, in: .rect(cornerRadius: 20))
                .textSelection(.enabled)

            if !message.changes.isEmpty {
                ProposalChangeList(changes: message.changes, dimmed: !isActive)
                    .padding(.horizontal, Space.s)
            }

            if message.pending != nil {
                ModeChoice(onChoose: onChooseMode)
            }

            if !message.options.isEmpty {
                ProposalOptionsView(options: message.options, onChoose: onChoose)
            }

            if !message.choices.isEmpty {
                DetailChoicesView(choices: message.choices, onChoose: onAnswer)
            }

            if message.canRetry, assistant.canRetry {
                Button(action: onRetry) {
                    Label("Reintentar", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, Space.m)
                        .frame(minHeight: 40)
                        .background(Theme.surface, in: .capsule)
                }
                .buttonStyle(.pressable)
                .foregroundStyle(Theme.orange)
            }

            if let state = message.proposal {
                ProposalCard(
                    draft: isActive ? assistant.draft : nil, state: isActive ? .active : (state == .active ? .replaced : state),
                    isFirst: message.changes.isEmpty && !message.asksToAccept,
                    asksToAccept: message.asksToAccept, canUndo: assistant.canUndo, canRedo: assistant.canRedo,
                    onReview: onReview, onModify: onModify, onAccept: onAccept, onUndo: onUndo, onRedo: onRedo,
                    onDiscard: onDiscard
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(isUser ? .leading : .trailing, message.proposal == nil ? Space.xxl : Space.s)
    }
}

/// Adjunto pendiente de enviar, con botón para quitarlo.
private struct AttachmentChip: View {
    let name: String
    let kind: AttachmentKind
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: kind.symbol)
                .foregroundStyle(Theme.orange)
                .accessibilityHidden(true)
            Text(name)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: 140)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quitar \(name)")
        }
        .padding(.leading, Space.s + 2)
        .background(Theme.surface, in: .capsule)
    }
}
