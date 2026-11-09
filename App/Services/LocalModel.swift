import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Observation
import os
import Tokenizers
import UIKit

// IA local en el iPhone: un modelo abierto (Qwen3.5, de Alibaba, licencia Apache 2.0) que corre
// con MLX, la librería de Apple para la GPU del iPhone. Es bastante más capaz que el modelo de
// Apple Intelligence y tiene mucho más contexto. Se descarga una vez de Hugging Face; después
// funciona sin conexión y nada sale del iPhone.

/// Los modelos que se pueden descargar.
enum LocalModelChoice: String, CaseIterable, Identifiable, Codable, Sendable {
    case qwen4B
    case qwen2B

    var id: String { rawValue }

    /// Repositorio en Hugging Face (versión MLX cuantizada a 4 bits).
    var repo: String {
        switch self {
        case .qwen4B: "mlx-community/Qwen3.5-4B-4bit"
        case .qwen2B: "mlx-community/Qwen3.5-2B-4bit"
        }
    }

    var title: String {
        switch self {
        case .qwen4B: "Qwen3.5 4B"
        case .qwen2B: "Qwen3.5 2B"
        }
    }

    var sizeText: String {
        switch self {
        case .qwen4B: "3,1 GB"
        case .qwen2B: "1,8 GB"
        }
    }

    var approximateBytes: Int64 {
        switch self {
        case .qwen4B: 3_100_000_000
        case .qwen2B: 1_800_000_000
        }
    }

    var detail: String {
        switch self {
        case .qwen4B: "El que mejor entiende lo que pides. Recomendado."
        case .qwen2B: "Más ligero y rápido, pero entiende algo peor. Úsalo si el 4B no cabe en la memoria."
        }
    }
}

enum LocalModelError: LocalizedError {
    case notInstalled
    case noSpace(needed: Int64)
    case download(String)
    case invalidAnswer

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "El modelo local no está descargado. Descárgalo en Ajustes › Plan › IA de planificación."
        case .noSpace(let needed):
            "No hay espacio suficiente: hacen falta unos \(ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)) libres."
        case .download(let reason):
            "No se pudo descargar el modelo: \(reason)"
        case .invalidAnswer:
            "El modelo local no ha dado una respuesta que se pueda leer. Prueba a escribirlo de otra forma."
        }
    }
}

// MARK: - Estado

@Observable
@MainActor
final class LocalModel {
    static let shared = LocalModel()

    enum Phase: Equatable { case idle, downloading, loading, thinking }

    private(set) var phase: Phase = .idle
    /// 0…1 durante la descarga.
    private(set) var downloadFraction: Double = 0
    /// Lo último que salió mal, para enseñarlo en Ajustes.
    private(set) var problem: String?
    private(set) var installed: Set<LocalModelChoice> = []

    var choice: LocalModelChoice {
        didSet {
            defaults.set(choice.rawValue, forKey: Keys.choice)
            unload()
        }
    }

