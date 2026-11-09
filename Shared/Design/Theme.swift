import SwiftUI

/// Paleta naranja sobre negro: un naranja vivo para concentrarse y tonos más cálidos y suaves para descansar.
enum Theme {
    static let orange = Color(red: 1.0, green: 0.48, blue: 0.10)
    static let amber = Color(red: 1.0, green: 0.66, blue: 0.32)
    static let sand = Color(red: 1.0, green: 0.80, blue: 0.56)
    /// Tinta del modo escritorio por la noche, como StandBy.
    static let night = Color(red: 0.86, green: 0.22, blue: 0.08)

    static let focus = orange
    static let shortBreak = amber
    static let longBreak = sand

    /// Superficie de las tarjetas de contenido. El cristal queda para los controles, como pide iOS 26.
    static let surface = Color.white.opacity(0.07)
    static let hairline = Color.white.opacity(0.10)
    /// Texto secundario sobre negro con contraste AA (≈ 7:1).
    static let secondaryText = Color.white.opacity(0.64)

    static let cardRadius: CGFloat = 24

    static func clock(_ size: CGFloat) -> Font {
        .system(size: size, weight: .thin, design: .rounded).monospacedDigit()
    }

    static let eyebrow = Font.caption.weight(.semibold)
}

/// Escala de espaciado de 4 pt.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

extension View {
    /// Tarjeta de contenido sobre fondo negro.
    func card(padding: CGFloat = Space.m) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.cardRadius))
    }
}

extension PhaseKind {
    var tint: Color {
        switch self {
        case .focus: Theme.focus
        case .shortBreak: Theme.shortBreak
        case .longBreak: Theme.longBreak
        }
    }

    var symbol: String {
        switch self {
        case .focus: "flame.fill"
        case .shortBreak: "cup.and.saucer.fill"
        case .longBreak: "leaf.fill"
        }
    }
}

extension PlanMode {
    /// Trabajo en naranja vivo; Normal en arena, más tranquilo.
    var tint: Color {
        switch self {
        case .work: Theme.orange
        case .personal: Theme.sand
        }
    }
}

/// Ritmo de respiración lenta: 4 s inhalando y 6 s exhalando.
enum Breath {
    static let inhale: TimeInterval = 4
    static let exhale: TimeInterval = 6

    /// 0 = pulmones vacíos, 1 = llenos, con entrada y salida suaves.
    static func level(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: inhale + exhale)
        let progress = t < inhale ? t / inhale : 1 - (t - inhale) / exhale
        return (1 - cos(progress * .pi)) / 2
    }

    static func isInhaling(at date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: inhale + exhale) < inhale
    }

    /// El siguiente tramo de la respiración: adónde va (1 lleno, 0 vacío) y cuánto le queda.
    /// Sigue el mismo reloj que «Inhala / Exhala», así el halo y el texto van a la par.
    static func nextTurn(after date: Date) -> (level: Double, duration: TimeInterval) {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: inhale + exhale)
        return t < inhale ? (1, max(0.05, inhale - t)) : (0, max(0.05, inhale + exhale - t))
    }
}

/// Halo naranja que respira despacio detrás del contenido.
///
/// Se dibuja una sola vez y solo se animan su tamaño y su opacidad: SwiftUI interpola entre
/// inhalar y exhalar sin volver a pintar el degradado, y la vista solo despierta dos veces por
/// respiración (no 30 veces por segundo). Así puede respirar siempre sin gastar batería.
struct BreathingGlow: View {
    let tint: Color
    var strength: Double = 0.22
    /// false: halo quieto (el modo escritorio de noche o atenuado).
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var level = 0.5

    var body: some View {
        RadialGradient(colors: [tint.opacity(strength), .clear], center: .center, startRadius: 0, endRadius: 400)
            // Lo mismo que antes: radio de 260 a 400 pt y brillo del 55 al 100 %.
            .scaleEffect(0.65 + 0.35 * level)
            .opacity(0.55 + 0.45 * level)
            .allowsHitTesting(false)
            .ignoresSafeArea()
            .accessibilityHidden(true)
            .task(id: animated && !reduceMotion) { await breathe(animated && !reduceMotion) }
    }

    private func breathe(_ on: Bool) async {
        guard on else {
            withAnimation(.easeInOut(duration: 1)) { level = 0.5 }
            return
        }
        // Empieza donde va la respiración y sigue con ella.
        level = Breath.level(at: .now)
        while !Task.isCancelled {
            let turn = Breath.nextTurn(after: .now)
            withAnimation(.easeInOut(duration: turn.duration)) { level = turn.level }
            try? await Task.sleep(for: .seconds(turn.duration))
        }
    }
}

/// Fondo negro con el halo de la fase; en los descansos respira con más presencia.
struct PhaseBackground: View {
    let tint: Color
    var isBreak = false
    /// Respira siempre (salvo con «Reducir movimiento»): la pantalla de concentrarse se siente
    /// viva, y con `BreathingGlow` apenas cuesta.
    var animated = true

    var body: some View {
        ZStack {
            Color.black
            BreathingGlow(tint: tint, strength: isBreak ? 0.30 : 0.16, animated: animated)
                .offset(y: -120)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.2), value: tint)
    }
}

struct Eyebrow: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text.uppercased())
            .font(Theme.eyebrow)
            .tracking(2.4)
            .foregroundStyle(color)
    }
}

struct RoundButton: View {
    let label: String
    let systemImage: String
    var prominent = false
    var tint: Color = Theme.orange
    /// Versión más baja para el modo escritorio en horizontal.
    var compact = false
    let action: () -> Void

    var body: some View {
        let size: CGFloat = compact ? (prominent ? 64 : 50) : (prominent ? 84 : 60)
        let button = Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.36, weight: .medium))
                .frame(width: size, height: size)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)

        if prominent {
            button
                .buttonStyle(.glassProminent)
                .tint(tint)
                .foregroundStyle(.black)
        } else {
            button.buttonStyle(.glass)
        }
    }
}

struct ProgressRing: View {
    let progress: Double
    let tint: Color
    var lineWidth: CGFloat = 6
    var glows = true

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(glows ? 0.55 : 0), radius: 10)
                .animation(.linear(duration: 1), value: progress)
        }
        .accessibilityHidden(true)
    }
}

extension TimerState {
    /// Nombre de la acción "saltar" según la fase.
    var skipLabel: String {
        switch phase {
        case .focus: method.isOpenEnded ? "Descansar" : "Saltar al descanso"
        case .shortBreak, .longBreak: "Volver a concentrarse"
        }
    }

    var skipSymbol: String {
        switch phase {
        case .focus: method.isOpenEnded ? "cup.and.saucer.fill" : "forward.end.fill"
        case .shortBreak, .longBreak: "flame.fill"
        }
    }
}

/// Texto que acompaña la respiración durante los descansos.
struct BreathingHint: View {
    let tint: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            Text(Breath.isInhaling(at: context.date) ? "Inhala" : "Exhala")
                .font(.footnote.weight(.medium))
                .foregroundStyle(tint.opacity(0.85))
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.8), value: Breath.isInhaling(at: context.date))
        }
    }
}
