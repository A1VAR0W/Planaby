import SwiftData
import SwiftUI

// MARK: - Concentración: solo lo importante de trabajo

/// «Trabajo · 2 importantes» encima de la tarea. Pequeña y apagada para no competir con el
/// temporizador; al tocarla enseña hasta dos líneas. Si llegó algo mientras Planaby estaba en
/// segundo plano, el punto naranja late una vez («Mientras estabas fuera»).
struct WorkCommsPill: View {
    @Query(sort: \MessageItem.received, order: .reverse) private var all: [MessageItem]
    @State private var comms = CommsCenter.shared
    @State private var expanded = false

    var body: some View {
        let items = comms.items(for: .focus, from: all)
        let away = comms.away?.phase == .focus ? comms.away : nil
        if !items.isEmpty, !comms.phaseCardVisible {
            VStack(spacing: Space.xs) {
                Button {
                    withAnimation(Motion.quick) { expanded.toggle() }
                    if away != nil { comms.dismissAway() }
                } label: {
                    HStack(spacing: Space.s) {
                        GlowDot(pulses: away != nil)
                        Text(away?.title ?? "Trabajo · \(items.count == 1 ? "1 importante" : "\(items.count) importantes")")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.secondaryText)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, Space.m)
                    .frame(minHeight: 36)
                    .background(Theme.surface, in: .capsule)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(away?.title ?? "Comunicaciones de trabajo: \(items.count) importantes")
                .accessibilityHint(expanded ? "Oculta el detalle" : "Muestra el detalle")

                if expanded {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        ForEach(items.prefix(2)) { item in
                            Text(comms.line(item))
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(2)
                        }
                        Button("Ver en la bandeja") { comms.inboxRequested = true }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.orange)
                            .frame(minHeight: 32)
                    }
                    .padding(.horizontal, Space.m)
                    .frame(maxWidth: 340, alignment: .leading)
                    .transition(.opacity)
                }
            }
            .transition(.opacity)
        }
    }
}

// MARK: - Descanso: lo que llegó mientras tanto

/// «Mientras te concentrabas… Tienes 4 comunicaciones pendientes», con el recuento por app.
/// Si acaba de llegar algo nuevo, se enseña la tarjeta animada en su lugar.
struct BreakCommsStrip: View {
    @Query(sort: \MessageItem.received, order: .reverse) private var all: [MessageItem]
    @State private var comms = CommsCenter.shared

    var body: some View {
        let items = comms.items(for: .rest, from: all)
        if comms.phaseCardVisible {
            EmptyView()
        } else if let away = comms.away, away.phase != .focus {
            AwayDigestCard(digest: away)
        } else if !items.isEmpty {
            Button { comms.inboxRequested = true } label: {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Mientras te concentrabas…")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    Text(items.count == 1 ? "Tienes 1 comunicación pendiente" : "Tienes \(items.count) comunicaciones pendientes")
                        .font(.subheadline.weight(.semibold))
                    Text(comms.breakdown(items).map { "\($0.app) \($0.count)" }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: 340, alignment: .leading)
                .padding(Space.m)
                .background(Theme.surface, in: .rect(cornerRadius: Theme.cardRadius))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Abre la bandeja")
        }
    }
}

// MARK: - Mientras estabas fuera

/// Punto naranja con halo. Late una sola vez al aparecer (nada de animaciones continuas) y no
/// se mueve con «Reducir movimiento».
struct GlowDot: View {
    var pulses = false
    var size: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false

    var body: some View {
        Circle()
            .fill(Theme.orange)
            .frame(width: size, height: size)
            .shadow(color: Theme.orange.opacity(pulses ? 0.9 : 0.5), radius: lit ? size : size / 2)
            .scaleEffect(lit && !reduceMotion ? 1.35 : 1)
            .accessibilityHidden(true)
            .task(id: pulses) {
                guard pulses, !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.5)) { lit = true }
                try? await Task.sleep(for: .milliseconds(900))
                withAnimation(.easeInOut(duration: 0.8)) { lit = false }
            }
    }
}

