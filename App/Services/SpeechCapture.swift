@preconcurrency import AVFoundation
import Foundation
import Observation
@preconcurrency import Speech

/// Dictado en español con el reconocimiento de voz del iPhone. Usa el servidor de Apple, que entiende
/// mejor fechas, horas y nombres; sin conexión pasa solo al reconocimiento en el dispositivo.
/// Se para solo tras una pausa larga, al pulsar Listo, si no se dice nada en 10 s o a los 60 s.
@Observable
@MainActor
final class SpeechCapture {
    enum Failure: Error {
        case denied, unavailable, audio

        var message: String {
            switch self {
            case .denied: "Planaby necesita permiso para el micrófono y el reconocimiento de voz. Actívalo en Ajustes › Apps › Planaby."
            case .unavailable: "El reconocimiento de voz no está disponible ahora mismo."
            case .audio: "No se pudo usar el micrófono. Prueba otra vez."
            }
        }
    }

    private(set) var transcript = ""
    private(set) var isListening = false
    /// Volumen de 0 a 1 para animar el micrófono.
    private(set) var level: Double = 0

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var lastChange = Date.now
    @ObservationIgnored private var startedAt = Date.now
    @ObservationIgnored private var finish: CheckedContinuation<String, Never>?
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    /// La petición en curso; el micrófono escribe aquí (se cambia al pasar al dispositivo).
    @ObservationIgnored private let sink = RequestSink()
    /// Lo reconocido antes de que el reconocedor empezara de nuevo tras una pausa.
    @ObservationIgnored private var committed = ""
    /// Último resultado parcial del reconocedor (sin lo ya fijado).
    @ObservationIgnored private var partial = ""
    @ObservationIgnored private var onDevice = false
    /// Cómo estaba el audio antes de escuchar, para dejarlo igual al terminar.
    @ObservationIgnored private var previousAudio: (category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions)?

    /// Pausa con la que se da por terminado: deja pensar a media frase.
    private static let silence: TimeInterval = 2.6
    private static let maximum: TimeInterval = 60
    /// Si no se dice nada en este tiempo, se deja de escuchar.
    private static let waitForSpeech: TimeInterval = 10
    /// Palabras que ayudan a acertar con tareas y fechas.
    private static let vocabulary = [
        "Planaby", "Trabajo", "Normal", "bloque", "bloques", "entrega", "entregar", "reunión", "cita", "examen",
        "recordatorio", "recuérdame", "pasado mañana", "esta tarde", "esta noche", "a primera hora",
        "lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo",
        "media hora", "una hora", "dos horas", "tres horas", "minutos", "prioridad alta", "urgente", "fecha límite",
    ]