    /// Usar el modelo local para planificar (si está descargado).
    var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: Keys.enabled)
            if enabled { problem = nil } else { unload() }
        }
    }

    /// Se usa para planificar: activado y descargado.
    var isActive: Bool { enabled && installed.contains(choice) }

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var loadedChoice: LocalModelChoice?
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let logger = Logger(subsystem: "com.alvaro.Planaby", category: "IA local")

    private enum Keys {
        static let choice = "localModel.choice"
        static let enabled = "localModel.enabled"
        /// Se apunta mientras el modelo trabaja: si sigue ahí al abrir, la app se cerró (casi
        /// siempre por falta de memoria).
        static let busy = "localModel.busy"
    }

    private init() {
        choice = LocalModelChoice(rawValue: defaults.string(forKey: Keys.choice) ?? "") ?? .qwen4B
        enabled = defaults.bool(forKey: Keys.enabled)
        installed = Set(LocalModelChoice.allCases.filter(LocalModelStore.isInstalled))
        if let crashed = defaults.string(forKey: Keys.busy).flatMap(LocalModelChoice.init(rawValue:)) {
            defaults.removeObject(forKey: Keys.busy)
            defaults.set(false, forKey: Keys.enabled)
            enabled = false
            problem = crashed == .qwen4B
                ? "La última vez Planaby se cerró mientras usaba \(crashed.title), seguramente por falta de memoria. Mientras, planifica con Apple Intelligence. Prueba el modelo 2B o vuelve a activarlo con menos apps abiertas."
                : "La última vez Planaby se cerró mientras usaba \(crashed.title), seguramente por falta de memoria. Mientras, planifica con Apple Intelligence."
        }
        // El modelo ocupa varios GB: se suelta al ir a segundo plano o si iOS pide memoria, y se
        // vuelve a cargar en la siguiente petición.
        let center = NotificationCenter.default
        for name in [UIApplication.didReceiveMemoryWarningNotification, UIApplication.didEnterBackgroundNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { LocalModel.shared.unload() }
            })
        }
    }

    // MARK: Descarga

    func download() {
        guard downloadTask == nil else { return }
        problem = nil
        let choice = self.choice
        phase = .downloading
        downloadFraction = 0
        // La pantalla no se apaga: si Planaby pasa a segundo plano, iOS corta la descarga.
        UIApplication.shared.isIdleTimerDisabled = true
        downloadTask = Task {
            defer {
                UIApplication.shared.isIdleTimerDisabled = false
                downloadTask = nil
                if phase == .downloading { phase = .idle }
            }
            do {
                try await LocalModelStore.download(choice) { fraction in
                    Task { @MainActor in LocalModel.shared.downloadFraction = fraction }
                }
                installed.insert(choice)
                if choice == self.choice { enabled = true }
            } catch {
                guard !Task.isCancelled else { return }
                Self.logger.error("Descarga: \(String(describing: error), privacy: .public)")
                problem = (error as? LocalizedError)?.errorDescription
                    ?? "No se pudo descargar el modelo: \(error.localizedDescription) Vuelve a intentarlo: lo ya descargado no se repite."
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    func remove(_ choice: LocalModelChoice) {
        if loadedChoice == choice { unload() }
        LocalModelStore.remove(choice)
        installed.remove(choice)
        if choice == self.choice { enabled = false }
    }

    // MARK: Uso

    /// Respuesta de texto a unas instrucciones y un mensaje. Carga el modelo si hace falta.
    func generate(instructions: String, prompt: String, maxTokens: Int = 1_500) async throws -> String {
        guard installed.contains(choice) else { throw LocalModelError.notInstalled }
        defaults.set(choice.rawValue, forKey: Keys.busy)
        defer {
            defaults.removeObject(forKey: Keys.busy)
            phase = .idle
        }
        let container = try await loadContainer()
        phase = .thinking
        let session = ChatSession(
            container, instructions: instructions,
            generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0.2, topP: 0.9),
            additionalContext: ["enable_thinking": false]
        )
        return try await session.respond(to: prompt)
    }

    func unload() {
        container = nil
        loadedChoice = nil
    }

    private func loadContainer() async throws -> ModelContainer {
        if let container, loadedChoice == choice { return container }
        unload()
        phase = .loading
        // Como en los ejemplos de MLX: una caché pequeña para no acumular memoria entre peticiones.
        Memory.cacheLimit = 20 * 1024 * 1024
        let loaded = try await LLMModelFactory.shared.loadContainer(
            from: LocalModelStore.directory(for: choice), using: TransformersTokenizerLoader()
        )
        container = loaded
        loadedChoice = choice
        return loaded
    }
}

// MARK: - Archivos

/// Dónde están los modelos y cómo se descargan (Application Support/Modelos, fuera de las copias
/// de iCloud).
enum LocalModelStore {
    struct RemoteFile: Sendable {
        let name: String
        let size: Int64
    }

    static var root: URL { URL.applicationSupportDirectory.appending(path: "Modelos", directoryHint: .isDirectory) }

    static func directory(for choice: LocalModelChoice) -> URL {
        root.appending(path: choice.rawValue, directoryHint: .isDirectory)
    }

    private static func marker(for choice: LocalModelChoice) -> URL {
        directory(for: choice).appending(path: ".completo")
    }

    static func isInstalled(_ choice: LocalModelChoice) -> Bool {
        FileManager.default.fileExists(atPath: marker(for: choice).path(percentEncoded: false))
    }

    static func remove(_ choice: LocalModelChoice) {
        try? FileManager.default.removeItem(at: directory(for: choice))
    }

    /// Descarga lo que falta (pesos, configuración y tokenizador). Lo ya descargado no se repite.
    static func download(_ choice: LocalModelChoice, progress: @escaping @Sendable (Double) -> Void) async throws {
        let directory = directory(for: choice)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)

        let files = try await remoteFiles(for: choice)
        let total = max(1, files.reduce(0) { $0 + $1.size })
        let pending = files.filter { !isComplete($0, in: directory) }
        let needed = pending.reduce(Int64(0)) { $0 + $1.size }
        if let free = try? URL.applicationSupportDirectory
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
            free < needed + 300_000_000 {
            throw LocalModelError.noSpace(needed: needed + 300_000_000)
        }

        var done = total - needed
        progress(Double(done) / Double(total))
        for file in pending {
            try Task.checkCancellation()
            guard let url = URL(string: "https://huggingface.co/\(choice.repo)/resolve/main/\(file.name)") else { continue }
            let base = done
            try await FileDownloader().download(url, to: directory.appending(path: file.name)) { written in
                progress(Double(base + written) / Double(total))
            }
            done += file.size
            progress(Double(done) / Double(total))
        }
        FileManager.default.createFile(atPath: marker(for: choice).path(percentEncoded: false), contents: Data())
    }

    private static func isComplete(_ file: RemoteFile, in directory: URL) -> Bool {
        let path = directory.appending(path: file.name).path(percentEncoded: false)
        guard let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber else { return false }
        return file.size == 0 || size.int64Value == file.size
    }

    /// Los archivos del repositorio que hacen falta (los mismos que descarga MLX).
    private static func remoteFiles(for choice: LocalModelChoice) async throws -> [RemoteFile] {
        guard let url = URL(string: "https://huggingface.co/api/models/\(choice.repo)?blobs=true") else { return [] }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let siblings = object["siblings"] as? [[String: Any]] else {
            throw LocalModelError.download("no se pudo leer la lista de archivos.")
        }
        let files = siblings.compactMap { entry -> RemoteFile? in
            guard let name = entry["rfilename"] as? String, !name.contains("/"),
                  name.hasSuffix(".safetensors") || name.hasSuffix(".json") || name.hasSuffix(".jinja") else { return nil }
            return RemoteFile(name: name, size: (entry["size"] as? NSNumber)?.int64Value ?? 0)
        }
        guard files.contains(where: { $0.name.hasSuffix(".safetensors") }) else {
            throw LocalModelError.download("el repositorio no tiene los pesos del modelo.")
        }
        return files
    }
}

