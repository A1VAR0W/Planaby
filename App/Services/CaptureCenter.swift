import Foundation
import Observation
import SwiftData
import SwiftUI

/// Captura rápida: «Apúntalo ahora. Organízalo después. Sigue concentrado».
/// Guarda lo apuntado en la base de datos al momento (sobrevive a cerrar la app, bloquear el
/// iPhone o terminar la sesión) y nunca toca el temporizador: ni pausa, ni salta, ni cambia la
/// tarea de la sesión. La lógica pura está en `CaptureRules` (Shared, con tests).
@Observable
@MainActor
final class CaptureCenter {
    static let shared = CaptureCenter()

    /// Petición de abrir el panel de captura.
    struct Composer: Identifiable, Equatable {
        let id = UUID()
        /// Empezar dictando en vez de con el teclado.
        var dictation: Bool
    }

    /// La confirmación a la vista («✓ Apuntado …»). Solo hay una: la nueva sustituye a la anterior.
    struct Confirmation: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let duringSession: Bool
    }

    /// Resumen al terminar una sesión con cosas apuntadas.
    struct SessionSummary: Identifiable, Equatable {
        let id = UUID()
        let sessionStart: Date
        let count: Int

        var title: String { CaptureRules.summary(count: count, duringSession: true) }
    }

    enum Failure: LocalizedError {
        case empty, notSaved

        var errorDescription: String? {
            switch self {
            case .empty: "Escribe o dicta algo para apuntarlo."
            case .notSaved: "No se ha podido guardar. Tu texto sigue aquí: prueba otra vez."
            }
        }
    }

    var composer: Composer?
    /// Lo escrito en el panel. Se conserva si se cierra sin querer o se gira el iPhone.
    var draft = ""
    private(set) var confirmation: Confirmation?
    /// Al terminar una sesión con capturas: «Has apuntado 4 tareas durante tu sesión».
    private(set) var sessionSummary: SessionSummary?
    /// Abre «Por organizar» desde cualquier sitio (descanso, fin de sesión, escritorio, atajo).
    var inboxRequested = false
    /// Sube con cada cambio para que las vistas se redibujen.
    private(set) var revision = 0

    private var context: ModelContext { PlanabyStore.container.mainContext }

    private init() {
        // Un control o un atajo que abre la app pide aquí el panel.
        CaptureRequest.handler = { [weak self] dictation in self?.open(dictation: dictation) }
    }

    // MARK: - Panel

    func open(dictation: Bool = false) {
        composer = Composer(dictation: dictation)
    }

    func close() {
        composer = nil
    }

    /// Al volver a la app: atiende la petición que dejó el control del Centro de Control.
    func consumePendingRequest() {
        if CaptureRequest.consume() { open() }
    }

    // MARK: - Guardar

    /// Guarda lo apuntado. Solo confirma si la base de datos lo ha guardado de verdad; si falla,
    /// deshace la inserción y lanza el error (el texto se queda en el panel).
    @discardableResult
    func save(_ raw: String, source: CaptureSource, context: ModelContext? = nil) throws -> CapturedTask {
        guard let text = CaptureRules.clean(raw) else { throw Failure.empty }
        let context = context ?? self.context
        let state = FocusTimer.shared.state
        let origin = CaptureRules.origin(of: state)
        let capture = CapturedTask(
            text: text, mode: ModeController.shared.mode, source: source,
            sessionStart: origin.sessionStart, phase: origin.phase
        )
        context.insert(capture)
        do {
            try context.save()
        } catch {
            context.delete(capture)
            throw Failure.notSaved
        }
        draft = ""
        confirmation = Confirmation(title: text, duringSession: state != nil)
        revision += 1
        return capture
    }

    /// Quita la confirmación pasado su tiempo (solo si sigue siendo la misma).
    func dismissConfirmation(_ id: UUID) {
        if confirmation?.id == id { confirmation = nil }
    }

    // MARK: - Consultas

    func all() -> [CapturedTask] {
        let descriptor = FetchDescriptor<CapturedTask>(sortBy: [SortDescriptor(\CapturedTask.created, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Por organizar ahora (sin las pospuestas), de la más reciente a la más antigua.
    func pending(now: Date = .now) -> [CapturedTask] {
        all().filter { CaptureRules.isPending($0.entry, now: now) }
    }

    /// Para el resumen del descanso: lo apuntado en esta sesión que aún no se ha enseñado.
    func toSummarize(sessionStart: Date?, now: Date = .now) -> [CapturedTask] {
        let wanted = Set(CaptureRules.toSummarize(all().map(\.entry), sessionStart: sessionStart, since: .distantPast, now: now).map(\.id))
        return all().filter { wanted.contains($0.uid) }
    }

    /// Marca como enseñadas («Después»): no se vuelven a resumir, pero siguen por organizar.
    func markPresented(_ captures: [CapturedTask]) {
        guard !captures.isEmpty else { return }
        for capture in captures where capture.presentedAt == nil { capture.presentedAt = .now }
        commit()
    }

    // MARK: - Fin de sesión

    /// Al terminar una sesión: si se apuntó algo durante ella, se ofrece organizarlo.
    func sessionEnded(start: Date) {
        let count = CaptureRules.fromSession(all().map(\.entry), sessionStart: start, now: .now).count
        sessionSummary = count > 0 ? SessionSummary(sessionStart: start, count: count) : nil
    }

    /// «Más tarde» u «Organizar ahora»: el resumen se va y lo apuntado queda en «Por organizar».
    func dismissSessionSummary() {
        if let summary = sessionSummary {
            markPresented(all().filter { $0.sessionStart == summary.sessionStart })
        }
        sessionSummary = nil
    }

    // MARK: - Organizar

    /// La captura ya es una tarea (o una cita) del plan. Si ya lo era, no hace nada: nunca se
    /// convierte dos veces.
    func markPlanned(_ capture: CapturedTask, draft: PlanDraft) {
        var entry = capture.entry
        guard CaptureRules.markPlanned(&entry, taskID: draft.tasks.first?.id) else { return }
        capture.status = entry.status
        capture.taskID = entry.taskID
        capture.convertedAt = .now
        capture.reviewedAt = .now
        capture.presentedAt = capture.presentedAt ?? .now
        commit()
    }

    /// Hecha sin pasar por el plan.
    func complete(_ capture: CapturedTask) {
        capture.status = .done
        capture.reviewedAt = .now
        capture.presentedAt = capture.presentedAt ?? .now
        commit()
    }

    /// Vuelve a «Por organizar» (deshacer «Completada»).
    func reopen(_ capture: CapturedTask) {
        guard capture.status == .done else { return }
        capture.status = .pending
        commit()
    }

    func edit(_ capture: CapturedTask, text raw: String) {
        guard let text = CaptureRules.clean(raw), text != capture.text else { return }
        capture.text = text
        capture.reviewedAt = .now
        commit()
    }

    func setMode(_ capture: CapturedTask, _ mode: PlanMode) {
        capture.mode = mode
        capture.reviewedAt = .now
        commit()
    }

    /// Posponer la revisión: desaparece de «Por organizar» hasta esa fecha.
    func snooze(_ capture: CapturedTask, until date: Date) {
        capture.snoozedUntil = date
        capture.reviewedAt = .now
        capture.presentedAt = capture.presentedAt ?? .now
        commit()
    }

    func delete(_ capture: CapturedTask) {
        context.delete(capture)
        commit()
    }

    /// Mañana a las 9:00.
    static var tomorrowMorning: Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private func commit() {
        try? context.save()
        revision += 1
    }
}
