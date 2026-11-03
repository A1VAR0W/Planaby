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

/// Calendario de Outlook (o Google, iCloud…) al que Planaby está suscrito por su enlace ICS.
/// Se descarga directamente, sin pasar por el Calendario de iOS.
struct CalendarSubscription: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var url: String
    var mode: PlanMode
    var lastSync: Date?
    var lastError: String?
}

/// Calendarios externos que Planaby tiene en cuenta, solo para leer: sus eventos se ven en la
/// agenda y el planificador no pone bloques encima.
/// - Suscripciones ICS (lo principal): el enlace «Publicar calendario» de Outlook, que incluye
///   las reuniones de Teams. Planaby lo descarga y guarda una copia para usarla sin conexión.
/// - Opcionalmente, calendarios del propio iPhone (EventKit).
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
    private(set) var subscriptions: [CalendarSubscription] = []
    private(set) var isSyncing = false
    @ObservationIgnored private var cache: [UUID: [ICSOccurrence]] = [:]

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?
    private static let key = "externalCalendars"
    private static let subscriptionsKey = "calendarSubscriptions"
    /// Cada cuánto se vuelve a descargar como mínimo al abrir la app.
    private static let refreshInterval: TimeInterval = 15 * 60
    /// Colores de las suscripciones: azul Outlook, morado Teams y otros.
    private static let palette: [Color] = [
        Color(red: 0.0, green: 0.47, blue: 0.83), Color(red: 0.38, green: 0.39, blue: 0.65),
        Color(red: 0.18, green: 0.64, blue: 0.31), Color(red: 0.83, green: 0.63, blue: 0.09),
    ]

    private init() {
        status = EKEventStore.authorizationStatus(for: .event)
        let saved = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        selection = saved.compactMapValues(PlanMode.init(rawValue:))
        subscriptions = UserDefaults.standard.data(forKey: Self.subscriptionsKey)
            .flatMap { try? JSONDecoder().decode([CalendarSubscription].self, from: $0) } ?? []
        for subscription in subscriptions {
            cache[subscription.id] = (try? Data(contentsOf: Self.cacheURL(for: subscription.id)))
                .flatMap { try? JSONDecoder().decode([ICSOccurrence].self, from: $0) }
        }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadCalendars() }
        }
        reloadCalendars()
    }

    var isAuthorized: Bool { status == .fullAccess }
    var usesDeviceCalendars: Bool { isAuthorized && !selection.isEmpty }
    var isActive: Bool { !subscriptions.isEmpty || usesDeviceCalendars }

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

    /// Eventos de las suscripciones y de los calendarios elegidos en un intervalo.
    func events(in interval: DateInterval) -> [ExternalEvent] {
        subscriptionEvents(in: interval) + deviceEvents(in: interval)
    }

    private func subscriptionEvents(in interval: DateInterval) -> [ExternalEvent] {
        subscriptions.enumerated().flatMap { index, subscription in
            (cache[subscription.id] ?? [])
                .filter { $0.end > interval.start && $0.start < interval.end }
                .map { occurrence in
                    ExternalEvent(
                        id: "\(subscription.id)-\(occurrence.uid)-\(occurrence.start.timeIntervalSinceReferenceDate)",
                        title: occurrence.title, start: occurrence.start, end: occurrence.end,
                        isAllDay: occurrence.isAllDay, isBusy: occurrence.isBusy,
                        calendarTitle: subscription.name, sourceTitle: "",
                        color: Self.palette[index % Self.palette.count], mode: subscription.mode
                    )
                }
        }
    }

    private func deviceEvents(in interval: DateInterval) -> [ExternalEvent] {
        guard usesDeviceCalendars else { return [] }
        let chosen = store.calendars(for: .event).filter {
            selection[$0.calendarIdentifier] != nil && $0.calendarIdentifier != CalendarMirror.shared.calendarID
        }
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

    // MARK: - Suscripciones

    func color(for subscription: CalendarSubscription) -> Color {
        let index = subscriptions.firstIndex { $0.id == subscription.id } ?? 0
        return Self.palette[index % Self.palette.count]
    }

    /// Descarga el enlace para comprobar que es un calendario y lo guarda. Devuelve cuántos eventos trae.
    func addSubscription(name: String, url text: String, mode: PlanMode) async throws -> Int {
        guard let url = Self.normalizedURL(text) else { throw SubscriptionError.invalidURL }
        let occurrences = try await Self.download(url)
        var subscription = CalendarSubscription(name: name, url: url.absoluteString, mode: mode)
        subscription.lastSync = .now
        subscriptions.append(subscription)
        store(occurrences, for: subscription.id)
        saveSubscriptions()
        return occurrences.count
    }

    /// Cambia nombre y plan (el resto lo lleva la descarga).
    func update(_ subscription: CalendarSubscription) {
        guard let index = subscriptions.firstIndex(where: { $0.id == subscription.id }) else { return }
        subscriptions[index].name = subscription.name
        subscriptions[index].mode = subscription.mode
        saveSubscriptions()
        revision += 1
    }

    func remove(_ subscription: CalendarSubscription) {
        subscriptions.removeAll { $0.id == subscription.id }
        cache[subscription.id] = nil
        try? FileManager.default.removeItem(at: Self.cacheURL(for: subscription.id))
        saveSubscriptions()
        revision += 1
    }

    /// Al abrir la app: vuelve a descargar si hace más de un rato.
    func syncIfNeeded() {
        let stale = subscriptions.contains { ($0.lastSync ?? .distantPast).timeIntervalSinceNow < -Self.refreshInterval }
        if stale { Task { await syncAll() } }
    }

    func syncAll() async {
        guard !isSyncing, !subscriptions.isEmpty else { return }
        isSyncing = true
        defer { isSyncing = false }
        for subscription in subscriptions {
            guard let url = Self.normalizedURL(subscription.url) else { continue }
            var updated = subscription
            do {
                let occurrences = try await Self.download(url)
                store(occurrences, for: subscription.id)
                updated.lastSync = .now
                updated.lastError = nil
            } catch {
                updated.lastError = error.localizedDescription
            }
            if let index = subscriptions.firstIndex(where: { $0.id == subscription.id }) {
                subscriptions[index] = updated
            }
        }
        saveSubscriptions()
        revision += 1
    }

    private func store(_ occurrences: [ICSOccurrence], for id: UUID) {
        cache[id] = occurrences
        if let data = try? JSONEncoder().encode(occurrences) {
            try? data.write(to: Self.cacheURL(for: id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        revision += 1
    }

    private func saveSubscriptions() {
        if let data = try? JSONEncoder().encode(subscriptions) {
            UserDefaults.standard.set(data, forKey: Self.subscriptionsKey)
        }
    }

    private static func cacheURL(for id: UUID) -> URL {
        let directory = URL.applicationSupportDirectory.appending(path: "Calendars", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "\(id.uuidString).json")
    }

    /// Acepta enlaces https y webcal (el de «Publicar calendario» de Outlook).
    static func normalizedURL(_ text: String) -> URL? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("webcal://") { value = "https://" + value.dropFirst("webcal://".count) }
        guard let url = URL(string: value), url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }

    /// Descarga y expande el calendario: desde una semana atrás hasta cuatro meses vista.
    nonisolated static func download(_ url: URL, now: Date = .now) async throws -> [ICSOccurrence] {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("text/calendar", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw SubscriptionError.http(status)
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              text.contains("BEGIN:VCALENDAR") else {
            throw SubscriptionError.notCalendar
        }
        return ICSCalendar.occurrences(
            in: text, from: now.addingTimeInterval(-7 * 86_400), to: now.addingTimeInterval(120 * 86_400)
        )
    }

    enum SubscriptionError: LocalizedError {
        case invalidURL, notCalendar, http(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                "El enlace no es válido. Tiene que empezar por https:// o webcal://."
            case .notCalendar:
                "El enlace no devuelve un calendario. Copia el enlace ICS, no el HTML."
            case .http(let code) where code == 401 || code == 403 || code == 404:
                "Outlook no permite acceder (error \(code)). Puede que el calendario ya no esté publicado o que tu empresa lo bloquee."
            case .http(let code):
                "El servidor respondió con un error (\(code)). Prueba más tarde."
            }
        }
    }

    // MARK: - Calendarios del iPhone

    private func reloadCalendars() {
        guard isAuthorized else {
            calendars = []
            revision += 1
            return
        }
        // El calendario «Planaby» es la copia del plan Normal: no se vuelve a leer.
        calendars = store.calendars(for: .event)
            .filter { $0.calendarIdentifier != CalendarMirror.shared.calendarID }
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source?.title ?? "", color: Color(cgColor: $0.cgColor)) }
            .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
        revision += 1
    }
}
