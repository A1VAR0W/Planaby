import Foundation
import Observation
import SwiftData
import UIKit
import UserNotifications

/// Bloqueo sin configurar nada: mientras te concentras, si sales de Planaby a otra app te
/// llegan avisos para volver y, al volver, ves cuánto rato estuviste fuera. Bloquear el
/// iPhone no cuenta (dejarlo apagado es justo lo que se busca).
///
/// iOS no deja saber qué app se abre sin Tiempo de uso (cuenta de pago), así que se vigila
/// lo único que Planaby sí ve: que deja de estar delante.
@Observable
@MainActor
final class LeaveGuard {
    static let shared = LeaveGuard()

    enum Keys {
        static let enabled = "leaveGuardEnabled"
        static let grace = "leaveGuardGrace"
        static let strict = "leaveGuardStrict"
        fileprivate static let leftAt = "leaveGuardLeftAt"
        fileprivate static let locked = "leaveGuardLocked"
        fileprivate static let excusedUntil = "leaveGuardExcusedUntil"
        /// Se ha tocado una app permitida: la próxima salida (en unos segundos) está autorizada.
        fileprivate static let allowedUntil = "leaveGuardAllowedUntil"
        fileprivate static let allowedName = "leaveGuardAllowedName"
        /// La salida en curso es a una app permitida.
        fileprivate static let leftAllowed = "leaveGuardLeftAllowed"
    }

    static let defaultGrace = 15
    static let graceOptions = [15, 30, 60, 120]

    /// Lo que se enseña al volver.
    struct Return: Identifiable {
        let id = UUID()
        let seconds: TimeInterval
        let strict: Bool
        let remaining: TimeInterval?
    }

    var returned: Return?

    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let ids = (0..<5).map { "leave-\($0)" }

