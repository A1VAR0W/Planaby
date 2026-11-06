import CoreMotion
import Foundation
import Observation
import UIKit

/// Comprueba cargador y orientación para «Abrir escritorio si toca» y pide a la interfaz que
/// enseñe el modo escritorio. Solo usa APIs públicas: el estado de la batería de UIDevice y la
/// gravedad de Core Motion. No detecta StandBy ni si el iPhone está bloqueado (iOS no lo dice).
@Observable
@MainActor
final class DeskLauncher {
    static let shared = DeskLauncher()

    /// La interfaz pasa a Enfoque (en horizontal es el modo escritorio).
    var deskRequested = 0

    struct Check: Equatable {
        var date: Date
        var trigger: DeskTrigger
        var charging: Bool?
        var landscape: Bool?
        var focusActive: Bool
        var decision: DeskLaunchDecision
    }

    private(set) var lastCheck: Check?

    @ObservationIgnored private let motion = CMMotionManager()

    private init() {}

    func requestDesk() { deskRequested += 1 }

    /// nil si iOS no lo sabe.
    func isCharging() -> Bool? {
        let device = UIDevice.current
        let wasMonitoring = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true
        defer { if !wasMonitoring { device.isBatteryMonitoringEnabled = false } }
        switch device.batteryState {
        case .charging, .full: return true
        case .unplugged: return false
        case .unknown: return nil
        @unknown default: return nil
        }
    }

    /// Orientación física por la gravedad (funciona aunque la interfaz no haya rotado).
    /// nil si está plano o no se puede medir.
    func isLandscape() async -> Bool? {
        if let gravity = await sampleGravity() {
            return DeskLaunchPolicy.landscape(fromGravityX: gravity.x, y: gravity.y, z: gravity.z)
        }
        // Sin Core Motion, lo que diga la interfaz si la app está delante.
        switch UIDevice.current.orientation {
        case .landscapeLeft, .landscapeRight: return true
        case .portrait, .portraitUpsideDown: return false
        default: return nil
        }
    }

    private func sampleGravity() async -> CMAcceleration? {
        guard motion.isDeviceMotionAvailable else { return nil }
        if let current = motion.deviceMotion?.gravity, motion.isDeviceMotionActive { return current }
        motion.deviceMotionUpdateInterval = 0.05
        motion.startDeviceMotionUpdates()
        defer { motion.stopDeviceMotionUpdates() }
        // Como mucho un segundo esperando la primera lectura.
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(50))
            if let gravity = motion.deviceMotion?.gravity { return gravity }
        }
        return nil
    }

    /// Junta todo y decide. No abre nada: eso lo hace el intent si la decisión es `.open`.
    func evaluate(trigger: DeskTrigger, focusName: String?) async -> Check {
        // Con la automatización B (trigger .focusOn) la Concentración se da por activa: así no
        // importa si el filtro de Planaby llega un instante después.
        let filterActive = SystemFocusState.isActive()
        let input = DeskLaunchInput(
            enabled: SystemFocusState.autoOpenEnabled(), trigger: trigger, currentFocusName: focusName,
            configuredFocus: SystemFocusState.focusName(), filterSaysActive: filterActive,
            charging: isCharging(), landscape: await isLandscape()
        )
        let check = Check(
            date: .now, trigger: trigger, charging: input.charging, landscape: input.landscape,
            focusActive: DeskLaunchPolicy.focusIsActive(input), decision: DeskLaunchPolicy.decide(input)
        )
        lastCheck = check
        let result = switch check.decision {
        case .open: "Abierto"
        case .skip(let reason): "No abierto: \(reason.text)"
        }
        IntentLog.record(.deskKind(for: trigger), result: result)
        return check
    }
}
