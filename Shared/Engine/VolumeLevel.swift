import Foundation

/// Cómo se enseña un nivel de volumen (0…1): icono, texto y si cuenta como silenciado. Solo
/// presentación: el volumen lo cambia siempre el control del sistema.
enum VolumeLevel {
    /// Por debajo de esto se considera sin sonido (iOS no ofrece un «silenciar» público).
    static let mutedThreshold: Float = 0.01

    static func clamped(_ level: Float) -> Float {
        guard level.isFinite else { return 0 }
        return min(1, max(0, level))
    }

    static func isMuted(_ level: Float) -> Bool { clamped(level) < mutedThreshold }

    /// Silenciado, bajo, medio o alto.
    static func symbol(for level: Float) -> String {
        switch clamped(level) {
        case ..<mutedThreshold: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }

    /// «45 %», o «Sin sonido».
    static func text(for level: Float) -> String {
        isMuted(level) ? "Sin sonido" : "\(Int((clamped(level) * 100).rounded())) %"
    }

    /// Para VoiceOver: «45 por ciento» o «sin sonido».
    static func spokenText(for level: Float) -> String {
        isMuted(level) ? "sin sonido" : "\(Int((clamped(level) * 100).rounded())) por ciento"
    }
}
