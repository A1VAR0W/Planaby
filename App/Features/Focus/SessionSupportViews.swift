import SwiftData
import SwiftUI

// MARK: - Contexto de la sesión

/// Lo que se está haciendo, para retomar sin pensar. Todo opcional.
struct SessionContextSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(FocusTimer.self) private var timer
    @Query private var tasks: [PlanTask]
    @State private var draft = SessionContext(sessionStart: .now)

    private var task: PlanTask? {
        guard let id = timer.state?.taskID else { return nil }
        return tasks.first { $0.uid == id }
    }

    var body: some View {
        Form {
            if let title = timer.state?.taskTitle {
                Section("Tarea") { Text(title).font(.headline) }
            }
            Section {
                TextField("Qué quieres tener al acabar el bloque", text: $draft.objective, axis: .vertical)
            } header: { Text("Objetivo") }
            Section {
                TextField("Lo siguiente que vas a hacer", text: $draft.nextStep, axis: .vertical)
            } header: { Text("Siguiente paso") } footer: {
                Text("Aparece en la pantalla del temporizador y en el aviso de vuelta del descanso.")
            }
            Section {
                TextField("Dónde lo has dejado, ideas sueltas…", text: $draft.note, axis: .vertical)
                TextField("Qué falta o de quién dependes", text: $draft.missing, axis: .vertical)
            } header: { Text("Notas") }
        }
        .navigationTitle("Contexto")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Guardar", action: save) }
        }
        .onAppear {
            guard let start = timer.state?.sessionStart else { return }
            draft = SessionContext.load(for: start) ?? SessionContext(sessionStart: start, nextStep: task?.firstStep ?? "")
        }
    }

    private func save() {
        SessionContext.save(draft)
        // El siguiente paso también queda en la tarea, para la próxima vez.
        let step = draft.nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
        if let task, !step.isEmpty {
            task.nextStep = step
            try? modelContext.save()
        }
        timer.sync()
        dismiss()
    }
}

// MARK: - Atascado

