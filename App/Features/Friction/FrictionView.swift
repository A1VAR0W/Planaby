import SwiftData
import SwiftUI

/// Pausa consciente: unos segundos respirando antes de decidir si se abre la app que distrae.
struct FrictionView: View {
    let request: FrictionGuard.Request
    /// true si vuelve a concentrarse.
    let onDone: (Bool) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(FocusTimer.self) private var timer
    @Query(sort: \DistractionRecord.date, order: .reverse) private var records: [DistractionRecord]
    @State private var started = Date.now
    @State private var reason = ""
    @State private var motive: DistractionMotive?
    @FocusState private var reasonFocused: Bool

    private var pause: Int { request.seconds }
    private var pass: Int { request.passMinutes }
    /// En modo estricto hay que decir para qué se abre.
    private var hasMotive: Bool { !request.asksMotive || motive != nil || !reason.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30)) { timeline in
            let left = max(0, pause - Int(timeline.date.timeIntervalSince(started)))
            VStack(spacing: Space.l) {
                Spacer(minLength: Space.l)
                breathing(at: timeline.date, left: left)
                Spacer(minLength: Space.m)
                VStack(spacing: Space.s) {
                    Text(question)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                    if let focusLine {
                        Text(focusLine)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    if request.recentAttempts > 0 {
                        Text(request.recentAttempts == 1
                             ? "Es la segunda vez en media hora: esta pausa es algo más larga."
                             : "Es la \(request.recentAttempts + 1).ª vez en media hora. ¿Qué te está costando?")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    if resistedToday > 0 {
                        Label("Hoy has vuelto a lo tuyo \(resistedToday == 1 ? "1 vez" : "\(resistedToday) veces")", systemImage: "leaf.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.orange)
                    }
                }
                motives
                TextField(request.asksMotive ? "¿Para qué la abres?" : "¿Para qué la abres? (opcional)", text: $reason)
                    .focused($reasonFocused)
                    .padding(.horizontal, Space.m)
                    .frame(minHeight: 48)
                    .background(Theme.surface, in: .rect(cornerRadius: 16))
                buttons(enabled: left == 0)
            }
            .padding(Space.l)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    // MARK: - Piezas

    private func breathing(at date: Date, left: Int) -> some View {
        let level = reduceMotion ? 0.6 : Breath.level(at: date)
        return ZStack {
            Circle()
                .fill(Theme.orange.opacity(0.14))
                .scaleEffect(0.55 + 0.45 * level)
            Circle()
                .stroke(Theme.orange.opacity(0.5), lineWidth: 2)
                .scaleEffect(0.55 + 0.45 * level)
            VStack(spacing: Space.xs) {
                Text(left > 0 ? "\(left)" : "Listo")
                    .font(.system(size: left > 0 ? 56 : 32, weight: .light, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
                Text(Breath.isInhaling(at: date) ? "Inhala" : "Exhala")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .opacity(reduceMotion || left == 0 ? 0 : 1)
            }
        }
        .frame(width: 220, height: 220)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(left > 0 ? "Respira. Quedan \(left) segundos" : "Ya puedes decidir")
    }

    /// Motivos rápidos: sirven para ver patrones («la abro por aburrimiento a las 17 h»).
    private var motives: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(DistractionMotive.allCases) { item in
                    let selected = motive == item
                    Button {
                        motive = selected ? nil : item
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                            .font(.footnote.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.black : Color.white)
                            .padding(.horizontal, Space.m)
                            .frame(minHeight: 36)
                            .background(selected ? Theme.orange : Theme.surface, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .sensoryFeedback(.selection, trigger: motive)
        .accessibilityLabel("Motivo")
    }

    private func buttons(enabled: Bool) -> some View {
        VStack(spacing: Space.s) {
            Button {
                reasonFocused = false
                FrictionGuard.shared.finish(request, reason: reason, motive: motive, resisted: true, context: context)
                onDone(true)
            } label: {
                Label("Volver a lo mío", systemImage: "arrow.uturn.backward")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.orange)
            .controlSize(.large)

            // Una automatización para varias apps no dice cuál se abrió: se elige aquí.
            let choices = FrictionGuard.chosenApps
            Group {
                if request.app.isEmpty, choices.count > 1 {
                    Menu {
                        ForEach(choices) { app in
                            Button(app.name) { openAnyway(app.name) }
                        }
                    } label: {
                        Text("Abrir igualmente")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .menuStyle(.button)
                } else {
                    Button {
                        openAnyway(request.app)
                    } label: {
                        Text("Abrir \(appName) \(pass) min")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                }
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(!enabled || !hasMotive)
            .accessibilityHint(enabled
                ? (hasMotive ? "Durante \(pass) minutos no te volveré a frenar con esta app" : "Antes di para qué la abres")
                : "Espera a que termine la cuenta atrás")
            if enabled, !hasMotive {
                Text("Elige un motivo o escribe para qué la abres.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func openAnyway(_ app: String) {
        reasonFocused = false
        var chosen = request
        // En un aviso sin nombre, el pase es el de la app elegida.
        if request.app.isEmpty, !app.isEmpty { chosen.passMinutes = FrictionGuard.passMinutes(for: app) }
        FrictionGuard.shared.finish(chosen, openedApp: app, reason: reason, motive: motive, resisted: false, context: context)
        // Abrirla igualmente da un pase: durante ese rato tampoco avisa al salir.
        LeaveGuard.shared.excuse(for: TimeInterval(chosen.passMinutes * 60))
        if let url = FrictionGuard.url(for: app) { openURL(url) }
        onDone(false)
    }

    // MARK: - Textos

    private var appName: String { request.app.isEmpty ? "la app" : request.app }

    private var question: String {
        request.app.isEmpty ? "¿Seguro que quieres abrirla ahora?" : "¿Seguro que quieres abrir \(request.app) ahora?"
    }

    private var focusLine: String? {
        guard let state = timer.state, state.phase == .focus else { return nil }
        let task = state.taskTitle.map { " en «\($0)»" } ?? ""
        if let remaining = state.remaining(at: .now) {
            return "Estás concentrándote\(task). Quedan \(FocusStats.format(remaining))."
        }
        return "Estás concentrándote\(task)."
    }

    private var resistedToday: Int {
        records.prefix(200).filter { $0.resisted && Calendar.current.isDateInToday($0.date) }.count
    }
}
