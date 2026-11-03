import Foundation
import PDFKit
import UniformTypeIdentifiers
import Vision

/// Adjunto recién importado, todavía sin guardar en la base de datos.
struct ImportedAttachment: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let kind: AttachmentKind
    let fileName: String
    let text: String
}

/// Copia capturas y archivos a la carpeta de la app y saca su texto: OCR (Vision) para
/// imágenes, PDFKit para PDF y lectura directa para texto. Todo en el dispositivo.
enum AttachmentStore {
    /// Lo que se le pasa al modelo, que tiene un contexto pequeño.
    static let maxTextPerFile = 2_500

    static var directory: URL {
        let url = URL.applicationSupportDirectory.appending(path: "Attachments", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(for fileName: String) -> URL {
        directory.appending(path: fileName)
    }

    static func delete(_ fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }

    static func importImage(_ data: Data, fileExtension: String = "jpg") async -> ImportedAttachment? {
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        do {
            try data.write(to: url(for: fileName))
        } catch {
            return nil
        }
        let text = await recognizeText(in: data)
        let name = "Captura \(Date.now.formatted(date: .abbreviated, time: .shortened))"
        return ImportedAttachment(name: name, kind: .image, fileName: fileName, text: String(text.prefix(maxTextPerFile)))
    }

    /// Importa un archivo elegido con el selector de Archivos (URL con acceso temporal).
    static func importFile(at source: URL) async -> ImportedAttachment? {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let fileName = "\(UUID().uuidString)-\(source.lastPathComponent)"
        let destination = url(for: fileName)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            return nil
        }

        let type = UTType(filenameExtension: source.pathExtension) ?? .data
        let kind: AttachmentKind
        let text: String
        if type.conforms(to: .pdf) {
            kind = .pdf
            text = PDFDocument(url: destination)?.string ?? ""
        } else if type.conforms(to: .image) {
            kind = .image
            text = "" // Se rellena con OCR más abajo.
        } else if type.conforms(to: .text) {
            kind = .text
            text = (try? String(contentsOf: destination, encoding: .utf8)) ?? ""
        } else {
            kind = .other
            text = ""
        }

        var extracted = text
        if kind == .image, let data = try? Data(contentsOf: destination) {
            extracted = await recognizeText(in: data)
        }
        return ImportedAttachment(
            name: source.lastPathComponent, kind: kind, fileName: fileName,
            text: String(extracted.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxTextPerFile))
        )
    }

    /// Texto de una imagen con el reconocimiento de Vision, en español e inglés.
    static func recognizeText(in data: Data) async -> String {
        var request = RecognizeTextRequest()
        request.recognitionLanguages = [Locale.Language(identifier: "es-ES"), Locale.Language(identifier: "en-US")]
        request.usesLanguageCorrection = true
        guard let observations = try? await request.perform(on: data) else { return "" }
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
