import SwiftUI

/// Aviso de cambio de fase con Planaby delante: sustituye a la notificación (que no se enseña
/// con la app abierta, para no avisar dos veces). Se cierra sola salvo tras «Empezar ahora»,
/// donde hay que decidir si seguir.
struct PhaseTransitionCard: View {
    let transition: FocusTimer.AutomaticTransition
    let onClose: () -> Void

    @Environment(FocusTimer.self) private var timer
    @Environment(MethodLibrary.self) private var library

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
