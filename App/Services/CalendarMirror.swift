import EventKit
import Foundation
import Observation
import SwiftData

/// Copia el plan Normal de Planaby (solo ese) a un calendario «Planaby» del Calendario de iOS.
/// Va en un sentido: lo que se cambie allí se sobrescribe en la siguiente copia. El plan de
/// Trabajo nunca sale de Planaby. Se actualiza cada vez que cambia el plan.
@Observable
@MainActor
final class CalendarMirror {
    static let shared = CalendarMirror()
    nonisolated static let enabledKey = "mirrorPersonalToiOS"
    private static let calendarKey = "mirrorCalendarID"
    /// Ventana copiada: de ayer a dos meses vista (los hábitos se copian día a día).
    private static let daysAhead = 60

    private(set) var isEnabled: Bool
    private(set) var lastSync: Date?
    private(set) var lastError: String?

    @ObservationIgnored private let store = EKEventStore()

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    /// Identificador del calendario «Planaby», para no leerlo como calendario externo.
    var calendarID: String? { UserDefaults.standard.string(forKey: Self.calendarKey) }

    func enable() {
        store.requestFullAccessToEvents { @Sendable granted, _ in
            Task { @MainActor in
                let mirror = CalendarMirror.shared
                guard granted else {
                    mirror.lastError = "Sin permiso para el Calendario. Actívalo en Ajustes › Apps › Planaby › Calendarios."
                    return
                }
                mirror.isEnabled = true
                mirror.lastError = nil
                UserDefaults.standard.set(true, forKey: CalendarMirror.enabledKey)
                mirror.sync()
            }
        }
    }

    /// Deja de copiar y quita el calendario «Planaby» del iPhone.
    func disable() {
        isEnabled = false
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        if let id = calendarID, let calendar = store.calendar(withIdentifier: id) {
            try? store.removeCalendar(calendar, commit: true)
        }
        UserDefaults.standard.removeObject(forKey: Self.calendarKey)
        lastSync = nil
    }

    /// Deja el calendario «Planaby» igual que el plan Normal: añade lo que falta y quita lo que sobra.
    func sync() {
        guard isEnabled, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        guard let calendar = planabyCalendar() else {
            lastError = "No se pudo crear el calendario «Planaby» en el iPhone."
            return
        }

        let now = Date.now
        let start = Calendar.current.startOfDay(for: now.addingTimeInterval(-86_400))
        let end = Calendar.current.date(byAdding: .day, value: Self.daysAhead, to: start) ?? now
        let window = DateInterval(start: start, end: end)

        let context = PlanabyStore.container.mainContext
        let events = ((try? context.fetch(FetchDescriptor<CalendarEvent>())) ?? []).filter { $0.mode == .personal }
        var wanted: [String: (title: String, interval: DateInterval, isAllDay: Bool, notes: String)] = [:]
        for event in events {
            for occurrence in event.occurrences(in: window) {
                let key = Self.key(event.title, occurrence)
                wanted[key] = (event.title, occurrence, event.isAllDay, event.notes)
            }
        }

        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: [calendar])
        var existing = Set<String>()
        for event in store.events(matching: predicate) {
            let key = Self.key(event.title ?? "", DateInterval(start: event.startDate, end: max(event.startDate, event.endDate)))
            if wanted[key] == nil || existing.contains(key) {
                try? store.remove(event, span: .thisEvent, commit: false)
            } else {
                existing.insert(key)
            }
        }
        for (key, item) in wanted where !existing.contains(key) {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = item.title
            event.startDate = item.interval.start
            event.endDate = item.interval.end
            event.isAllDay = item.isAllDay
            event.notes = item.notes.isEmpty ? "Desde Planaby (plan Normal)." : item.notes
            try? store.save(event, span: .thisEvent, commit: false)
        }
        do {
            try store.commit()
            lastSync = .now
            lastError = nil
        } catch {
            lastError = "No se pudo actualizar el Calendario: \(error.localizedDescription)"
        }
    }

    private static func key(_ title: String, _ interval: DateInterval) -> String {
        "\(title)|\(Int(interval.start.timeIntervalSince1970))|\(Int(interval.end.timeIntervalSince1970))"
    }

    /// El calendario «Planaby»: en iCloud si hay (así llega al Mac y al iPad), si no en el iPhone.
    private func planabyCalendar() -> EKCalendar? {
        if let id = calendarID, let calendar = store.calendar(withIdentifier: id) { return calendar }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Planaby"
        calendar.cgColor = CGColor(red: 0.95, green: 0.78, blue: 0.56, alpha: 1)
        let sources = store.sources
        calendar.source = sources.first { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("icloud") }
            ?? store.defaultCalendarForNewEvents?.source
            ?? sources.first { $0.sourceType == .local }
        guard calendar.source != nil, (try? store.saveCalendar(calendar, commit: true)) != nil else { return nil }
        UserDefaults.standard.set(calendar.calendarIdentifier, forKey: Self.calendarKey)
        return calendar
    }
}
