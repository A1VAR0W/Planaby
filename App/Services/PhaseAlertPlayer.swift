import AVFoundation
import UIKit
import UserNotifications

/// Sonido y vibración del cambio de fase con Planaby delante (con la app cerrada o en segundo
/// plano avisa la notificación programada, y la app no suena: nunca hay dos sonidos).
///
/// Usa la sesión de audio «ambient», que respeta el modo silencio (es una regla de iOS). Si suena
/// música de otra app, la baja un momento (`duckOthers`), suena el aviso y, al terminar, desactiva
/// la sesión avisando a las demás (`notifyOthersOnDeactivation`): iOS devuelve la música a su
/// volumen. Nunca la para ni toca el volumen del iPhone.
@MainActor
final class PhaseAlertPlayer {
    static let shared = PhaseAlertPlayer()

    /// Qué pasó con el último aviso, para explicarlo en Ajustes.
    enum Outcome: Equatable {
        case played
        /// Sonó bajando un momento la música de otra app.
        case playedOverMusic
        /// Opción de Planaby: «Solo vibración» o «Solo visual».
        case styleWithoutSound
        /// Opción de Planaby: no sonar mientras suena música.
        case skippedForMusic
        /// Error de Planaby: falta el sonido o no se pudo reproducir.
        case failed(String)

        var text: String {
            switch self {
            case .played: "Sonó con Planaby abierta. Si no lo oíste, el iPhone está en silencio o con el volumen bajo."
            case .playedOverMusic: "Sonó con Planaby abierta y bajó la música un momento. Si no lo oíste, el iPhone está en silencio."
            case .styleWithoutSound: "No sonó porque el aviso es «Solo vibración» o «Solo visual»."
            case .skippedForMusic: "No sonó porque sonaba música y está desactivado «Sonar aunque haya música»."
            case .failed(let reason): "Error de Planaby: \(reason)"
            }
        }
    }

    private(set) var lastOutcome: Outcome?
    private var player: AVAudioPlayer?
    /// Devuelve la música a su volumen al acabar el aviso (uno solo: el último aviso manda).
    private var restoreTask: Task<Void, Never>?

    private init() {}

    /// Aviso de cambio de fase con la app en primer plano.
    func play(intoBreak: Bool) {
        let style = AlertPreferences.style
        guard style != .visual else {
            lastOutcome = .styleWithoutSound
            return
        }
        haptic(intoBreak: intoBreak)
        guard style == .sound else {
            lastOutcome = .styleWithoutSound
            return
        }
        let handling = currentMusicHandling()
        if handling == .skip {
            lastOutcome = .skippedForMusic
            return
        }
        lastOutcome = playSound(AlertPreferences.soundSet, isBreak: intoBreak, duck: handling == .duck)
    }

    /// Para escuchar un juego de sonidos en Ajustes (también cómo baja la música, si suena).
    func preview(_ set: AlertSoundSet) {
        _ = playSound(set, isBreak: true, duck: currentMusicHandling() == .duck)
    }

    private func currentMusicHandling() -> AlertPreferences.MusicHandling {
        AlertPreferences.musicHandling(
            otherAudioPlaying: AVAudioSession.sharedInstance().isOtherAudioPlaying,
            respectsMusic: AlertPreferences.respectsMusic,
            ducksMusic: AlertPreferences.ducksMusic
        )
    }

    private func playSound(_ set: AlertSoundSet, isBreak: Bool, duck: Bool) -> Outcome {
        // «Sonido del sistema» solo existe para las notificaciones; dentro de la app, la campana.
        let chosen = set == .system ? AlertSoundSet.soft : set
        guard let name = chosen.fileName(isBreak: isBreak),
              let url = Bundle.main.url(forResource: (name as NSString).deletingPathExtension, withExtension: "wav") else {
            return .failed("no encuentro el sonido «\(set.title)» en la app.")
        }
        let session = AVAudioSession.sharedInstance()
        var ducking = false
        // Mientras se dicta (captura rápida o voz) la sesión es de grabación: no se toca.
        if session.category != .playAndRecord, session.category != .record {
            do {
                if duck {
                    do {
                        try session.setCategory(.ambient, options: [.duckOthers])
                        ducking = true
                    } catch {
                        // Si iOS no deja bajar la música, suena mezclado por encima.
                        try session.setCategory(.ambient, options: [.mixWithOthers])
                    }
                } else {
                    try session.setCategory(.ambient, options: [.mixWithOthers])
                }
                try session.setActive(true)
            } catch {
                if ducking { restoreMusic() }
                return .failed("no se pudo preparar el audio (\(error.localizedDescription)).")
            }
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 1
            player.prepareToPlay()
            self.player = player
            guard player.play() else {
                if ducking { restoreMusic() }
                return .failed("iOS no dejó reproducir el sonido.")
            }
            // Si un aviso anterior dejó la música baja, este también la devuelve al acabar.
            let pendingRestore = restoreTask != nil
            restoreTask?.cancel()
            restoreTask = nil
            guard ducking || pendingRestore else { return .played }
            // Al acabar (y un respiro), la música vuelve sola a su volumen.
            let wait = player.duration + 0.3
            restoreTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled else { return }
                self?.restoreMusic()
            }
            return ducking ? .playedOverMusic : .played
        } catch {
            if ducking { restoreMusic() }
            return .failed("el sonido no se pudo abrir (\(error.localizedDescription)).")
        }
    }

    /// Quita la atenuación: desactivar la sesión avisando a las demás es lo que hace que iOS
    /// devuelva la música a su volumen. Si en medio empezó un dictado, la sesión ya no es nuestra.
    private func restoreMusic() {
        restoreTask = nil
        let session = AVAudioSession.sharedInstance()
        guard session.category == .ambient else { return }
        player?.stop()
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Plan B: quitar la opción de atenuar y volver a intentarlo.
            try? session.setCategory(.ambient, options: [.mixWithOthers])
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
        try? session.setCategory(.ambient, options: [.mixWithOthers])
    }

    private func haptic(intoBreak: Bool) {
        if intoBreak {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    // MARK: - Diagnóstico

    /// Por qué una notificación de fase podría no sonar, separando permisos de iOS y opciones.
    struct NotificationStatus: Equatable {
        var authorized: Bool
        var soundsAllowed: Bool
        var lockScreen: Bool
    }

    static func notificationStatus() async -> NotificationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let authorized = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        return NotificationStatus(
            authorized: authorized,
            soundsAllowed: settings.soundSetting == .enabled,
            lockScreen: settings.lockScreenSetting == .enabled
        )
    }

    /// Notificación de prueba en 5 s con el sonido elegido, para probarla con el iPhone bloqueado.
    static func scheduleTest(intoBreak: Bool = true) {
        let content = UNMutableNotificationContent()
        content.title = "Prueba de aviso"
        content.body = "Así suena el cambio de fase con Planaby cerrada o el iPhone bloqueado."
        content.interruptionLevel = .active
        content.sound = AlertPreferences.style == .sound
            ? AlertPreferences.soundSet.fileName(isBreak: intoBreak).map { UNNotificationSound(named: UNNotificationSoundName($0)) } ?? .default
            : nil
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: testID, content: content, trigger: trigger))
    }

    nonisolated static let testID = "planaby-alert-test"
}