    /// Escucha hasta el silencio y devuelve lo dictado (vacío si no se dijo nada o se canceló).
    /// `keepingMusic`: la música de otras apps (Spotify) sigue sonando, más baja, en vez de
    /// pararse; al terminar se deja el audio como estaba. Lo usa la captura rápida para no romper
    /// la sesión de concentración.
    func listen(keepingMusic: Bool = false) async throws -> String {
        guard !isListening else { return "" }
        guard await Self.authorize() else { throw Failure.denied }
        guard let recognizer = Self.makeRecognizer(), recognizer.isAvailable else { throw Failure.unavailable }
        self.recognizer = recognizer
        onDevice = false
        let request = makeRequest(onDevice: false)
        sink.set(request)

        do {
            let session = AVAudioSession.sharedInstance()
            previousAudio = (session.category, session.mode, session.categoryOptions)
            if keepingMusic {
                try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker, .allowBluetoothA2DP])
            } else {
                try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            }
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            Self.installTap(on: engine.inputNode, sink: sink) { [weak self] level in
                Task { @MainActor in self?.level = level }
            }
            engine.prepare()
            try engine.start()
        } catch {
            stopAudio()
            throw Failure.audio
        }

        self.request = request
        transcript = ""
        committed = ""
        partial = ""
        level = 0
        isListening = true
        lastChange = .now
        startedAt = .now
        startRecognition(request)

        return await withCheckedContinuation { continuation in
            finish = continuation
            Task { await watchSilence() }
        }
    }

    /// Termina y se queda con lo dictado hasta ahora.
    func stop() { complete(with: transcript) }

    /// Termina sin usar nada.
    func cancel() { complete(with: "") }

    // MARK: - Interno

    private func makeRequest(onDevice: Bool) -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = onDevice
        request.contextualStrings = Self.vocabulary
        return request
    }

    private func startRecognition(_ request: SFSpeechAudioBufferRecognitionRequest) {
        guard let recognizer else { return }
        task = Self.recognize(with: recognizer, request: request) { [weak self] text, isFinal, failed in
            Task { @MainActor in self?.received(text, isFinal: isFinal, failed: failed) }
        }
    }

    private func received(_ text: String?, isFinal: Bool, failed: Bool) {
        guard isListening else { return }
        // Sin conexión, el servidor falla enseguida: se sigue escuchando en el dispositivo.
        if failed, !onDevice, transcript.isEmpty, recognizer?.supportsOnDeviceRecognition == true {
            onDevice = true
            task?.cancel()
            let request = makeRequest(onDevice: true)
            self.request = request
            sink.set(request)
            startRecognition(request)
            return
        }
        if let text, !text.isEmpty {
            // Tras una pausa el reconocedor a veces empieza de cero: se conserva lo anterior.
            if !partial.isEmpty, text.count < partial.count / 2,
               !partial.lowercased().hasPrefix(String(text.lowercased().prefix(4))) {
                committed += partial + " "
            }
            partial = text
            let joined = committed + text
            if joined != transcript {
                transcript = joined
                lastChange = .now
            }
        }
        if isFinal || failed { complete(with: transcript) }
    }

    private func watchSilence() async {
        while isListening {
            try? await Task.sleep(for: .milliseconds(300))
            let quiet = Date.now.timeIntervalSince(lastChange)
            let elapsed = Date.now.timeIntervalSince(startedAt)
            if (!transcript.isEmpty && quiet > Self.silence) || (transcript.isEmpty && elapsed > Self.waitForSpeech) || elapsed > Self.maximum {
                complete(with: transcript)
            }
        }
    }

    private func complete(with text: String) {
        guard isListening else { return }
        isListening = false
        level = 0
        sink.set(nil)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        stopAudio()
        finish?.resume(returning: text.trimmingCharacters(in: .whitespacesAndNewlines))
        finish = nil
    }

    private func stopAudio() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        // El micrófono queda libre y el audio vuelve a como estaba (p. ej. los avisos de fase).
        if let previous = previousAudio {
            try? session.setCategory(previous.category, mode: previous.mode, options: previous.options)
            previousAudio = nil
        }
    }

    // Lo que corre en los hilos de audio y de voz va fuera del actor principal.

    private nonisolated static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    /// Español del iPhone si está en español (es-MX, es-AR…); si no, de España.
    private static func makeRecognizer() -> SFSpeechRecognizer? {
        let current = Locale.current
        if current.language.languageCode == .spanish, let recognizer = SFSpeechRecognizer(locale: current) {
            return recognizer
        }
        return SFSpeechRecognizer(locale: Locale(identifier: "es-ES")) ?? SFSpeechRecognizer()
    }

    private nonisolated static func installTap(
        on input: AVAudioInputNode, sink: RequestSink,
        level: @escaping @Sendable (Double) -> Void
    ) {
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            sink.append(buffer)
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var sum: Float = 0
            for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
            let rms = sqrt(sum / Float(buffer.frameLength))
            level(min(1, Double(rms) * 12))
        }
    }

    private nonisolated static func recognize(
        with recognizer: SFSpeechRecognizer, request: SFSpeechAudioBufferRecognitionRequest,
        update: @escaping @Sendable (String?, Bool, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            update(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }
}

/// Une el hilo de audio con la petición de voz actual, que puede cambiar a media escucha.
private final class RequestSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.withLock { self.request = request }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { request }?.append(buffer)
    }
}