/// «Me he atascado»: apuntar qué bloquea y pasar a otra tarea, o hacer el paso más pequeño.
struct StuckSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(FocusTimer.self) private var timer
    @Query(filter: #Predicate<PlanTask> { !$0.isDone }, sort: \PlanTask.deadline) private var tasks: [PlanTask]
    @State private var blocker = ""
    @State private var smallerStep = ""

    private var current: PlanTask? {
        guard let id = timer.state?.taskID else { return nil }
        return tasks.first { $0.uid == id }
    }

    private var others: [PlanTask] {
        tasks.filter { !$0.isBlocked && $0.uid != timer.state?.taskID }
            .sorted { $0.priority != $1.priority ? $0.priority > $1.priority : $0.deadline < $1.deadline }
    }

    var body: some View {
        Form {
            Section {
                Text("Pasa a todo el mundo. Elige una salida y sigue: no hace falta resolverlo ahora.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }

            Section {
                TextField("Un paso aún más pequeño", text: $smallerStep, axis: .vertical)
                Button {
                    retry()
                } label: {
                    Label("Intentarlo 10 minutos con este paso", systemImage: "arrow.clockwise")
                }
                .disabled(smallerStep.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("Seguir con esto")
            }

            Section {
                if current != nil {
                    TextField("Qué te bloquea (opcional)", text: $blocker, axis: .vertical)
                }
                if others.isEmpty {
                    Text("No hay otras tareas pendientes.")
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    ForEach(others.prefix(6)) { task in
                        Button {
                            switchTo(task)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title).foregroundStyle(.white)
                                if let step = task.firstStep {
                                    Text(step).font(.footnote).foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text(current == nil ? "Cambiar a una tarea" : "Aparcarla y cambiar de tarea")
            } footer: {
                if current != nil {
                    Text("La tarea queda marcada como atascada con tu nota; no te la volveré a proponer hasta que la desbloquees.")
                }
            }
        }
        .navigationTitle("Me he atascado")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
        }
    }

    private func retry() {
        let step = smallerStep.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = timer.state?.sessionStart {
            var context = SessionContext.load(for: start) ?? SessionContext(sessionStart: start)
            context.nextStep = step
            SessionContext.save(context)
        }
        if let current {
            current.nextStep = step
            try? modelContext.save()
        }
        timer.refocus(minutes: 10)
        dismiss()
    }

    private func switchTo(_ task: PlanTask) {
        if let current {
            current.blockedAt = .now
            current.blockedNote = blocker.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        try? modelContext.save()
        timer.setTask(task.title, id: task.stableID)
        if let start = timer.state?.sessionStart {
            SessionContext.save(SessionContext(sessionStart: start, nextStep: task.firstStep ?? ""))
        }
        if timer.state?.phase == .focus {
            timer.refocus()
        } else {
            timer.sync()
        }
        dismiss()
    }
}

// MARK: - Vuelta tras salir

/// «Bienvenido de nuevo»: al volver a Planaby tras salir en mitad de un bloque. Recuerda qué
/// estabas haciendo y propone retomar; tras una ausencia larga, con un bloque corto.
struct RecoveryView: View {
    let info: LeaveGuard.Return
    let onStuck: () -> Void
    var onInbox: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(FocusTimer.self) private var timer
    /// Lo que llegó mientras estabas fuera va en esta hoja (y no en otra tarjeta a la vez).
    @State private var digest: CommsCenter.AwayDigest?

    /// Más de diez minutos fuera: volver con un bloque corto cuesta menos.
    private var isLong: Bool { info.seconds >= 600 }

    private var context: SessionContext? {
        timer.state.flatMap { SessionContext.load(for: $0.sessionStart) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Bienvenido de nuevo")
                    .font(.title2.weight(.semibold))
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if timer.state?.taskTitle != nil || !(context?.nextStep.isEmpty ?? true) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    if let task = timer.state?.taskTitle {
                        Label(task, systemImage: "square.stack.3d.up.fill")
                            .font(.headline)
                    }
                    if let step = context?.nextStep, !step.isEmpty {
                        Text("Siguiente paso: \(step)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    if let note = context?.note, !note.isEmpty {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }

            if let digest {
                AwayDigestCard(digest: digest, showsClose: false) {
                    onInbox()
                    dismiss()
                }
            }

            VStack(spacing: Space.s) {
                Button {
                    if isLong { timer.refocus(minutes: 10) }
                    dismiss()
                } label: {
                    Text(isLong ? "Retomar con 10 minutos" : "Retomar concentración")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.orange)
                .controlSize(.large)

                HStack(spacing: Space.s) {
                    Button {
                        onStuck()
                        dismiss()
                    } label: {
                        Text("Me he atascado").frame(maxWidth: .infinity, minHeight: 32)
                    }
                    Button {
                        timer.pause()
                        dismiss()
                    } label: {
                        Text("Pausar").frame(maxWidth: .infinity, minHeight: 32)
                    }
                }
                .buttonStyle(.glass)
            }
        }
        .padding(Space.l)
        .presentationDetents(digest == nil ? [.medium] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { if digest == nil { digest = CommsCenter.shared.takeAway() } }
    }

    private var summary: String {
        var text = "Has estado fuera \(LeaveGuard.minutes(info.seconds))."
        if info.strict { text += " Ese rato no ha contado: el bloque sigue donde lo dejaste." }
        if let remaining = info.remaining { text += " Te quedan \(LeaveGuard.minutes(remaining)) de concentración." }
        if isLong { text += " Después de tanto rato, mejor un bloque corto para volver a entrar." }
        return text
    }
}

// MARK: - Valoración al terminar

/// Pregunta opcional al terminar: ayuda a que las recomendaciones no premien sesiones largas
/// pero dispersas. Un toque o «Omitir».
struct SessionRatingSheet: View {
    let sessionStart: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private struct Option: Identifiable {
        let id: Int
        let title: String
        let symbol: String
    }

    private let options = [
        Option(id: 1, title: "Disperso", symbol: "cloud.drizzle"),
        Option(id: 2, title: "Normal", symbol: "circle.lefthalf.filled"),
        Option(id: 3, title: "Muy centrado", symbol: "scope"),
    ]

    var body: some View {
        VStack(spacing: Space.l) {
            Text("¿Cómo te has concentrado?")
                .font(.headline)
            HStack(spacing: Space.s) {
                ForEach(options) { option in
                    Button {
                        rate(option.id)
                    } label: {
                        VStack(spacing: Space.xs) {
                            Image(systemName: option.symbol).font(.title2)
                            Text(option.title).font(.footnote)
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                    }
                    .buttonStyle(.glass)
                }
            }
            Button("Omitir") { dismiss() }
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(Space.l)
        .presentationDetents([.height(240)])
    }

    private func rate(_ value: Int) {
        let start = sessionStart
        let descriptor = FetchDescriptor<FocusSessionRecord>(predicate: #Predicate { $0.start == start })
        if let record = try? modelContext.fetch(descriptor).first {
            record.focusRating = value
            try? modelContext.save()
        }
        dismiss()
    }
}
