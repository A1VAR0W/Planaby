import SwiftData
import SwiftUI

/// Añadir por voz: escuchar, interpretar con Apple Intelligence y enseñar una tarjeta para
/// confirmar. Como en el resto de Planaby, no se guarda nada sin pulsar «Añadir».
@Observable
@MainActor
final class VoiceTaskFlow {
    enum Phase: Equatable {
        case listening, thinking, ready, saved
        /// No se sabe si va a Trabajo o a Normal: se pregunta.
        case askingMode(String)
        case failed(String)
    }

    private(set) var phase = Phase.listening
    let speech = SpeechCapture()
    private(set) var heard = ""
    var draft: PlanDraft?
    /// Aviso de cómo se ha entendido (sin IA, o una pregunta de la IA).
    private(set) var note: String?
    /// Lo entendido mientras se espera la respuesta a «¿Trabajo o Normal?».
    @ObservationIgnored private var pending: Interpretation?
    @ObservationIgnored private var cancelled = false

    func start(context: ModelContext) async {
        cancelled = false
        phase = .listening
        draft = nil
        note = nil
        pending = nil
        heard = ""
        do {
            let text = try await speech.listen()
            guard !cancelled else { return }
            guard !text.isEmpty else {
                phase = .failed("No te he oído. Toca el micrófono y prueba otra vez.")
                return
            }
            heard = text
            phase = .thinking
            if let draft = try await makeDraft(from: text, context: context) {
                self.draft = draft
                phase = .ready
            }
        } catch let failure as SpeechCapture.Failure {
            phase = .failed(failure.message)
        } catch {
            phase = .failed(PlanningAssistant.message(for: error))
        }
    }

    func cancel() {
        cancelled = true
        speech.cancel()
    }

    func accept(context: ModelContext) {
        guard let draft else { return }
        PlanBuilder.accept(draft, context: context)
        phase = .saved
        Task { await NotificationAccess.requestIfNeeded() }
    }

    /// Respuesta a «¿Trabajo o Normal?».
    func choose(_ mode: PlanMode, context: ModelContext) {
        guard var result = pending else { return }
        pending = nil
        result.assign(mode)
        draft = result.makeDraft(context: context)
        phase = .ready
    }

    /// Lo marca como guardado cuando se acepta desde la revisión completa.
    func markSaved() { phase = .saved }

    private func makeDraft(from text: String, context: ModelContext) async throws -> PlanDraft? {
        if PlanningAssistant.unavailableReason == nil {
            let result = try await PlanningAssistant.interpret(text, context: context)
            if !result.isEmpty {
                note = result.question.isEmpty ? nil : result.question
                return ask(result, context: context)
            }
            if !result.question.isEmpty {
                phase = .failed(result.question)
                return nil
            }
        }
        // Sin IA (o sin nada que interpretar): una tarea sencilla con lo dicho.
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        let deadline = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: tomorrow) ?? tomorrow
        var title = text.trimmingCharacters(in: CharacterSet(charactersIn: " .")).prefix(80)
        if let first = title.first { title = Substring(first.uppercased()) + title.dropFirst() }
        let task = PlanDraft.Workload(
            id: UUID(), title: String(title), mode: ModeController.shared.mode, deadline: deadline,
            estimatedMinutes: 30, priority: 1, difficulty: 2
        )
        note = "La apunto para mañana, unos 30 min. Puedes cambiarlo en su ficha."
        // Sin IA no se sabe en qué plan va: se pregunta.
        return ask(Interpretation(tasks: [task], undecidedTasks: [task.id]), context: context)
    }

    /// Si falta saber el plan, pregunta y devuelve nil; si no, la propuesta.
    private func ask(_ result: Interpretation, context: ModelContext) -> PlanDraft? {
        guard result.needsMode else { return result.makeDraft(context: context) }
        pending = result
        phase = .askingMode(result.modeQuestion)
        return nil
    }
}

