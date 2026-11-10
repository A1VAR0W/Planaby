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
        VStack(spacing: Space.m) {
            // Todo centrado: icono, título y mensaje en el medio de la tarjeta.
            VStack(spacing: Space.s) {
                Image(systemName: symbol)
                    .font(.largeTitle)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            commsSummary
            captureSummary
            actions
        }
        .padding(Space.l)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardRadius))
        // Acento del color de la fase que empieza: se distingue a la primera de la música de detrás.
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(tint.opacity(0.4), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.4), radius: 18, y: 6)
        .padding(.horizontal, Space.m)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .task(id: transition.id) {
            // Tras «Empezar ahora» se espera a que decida; si no, se cierra sola (y la sesión sigue
            // con la fase que toca). Al acabar la concentración se deja más rato para elegir.
            // Con «Preguntar qué hacer» tampoco se cierra: el descanso espera a que se elija.
            guard !transition.endedStarter, !awaiting else { return }
            try? await Task.sleep(for: .seconds(intoBreak ? 30 : 12))
            if !Task.isCancelled { onClose() }
        }
    }

    // MARK: - Textos

    private var intoBreak: Bool { transition.next.isBreak }

    /// El descanso está esperando a que se elija («Preguntar qué hacer»).
    private var awaiting: Bool { intoBreak && timer.state?.isAwaitingChoice == true }

    /// «Descansar»: si el descanso esperaba, empieza ahora; si ya corría, solo se cierra.
    private func rest() {
        if awaiting { timer.resume() }
        onClose()
    }

    private var symbol: String {
        if transition.endedStarter { return "flag.checkered" }
        return intoBreak ? "cup.and.saucer.fill" : "bolt.fill"
    }

    private var tint: Color { intoBreak ? Theme.shortBreak : Theme.orange }

    private var title: String {
        if transition.endedStarter { return "Ya has empezado" }
        return PhaseAlertText.title(finished: transition.finished, next: transition.next)
    }

    /// «Has trabajado durante 25 minutos. Comienza tu descanso de 5 minutos».
    private var summary: String {
        PhaseAlertText.message(
            finished: transition.finished, finishedDuration: transition.finishedDuration,
            next: transition.next, nextDuration: transition.nextDuration
        )
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
        if awaiting {
            var text = "Tu concentración ha terminado. ¿Descansas, sigues o lo dejas por hoy?"
            if let nextStep { text += " Siguiente paso: \(nextStep)." }
            return text
        }
        if intoBreak {
            var text = summary + " Levántate y mira lejos un rato."
            if let nextStep { text += " Al volver: \(nextStep)." }
            return text
        }
        var text = summary
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
                    Button { rest() } label: {
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
            // Al acabar la concentración: descansar, seguir concentrado o dar la sesión por terminada.
            // Al acabar el descanso: volver, o terminar.
            VStack(spacing: Space.s) {
                Button { rest() } label: {
                    Text(intoBreak ? "Descansar" : "Vamos")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.glassProminent)
                .tint(tint)
                HStack(spacing: Space.s) {
                    if intoBreak {
                        Button {
                            // Otro bloque de concentración desde ahora, sin descanso.
                            timer.refocus()
                            onClose()
                        } label: {
                            Text("Seguir").frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .accessibilityLabel("Seguir concentrado sin descansar")
                    }
                    Button {
                        timer.stop()
                        onClose()
                    } label: {
                        Text("Finalizar").frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .accessibilityLabel("Finalizar la sesión")
                }
                .buttonStyle(.glass)
            }
        }
    }
}
