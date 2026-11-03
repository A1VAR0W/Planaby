import SwiftData
import SwiftUI

/// Chat de planificación con Apple Intelligence. Cada respuesta con algo que añadir trae una
/// propuesta que hay que revisar y aceptar; el chat nunca guarda nada por su cuenta.
struct PlanChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(PlanInbox.self) private var inbox
    @State private var assistant = PlanningAssistant()
    @State private var input = ""
    @State private var reviewing: PlanningAssistant.Message.ID?
    @State private var attachments: [ImportedAttachment] = []
    @State private var showsPhotos = false
    @State private var showsFiles = false
    @State private var importing = 0
    @FocusState private var inputFocused: Bool

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
        }
        .navigationDestination(item: $reviewing) { id in
            ProposalReviewView(draft: draftBinding(for: id)) {
                assistant.markAccepted(id)
                reviewing = nil
            }
        }
        .task {
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
                        MessageBubble(message: message) { reviewing = message.id }
                            .id(message.id)
                    }
                    if assistant.isThinking {
                        HStack(spacing: Space.s) {
                            ProgressView()
                            Text("Organizando…")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .padding(.vertical, Space.s)
                        .id("thinking")
                    }
                }
                .padding(Space.m)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: assistant.messages.count) {
                if let last = assistant.messages.last?.id {
                    withAnimation(.smooth) { proxy.scrollTo(last, anchor: .bottom) }
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
                        Task { await assistant.send(suggestion, context: context) }
                    } label: {
                        Text(suggestion)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, Space.m)
                            .frame(minHeight: 44)
                            .background(Theme.surface, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, Space.l)
    }

    private var composer: some View {
        let hasContent = !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
        let canSend = hasContent && !assistant.isThinking && importing == 0
        return VStack(alignment: .leading, spacing: Space.s) {
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
                TextField("Escribe qué quieres planificar", text: $input, axis: .vertical)
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

    private func send() {
        let text = input
        let files = attachments
        input = ""
        attachments = []
        Task { await assistant.send(text, attachments: files, context: context) }
    }

    private func draftBinding(for id: PlanningAssistant.Message.ID) -> Binding<PlanDraft> {
        Binding(
            get: {
                assistant.messages.first { $0.id == id }?.draft
                    ?? PlanDraft(items: [], tasks: [], summary: "", warnings: [])
            },
            set: { assistant.updateDraft($0, in: id) }
        )
    }
}

private struct MessageBubble: View {
    let message: PlanningAssistant.Message
    let onReview: () -> Void

    var body: some View {
        let isUser = message.role == .user
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

            if let draft = message.draft {
                VStack(alignment: .leading, spacing: Space.s) {
                    if !draft.warnings.isEmpty {
                        Label(draft.warnings.count == 1 ? "1 aviso" : "\(draft.warnings.count) avisos", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.orange)
                    }
                    Button(action: onReview) {
                        Label("Revisar propuesta", systemImage: "checklist")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black)
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.orange)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(isUser ? .leading : .trailing, Space.xxl)
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
