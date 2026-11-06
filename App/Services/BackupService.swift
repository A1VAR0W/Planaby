import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Copia completa de Planaby: sesiones, tareas, calendario, adjuntos (con sus archivos), ajustes
/// y conversación. Se guarda en JSON para poder sacarla a Archivos o iCloud Drive.
struct PlanabyBackup: Codable {
    var format = 1
    var created: Date
    var appVersion: String
    var sessions: [Session]
    var tasks: [TaskItem]
    var events: [Event]
    var attachments: [Attachment]
    /// Ajustes del App Group y de la app, como property list.
    var groupSettings: Data?
    var localSettings: Data?
    var chat: Data?
    /// Pausas conscientes (copias desde la 0.1.23).
    var distractions: [Distraction]?
    /// Capturas rápidas por organizar (copias desde la 1.0.46).
    var captures: [CaptureBackup]?

    struct Session: Codable {
        var start: Date, end: Date, methodName: String, focusedSeconds: Double, completedCycles: Int, taskTitle: String?
        // Desde la 1.1 (opcionales para leer copias anteriores).
        var taskID: UUID?, methodID: String?, modeRaw: String?, plannedFocusMinutes: Int?, endedEarly: Bool?
        var abandonedAfterMinutes: Double?, pauseCount: Int?, leaveCount: Int?, awaySeconds: Double?
        var skippedBreaks: Int?, isStarter: Bool?, focusRating: Int?
    }

    struct TaskItem: Codable {
        var ref: Int, title: String, modeRaw: String, deadline: Date, estimatedMinutes: Int, priority: Int
        var isDone: Bool, created: Date, difficulty: Int, notes: String, completedAt: Date?
        var uid: UUID?, nextStep: String?, blockedNote: String?, blockedAt: Date?
    }

    struct Event: Codable {
        var title: String, notes: String, start: Date, end: Date, isAllDay: Bool
        var modeRaw: String, kindRaw: String, recurrenceRaw: String, reminderMinutes: Int?, taskRef: Int?
    }

    struct Distraction: Codable {
        var date: Date, app: String, reason: String, resisted: Bool, duringFocus: Bool
        var kindRaw: String?, motiveRaw: String?, awaySeconds: Double?
    }

    struct Attachment: Codable {
        var name: String, kindRaw: String, fileName: String, extractedText: String, created: Date
        var taskRef: Int?, data: Data?
    }
}

/// Copias de seguridad automáticas (una por día, las 14 últimas) en la carpeta de Planaby de la
/// app Archivos, más exportar y restaurar a mano.
@MainActor
enum BackupService {
    /// Ajustes que se copian. El estado del temporizador no (es momentáneo).
    private static let groupKeys = [
        "dailyGoalMinutes", "phaseAlerts", "planMode", "planModeSource", "planSchedule.work", "planSchedule.personal",
        "customMethods", "selectedMethodID", "focusProfile",
        "alertStyle", "alertSoundSet", "alertBreakStart", "alertBreakEnd", "alertRespectMusic", "alertOverlay",
    ]
    private static let localKeys = [
        "deskDimmed", "deskNightMode", "deskNightStart", "deskNightEnd", "deskKeepAwake", "deskShowsTasks", "deskShowsMusic", "frictionApps", "deskAutoMusic", "planShowsMonth", "spotifyClientID",
        "frictionEnabled", "frictionIntensity", "frictionRules", "adaptiveEnabled", "adaptiveDismissed", "learningResetDate", "prioritySenders", "senderOverrides", "leaveGuardEnabled", "leaveGuardGrace", "leaveGuardStrict", "frictionScope", "frictionPauseSeconds", "frictionPassMinutes", "musicFocusURL", "musicBreakURL", "musicAutoOpen", "messageNotifyLevel",
        "externalCalendars", "calendarSubscriptions", CalendarMirror.enabledKey, "deviceCalendarsAdopted",
    ]
    private static let maxFileSize = 10 * 1024 * 1024
    private static let keep = 14
    private static let lastBackupKey = "lastAutomaticBackup"

