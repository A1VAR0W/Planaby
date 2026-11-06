import SwiftData
import SwiftUI

/// Aviso de cambio de fase con Planaby delante: sustituye a la notificación (que no se enseña
/// con la app abierta, para no avisar dos veces). Se cierra sola salvo tras «Empezar ahora»,
/// donde hay que decidir si seguir.
struct PhaseTransitionCard: View {
    let transition: FocusTimer.AutomaticTransition
    let onClose: () -> Void

    @Environment(FocusTimer.self) private var timer
    @Environment(MethodLibrary.self) private var library
    @Query(sort: \MessageItem.received, order: .reverse) private var messages: [MessageItem]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top, spacing: Space.m) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(title)
                        .font(.headline)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            commsSummary
            captureSummary
            actions
        }
        .padding(Space.m)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardRadius))
        .padding(.horizontal, Space.m)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .task(id: transition.id) {
            // Tras «Empezar ahora» se espera a que decida; si no, se cierra sola.
            guard !transition.endedStarter else { return }
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { onClose() }
        }
    }

    // MARK: - Textos

    private var intoBreak: Bool { transition.next.isBreak }

    private var symbol: String {
        if transition.endedStarter { return "flag.checkered" }
        return intoBreak ? "cup.and.saucer.fill" : "bolt.fill"
    }

    private var tint: Color { intoBreak ? Theme.shortBreak : Theme.orange }

    private var title: String {
        if transition.endedStarter { return "Ya has empezado" }
        return intoBreak ? "Buen trabajo. Es hora de descansar" : "Es hora de continuar"
    }

    private var minutes: String {
        transition.nextDuration.map { "\(Int(($0 / 60).rounded())) min" } ?? ""
    }

    private var nextStep: String? {
        guard let state = timer.state else { return nil }
        let step = SessionContext.load(for: state.sessionStart)?.nextStep ?? ""
        return step.isEmpty ? nil : step
    }

    private var message: String {
        if transition.endedStarter {
            return "Lo más difícil era arrancar. Puedes seguir con un bloque de \(library.selected.name) o descansar un momento."
        }
        if intoBreak {
            var text = "\(transition.next.title) de \(minutes). Levántate y mira lejos un rato."
            if let nextStep { text += " Al volver: \(nextStep)." }
            return text
        }
        var text = transition.nextDuration == nil ? "Concentración libre." : "\(minutes) de concentración."
        if let nextStep {
            text += " Siguiente paso: \(nextStep)."
        } else if let task = timer.state?.taskTitle {
            text += " Con «\(task)»."
        }
        return text
    }

    // MARK: - Comunicaciones

    /// Al empezar el descanso: lo que se guardó mientras te concentrabas, dentro de esta misma
    /// tarjeta (sin otra tarjeta ni hoja encima).
    @ViewBuilder
    private var commsSummary: some View {
        if intoBreak, !transition.endedStarter {
            let comms = CommsCenter.shared
            let pending = comms.items(for: .rest, from: messages)
            if !pending.isEmpty {
                Button {
                    onClose()
                    comms.inboxRequested = true
                } label: {
                    HStack(spacing: Space.s) {
                        GlowDot()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pending.count == 1 ? "Mientras te concentrabas: 1 pendiente" : "Mientras te concentrabas: \(pending.count) pendientes")
                                .font(.subheadline.weight(.semibold))
                            Text(comms.breakdown(pending).map { "\($0.app) \($0.count)" }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text("Ver")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.orange)
                    }
                    .padding(Space.s)
                    .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 16))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Abre la bandeja")
            }
        }
    }

    // MARK: - Capturas

    /// Lo apuntado con la captura rápida durante el bloque, en la misma tarjeta. Al tocarlo se
    /// abre «Por organizar»; si no, la línea vuelve a salir en el descanso al cerrarse la tarjeta.
    @ViewBuilder
    private var captureSummary: some View {
        if intoBreak, !transition.endedStarter, let state = timer.state {
            let center = CaptureCenter.shared
            let _ = center.revision
            let captures = center.toSummarize(sessionStart: state.sessionStart)
            if !captures.isEmpty {
                Button {
                    center.markPresented(captures)
                    onClose()
                    center.inboxRequested = true
                } label: {
                    HStack(spacing: Space.s) {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(Theme.orange)
                            .accessibilityHidden(true)
                        Text(CaptureRules.summary(count: captures.count))
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                        Text("Organizarlas")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.orange)
                    }
                    .padding(Space.s)
                    .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 16))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Abre «Por organizar»")
            }
        }
    }

    // MARK: - Acciones

    @ViewBuilder
    private var actions: some View {
        if transition.endedStarter {
            VStack(spacing: Space.s) {
                Button {
                    timer.continueWithBlock(library.selected)
                    onClose()
                } label: {
                    Text("Seguir con \(library.selected.name)")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.orange)
                HStack(spacing: Space.s) {
                    Button { onClose() } label: {
                        Text("Descansar").frame(maxWidth: .infinity, minHeight: 32)
                    }
                    Button {
                        timer.stop()
                        onClose()
                    } label: {
                        Text("Terminar").frame(maxWidth: .infinity, minHeight: 32)
                    }
                }
                .buttonStyle(.glass)
            }
        } else {
            HStack(spacing: Space.s) {
                if intoBreak {
                    Button {
                        timer.skip()
                        onClose()
                    } label: {
                        Text("Saltar descanso").frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.glass)
                }
                Button { onClose() } label: {
                    Text(intoBreak ? "Descansar" : "Vamos")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.glassProminent)
                .tint(tint)
            }
        }
    }
}