    private init() {
        // Al bloquear el iPhone con código, iOS avisa de que protege los datos.
        NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { LeaveGuard.shared.deviceLocked() }
        }
        // Aviso del sistema al terminar de bloquear (llega antes; no todas las versiones lo mandan).
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), nil,
            { _, _, _, _, _ in Task { @MainActor in LeaveGuard.shared.deviceLocked() } },
            "com.apple.springboard.lockcomplete" as CFString, nil, .deliverImmediately
        )
    }

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? true }
    static var grace: Int { UserDefaults.standard.object(forKey: Keys.grace) as? Int ?? defaultGrace }
    static var isStrict: Bool { UserDefaults.standard.bool(forKey: Keys.strict) }

    /// Planaby abre otra app a propósito (Spotify, «Abrir igualmente»…): durante ese rato no avisa.
    func excuse(for seconds: TimeInterval) {
        let until = max(defaults.double(forKey: Keys.excusedUntil), Date.now.addingTimeInterval(seconds).timeIntervalSince1970)
        defaults.set(until, forKey: Keys.excusedUntil)
    }

    /// Se va a una app permitida: el tiempo sigue corriendo, sin avisos de «vuelve» y sin apuntar
    /// nada al volver. Si se pasa del límite elegido, lo que sobre sí cuenta.
    func allow(_ name: String) {
        defaults.set(Date.now.addingTimeInterval(20).timeIntervalSince1970, forKey: Keys.allowedUntil)
        defaults.set(name, forKey: Keys.allowedName)
    }

    private var isExcused: Bool { defaults.double(forKey: Keys.excusedUntil) > Date.now.timeIntervalSince1970 }

    // MARK: Salir y volver

    /// Planaby pasa a segundo plano.
    func didLeave() {
        guard Self.isEnabled, !isExcused, FrictionGuard.shared.isFocusing, let state = FocusTimer.shared.state else { return }
        let now = Date.now
        defaults.set(now.timeIntervalSince1970, forKey: Keys.leftAt)
        defaults.set(false, forKey: Keys.locked)
        let allowed = defaults.double(forKey: Keys.allowedUntil) > now.timeIntervalSince1970
        defaults.removeObject(forKey: Keys.allowedUntil)
        defaults.set(allowed, forKey: Keys.leftAllowed)
        if allowed {
            // App permitida: nada de avisos hasta que se pase del límite (si lo hay).
            let limit = TimeInterval(AllowedApps.limit() * 60)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Self.ids)
            if limit > 0 {
                schedule(from: now, remaining: state.remaining(at: now), after: limit, app: defaults.string(forKey: Keys.allowedName))
            }
            return
        }
        schedule(from: now, remaining: state.remaining(at: now))
        // Unos segundos despierta para notar si lo que ha pasado es que se ha bloqueado el iPhone.
        endBackground()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "leave-guard") {
            MainActor.assumeIsolated { LeaveGuard.shared.endBackground() }
        }
        Task {
            try? await Task.sleep(for: .seconds(25))
            endBackground()
        }
    }

    /// Planaby vuelve a estar delante. Va antes de poner al día el temporizador.
    func didReturn() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Self.ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: Self.ids)
        endBackground()
        let left = defaults.double(forKey: Keys.leftAt)
        let locked = defaults.bool(forKey: Keys.locked)
        let allowed = defaults.bool(forKey: Keys.leftAllowed)
        defaults.removeObject(forKey: Keys.leftAt)
        defaults.removeObject(forKey: Keys.locked)
        defaults.removeObject(forKey: Keys.leftAllowed)
        guard left > 0, !locked else { return }
        let wentAt = Date(timeIntervalSince1970: left)
        guard Date.now.timeIntervalSince(wentAt) < 2 * 3600, FocusTimer.shared.state != nil else { return }
        // En una app permitida no pasa nada; solo cuenta lo que se pase del límite.
        let verdict = LeaveVerdict.judge(
            leftAt: wentAt, now: .now, grace: TimeInterval(Self.grace), authorized: allowed,
            limit: TimeInterval(AllowedApps.limit() * 60)
        )
        guard case .distraction(let away, let leftAt) = verdict else { return }

        let strict = Self.isStrict
        // Modo estricto: el rato fuera no cuenta; el bloque sigue donde lo dejaste.
        if strict { FocusTimer.shared.discount(from: leftAt, to: .now) }
        FocusTimer.shared.noteLeave(seconds: away)
        let context = PlanabyStore.container.mainContext
        context.insert(DistractionRecord(
            date: leftAt, app: "", reason: "Fuera de Planaby \(Self.minutes(away))",
            resisted: false, duringFocus: true, kind: .leave, awaySeconds: away
        ))
        try? context.save()
        let state = TimerState.loadShared()
        returned = Return(
            seconds: away, strict: strict,
            remaining: state?.phase == .focus ? state?.remaining(at: .now) : nil
        )
    }

    /// Se ha bloqueado el iPhone: no es una distracción.
    func deviceLocked() {
        guard defaults.double(forKey: Keys.leftAt) > 0 else { return }
        defaults.set(true, forKey: Keys.locked)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Self.ids)
        endBackground()
    }

    private func endBackground() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: Avisos

    /// `after`: segundos de app permitida antes de empezar a avisar.
    private func schedule(from now: Date, remaining: TimeInterval?, after: TimeInterval = 0, app: String? = nil) {
        let grace = TimeInterval(Self.grace) + after
        let left = remaining.map { " Te quedan \(Self.minutes(max(0, $0 - grace))) de concentración." } ?? ""
        let strict = Self.isStrict ? " Este rato no cuenta." : ""
        let steps: [(after: TimeInterval, title: String, body: String)] = [
            (grace, "Vuelve a Planaby", (app.map { "Llevas \(Self.minutes(after)) en \($0). " } ?? "") + "Estás en un bloque de concentración." + left),
            (grace + 60, "Sigues fuera", "Llevas más de un minuto fuera de tu bloque." + strict),
            (grace + 180, "Sigues fuera", "Llevas \(Self.minutes(grace + 180)) fuera de tu bloque." + strict),
            (grace + 600, "¿Sigues ahí?", "Llevas \(Self.minutes(grace + 600)) fuera. Vuelve o pausa la sesión."),
            (grace + 1500, "Bloque abandonado", "Llevas casi media hora fuera de la concentración."),
        ]
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Self.ids)
        for (index, step) in steps.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = step.title
            content.body = step.body
            content.sound = .default
            content.interruptionLevel = .active
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: step.after, repeats: false)
            center.add(UNNotificationRequest(identifier: Self.ids[index], content: content, trigger: trigger))
        }
    }

    static func minutes(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) s" }
        return "\(Int((Double(total) / 60).rounded())) min"
    }
}