/// Panel de voz. En vertical va en una hoja (con «Revisar»); en el modo escritorio, flotando.
struct VoiceTaskPanel: View {
    let flow: VoiceTaskFlow
    var tint: Color = Theme.orange
    var ink: Color = .white
    /// Permite abrir la revisión completa (hace falta un NavigationStack).
    var allowsReview = false
    let onClose: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reviewing = false

    var body: some View {
        VStack(spacing: Space.l) {
            switch flow.phase {
            case .listening:
                listening
            case .thinking:
                VStack(spacing: Space.m) {
                    ProgressView().tint(tint).controlSize(.large)
                    Text("«\(flow.heard)»")
                        .font(.body)
                        .foregroundStyle(ink.opacity(0.8))
                        .multilineTextAlignment(.center)
                    Text("Organizando…")
                        .font(.subheadline)
                        .foregroundStyle(ink.opacity(0.6))
                }
                .padding(.vertical, Space.l)
            case .ready:
                if let draft = flow.draft { proposal(draft) }
            case .askingMode(let question):
                VStack(spacing: Space.l) {
                    Text("«\(flow.heard)»")
                        .font(.subheadline)
                        .foregroundStyle(ink.opacity(0.6))
                        .multilineTextAlignment(.center)
                    Text(question)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ink)
                        .multilineTextAlignment(.center)
                    ModeChoice(tint: tint) { flow.choose($0, context: context) }
                }
                .padding(.vertical, Space.m)
            case .saved:
                Label("Añadido a tu plan", systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.vertical, Space.xl)
                    .task {
                        try? await Task.sleep(for: .seconds(1.2))
                        onClose()
                    }
            case .failed(let message):
                VStack(spacing: Space.m) {
                    Image(systemName: "exclamationmark.bubble")
                        .font(.largeTitle)
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                    Text(message)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(ink)
                    actions(primary: "Repetir", primaryIcon: "mic.fill") { restart() }
                }
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: flow.phase)
        .sensoryFeedback(.success, trigger: flow.phase == .saved)
        .task { await flow.start(context: context) }
        // Al cerrar la hoja deslizando, el micrófono se apaga.
        .onDisappear { if flow.phase == .listening { flow.cancel() } }
        .navigationDestination(isPresented: $reviewing) {
            ProposalReviewView(draft: Binding(
                get: { flow.draft ?? PlanDraft(items: [], tasks: [], summary: "", warnings: []) },
                set: { flow.draft = $0 }
            )) {
                reviewing = false
                flow.markSaved()
            }
        }
    }

    // MARK: - Fases