    /// Carpeta visible en Archivos › En mi iPhone › Planaby › Copias de seguridad.
    static var folder: URL {
        let url = URL.documentsDirectory.appending(path: "Copias de seguridad", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var lastAutomaticBackup: Date? {
        UserDefaults.standard.object(forKey: lastBackupKey) as? Date
    }

    // MARK: - Crear

    static func makeBackup(context: ModelContext) -> PlanabyBackup {
        let tasks = (try? context.fetch(FetchDescriptor<PlanTask>())) ?? []
        var refs: [PersistentIdentifier: Int] = [:]
        for (index, task) in tasks.enumerated() { refs[task.persistentModelID] = index }

        let sessions = (try? context.fetch(FetchDescriptor<FocusSessionRecord>())) ?? []
        let events = (try? context.fetch(FetchDescriptor<CalendarEvent>())) ?? []
        let attachments = (try? context.fetch(FetchDescriptor<TaskAttachment>())) ?? []
        let distractions = (try? context.fetch(FetchDescriptor<DistractionRecord>())) ?? []
        let captures = (try? context.fetch(FetchDescriptor<CapturedTask>())) ?? []

        return PlanabyBackup(
            created: .now,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            sessions: sessions.map {
                PlanabyBackup.Session(start: $0.start, end: $0.end, methodName: $0.methodName, focusedSeconds: $0.focusedSeconds,
                      completedCycles: $0.completedCycles, taskTitle: $0.taskTitle, taskID: $0.taskID, methodID: $0.methodID,
                      modeRaw: $0.modeRaw, plannedFocusMinutes: $0.plannedFocusMinutes, endedEarly: $0.endedEarly,
                      abandonedAfterMinutes: $0.abandonedAfterMinutes, pauseCount: $0.pauseCount, leaveCount: $0.leaveCount,
                      awaySeconds: $0.awaySeconds, skippedBreaks: $0.skippedBreaks, isStarter: $0.isStarter, focusRating: $0.focusRating)
            },
            tasks: tasks.enumerated().map { index, task in
                PlanabyBackup.TaskItem(ref: index, title: task.title, modeRaw: task.modeRaw, deadline: task.deadline,
                      estimatedMinutes: task.estimatedMinutes, priority: task.priority, isDone: task.isDone,
                      created: task.created, difficulty: task.difficulty, notes: task.notes, completedAt: task.completedAt,
                      uid: task.uid, nextStep: task.nextStep, blockedNote: task.blockedNote, blockedAt: task.blockedAt)
            },
            events: events.map { event in
                PlanabyBackup.Event(title: event.title, notes: event.notes, start: event.start, end: event.end, isAllDay: event.isAllDay,
                      modeRaw: event.modeRaw, kindRaw: event.kindRaw, recurrenceRaw: event.recurrenceRaw,
                      reminderMinutes: event.reminderMinutes, taskRef: event.task.flatMap { refs[$0.persistentModelID] })
            },
            attachments: attachments.map { file -> PlanabyBackup.Attachment in
                let url = AttachmentStore.url(for: file.fileName)
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return PlanabyBackup.Attachment(name: file.name, kindRaw: file.kindRaw, fileName: file.fileName, extractedText: file.extractedText,
                             created: file.created, taskRef: file.task.flatMap { refs[$0.persistentModelID] },
                             data: size <= maxFileSize ? try? Data(contentsOf: url) : nil)
            },
            groupSettings: settings(groupKeys, from: AppGroup.defaults),
            localSettings: settings(localKeys, from: .standard),
            chat: try? Data(contentsOf: URL.applicationSupportDirectory.appending(path: "chat.json")),
            distractions: distractions.map {
                PlanabyBackup.Distraction(date: $0.date, app: $0.app, reason: $0.reason, resisted: $0.resisted, duringFocus: $0.duringFocus,
                      kindRaw: $0.kindRaw, motiveRaw: $0.motiveRaw, awaySeconds: $0.awaySeconds)
            },
            captures: captures.map { CaptureBackup($0) }
        )
    }

    /// Escribe una copia en la carpeta de copias y devuelve dónde.
    @discardableResult
    static func writeBackup(context: ModelContext, name: String? = nil) throws -> URL {
        let backup = makeBackup(context: context)
        let data = try JSONEncoder().encode(backup)
        let fileName = name ?? "Planaby \(Self.dayFormatter.string(from: .now)).json"
        let url = folder.appending(path: fileName)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        prune()
        return url
    }

    /// Al pasar a segundo plano: guarda la copia del día (se sobrescribe durante el día).
    static func automaticBackup(context: ModelContext) {
        if (try? writeBackup(context: context)) != nil {
            UserDefaults.standard.set(Date.now, forKey: lastBackupKey)
        }
    }

    /// Copias guardadas, de la más reciente a la más antigua.
    static func savedBackups() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { modified($0) > modified($1) }
    }

    static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func prune() {
        let automatic = savedBackups().filter { $0.lastPathComponent.hasPrefix("Planaby 2") }
        automatic.dropFirst(keep).forEach { try? FileManager.default.removeItem(at: $0) }
    }

    private static func settings(_ keys: [String], from defaults: UserDefaults) -> Data? {
        var values: [String: Any] = [:]
        for key in keys {
            if let value = defaults.object(forKey: key) { values[key] = value }
        }
        return try? PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - Restaurar

    enum RestoreError: LocalizedError {
        case unreadable

        var errorDescription: String? { "El archivo no es una copia de Planaby o está dañado." }
    }

    /// Sustituye todo por el contenido de la copia. Antes guarda una copia de lo actual.
    static func restore(from url: URL, context: ModelContext) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let backup = try? JSONDecoder().decode(PlanabyBackup.self, from: data) else {
            throw RestoreError.unreadable
        }
        try writeBackup(context: context, name: "Antes de restaurar \(Int(Date.now.timeIntervalSince1970)).json")

        // Fuera lo actual (los bloques y adjuntos se borran con su tarea).
        for file in (try? context.fetch(FetchDescriptor<TaskAttachment>())) ?? [] {
            AttachmentStore.delete(file.fileName)
            context.delete(file)
        }
        for event in (try? context.fetch(FetchDescriptor<CalendarEvent>())) ?? [] { context.delete(event) }
        for task in (try? context.fetch(FetchDescriptor<PlanTask>())) ?? [] { context.delete(task) }
        for session in (try? context.fetch(FetchDescriptor<FocusSessionRecord>())) ?? [] { context.delete(session) }
        for record in (try? context.fetch(FetchDescriptor<DistractionRecord>())) ?? [] { context.delete(record) }
        // Las capturas solo se sustituyen si la copia las trae: una copia anterior a la captura
        // rápida no borra lo apuntado desde entonces.
        if backup.captures != nil {
            for capture in (try? context.fetch(FetchDescriptor<CapturedTask>())) ?? [] { context.delete(capture) }
        }

        var tasks: [Int: PlanTask] = [:]
        for item in backup.tasks {
            let task = PlanTask(
                title: item.title, mode: PlanMode(rawValue: item.modeRaw) ?? .work, deadline: item.deadline,
                estimatedMinutes: item.estimatedMinutes, priority: item.priority, difficulty: item.difficulty, notes: item.notes
            )
            task.isDone = item.isDone
            task.created = item.created
            task.completedAt = item.completedAt
            if let uid = item.uid { task.uid = uid }
            task.nextStep = item.nextStep ?? ""
            task.blockedNote = item.blockedNote ?? ""
            task.blockedAt = item.blockedAt
            context.insert(task)
            tasks[item.ref] = task
        }
        for item in backup.events {
            let event = CalendarEvent(
                title: item.title, notes: item.notes, start: item.start, end: item.end, isAllDay: item.isAllDay,
                mode: PlanMode(rawValue: item.modeRaw) ?? .personal, kind: EventKind(rawValue: item.kindRaw) ?? .event,
                recurrence: Recurrence(rawValue: item.recurrenceRaw) ?? .none, reminderMinutes: item.reminderMinutes
            )
            context.insert(event)
            event.task = item.taskRef.flatMap { tasks[$0] }
        }
        for item in backup.attachments {
            if let data = item.data {
                try? data.write(to: AttachmentStore.url(for: item.fileName), options: .atomic)
            }
            let attachment = TaskAttachment(
                name: item.name, kind: AttachmentKind(rawValue: item.kindRaw) ?? .other,
                fileName: item.fileName, extractedText: item.extractedText
            )
            attachment.created = item.created
            context.insert(attachment)
            attachment.task = item.taskRef.flatMap { tasks[$0] }
        }
        for item in backup.sessions {
            let record = FocusSessionRecord(CompletedSession(
                start: item.start, end: item.end, methodName: item.methodName, focusedSeconds: item.focusedSeconds,
                completedCycles: item.completedCycles, taskTitle: item.taskTitle, taskID: item.taskID,
                methodID: item.methodID ?? "", mode: item.modeRaw ?? "", plannedFocusMinutes: item.plannedFocusMinutes ?? 0,
                endedEarly: item.endedEarly ?? false, abandonedAfterMinutes: item.abandonedAfterMinutes ?? 0,
                pauses: item.pauseCount ?? 0, leaves: item.leaveCount ?? 0, awaySeconds: item.awaySeconds ?? 0,
                skippedBreaks: item.skippedBreaks ?? 0, isStarter: item.isStarter ?? false
            ))
            record.focusRating = item.focusRating ?? 0
            context.insert(record)
        }
        for item in backup.distractions ?? [] {
            context.insert(DistractionRecord(
                date: item.date, app: item.app, reason: item.reason, resisted: item.resisted, duringFocus: item.duringFocus,
                kind: AttemptSample.Kind(rawValue: item.kindRaw ?? "") ?? .pause,
                motive: DistractionMotive(rawValue: item.motiveRaw ?? ""), awaySeconds: item.awaySeconds ?? 0
            ))
        }
        for item in backup.captures ?? [] { context.insert(item.makeModel()) }
        try context.save()

        apply(backup.groupSettings, to: AppGroup.defaults)
        apply(backup.localSettings, to: .standard)
        if let chat = backup.chat {
            try? chat.write(to: URL.applicationSupportDirectory.appending(path: "chat.json"), options: .atomic)
        }
        ReminderScheduler.shared.reschedule()
    }

    private static func apply(_ data: Data?, to defaults: UserDefaults) {
        guard let data,
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return }
        for (key, value) in values { defaults.set(value, forKey: key) }
    }
}

/// Envoltorio para exportar una copia con el selector de Archivos.
struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
