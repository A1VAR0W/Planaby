import Foundation
import SwiftData

/// Base de datos de Planaby. Pensada para no perder nada al cerrar o actualizar la app:
/// - Antes de abrirla con una versión nueva, copia los archivos de la base de datos.
/// - Si no se puede abrir, no borra nada: aparta los archivos y arranca con una vacía para
///   que la persona pueda restaurar una copia desde Ajustes.
@MainActor
enum PlanabyStore {
    static let schema = Schema([FocusSessionRecord.self, CalendarEvent.self, PlanTask.self, TaskAttachment.self, DistractionRecord.self])

    /// Aviso para Ajustes si hubo que apartar la base de datos.
    private(set) static var recoveryNote: String?

    static let container: ModelContainer = {
        let configuration = ModelConfiguration(schema: schema)
        snapshotIfNewVersion(of: configuration.url)
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            let folder = move(storeAt: configuration.url, to: "Apartada \(Int(Date.now.timeIntervalSince1970))")
            recoveryNote = "No se pudo abrir la base de datos (\(error.localizedDescription)). Está guardada aparte en «\(folder)»; restaura una copia de seguridad para recuperar tus datos."
            do {
                return try ModelContainer(for: schema, configurations: configuration)
            } catch {
                // Último recurso: en memoria, para que la app abra y se pueda restaurar una copia.
                return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
            }
        }
    }()

    /// Guarda lo pendiente (al pasar a segundo plano).
    static func saveNow() {
        let context = container.mainContext
        if context.hasChanges { try? context.save() }
    }

    // MARK: - Copias de los archivos

    private static let versionKey = "storeVersion"
    private static var backupsFolder: URL {
        URL.applicationSupportDirectory.appending(path: "StoreBackups", directoryHint: .isDirectory)
    }

    /// Con cada versión nueva, copia la base de datos tal cual estaba (se guardan las 3 últimas).
    private static func snapshotIfNewVersion(of url: URL) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let previous = UserDefaults.standard.string(forKey: versionKey)
        defer { UserDefaults.standard.set(version, forKey: versionKey) }
        guard previous != version, FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }

        let target = backupsFolder.appending(path: "Antes de \(version)", directoryHint: .isDirectory)
        let manager = FileManager.default
        try? manager.removeItem(at: target)
        try? manager.createDirectory(at: target, withIntermediateDirectories: true)
        for file in storeFiles(at: url) {
            try? manager.copyItem(at: file, to: target.appending(path: file.lastPathComponent))
        }

        let all = (try? manager.contentsOfDirectory(at: backupsFolder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let sorted = all.sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a > b
        }
        sorted.dropFirst(3).forEach { try? manager.removeItem(at: $0) }
    }

    private static func move(storeAt url: URL, to name: String) -> String {
        let target = backupsFolder.appending(path: name, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for file in storeFiles(at: url) {
            try? FileManager.default.moveItem(at: file, to: target.appending(path: file.lastPathComponent))
        }
        return name
    }

    /// La base de datos y sus archivos auxiliares (-wal, -shm).
    private static func storeFiles(at url: URL) -> [URL] {
        [url, URL(filePath: url.path(percentEncoded: false) + "-wal"), URL(filePath: url.path(percentEncoded: false) + "-shm")]
            .filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }
}
