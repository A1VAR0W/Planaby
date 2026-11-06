import Foundation
import Observation
import SwiftData

/// Une el motor de atención (reglas puras) con la app: arma las muestras desde el historial,
/// filtra lo descartado y aplica lo aceptado. Nunca cambia nada sin que la persona lo acepte.
@Observable
@MainActor
final class AdaptiveFocusCoordinator {
    static let shared = AdaptiveFocusCoordinator()

    enum Keys {
        static let enabled = "adaptiveEnabled"
        /// id de la recomendación → fecha en que se descartó.
        static let dismissed = "adaptiveDismissed"
        /// Lo anterior a esta fecha no cuenta para aprender (segundos desde 1970).
        static let resetDate = "learningResetDate"
    }

    /// Una recomendación descartada no vuelve hasta pasados estos días.
    static let quietDays: TimeInterval = 14

    /// Cambia al aceptar o descartar, para que las vistas se refresquen.
    private(set) var revision = 0

    private let defaults = UserDefaults.standard

    private init() {}

    var isEnabled: Bool {
        get { defaults.object(forKey: Keys.enabled) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: Keys.enabled)
            revision += 1
        }
    }

    var resetDate: Date? {
        let value = defaults.double(forKey: Keys.resetDate)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    // MARK: - Informe

    func report(
        sessions: [FocusSessionRecord], distractions: [DistractionRecord], mode: PlanMode, now: Date = .now
    ) -> AttentionReport {
        let since = resetDate ?? .distantPast
        let method = MethodLibrary.shared.selected
        return AttentionProfileEngine().report(
            sessions: sessions.filter { $0.start >= since }.map(\.sample),
            attempts: distractions.filter { $0.date >= since }.map(\.sample),
            mode: mode.rawValue,
            currentMethodID: method.id,
            currentFocusMinutes: method.focusMinutes,
            currentBreakMinutes: method.shortBreakMinutes,
            now: now
        )
    }

    /// La sugerencia que toca enseñar ahora (una sola, para no pedir atención de más).
    func suggestion(sessions: [FocusSessionRecord], distractions: [DistractionRecord], mode: PlanMode) -> FocusRecommendation? {
        _ = revision
        guard isEnabled else { return nil }
        let dismissed = defaults.dictionary(forKey: Keys.dismissed) as? [String: Double] ?? [:]
        let now = Date.now.timeIntervalSince1970
        return report(sessions: sessions, distractions: distractions, mode: mode).recommendations.first { recommendation in
            guard let when = dismissed[recommendation.id] else { return true }
            return now - when > Self.quietDays * 86_400
        }
    }

    // MARK: - Aceptar y descartar

    /// Aplica la recomendación: crea o actualiza el método «Adaptado» del plan, o elige el método propuesto.
    func accept(_ recommendation: FocusRecommendation) {
        let library = MethodLibrary.shared
        switch recommendation.kind {
        case .shorter, .longer, .shorterBreaks, .longerBreaks:
            let base = library.selected
            let mode = PlanMode(rawValue: recommendation.mode) ?? .work
            let id = "adapted-\(mode.rawValue)"
            var method = library.custom.first { $0.id == id } ?? FocusMethod(
                id: id, name: "Adaptado · \(mode == .work ? "Trabajo" : "Normal")",
                summary: "Ajustado a cómo te concentras de verdad.",
                focusMinutes: base.focusMinutes ?? 25, shortBreakMinutes: base.shortBreakMinutes,
                longBreakMinutes: base.longBreakMinutes, cyclesBeforeLongBreak: base.cyclesBeforeLongBreak,
                flowBreakRatio: nil, isBuiltIn: false
            )
            if method.id != base.id {
                // Parte del método que se está usando.
                method.focusMinutes = base.focusMinutes ?? method.focusMinutes
                method.shortBreakMinutes = base.shortBreakMinutes
                method.longBreakMinutes = base.longBreakMinutes
                method.cyclesBeforeLongBreak = base.cyclesBeforeLongBreak
            }
            if let focus = recommendation.focusMinutes { method.focusMinutes = focus }
            if let rest = recommendation.breakMinutes { method.shortBreakMinutes = rest }
            method.summary = recommendation.title + ". " + "Propuesto por Planaby a partir de \(recommendation.samples) sesiones."
            library.save(method)
            library.selectedID = method.id
        case .switchMethod:
            if let id = recommendation.methodID,
               let method = library.all.first(where: { $0.id == id || $0.name == id }) {
                library.selectedID = method.id
            }
        case .bestHours:
            break
        }
        dismiss(recommendation)
    }

    func dismiss(_ recommendation: FocusRecommendation) {
        var dismissed = defaults.dictionary(forKey: Keys.dismissed) as? [String: Double] ?? [:]
        dismissed[recommendation.id] = Date.now.timeIntervalSince1970
        // Lo muy antiguo sobra.
        let limit = Date.now.timeIntervalSince1970 - 60 * 86_400
        dismissed = dismissed.filter { $0.value > limit }
        defaults.set(dismissed, forKey: Keys.dismissed)
        revision += 1
    }

    /// Empieza a aprender desde cero. No borra el historial ni las estadísticas.
    func resetLearning() {
        defaults.set(Date.now.timeIntervalSince1970, forKey: Keys.resetDate)
        defaults.removeObject(forKey: Keys.dismissed)
        revision += 1
    }
}
