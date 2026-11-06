import SwiftData
import SwiftUI

// MARK: - Botón

/// Botón discreto de captura rápida. Tocarlo abre el panel; mantenerlo pulsado ofrece dictar.
/// Tras guardar se convierte un momento en una marca de verificación.
struct QuickCaptureButton: View {
    var size: CGFloat = 44
    @State private var center = CaptureCenter.shared
    @State private var showsCheck = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Menu {
            Button("Escribir", systemImage: "keyboard") { center.open() }
            Button("Dictar", systemImage: "mic.fill") { center.open(dictation: true) }
        } label: {
            Image(systemName: showsCheck ? "checkmark" : "square.and.pencil")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.orange)
                .frame(width: size, height: size)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
        } primaryAction: {
            center.open()
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Captura rápida")
        .accessibilityHint("Apunta una tarea sin salir de la sesión. Mantén pulsado para dictar.")
        .accessibilityAction(named: "Dictar") { center.open(dictation: true) }
        .task(id: center.confirmation?.id) {
            guard center.confirmation != nil else { return }
            showsCheck = true
            try? await Task.sleep(for: .seconds(1.2))
            showsCheck = false
        }
    }
}

// MARK: - Panel

/// Panel compacto: un campo, el micrófono y Guardar. Nada de navegación ni de planificar aquí.
/// Se usa en una hoja baja (vertical) y flotando en el modo escritorio.
struct QuickCapturePanel: View {
    let startsDictation: Bool
    var tint: Color = Theme.orange
    var ink: Color = .white
    /// En horizontal (modo escritorio): una tarjeta ancha y baja, pensada para quedar encima del
    /// teclado: título y estado arriba; campo, micrófono, Cancelar y Guardar en una sola fila.
    var compact = false
    let onClose: () -> Void
    @State private var center = CaptureCenter.shared
    @State private var speech = SpeechCapture()
    @State private var usedVoice = false
    @State private var message: String?
    /// Detalles opcionales (solo en horizontal). nil: captura rápida a «Por organizar».
    @State private var details: CaptureDetails?
    @FocusState private var focused: Bool
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var canSave: Bool { CaptureRules.clean(center.draft) != nil && !speech.isListening }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? Space.s : Space.m) {
            HStack {
                Text("Captura rápida")
                    .font(compact ? .subheadline.weight(.semibold) : .headline)
                    .foregroundStyle(ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if compact {
                    status
                    detailsToggle
                } else {
                    closeButton
                }
            }

            if compact {
                HStack(spacing: Space.s) {
                    micButton
                    field
                    cancelButton
                    saveButton
                }
                if let details {
                    detailsRow(Binding(get: { details }, set: { self.details = $0 }))
                        .transition(.opacity)
                }
            } else {
                field
            }

            if let message, !compact {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !compact {
                HStack(spacing: Space.m) {
                    micButton
                    Spacer()
                    saveButton
                }
            }
        }
        .padding(compact ? Space.m : Space.l)
        .task {
            if startsDictation {
                dictate()
            } else {
                // La hoja tiene que estar a la vista para que el teclado suba.
                try? await Task.sleep(for: .milliseconds(300))
                focused = true
            }
        }
        // El micrófono nunca sigue abierto al cerrar el panel o salir de la app.
        .onDisappear { speech.cancel() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { speech.cancel() }
        }
    }

    /// Estado en una línea (horizontal): escuchando, error o la pista de que no hace falta fecha.
    private var status: some View {
        Group {
            if let message {
                Label(message, systemImage: "exclamationmark.circle")
                    .foregroundStyle(tint)
            } else if speech.isListening {
                Label("Te escucho…", systemImage: "waveform")
                    .foregroundStyle(tint)
            } else if details != nil {
                Text("Va directa a tus tareas")
                    .foregroundStyle(ink.opacity(0.6))
            } else {
                Text("Sin fecha ni plan: lo organizas después")
                    .foregroundStyle(ink.opacity(0.5))
            }
        }
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// «Detalles»: abre o cierra la fila opcional sin perder lo escrito.
    private var detailsToggle: some View {
        Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                details = details == nil ? CaptureDetails(mode: ModeController.shared.mode) : nil
            }
        } label: {
            HStack(spacing: Space.xs) {
                Text("Detalles")
                Image(systemName: details == nil ? "chevron.down" : "chevron.up")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(details == nil ? ink.opacity(0.75) : tint)
            .padding(.horizontal, Space.s)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(details == nil ? "Añadir detalles" : "Quitar detalles")
        .accessibilityHint("Plan, prioridad, fecha, duración y notas. Opcional.")
    }

    /// Plan, prioridad, fecha, duración y notas en una sola fila, para que con el teclado abierto
    /// todo siga a la vista.
    private func detailsRow(_ details: Binding<CaptureDetails>) -> some View {
        HStack(spacing: Space.s) {
            Menu {
                Picker("Plan", selection: details.mode) {
                    ForEach(PlanMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
            } label: {
                chip(details.wrappedValue.mode.title, systemImage: details.wrappedValue.mode.symbol)
            }
            .accessibilityLabel("Plan: \(details.wrappedValue.mode.title)")

            Menu {
                Picker("Prioridad", selection: details.priority) {
                    ForEach(0..<3, id: \.self) { Text(CaptureDetails.priorityTitle($0)).tag($0) }
                }
            } label: {
                chip(CaptureDetails.priorityTitle(details.wrappedValue.priority), systemImage: "flag.fill")
            }
            .accessibilityLabel("Prioridad: \(CaptureDetails.priorityTitle(details.wrappedValue.priority))")

            DatePicker(
                "Fecha", selection: details.deadline,
                in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .tint(tint)
            .fixedSize()
            .accessibilityLabel("Fecha")

            Menu {
                Picker("Duración", selection: details.minutes) {
                    ForEach(CaptureDetails.durations, id: \.self) { Text("\($0) min").tag($0) }
                }
            } label: {
                chip("\(details.wrappedValue.minutes) min", systemImage: "clock")
            }
            .accessibilityLabel("Duración: \(details.wrappedValue.minutes) minutos")

            TextField("Notas (opcional)", text: details.notes)
                .font(.subheadline)
                .foregroundStyle(ink)
                .submitLabel(.done)
                .onSubmit(save)
                .padding(.horizontal, Space.s)
                .frame(minHeight: 44)
                .background(ink.opacity(0.08), in: .rect(cornerRadius: 12))
        }
    }

    private func chip(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(ink.opacity(0.9))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Space.s + 2)
            .frame(minHeight: 44)
            .background(ink.opacity(0.08), in: .capsule)
            .contentShape(.capsule)
    }

    private var cancelButton: some View {
        Button("Cancelar") {
            center.draft = ""
            close()
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(ink.opacity(0.8))
        .frame(minHeight: 44)
        .padding(.horizontal, Space.xs)
        .buttonStyle(.plain)
    }

    private var closeButton: some View {
        Button("Cerrar", systemImage: "xmark") {
            center.draft = ""
            close()
        }
        .labelStyle(.iconOnly)
        .font(.body.weight(.semibold))
        .frame(width: 44, height: 44)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }

    private var field: some View {
        Group {
            if speech.isListening {
                HStack(spacing: Space.s) {
                    Circle()
                        .fill(tint)
                        .frame(width: 10, height: 10)
                        .scaleEffect(reduceMotion ? 1 : 1 + speech.level)
                        .animation(.easeOut(duration: 0.12), value: speech.level)
                        .accessibilityHidden(true)
                    Text(speech.transcript.isEmpty ? "Te escucho…" : speech.transcript)
                        .foregroundStyle(ink.opacity(speech.transcript.isEmpty ? 0.6 : 1))
                        .lineLimit(compact ? 1 : 3)
                        .accessibilityAddTraits(.updatesFrequently)
                    Spacer(minLength: 0)
                }
            } else {
                TextField("¿Qué necesitas recordar?", text: $center.draft)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .foregroundStyle(ink)
                    .textInputAutocapitalization(.sentences)
            }
        }
        .padding(.horizontal, Space.m)
        .frame(minHeight: 48)
        .background(ink.opacity(0.08), in: .rect(cornerRadius: 14))
    }

    private var micButton: some View {
        Button(speech.isListening ? "Listo" : "Dictar", systemImage: speech.isListening ? "stop.fill" : "mic.fill") {
            dictate()
        }
        .labelStyle(.iconOnly)
        .font(.body.weight(.semibold))
        .foregroundStyle(speech.isListening ? Color.black : tint)
        .frame(width: 44, height: 44)
        .background(speech.isListening ? tint : Color.clear, in: .circle)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(speech.isListening ? "Terminar de dictar" : "Dictar")
    }

    private var saveButton: some View {
        Button(action: save) {
            Text("Guardar")
                .font(.headline)
                .foregroundStyle(.black)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, compact ? Space.s : Space.m)
                .frame(minHeight: 36)
        }
        .buttonStyle(.glassProminent)
        .tint(tint)
        .controlSize(.large)
        .disabled(!canSave)
    }

    private func dictate() {
        if speech.isListening {
            speech.stop()
            return
        }
        message = nil
        focused = false
        Task {
            do {
                let text = try await speech.listen(keepingMusic: true)
                if text.isEmpty {
                    message = "No te he oído. Prueba otra vez o escríbelo."
                } else {
                    center.draft = center.draft.isEmpty ? text : center.draft + " " + text
                    usedVoice = true
                }
            } catch let failure as SpeechCapture.Failure {
                message = failure.message + " Mientras, puedes escribirlo."
            } catch {
                message = "No se pudo dictar. Puedes escribirlo."
            }
            // Para corregir lo dictado o escribir.
            focused = true
        }
    }

    private func save() {
        guard canSave else { return }
        do {
            if let details {
                try center.saveTask(center.draft, details: details, context: context)
            } else {
                try center.save(center.draft, source: usedVoice ? .voice : .text, context: context)
            }
            close()
        } catch {
            message = error.localizedDescription
        }
    }

    private func close() {
        speech.cancel()
        onClose()
    }
}

extension View {
    /// Hoja baja con la captura rápida (en vertical; el modo escritorio la enseña flotando).
    func quickCaptureSheet(isEnabled: Bool) -> some View {
        modifier(QuickCaptureSheet(isEnabled: isEnabled))
    }
}

private struct QuickCaptureSheet: ViewModifier {
    let isEnabled: Bool
    @State private var center = CaptureCenter.shared

    func body(content: Content) -> some View {
        content.sheet(item: Binding(
            get: { isEnabled ? center.composer : nil },
            set: { if $0 == nil, isEnabled { center.close() } }
        )) { request in
            QuickCapturePanel(startsDictation: request.dictation) { center.close() }
                .presentationDetents([.height(250)])
                .presentationBackground(.ultraThinMaterial)
                .presentationCornerRadius(28)
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Confirmación

/// «✓ Apuntado "título"». Se va sola en 1,8 s; si se guarda otra, la sustituye (nunca se apilan).
struct CaptureToast: View {
    let confirmation: CaptureCenter.Confirmation

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Tarea apuntada")
                    .font(.subheadline.weight(.semibold))
                Text("«\(confirmation.title)» · " + (confirmation.addedToTasks
                    ? "en tus tareas"
                    : (confirmation.duringSession ? "la organizas al terminar" : "en Plan › Por organizar")))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, Space.l)
        .accessibilityElement(children: .combine)
    }
}

/// Coloca la confirmación abajo, la retira a su tiempo y vibra al guardar.
struct CaptureToastOverlay: ViewModifier {
    var bottomPadding: CGFloat
    @State private var center = CaptureCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let confirmation = center.confirmation {
                    CaptureToast(confirmation: confirmation)
                        .id(confirmation.id)
                        .padding(.bottom, bottomPadding)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        .allowsHitTesting(false)
                        .task {
                            AccessibilityNotification.Announcement("Tarea apuntada:\(confirmation.title)").post()
                            try? await Task.sleep(for: .seconds(1.8))
                            withAnimation(.easeIn(duration: 0.25)) { center.dismissConfirmation(confirmation.id) }
                        }
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.15), value: center.confirmation?.id)
            .sensoryFeedback(.success, trigger: center.confirmation?.id) { _, new in new != nil }
    }
}

// MARK: - Resúmenes

/// «Mientras te concentrabas… Has apuntado 3 tareas [Organizarlas] [Después]». En el descanso,
/// cuando ya se ha cerrado la tarjeta de cambio de fase.
struct CaptureBreakStrip: View {
    let sessionStart: Date
    @State private var center = CaptureCenter.shared
    @State private var comms = CommsCenter.shared

    var body: some View {
        let _ = center.revision
        let captures = center.toSummarize(sessionStart: sessionStart)
        if !captures.isEmpty, !comms.phaseCardVisible {
            CaptureSummaryCard(
                eyebrow: "Mientras te concentrabas…",
                title: CaptureRules.summary(count: captures.count),
                primary: "Organizarlas",
                onPrimary: {
                    center.markPresented(captures)
                    center.inboxRequested = true
                },
                onLater: { center.markPresented(captures) }
            )
            .transition(.opacity)
        }
    }
}

/// Tarjeta común de los resúmenes de captura.
struct CaptureSummaryCard: View {
    var eyebrow: String?
    let title: String
    let primary: String
    let onPrimary: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(Theme.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    if let eyebrow {
                        Text(eyebrow)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }
            }
            HStack(spacing: Space.s) {
                Button(primary, action: onPrimary)
                    .buttonStyle(.glassProminent)
                    .tint(Theme.orange)
                    .foregroundStyle(.black)
                Button("Después", action: onLater)
                    .buttonStyle(.glass)
            }
            .font(.subheadline.weight(.semibold))
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.m)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

// MARK: - Por organizar

/// Una captura en una lista: título, cuándo, plan, de qué sesión y en qué estado.
struct CaptureRow: View {
    let capture: CapturedTask

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(capture.text)
                .font(.body)
                .foregroundStyle(capture.status == .pending ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
                .strikethrough(capture.status == .done)
                .lineLimit(3)
            HStack(spacing: Space.xs) {
                Image(systemName: capture.source.symbol)
                    .accessibilityLabel(capture.source.title)
                Text(Self.detail(for: capture))
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    static func detail(for capture: CapturedTask, now: Date = .now) -> String {
        let style: Date.FormatStyle = Calendar.current.isDateInToday(capture.created)
            ? Date.FormatStyle.dateTime.hour().minute()
            : Date.FormatStyle.dateTime.weekday(.abbreviated).day().hour().minute()
        var parts = [capture.created.formatted(style)]
        parts.append(capture.mode.title)
        if capture.sessionStart != nil {
            parts.append(capture.phaseRaw == "break" ? "en un descanso" : "en una sesión")
        }
        switch capture.status {
        case .planned: parts.append("en el plan")
        case .done: parts.append("hecha")
        case .pending:
            if let until = capture.snoozedUntil, until > now {
                parts.append("pospuesta hasta \(until.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
            } else if capture.reviewedAt == nil {
                parts.append("sin revisar")
            }
        }
        return parts.joined(separator: " · ")
    }
}

/// Acciones de una captura (deslizar y menú contextual): planificar, editar, plan, hecha,
/// posponer y eliminar.
struct CaptureActions: ViewModifier {
    let capture: CapturedTask
    let onPlan: (CapturedTask) -> Void
    @State private var center = CaptureCenter.shared
    @State private var editing = false
    @State private var editText = ""

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading) {
                if capture.status == .pending {
                    Button("Hecha", systemImage: "checkmark") { center.complete(capture) }
                        .tint(.green)
                }
            }
            .swipeActions(edge: .trailing) {
                Button("Eliminar", systemImage: "trash", role: .destructive) { center.delete(capture) }
                if capture.status == .pending {
                    Button("Posponer", systemImage: "clock") { center.snooze(capture, until: CaptureCenter.tomorrowMorning) }
                        .tint(.indigo)
                }
            }
            .contextMenu {
                if capture.status == .pending {
                    Button("Planificar", systemImage: "sparkles") { onPlan(capture) }
                    Button("Editar", systemImage: "pencil") {
                        editText = capture.text
                        editing = true
                    }
                    Menu("Cambiar de plan", systemImage: "arrow.left.arrow.right") {
                        ForEach(PlanMode.allCases) { mode in
                            Button(mode.title) { center.setMode(capture, mode) }
                                .disabled(capture.mode == mode)
                        }
                    }
                    Button("Marcar como hecha", systemImage: "checkmark.circle") { center.complete(capture) }
                    Menu("Posponer la revisión", systemImage: "clock") {
                        Button("Dentro de 1 hora") { center.snooze(capture, until: .now.addingTimeInterval(3600)) }
                        Button("Mañana a las 9:00") { center.snooze(capture, until: CaptureCenter.tomorrowMorning) }
                    }
                } else if capture.status == .done {
                    Button("Volver a por organizar", systemImage: "arrow.uturn.backward") { center.reopen(capture) }
                }
                Button("Eliminar", systemImage: "trash", role: .destructive) { center.delete(capture) }
            }
            .alert("Editar", isPresented: $editing) {
                TextField("¿Qué necesitas recordar?", text: $editText)
                Button("Guardar") { center.edit(capture, text: editText) }
                Button("Cancelar", role: .cancel) {}
            }
    }
}

/// «Por organizar»: todo lo apuntado deprisa, para planificarlo con calma.
struct CaptureInboxView: View {
    var showsDone = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \CapturedTask.created, order: .reverse) private var captures: [CapturedTask]
    @State private var center = CaptureCenter.shared
    @State private var planning: VoiceTaskFlow?

    var body: some View {
        let now = Date.now
        let pending = captures.filter { CaptureRules.isPending($0.entry, now: now) }
        let snoozed = captures.filter { $0.status == .pending && !CaptureRules.isPending($0.entry, now: now) }
        let finished = captures.filter { $0.status != .pending }.prefix(30)

        List {
            if pending.isEmpty {
                ContentUnavailableView(
                    "Nada por organizar",
                    systemImage: "tray",
                    description: Text("Lo que apuntes con el botón de captura rápida aparecerá aquí.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(pending) { capture in
                        Button { plan(capture) } label: { CaptureRow(capture: capture) }
                            .buttonStyle(.plain)
                            .modifier(CaptureActions(capture: capture, onPlan: plan))
                    }
                } footer: {
                    Text("Toca una para planificarla. Mantén pulsada para editarla, cambiar de plan, marcarla como hecha o posponerla.")
                }
            }
            if !snoozed.isEmpty {
                Section("Pospuestas") {
                    ForEach(snoozed) { capture in
                        CaptureRow(capture: capture)
                            .modifier(CaptureActions(capture: capture, onPlan: plan))
                    }
                }
            }
            if showsDone, !finished.isEmpty {
                Section("Organizadas") {
                    ForEach(Array(finished)) { capture in
                        CaptureRow(capture: capture)
                            .modifier(CaptureActions(capture: capture, onPlan: plan))
                    }
                }
            }
        }
        .navigationTitle("Por organizar")
        .navigationBarTitleDisplayMode(.inline)
        .voiceTaskSheet($planning)
    }

    private func plan(_ capture: CapturedTask) {
        planning = CaptureCenter.planningFlow(for: capture)
    }
}

extension CaptureCenter {
    /// Organizar una captura con el mismo flujo que «Añadir por voz» (Apple Intelligence si está,
    /// y si no una propuesta sencilla), siempre con confirmación. Al aceptar, la captura queda
    /// enlazada a la tarea creada.
    static func planningFlow(for capture: CapturedTask) -> VoiceTaskFlow {
        VoiceTaskFlow(presetText: capture.text, preferredMode: capture.mode) { draft in
            CaptureCenter.shared.markPlanned(capture, draft: draft)
        }
    }
}
