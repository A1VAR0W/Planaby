import Foundation
import FoundationModels
import Observation
import SwiftData
import UIKit
import WidgetKit

/// Une la bandeja de comunicaciones con el momento de la sesión: qué se ve concentrándose, qué se
/// guarda para el descanso, el recuento para widgets y StandBy, y «Mientras estabas fuera».
/// La lógica de qué enseñar está en `CommPolicy` (Shared, con tests); aquí solo se aplica.
@Observable
@MainActor
final class CommsCenter {
    static let shared = CommsCenter()

    /// Lo nuevo que llegó con Planaby en segundo plano y aún no se ha enseñado.
    struct AwayDigest: Identifiable, Equatable {
        let id = UUID()
        let phase: CommPhase
        let items: [MessageItem]

        static func == (a: AwayDigest, b: AwayDigest) -> Bool { a.id == b.id }

        var title: String {
            let count = items.count
            let what = count == 1 ? "1 comunicación importante" : "\(count) comunicaciones importantes"
            return phase == .focus
                ? "Mientras estabas fuera: \(count == 1 ? "1 de trabajo" : "\(count) de trabajo")"
                : "Mientras estabas fuera, \(count == 1 ? "llegó" : "llegaron") \(what)"
        }
    }

    var settings: CommSettings {
        didSet {
            settings.save()
            refresh()
        }
    }

    /// Lo enseña la tarjeta en Enfoque o la hoja «Bienvenido de nuevo» (nunca las dos).
    private(set) var away: AwayDigest?
    /// Abre la bandeja desde cualquier sitio (tarjeta de fase, escritorio, «Ver todo»).
    var inboxRequested = false
    /// La tarjeta de cambio de fase está a la vista: las tarjetas de comunicaciones esperan para no
    /// quedar debajo de ella.
    var phaseCardVisible = false
    /// Sube con cada cambio para que las vistas se redibujen.
    private(set) var revision = 0

    private enum Keys {
        static let lastPresented = "commsLastPresented"
    }

    private var context: ModelContext { PlanabyStore.container.mainContext }

    private init() {
        settings = CommSettings.load()
    }

    var rules: TriageRules { MessageTriage.rules }

    /// Momento según el temporizador; sin sesión, la Concentración Trabajo del iPhone cuenta como
    /// concentración (el plan Trabajo de Planaby elegido a mano, no).
    static func phase(of state: TimerState?) -> CommPhase {
        guard let state else { return SystemFocusState.isOn() ? .focus : .idle }
        return state.phase.isBreak ? .rest : .focus
    }

    var phase: CommPhase { Self.phase(of: FocusTimer.shared.state) }

    // MARK: Consultas

    private func allItems() -> [MessageItem] {
        let descriptor = FetchDescriptor<MessageItem>(sortBy: [SortDescriptor(\.received, order: .reverse)])
        return ((try? context.fetch(descriptor)) ?? []).filter { $0.category != .noise || $0.needsReply }
    }

    /// Mensajes que se ven ahora, ya ordenados (de `source`, o de toda la bandeja).
    func items(for phase: CommPhase, from source: [MessageItem]? = nil, now: Date = .now) -> [MessageItem] {
        let rules = rules
        let pairs = (source ?? allItems()).map { ($0, $0.entry(rules: rules)) }
        let filtered = pairs.filter { _, entry in
            phase == .focus
                ? CommPolicy.showsDuringFocus(entry, settings: settings, now: now)
                : CommPolicy.isPending(entry, now: now)
        }
        return filtered.sorted { CommPolicy.order($0.1, $1.1) }.map(\.0)
    }

    var snapshot: CommsSnapshot { CommsSnapshot.load() }

    /// Recuento por app de lo pendiente.
    func breakdown(_ items: [MessageItem]) -> [(app: String, count: Int)] {
        let rules = rules
        return CommPolicy.breakdown(items.map { $0.entry(rules: rules) })
    }

    func line(_ item: MessageItem) -> String { CommPolicy.line(item.entry(rules: rules)) }

    /// Resumen de lo pendiente: con Apple Intelligence, redactado; sin ella, recuento por app.
    func digestSummary(_ items: [MessageItem]) async -> String {
        let plain = breakdown(items).map { "\($0.app): \($0.count)" }.joined(separator: " · ")
        let replies = items.filter(\.needsReply).count
        let fallback = plain + (replies > 0 ? ". \(replies == 1 ? "1 espera" : "\(replies) esperan") respuesta." : ".")
        guard AIProvider.isAvailable, !items.isEmpty else { return fallback }
        let session = AIProvider.session(instructions: """
            Resumes en dos frases como mucho las comunicaciones pendientes de una persona que vuelve de \
            concentrarse: qué es lo más importante y a quién conviene contestar. Escribe en español, de tú.
            """)
        let lines = items.prefix(8).map { line($0) + ($0.needsReply ? " (espera respuesta)" : "") }.joined(separator: "\n")
        guard let response = try? await session.respond(to: AIProvider.wrap(lines, limit: 1_200)) else { return fallback }
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? fallback : String(text.prefix(400))
    }

