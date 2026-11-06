import AVFoundation
import UIKit

/// Sonido y vibración del cambio de fase con Planaby delante (con la app cerrada avisa la
/// notificación). Usa la sesión de audio «ambient»: respeta el modo silencio, se mezcla con la
/// música sin pararla y no mantiene audio en segundo plano.
@MainActor
final class PhaseAlertPlayer {
    static let shared = PhaseAlertPlayer()

    private var player: AVAudioPlayer?

    private init() {}

    func play(intoBreak: Bool) {
        let style = AlertPreferences.style
        guard style != .visual else { return }
        haptic(intoBreak: intoBreak)
        guard style == .sound else { return }
        let session = AVAudioSession.sharedInstance()
        // Si ya suena música, basta con la vibración.
        if AlertPreferences.respectsMusic, session.isOtherAudioPlaying { return }
        let set = AlertPreferences.soundSet == .system ? AlertSoundSet.soft : AlertPreferences.soundSet
        guard let name = set.fileName(isBreak: intoBreak),
              let url = Bundle.main.url(forResource: (name as NSString).deletingPathExtension, withExtension: "wav") else { return }
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = 0.8
        player?.play()
    }

    /// Para escuchar un juego de sonidos en Ajustes.
    func preview(_ set: AlertSoundSet) {
        let chosen = set == .system ? AlertSoundSet.soft : set
        guard let name = chosen.fileName(isBreak: true),
              let url = Bundle.main.url(forResource: (name as NSString).deletingPathExtension, withExtension: "wav") else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }

    private func haptic(intoBreak: Bool) {
        if intoBreak {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
}
