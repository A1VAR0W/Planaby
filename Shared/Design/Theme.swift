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

/// Aura que respira despacio detrás del contenido: un núcleo de luz y dos velos que derivan
/// muy lentamente, como brasas tras un cristal.
///
/// - Cada capa es un círculo con su propio tamaño, que se desvanece del todo antes de llegar a
///   su borde. Así nunca se ve un corte al encoger (antes el degradado se pintaba en el
///   rectángulo de la pantalla y al exhalar aparecía un cuadrado).
/// - Se dibuja una sola vez. Solo se animan tamaño, posición y opacidad, que el sistema
///   interpola sin volver a pintar: la vista despierta dos veces por respiración, no 30 veces
///   por segundo. Puede respirar siempre sin gastar batería.
struct BreathingGlow: View {
    let tint: Color
    var strength: Double = 0.22
    /// false: aura quieta (el modo escritorio de noche o atenuado).
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var level = 0.5
    /// Los dos velos van y vuelven con periodos distintos, así el dibujo no se repite a la vista.
    @State private var driftA = false
    @State private var driftB = false

    var body: some View {
        // `Color.clear` ocupa lo que le den; las capas van encima sin recortarse ni empujar.
        Color.clear
            .overlay {
                ZStack {
                    // Velo ancho y tenue: da profundidad al negro.
                    AuraLayer(tint: tint, opacity: strength * 0.55, diameter: 1100)
                        .scaleEffect(0.92 + 0.08 * level)
                        .offset(x: driftA ? 46 : -38, y: driftA ? 90 : 150)
                    // Velo lateral: se cruza con el otro muy despacio.
                    AuraLayer(tint: tint, opacity: strength * 0.5, diameter: 720)
                        .scaleEffect(0.9 + 0.1 * level)
                        .offset(x: driftB ? -84 : 70, y: driftB ? -70 : -20)
                    // Núcleo: el que respira de verdad.
                    AuraLayer(tint: tint, opacity: strength, diameter: 860)
                        .scaleEffect(0.74 + 0.26 * level)
                        .opacity(0.6 + 0.4 * level)
                }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
            .accessibilityHidden(true)
            .task(id: animated && !reduceMotion) { await breathe(animated && !reduceMotion) }
    }

    private func breathe(_ on: Bool) async {
        guard on else {
            withAnimation(.easeInOut(duration: 1.5)) {
                level = 0.5
                driftA = false
                driftB = false
            }
            return
        }
        withAnimation(.easeInOut(duration: 37).repeatForever(autoreverses: true)) { driftA = true }
        withAnimation(.easeInOut(duration: 53).repeatForever(autoreverses: true)) { driftB = true }
        // Empieza donde va la respiración y sigue con ella.
        level = Breath.level(at: .now)
        while !Task.isCancelled {
            let turn = Breath.nextTurn(after: .now)
            withAnimation(.easeInOut(duration: turn.duration)) { level = turn.level }
            try? await Task.sleep(for: .seconds(turn.duration))
        }
    }
}

/// Una capa del aura: luz que cae como una campana (sin anillo ni borde visibles) y llega a
/// cero antes del límite de su propio círculo.
private struct AuraLayer: View {
    let tint: Color
    let opacity: Double
    let diameter: CGFloat

    /// Caída suave: mucha luz en el centro y una cola larga y casi invisible.
    private static let falloff: [(location: Double, weight: Double)] = [
        (0, 1), (0.12, 0.86), (0.26, 0.6), (0.42, 0.36), (0.58, 0.18), (0.74, 0.07), (0.88, 0.02), (1, 0),
    ]

    var body: some View {
        RadialGradient(
            stops: Self.falloff.map { Gradient.Stop(color: tint.opacity(opacity * $0.weight), location: $0.location) },
            center: .center, startRadius: 0, endRadius: diameter / 2
        )
        .frame(width: diameter, height: diameter)
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
            BreathingGlow(tint: tint, strength: isBreak ? 0.34 : 0.2, animated: animated)
                .offset(y: -120)
            // El borde inferior se apaga: los botones quedan sobre negro limpio.
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)
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