    // MARK: Recuento compartido

    /// Recalcula el recuento sin textos para widgets, Live Activity y StandBy.
    func refresh(now: Date = .now) {
        let rules = rules
        let entries = allItems().map { $0.entry(rules: rules) }
        let new = CommsSnapshot.make(entries, settings: settings, now: now)
        let old = CommsSnapshot.load()
        new.save()
        revision += 1
        let changed = new.focusVisible != old.focusVisible || new.pending != old.pending || new.urgent != old.urgent
        if changed { FocusTimer.shared.refreshSurfaces() }
    }

    // MARK: Mientras estabas fuera

    private var lastPresented: Date? {
        get { UserDefaults.standard.object(forKey: Keys.lastPresented) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Keys.lastPresented) }
    }

    /// Al volver a primer plano: lo nuevo y relevante que no se ha enseñado. Se basa en la fecha de
    /// llegada y en lo ya presentado; iOS no dice si el iPhone estuvo bloqueado.
    func checkAway(now: Date = .now) {
        refresh(now: now)
        let phase = phase
        let rules = rules
        let pairs = allItems().map { ($0, $0.entry(rules: rules)) }
        let fresh = CommPolicy.awayDigest(pairs.map(\.1), lastPresented: lastPresented, phase: phase, settings: settings, now: now)
        let ids = Set(fresh.map(\.id))
        let items = pairs.filter { ids.contains($0.1.id) }.sorted { CommPolicy.order($0.1, $1.1) }.map(\.0)
        guard !items.isEmpty else { return }
        away = AwayDigest(phase: phase, items: Array(items.prefix(phase == .focus ? 2 : 4)))
        // Lo que no cabe se da por visto igualmente: no se repite en la siguiente vuelta.
        markPresented(items, now: now)
    }

    /// Se lo queda quien lo vaya a enseñar (la hoja de vuelta o la tarjeta), para que no salga dos veces.
    func takeAway() -> AwayDigest? {
        defer { away = nil }
        return away
    }

    func dismissAway() { away = nil }

    private func markPresented(_ items: [MessageItem], now: Date) {
        for item in items where item.presentedAt == nil { item.presentedAt = now }
        lastPresented = now
        try? context.save()
    }

    // MARK: Acciones

    func markReviewed(_ item: MessageItem) {
        item.isRead = true
        item.reviewedAt = .now
        save()
    }

    func markReplied(_ item: MessageItem) {
        item.isRead = true
        item.repliedAt = .now
        item.needsReply = false
        save()
    }

    func reopen(_ item: MessageItem) {
        item.isRead = false
        item.reviewedAt = nil
        item.repliedAt = nil
        save()
    }

    /// Pospone hasta el siguiente descanso aproximado (o los minutos dados).
    func snooze(_ item: MessageItem, minutes: Int = 60) {
        item.snoozedUntil = Date.now.addingTimeInterval(TimeInterval(minutes * 60))
        item.presentedAt = nil
        save()
    }

    /// Crea una tarea en el plan con lo que pide el mensaje (el original sigue en su app).
    @discardableResult
    func addToPlan(_ item: MessageItem) -> PlanTask {
        let what = item.summary.isEmpty ? (item.subject.isEmpty ? item.body : item.subject) : item.summary
        let title = String(what.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        let mode: PlanMode = settings.isWork(item.app) ? .work : .personal
        let deadline = Calendar.current.date(byAdding: .day, value: item.category == .urgent ? 0 : 1, to: .now)
            .map { Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: $0) ?? $0 } ?? .now
        let task = PlanTask(
            title: title.isEmpty ? "Responder a \(item.sender)" : title, mode: mode, deadline: deadline,
            estimatedMinutes: 15, priority: item.category == .urgent ? 2 : 1,
            notes: "De \(item.sender.isEmpty ? item.appTitle : item.sender) (\(item.appTitle))."
        )
        task.uid = UUID()
        task.nextStep = item.needsReply ? "Contestar a \(item.sender.isEmpty ? item.appTitle : item.sender)" : ""
        context.insert(task)
        item.isRead = true
        item.reviewedAt = .now
        item.addedToPlanAt = .now
        save()
        return task
    }

    /// Abre la app de origen si tiene un esquema oficial y está instalada. Solo abre la app: iOS no
    /// permite ir a un mensaje concreto desde fuera.
    func canOpen(_ item: MessageItem) -> Bool { item.app.openURL != nil }

    func open(_ item: MessageItem) {
        guard let url = item.app.openURL else { return }
        markReviewed(item)
        UIApplication.shared.open(url)
    }

    private func save() {
        try? context.save()
        refresh()
    }
}
