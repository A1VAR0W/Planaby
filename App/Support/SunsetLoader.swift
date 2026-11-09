import SwiftUI

/// Animación de carga de la IA con el atardecer del icono: el medio sol sobre un horizonte que
/// brilla, un destello que lo recorre y el reflejo en cuatro barras que ondulan. Cargando, el
/// sol amanece y se pone; pensando, respira; descargando, sube con el progreso. Con «Reducir
/// movimiento» se queda quieto, como el icono. Es decorativa: va siempre con un texto.
struct SunsetLoader: View {
    var phase: SunsetMotion.Phase = .thinking
    /// Ancho; el alto sale de las proporciones del icono.
    var size: CGFloat = 44
    var tint: Color = Theme.orange
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // 30 fotogramas por segundo bastan para algo tan suave y gastan la mitad.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? SunsetMotion.stillTime : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, canvas in
                draw(in: &context, width: canvas.width, time: time)
            }
        }
        .frame(width: size, height: size * SunsetMotion.Icon.aspect)
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, width w: CGFloat, time: Double) {
        typealias Icon = SunsetMotion.Icon
        func y(_ value: Double) -> CGFloat { CGFloat(value - Icon.top) * w }
        let light = tint.mix(with: .white, by: 0.45)
        let center = w / 2
        let horizon = y(Icon.horizon)
        let radius = CGFloat(Icon.sunRadius) * w
        let rise = SunsetMotion.rise(phase, at: time)

        // Cielo: el resplandor y el sol, que se esconde bajo el horizonte.
        var sky = context
        sky.clip(to: Path(CGRect(x: 0, y: 0, width: w, height: horizon)))
        sky.fill(
            Path(ellipseIn: CGRect(x: center - radius * 2, y: horizon - radius * 2, width: radius * 4, height: radius * 4)),
            with: .radialGradient(
                Gradient(colors: [tint.opacity(0.38 * rise), tint.opacity(0)]),
                center: CGPoint(x: center, y: horizon), startRadius: radius * 0.5, endRadius: radius * 2
            )
        )
        let sunY = horizon + radius * CGFloat(1 - rise)
        sky.fill(
            Path(ellipseIn: CGRect(x: center - radius, y: sunY - radius, width: radius * 2, height: radius * 2)),
            with: .linearGradient(
                Gradient(colors: [light, tint]),
                startPoint: CGPoint(x: center, y: sunY - radius), endPoint: CGPoint(x: center, y: horizon)
            )
        )

        // Horizonte, más brillante en el centro, y el destello que lo recorre.
        let thickness = max(1, w * 0.014)
        context.fill(
            Path(roundedRect: CGRect(x: 0, y: horizon - thickness / 2, width: w, height: thickness), cornerRadius: thickness / 2),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: tint.opacity(0), location: 0),
                    .init(color: light.opacity(0.85), location: 0.5),
                    .init(color: tint.opacity(0), location: 1),
                ]),
                startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: w, y: horizon)
            )
        )
        let glint = CGFloat(SunsetMotion.glint(at: time)) * w
        let glintWidth = w * 0.3
        context.fill(
            Path(roundedRect: CGRect(x: glint - glintWidth / 2, y: horizon - thickness, width: glintWidth, height: thickness * 2), cornerRadius: thickness),
            with: .linearGradient(
                Gradient(colors: [Color.white.opacity(0), Color.white.opacity(0.9), Color.white.opacity(0)]),
                startPoint: CGPoint(x: glint - glintWidth / 2, y: horizon), endPoint: CGPoint(x: glint + glintWidth / 2, y: horizon)
            )
        )

        // Reflejo: cuatro barras que ondulan, más tenues cuanto menos asoma el sol.
        let amplitude = SunsetMotion.rippleAmplitude(phase)
        for (index, bar) in Icon.bars.enumerated() {
            let ripple = SunsetMotion.ripple(index, at: time)
            let barWidth = CGFloat(bar.width * (1 + amplitude * ripple)) * w
            let barHeight = max(1.5, CGFloat(bar.height) * w)
            let rect = CGRect(x: center - barWidth / 2, y: y(bar.y) - barHeight / 2, width: barWidth, height: barHeight)
            let opacity = bar.opacity * (0.8 + 0.2 * ripple) * (0.35 + 0.65 * rise)
            context.fill(Path(roundedRect: rect, cornerRadius: barHeight / 2), with: .color(tint.opacity(opacity)))
        }
    }
}

extension SunsetMotion.Phase {
    /// Lo que está haciendo la IA local ahora (si no carga, piensa).
    @MainActor
    static var current: SunsetMotion.Phase {
        LocalModel.shared.phase == .loading ? .preparing : .thinking
    }
}
