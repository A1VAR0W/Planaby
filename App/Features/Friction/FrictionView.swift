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
    @FocusState private var reasonFocused: Bool

    private let pause = FrictionGuard.pauseSeconds
    private let pass = FrictionGuard.passMinutes

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
                    if resistedToday > 0 {
                        Label("Hoy has vuelto a lo tuyo \(resistedToday == 1 ? "1 vez" : "\(resistedToday) veces")", systemImage: "leaf.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.orange)
                    }
                }
                TextField("¿Para qué la abres? (opcional)", text: $reason)
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

    private func buttons(enabled: Bool) -> some View {
        VStack(spacing: Space.s) {
            Button {
                reasonFocused = false
                FrictionGuard.shared.finish(request, reason: reason, resisted: true, context: context)
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

            Button {
                reasonFocused = false
                FrictionGuard.shared.finish(request, reason: reason, resisted: false, context: context)
                if let url = FrictionGuard.url(for: request.app) { openURL(url) }
                onDone(false)
            } label: {
                Text("Abrir \(appName) \(pass) min")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(!enabled)
            .accessibilityHint(enabled ? "Durante \(pass) minutos no te volveré a frenar" : "Espera a que termine la cuenta atrás")
        }
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
