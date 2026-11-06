import SwiftUI

/// Animaciones compartidas de Planaby. Los tiempos están en `MotionTiming`; aquí se convierten
/// en curvas, muelles y transiciones de SwiftUI, siempre con su versión para «Reducir movimiento».
enum Motion {
    static let press = Animation.snappy(duration: MotionTiming.press)
    static let quick = Animation.smooth(duration: MotionTiming.quick)
    static let standard = Animation.smooth(duration: MotionTiming.standard)
    static let emphasized = Animation.spring(duration: MotionTiming.emphasized, bounce: MotionTiming.bounce)
    static let panel = Animation.spring(duration: MotionTiming.panel, bounce: MotionTiming.panelBounce)
    static let exit = Animation.smooth(duration: MotionTiming.exit(for: MotionTiming.emphasized))
    static let reduced = Animation.easeInOut(duration: MotionTiming.reduced)

    /// La animación pedida o, con «Reducir movimiento», un fundido corto.
    static func adaptive(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : animation
    }

    /// El elemento `index` de una entrada escalonada.
    static func stagger(_ index: Int, base: Animation = emphasized, reduceMotion: Bool = false) -> Animation {
        reduceMotion ? reduced : base.delay(MotionTiming.staggerDelay(index))
    }
}

extension AnyTransition {
    /// Sube un poco y aparece; al irse, solo se desvanece (más rápido).
    static func rise(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .offset(y: 10).combined(with: .opacity).combined(with: .scale(scale: 0.98, anchor: .bottom)),
            removal: .opacity.animation(Motion.exit)
        )
    }

    /// Crece desde su sitio (botones, avisos pequeños).
    static func pop(reduceMotion: Bool, anchor: UnitPoint = .center) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .scale(scale: 0.9, anchor: anchor).combined(with: .opacity),
            removal: .scale(scale: 0.96, anchor: anchor).combined(with: .opacity).animation(Motion.exit)
        )
    }

    /// Un panel que entra desde un borde y empuja a los demás.
    static func panel(from edge: Edge, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: edge).combined(with: .opacity),
            removal: .move(edge: edge).combined(with: .opacity).animation(Motion.exit)
        )
    }
}

/// Respuesta al tocar: el botón se hunde un poco y se aclara. Sin «Reducir movimiento» escala;
/// con él, solo cambia la opacidad.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.95
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(Motion.adaptive(Motion.press, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

/// Entrada escalonada: aparece la primera vez con un pequeño retardo según su posición. Para
/// listas cortas que no se reciclan (paneles, tarjetas); no para listas perezosas largas.
private struct StaggeredAppear: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .onAppear {
                guard !shown else { return }
                withAnimation(Motion.stagger(index, reduceMotion: reduceMotion)) { shown = true }
            }
    }
}

/// Un cambio recién hecho se marca con un borde naranja que se apaga solo (una vez).
private struct ChangeHighlight<Value: Equatable>: ViewModifier {
    let value: Value
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Theme.orange.opacity(lit ? 0.85 : 0), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
            .onChange(of: value) {
                withAnimation(.easeOut(duration: MotionTiming.quick)) { lit = true } completion: {
                    withAnimation(.easeOut(duration: reduceMotion ? MotionTiming.reduced : 0.9)) { lit = false }
                }
            }
    }
}

extension View {
    func staggeredAppear(_ index: Int) -> some View {
        modifier(StaggeredAppear(index: index))
    }

    /// Marca brevemente la vista cuando cambia `value`.
    func highlightOnChange<Value: Equatable>(of value: Value, cornerRadius: CGFloat = 20) -> some View {
        modifier(ChangeHighlight(value: value, cornerRadius: cornerRadius))
    }
}
