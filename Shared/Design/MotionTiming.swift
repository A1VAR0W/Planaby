import Foundation

/// Los tiempos del sistema de movimiento de Planaby, sin SwiftUI para poder probarlos.
///
/// Reglas:
/// - Lo pequeño (pulsar, marcar) es rápido; lo que cambia la composición (paneles) tarda más.
/// - Salir es más rápido que entrar.
/// - Nada se anima en bucle para decorar. Los widgets y la Live Activity no animan nada continuo.
/// - Con «Reducir movimiento» no hay desplazamientos, escalas ni rebotes: solo fundidos cortos.
enum MotionTiming {
    /// Respuesta al tocar.
    static let press: TimeInterval = 0.16
    /// Cambios pequeños: un icono, un color, un número.
    static let quick: TimeInterval = 0.22
    /// Contenido que cambia dentro de una tarjeta.
    static let standard: TimeInterval = 0.32
    /// Tarjetas que aparecen, menús, avisos.
    static let emphasized: TimeInterval = 0.42
    /// Paneles que reparten la pantalla.
    static let panel: TimeInterval = 0.5
    /// Salidas: un 40 % más rápidas que la entrada equivalente.
    static func exit(for enter: TimeInterval) -> TimeInterval { (enter * 0.6 * 100).rounded() / 100 }
    /// Fundido de «Reducir movimiento».
    static let reduced: TimeInterval = 0.18

    /// Rebote de los muelles (0 = sin rebote). Discreto: Planaby es tranquila.
    static let bounce = 0.14
    static let panelBounce = 0.1

    /// Paso entre elementos de una entrada escalonada, y cuántos como mucho se escalonan (el
    /// resto entra con el último, para que una lista larga no tarde).
    static let staggerStep: TimeInterval = 0.04
    static let staggerLimit = 8

    static func staggerDelay(_ index: Int) -> TimeInterval {
        guard index > 0 else { return 0 }
        return Double(min(index, staggerLimit)) * staggerStep
    }

    /// Cuánto dura una animación según «Reducir movimiento».
    static func duration(_ value: TimeInterval, reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? min(value, reduced) : value
    }
}