/// «Mientras estabas fuera, llegaron 3 comunicaciones importantes», con las tarjetas entrando
/// una detrás de otra. Se usa en los descansos y sin sesión; concentrándose basta con la píldora.
struct AwayDigestCard: View {
    let digest: CommsCenter.AwayDigest
    var showsClose = true
    /// Por defecto abre la bandeja; dentro de otra hoja, primero hay que cerrarla.
    var onOpenInbox: (() -> Void)?
    @State private var comms = CommsCenter.shared
    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                GlowDot(pulses: true, size: 10)
                Text(digest.title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if showsClose {
                    Button("Cerrar", systemImage: "xmark") { withAnimation(Motion.quick) { comms.dismissAway() } }
                        .labelStyle(.iconOnly)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 44, height: 44)
                }
            }
            ForEach(Array(digest.items.enumerated()), id: \.offset) { index, item in
                if index < shown {
                    CommLineView(item: item)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            Button {
                comms.dismissAway()
                if let onOpenInbox { onOpenInbox() } else { comms.inboxRequested = true }
            } label: {
                Text("Abrir la bandeja")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.orange)
        }
        .padding(Space.m)
        .frame(maxWidth: 400)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.cardRadius))
        .accessibilityElement(children: .contain)
        .task(id: digest.id) {
            // Entrada escalonada una sola vez; con «Reducir movimiento», todas a la vez.
            if reduceMotion {
                shown = digest.items.count
                return
            }
            for index in digest.items.indices {
                try? await Task.sleep(for: .milliseconds(index == 0 ? 150 : 110))
                withAnimation(Motion.emphasized) { shown = index + 1 }
            }
        }
    }
}

/// Una comunicación en una línea: icono de la app, «App — Remitente: lo que pide».
struct CommLineView: View {
    let item: MessageItem
    @State private var comms = CommsCenter.shared

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: item.app.symbol)
                .font(.footnote)
                .foregroundStyle(item.category == .urgent ? Theme.orange : Theme.secondaryText)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(comms.line(item))
                .font(.footnote)
                .lineLimit(2)
            Spacer(minLength: 0)
            if item.needsReply {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.orange)
                    .accessibilityLabel("Espera respuesta")
            }
        }
        .padding(Space.s)
        .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 14))
        .commActions(item)
    }
}

// MARK: - Acciones sobre una comunicación

extension View {
    /// Menú contextual con las acciones: revisado, respondido, posponer, al plan y abrir la app.
    func commActions(_ item: MessageItem) -> some View {
        modifier(CommActionsModifier(item: item))
    }
}

private struct CommActionsModifier: ViewModifier {
    let item: MessageItem

    func body(content: Content) -> some View {
        content.contextMenu {
            CommActionButtons(item: item)
        }
    }
}

/// Los mismos botones en el menú contextual y en la bandeja.
struct CommActionButtons: View {
    let item: MessageItem
    @State private var comms = CommsCenter.shared

    var body: some View {
        if item.isOpen {
            Button("Marcar como revisado", systemImage: "checkmark.circle") { comms.markReviewed(item) }
            Button("Ya lo he respondido", systemImage: "arrowshape.turn.up.left.circle") { comms.markReplied(item) }
            Menu("Posponer", systemImage: "clock") {
                Button("30 minutos") { comms.snooze(item, minutes: 30) }
                Button("1 hora") { comms.snooze(item, minutes: 60) }
                Button("3 horas") { comms.snooze(item, minutes: 180) }
            }
        } else {
            Button("Marcar como pendiente", systemImage: "circle") { comms.reopen(item) }
        }
        Button("Añadir al plan como tarea", systemImage: "plus.square.on.square") { comms.addToPlan(item) }
        if comms.canOpen(item) {
            Button("Abrir \(item.appTitle)", systemImage: "arrow.up.forward.app") { comms.open(item) }
        }
    }
}
