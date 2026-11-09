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
}

/// Halo naranja que respira despacio detrás del contenido.
struct BreathingGlow: View {
    let tint: Color
    var strength: Double = 0.22
    /// false: halo quieto (pantallas que pasan mucho rato encendidas).
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion || !animated {
                gradient(level: 0.5)
            } else {
                // La respiración dura varios segundos: 20 fotogramas por segundo se ven igual de
                // suaves y gastan un tercio menos.
                TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
                    gradient(level: Breath.level(at: context.date))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func gradient(level: Double) -> some View {
        RadialGradient(
            colors: [tint.opacity(strength * (0.55 + 0.45 * level)), .clear],
            center: .center,
            startRadius: 0,
            endRadius: 260 + 140 * level
        )
    }
}

/// Fondo negro con el halo de la fase; en los descansos respira con más presencia.
struct PhaseBackground: View {
    let tint: Color
    var isBreak = false
    /// Solo respira cuando sirve (un descanso en marcha); el resto del tiempo, quieto: un halo
    /// a pantalla completa repintándose sin parar gasta batería aunque no se mire.
    var animated = false

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