    private var listening: some View {
        VStack(spacing: Space.l) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .scaleEffect(reduceMotion ? 1 : 1 + 0.5 * flow.speech.level)
                    .animation(.easeOut(duration: 0.12), value: flow.speech.level)
                Circle()
                    .fill(tint)
                    .frame(width: 72, height: 72)
                Image(systemName: "mic.fill")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.black)
            }
            .frame(width: 120, height: 120)
            .accessibilityHidden(true)

            Text(flow.speech.transcript.isEmpty ? "Te escucho…" : flow.speech.transcript)
                .font(.title3)
                .foregroundStyle(ink.opacity(flow.speech.transcript.isEmpty ? 0.6 : 1))
                .multilineTextAlignment(.center)
                .lineLimit(5)
                .frame(minHeight: 56)
                .accessibilityAddTraits(.updatesFrequently)

            if flow.speech.transcript.isEmpty {
                Text("Por ejemplo: «Preparar la presentación para el viernes, unas 3 horas» o «Llamar al dentista mañana».")
                    .font(.footnote)
                    .foregroundStyle(ink.opacity(0.55))
                    .multilineTextAlignment(.center)
            }

            actions(primary: "Listo", primaryIcon: "checkmark") { flow.speech.stop() }
        }
    }

    private func proposal(_ draft: PlanDraft) -> some View {
        let events = draft.items.filter { $0.kind != .workBlock }
        return VStack(alignment: .leading, spacing: Space.m) {
            Text("«\(flow.heard)»")
                .font(.subheadline)
                .foregroundStyle(ink.opacity(0.6))

            ForEach(draft.tasks) { task in
                let blocks = draft.items.filter { $0.taskID == task.id }
                ProposalLine(
                    symbol: "square.stack.3d.up.fill", tint: tint, ink: ink, title: task.title,
                    detail: "Entrega \(task.deadline.formatted(.dateTime.weekday(.abbreviated).day().hour().minute())) · \(FocusStats.format(TimeInterval(task.estimatedMinutes * 60))) · \(blocks.count == 1 ? "1 bloque" : "\(blocks.count) bloques")"
                )
            }
            ForEach(events) { event in
                ProposalLine(
                    symbol: event.kind.symbol, tint: tint, ink: ink, title: event.title,
                    detail: event.start.formatted(.dateTime.weekday(.wide).day().month().hour().minute())
                )
            }
            if draft.tasks.isEmpty && events.isEmpty {
                Text(draft.summary).foregroundStyle(ink)
            }
            ForEach(draft.warnings + (flow.note.map { [$0] } ?? []), id: \.self) { warning in
                Label(warning, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(ink.opacity(0.7))
            }

            HStack(spacing: Space.s) {
                if allowsReview {
                    Button("Revisar") { reviewing = true }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                }
                Spacer(minLength: 0)
                actions(primary: "Añadir", primaryIcon: "plus") { flow.accept(context: context) }
            }
        }
    }

    // MARK: - Piezas

    private func actions(primary: String, primaryIcon: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: Space.m) {
            Button("Cancelar", systemImage: "xmark") {
                flow.cancel()
                onClose()
            }
            .labelStyle(.iconOnly)
            .font(.body.weight(.semibold))
            .frame(width: 44, height: 44)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Cancelar")

            Button(action: action) {
                Label(primary, systemImage: primaryIcon)
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, Space.s)
                    .frame(minHeight: 36)
            }
            .buttonStyle(.glassProminent)
            .tint(tint)
            .controlSize(.large)
        }
    }

    private func restart() {
        Task { await flow.start(context: context) }
    }
}

private struct ProposalLine: View {
    let symbol: String
    let tint: Color
    let ink: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(ink.opacity(0.6))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Botón de micrófono para añadir por voz.
struct VoiceButton: View {
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "mic.fill")
                .font(.system(size: compact ? 16 : 18, weight: .semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Añadir por voz")
        .accessibilityHint("Dicta una tarea o una cita")
    }
}

extension VoiceTaskFlow: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}

extension View {
    /// Hoja de "Añadir por voz" para las pantallas en vertical.
    func voiceTaskSheet(_ flow: Binding<VoiceTaskFlow?>) -> some View {
        sheet(item: flow) { current in
            VoiceTaskSheet(flow: current) { flow.wrappedValue = nil }
        }
    }
}

/// La hoja de voz: a media altura mientras escucha y entera en cuanto hay algo que revisar,
/// para que la propuesta y sus botones se vean sin recortes.
private struct VoiceTaskSheet: View {
    let flow: VoiceTaskFlow
    let onClose: () -> Void
    @State private var detent = PresentationDetent.medium

    var body: some View {
        NavigationStack {
            ScrollView {
                VoiceTaskPanel(flow: flow, allowsReview: true, onClose: onClose)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Añadir por voz")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationBackground(.black)
        .presentationDragIndicator(.visible)
        // Mientras piensa no se cierra por accidente.
        .interactiveDismissDisabled(flow.phase == .thinking)
        .onChange(of: flow.phase) { _, phase in
            switch phase {
            case .ready, .askingMode: detent = .large
            default: break
            }
        }
    }
}