/// Descarga de un archivo grande con progreso (URLSession, mientras Planaby está abierta).
private final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var destination: URL?
    private var task: URLSessionDownloadTask?
    private var progress: (@Sendable (Int64) -> Void)?
    private var reported: Int64 = 0

    func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let task = session.downloadTask(with: url)
                self.lock.withLock {
                    self.continuation = continuation
                    self.destination = destination
                    self.progress = progress
                    self.task = task
                }
                task.resume()
            }
        } onCancel: {
            self.lock.withLock { self.task }?.cancel()
        }
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        // Cada 8 MB, para no inundar la interfaz.
        let handler: (@Sendable (Int64) -> Void)? = lock.withLock {
            guard totalBytesWritten - reported >= 8_000_000 else { return nil }
            reported = totalBytesWritten
            return progress
        }
        handler?(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status), let destination = lock.withLock({ self.destination }) else {
            finish(LocalModelError.download("el servidor respondió \(status)."))
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(nil)
        } catch {
            finish(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(error) }
    }

    private func finish(_ error: Error?) {
        let continuation = lock.withLock {
            let current = self.continuation
            self.continuation = nil
            return current
        }
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }
}

// MARK: - Tokenizador

// Lo mismo que generaría la macro `#huggingFaceTokenizerLoader()` de mlx-swift-lm, escrito a mano
// para no compilar macros: el tokenizador de swift-transformers adaptado al de MLX.

struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
        return TokenizerBridge(upstream)
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    // swift-transformers usa `decode(tokens:)` en vez de `decode(tokenIds:)`.
    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
