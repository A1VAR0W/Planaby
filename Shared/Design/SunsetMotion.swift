import Foundation

/// La animación de carga de la IA: el atardecer del icono de Planaby (el sol sobre el horizonte
/// y su reflejo en cuatro barras). Aquí solo están las cuentas, para poder probarlas; se dibuja
/// en `SunsetLoader`.
enum SunsetMotion {
    enum Phase: Equatable, Sendable {
        /// El modelo se está cargando: el sol sube y baja despacio, como amaneciendo.
        case preparing
        /// Está pensando: el sol fuera, respirando, y el reflejo ondulando como el agua.
        case thinking
        /// Una descarga: el sol asoma según lo descargado (0…1).
        case progress(Double)
    }

    /// Las proporciones del icono (1024 × 1024), en fracciones de su ancho.
    enum Icon {
        static let horizon = 0.547
        static let sunRadius = 0.23
        /// Barras del reflejo, de arriba abajo: altura del centro, ancho, grueso y opacidad.
        static let bars: [(y: Double, width: Double, height: Double, opacity: Double)] = [
            (0.623, 0.422, 0.043, 0.85),
            (0.703, 0.305, 0.039, 0.55),
            (0.777, 0.180, 0.035, 0.32),
            (0.846, 0.070, 0.031, 0.18),
        ]
        /// Lo que se dibuja del icono, en vertical (lo de arriba y abajo es solo fondo).
        static let top = 0.24
        static let bottom = 0.90
        static var aspect: Double { bottom - top }
    }

    static let preparingPeriod = 2.6
    static let breathPeriod = 2.2
    static let ripplePeriod = 1.6
    static let glintPeriod = 2.4

    /// El instante que se enseña quieto con «Reducir movimiento»: el sol arriba y el destello en
    /// el centro, como en el icono.
    static let stillTime = glintPeriod / 2

    /// Cuánto asoma el sol: 0 escondido bajo el horizonte, 1 el medio sol entero.
    static func rise(_ phase: Phase, at time: Double) -> Double {
        min(1, max(0, unclampedRise(phase, at: time)))
    }

    private static func unclampedRise(_ phase: Phase, at time: Double) -> Double {
        switch phase {
        case .preparing:
            let wave = (1 - cos(2 * .pi * time / preparingPeriod)) / 2
            return 0.3 + 0.7 * smooth(wave)
        case .thinking:
            return 0.95 + 0.05 * sin(2 * .pi * time / breathPeriod)
        case .progress(let fraction):
            return 0.12 + 0.88 * min(1, max(0, fraction))
        }
    }

    /// La ondulación de la barra `index` del reflejo (−1…1): una ola que baja de barra en barra.
    static func ripple(_ index: Int, at time: Double) -> Double {
        sin(2 * .pi * time / ripplePeriod - Double(index) * 0.9)
    }

    /// Cuánto cambia el ancho de las barras con la ola.
    static func rippleAmplitude(_ phase: Phase) -> Double {
        switch phase {
        case .preparing: 0.08
        case .thinking: 0.14
        case .progress: 0.05
        }
    }

    /// Dónde está el destello que recorre el horizonte (0 izquierda, 1 derecha; fuera, no se ve).
    static func glint(at time: Double) -> Double {
        let lap = (time / glintPeriod).truncatingRemainder(dividingBy: 1)
        return -0.25 + 1.5 * (lap < 0 ? lap + 1 : lap)
    }

    private static func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }
}
