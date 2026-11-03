@preconcurrency import AVFoundation
import Foundation
import Observation
@preconcurrency import Speech

/// Dictado en español con el reconocimiento de voz del iPhone (en el dispositivo si es posible).
/// Se para solo tras un silencio, al pulsar Listo, si no se dice nada en 8 s o a los 45 s.
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

    private static let silence: TimeInterval = 1.8
    private static let maximum: TimeInterval = 45
    /// Si no se dice nada en este tiempo, se deja de escuchar.
    private static let waitForSpeech: TimeInterval = 8

    /// Escucha hasta el silencio y devuelve lo dictado (vacío si no se dijo nada o se canceló).
    func listen() async throws -> String {
        guard await Self.authorize() else { throw Failure.denied }
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-ES")) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else { throw Failure.unavailable }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        request.contextualStrings = ["Planaby", "Trabajo", "Normal", "bloque", "entrega"]

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            Self.installTap(on: engine.inputNode, request: request) { [weak self] level in
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
        level = 0
        isListening = true
        lastChange = .now
        startedAt = .now
        task = Self.recognize(with: recognizer, request: request) { [weak self] text, isFinal in
            Task { @MainActor in self?.received(text, isFinal: isFinal) }
        }

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

    private func received(_ text: String?, isFinal: Bool) {
        guard isListening else { return }
        if let text, text != transcript {
            transcript = text
            lastChange = .now
        }
        if isFinal { complete(with: transcript) }
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
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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

    private nonisolated static func installTap(
        on input: AVAudioInputNode, request: SFSpeechAudioBufferRecognitionRequest,
        level: @escaping @Sendable (Double) -> Void
    ) {
        nonisolated(unsafe) let request = request
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var sum: Float = 0
            for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
            let rms = sqrt(sum / Float(buffer.frameLength))
            level(min(1, Double(rms) * 12))
        }
    }

    private nonisolated static func recognize(
        with recognizer: SFSpeechRecognizer, request: SFSpeechAudioBufferRecognitionRequest,
        update: @escaping @Sendable (String?, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            update(result?.bestTranscription.formattedString, (result?.isFinal ?? false) || error != nil)
        }
    }
}
