import CallKit
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
/// lo único que Planaby sí ve: que deja de estar delante. Solo con APIs públicas:
/// - Centro de Control, Centro de Notificaciones o el aviso de una llamada dejan Planaby
///   «inactiva», no en segundo plano: no cuentan.
/// - Bloquear el iPhone (con código, como en cualquier iPhone con Face ID) se nota porque iOS
///   protege los datos (`protectedDataWillBecomeUnavailable` / `isProtectedDataAvailable`).
/// - Una llamada en curso se ve con CallKit (`CXCallObserver`), sin permisos especiales.
/// - Lo que no se puede distinguir (bloquear un iPhone sin código) se trata como salida: es
///   lo que dice la documentación (docs/V1_1.md, «Límites de iOS»).
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
        /// La salida en curso se hizo con un pase de app permitida.
        fileprivate static let leftAllowed = "leaveGuardLeftAllowed"
        /// Cuándo acababa la concentración al salir: lo que pase de ahí ya es descanso y no cuenta.
        fileprivate static let focusEndsAt = "leaveGuardFocusEndsAt"
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

    /// Pase de app permitida, para enseñarlo en Enfoque. Si sigue valiendo lo dice `currentPass`.
    private(set) var pass: AllowedPass? = AllowedPass.load()

    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let calls = CallWatcher()
    private static let ids = (0..<5).map { "leave-\($0)" }

    private init() {
        // Al bloquear el iPhone con código, iOS avisa de que protege los datos.
        NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { LeaveGuard.shared.deviceLocked() }
        }
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
    /// nada al volver, durante `minutes` (0 = hasta terminar la sesión). Lo que pase de ahí sí
    /// cuenta. Sin sesión en marcha no hace nada.
    func allow(_ name: String, minutes: Int = AllowedApps.limit()) {
        guard let session = FocusTimer.shared.state?.sessionStart else { return }
        set(AllowedPass(app: name, grantedAt: .now, minutes: minutes, session: session))
    }

    /// Termina el pase antes de tiempo («Ya he vuelto»).
    func endPass() { set(nil) }

    /// El pase, solo si sigue valiendo para la sesión en marcha.
    func currentPass(at now: Date = .now) -> AllowedPass? {
        guard let pass, pass.isValid(at: now, session: FocusTimer.shared.state?.sessionStart) else { return nil }
        return pass
    }

    private func set(_ new: AllowedPass?) {
        pass = new
        AllowedPass.save(new)
    }

    private var isExcused: Bool { defaults.double(forKey: Keys.excusedUntil) > Date.now.timeIntervalSince1970 }

    // MARK: Salir y volver

    /// Planaby pasa a segundo plano.
    func didLeave() {
        guard Self.isEnabled, !isExcused, FrictionGuard.shared.isFocusing, let state = FocusTimer.shared.state else { return }
        let now = Date.now
        defaults.set(now.timeIntervalSince1970, forKey: Keys.leftAt)
        defaults.set(false, forKey: Keys.locked)
        if let end = state.phaseEnd, !state.isPaused {
            defaults.set(end.timeIntervalSince1970, forKey: Keys.focusEndsAt)
        } else {
            defaults.removeObject(forKey: Keys.focusEndsAt)
        }
        // Salir para contestar una llamada no es distraerse.
        if calls.hasActiveCall {
            deviceLocked()
            return
        }
        let pass = currentPass(at: now)
        defaults.set(pass != nil, forKey: Keys.leftAllowed)
        if let pass {
            // Salida autorizada: nada de avisos hasta que se acabe el pase (si tiene final).
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Self.ids)
            if let left = pass.remaining(at: now) {
                schedule(from: now, remaining: state.remaining(at: now), after: left, passMinutes: pass.minutes)
            }
        } else {
            schedule(from: now, remaining: state.remaining(at: now))
        }
        // Unos segundos despierta para notar si lo que ha pasado es que se ha bloqueado el iPhone.
        endBackground()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "leave-guard") {
            MainActor.assumeIsolated { LeaveGuard.shared.endBackground() }
        }
        Task {
            // Por si el aviso de datos protegidos no llega: se mira unas veces mientras dura el
            // rato despierto. Sin código de bloqueo esto no cambia nunca (límite de iOS).
            for delay in [1, 3, 8, 13] {
                try? await Task.sleep(for: .seconds(delay))
                guard backgroundTask != .invalid else { return }
                if !UIApplication.shared.isProtectedDataAvailable || calls.hasActiveCall {
                    deviceLocked()
                    return
                }
            }
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
        let focusEndsAt = defaults.object(forKey: Keys.focusEndsAt) as? Double
        defaults.removeObject(forKey: Keys.leftAt)
        defaults.removeObject(forKey: Keys.locked)
        defaults.removeObject(forKey: Keys.leftAllowed)
        defaults.removeObject(forKey: Keys.focusEndsAt)
        // El pase con el que se salió, aunque haya caducado estando fuera (hace falta para juzgar).
        let session = FocusTimer.shared.state?.sessionStart
        let used = allowed && pass?.session == session ? pass : nil
        // Un pase caducado o de otra sesión deja de enseñarse.
        if pass != nil, currentPass() == nil { set(nil) }
        guard left > 0, !locked else { return }
        let wentAt = Date(timeIntervalSince1970: left)
        // Una llamada mientras se estaba fuera tampoco cuenta.
        if calls.lastActivity.map({ $0 >= wentAt }) == true { return }
        guard Date.now.timeIntervalSince(wentAt) < 2 * 3600, session != nil else { return }
        // Solo cuenta el rato de concentración: si el bloque acabó estando fuera, lo de después
        // ya era descanso.
        let until = LeaveVerdict.countUntil(now: .now, focusEndsAt: focusEndsAt.map(Date.init(timeIntervalSince1970:)))
        // Con pase no pasa nada; solo cuenta lo que se pase de su final.
        let verdict = LeaveVerdict.judge(leftAt: wentAt, now: until, grace: TimeInterval(Self.grace), pass: used)
        guard case .distraction(let away, let leftAt) = verdict else { return }

        let strict = Self.isStrict
        // Modo estricto: el rato fuera no cuenta; el bloque sigue donde lo dejaste.
        if strict { FocusTimer.shared.discount(from: leftAt, to: .now) }
        FocusTimer.shared.noteLeave(seconds: away)
        let context = PlanabyStore.container.mainContext
        context.insert(DistractionRecord(
            date: leftAt, app: "",
            reason: "Fuera de Planaby \(Self.minutes(away))" + (used == nil ? "" : " tras acabar el tiempo permitido"),
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

    /// `after`: segundos de pase que quedan antes de empezar a avisar.
    private func schedule(from now: Date, remaining: TimeInterval?, after: TimeInterval = 0, passMinutes: Int? = nil) {
        let grace = TimeInterval(Self.grace) + after
        let left = remaining.map { " Te quedan \(Self.minutes(max(0, $0 - grace))) de concentración." } ?? ""
        let strict = Self.isStrict ? " Este rato no cuenta." : ""
        let steps: [(after: TimeInterval, title: String, body: String)] = [
            (grace, "Vuelve a Planaby", (passMinutes.map { "Se ha acabado el tiempo permitido (\($0) min). " } ?? "") + "Estás en un bloque de concentración." + left),
            (grace + 60, "Sigues fuera", "Llevas más de un minuto fuera de tu bloque." + strict),
            (grace + 180, "Sigues fuera", "Llevas \(Self.minutes(grace + 180)) fuera de tu bloque." + strict),
            (grace + 600, "¿Sigues ahí?", "Llevas \(Self.minutes(grace + 600)) fuera. Vuelve o pausa la sesión."),
            (grace + 1500, "Bloque abandonado", "Llevas casi media hora fuera de la concentración."),
        ]
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Self.ids)
        for (index, step) in steps.enumerated() {
            // Cuando acaba la concentración ya no hay de qué avisar.
            if let remaining, step.after >= remaining { break }
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

/// Llamadas de teléfono o VoIP, con CallKit (público y sin permisos): contestar una llamada en
/// mitad de un bloque no es una distracción.
private final class CallWatcher: NSObject, CXCallObserverDelegate {
    private let observer = CXCallObserver()
    /// La última vez que empezó, se contestó o terminó una llamada.
    private(set) var lastActivity: Date?

    override init() {
        super.init()
        observer.setDelegate(self, queue: .main)
    }

    var hasActiveCall: Bool { observer.calls.contains { !$0.hasEnded } }

    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        lastActivity = .now
    }
}

