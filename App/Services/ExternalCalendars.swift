import EventKit
import Foundation
import Observation
import SwiftUI

/// Evento de otro calendario (Outlook, Teams, iCloud, Google…) leído del Calendario de iOS.
struct ExternalEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    /// Ocupa tiempo (no está marcado como «libre» ni rechazado).
    let isBusy: Bool
    let calendarTitle: String
    let sourceTitle: String
    let color: Color
    let mode: PlanMode

    var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }
}

/// Calendarios de iOS que Planaby tiene en cuenta. Outlook y Teams llegan a través de la cuenta
/// de Microsoft añadida al Calendario de iOS (o de la app Outlook con «Sincronizar calendarios»).
/// Solo se leen: sus eventos se ven en la agenda y el planificador no pone bloques encima.
@Observable
@MainActor
final class ExternalCalendars {
    static let shared = ExternalCalendars()

    struct CalendarInfo: Identifiable {
        let id: String
        let title: String
        let sourceTitle: String
        let color: Color
    }

    private(set) var status: EKAuthorizationStatus
    private(set) var calendars: [CalendarInfo] = []
    /// Calendarios elegidos y a qué plan pertenecen sus eventos.
    private(set) var selection: [String: PlanMode]
    /// Cambia cada vez que cambian los calendarios, para refrescar las vistas.
    private(set) var revision = 0

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?
    private static let key = "externalCalendars"

    private init() {
        status = EKEventStore.authorizationStatus(for: .event)
        let saved = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        selection = saved.compactMapValues(PlanMode.init(rawValue:))
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadCalendars() }
        }
        reloadCalendars()
    }

    var isAuthorized: Bool { status == .fullAccess }
    var isActive: Bool { isAuthorized && !selection.isEmpty }

    func requestAccess() {
        // EventKit responde desde otro hilo: el cierre no puede heredar el actor principal.
        store.requestFullAccessToEvents { @Sendable [weak self] _, _ in
            Task { @MainActor in
                self?.status = EKEventStore.authorizationStatus(for: .event)
                self?.reloadCalendars()
            }
        }
    }

    func refreshStatus() {
        let current = EKEventStore.authorizationStatus(for: .event)
        guard current != status else { return }
        status = current
        reloadCalendars()
    }

    func mode(for calendarID: String) -> PlanMode? { selection[calendarID] }

    func setMode(_ mode: PlanMode?, for calendarID: String) {
        selection[calendarID] = mode
        UserDefaults.standard.set(selection.mapValues(\.rawValue), forKey: Self.key)
        revision += 1
    }

    /// Eventos de los calendarios elegidos en un intervalo.
    func events(in interval: DateInterval) -> [ExternalEvent] {
        guard isActive else { return [] }
        let chosen = store.calendars(for: .event).filter { selection[$0.calendarIdentifier] != nil }
        guard !chosen.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: chosen)
        return store.events(matching: predicate).compactMap { event in
            guard let calendar = event.calendar, let mode = selection[calendar.calendarIdentifier] else { return nil }
            let declined = event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
            return ExternalEvent(
                id: "\(event.calendarItemIdentifier)-\(event.startDate.timeIntervalSinceReferenceDate)",
                title: event.title ?? "Sin título",
                start: event.startDate, end: event.endDate,
                isAllDay: event.isAllDay,
                isBusy: event.availability != .free && !declined,
                calendarTitle: calendar.title,
                sourceTitle: calendar.source?.title ?? "",
                color: Color(cgColor: calendar.cgColor),
                mode: mode
            )
        }
    }

    /// Lo que ocupa tiempo de verdad: sin eventos de todo el día, libres ni rechazados.
    func busyIntervals(in interval: DateInterval) -> [DateInterval] {
        events(in: interval).filter { $0.isBusy && !$0.isAllDay }.map(\.interval)
    }

    private func reloadCalendars() {
        guard isAuthorized else {
            calendars = []
            revision += 1
            return
        }
        calendars = store.calendars(for: .event)
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source?.title ?? "", color: Color(cgColor: $0.cgColor)) }
            .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
        revision += 1
    }
}
