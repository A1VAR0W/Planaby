import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Filas para añadir capturas (Fotos) o archivos (Archivos) en un formulario.
struct AttachmentAdder: View {
    let onImport: (ImportedAttachment) -> Void
    @State private var showsPhotos = false
    @State private var showsFiles = false
    @State private var importing = 0

    var body: some View {
        Button("Capturas o fotos", systemImage: "photo.on.rectangle") { showsPhotos = true }
        Button("Archivo (PDF, texto, imagen)", systemImage: "doc.badge.plus") { showsFiles = true }
            .attachmentImporters(photos: $showsPhotos, files: $showsFiles, importing: $importing, onImport: onImport)
        if importing > 0 {
            HStack(spacing: Space.s) {
                ProgressView()
                Text("Leyendo el contenido…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

/// Selectores de Fotos y Archivos. Cada adjunto se copia a la app y se lee en el dispositivo
/// (OCR o PDF) antes de entregarlo.
private struct AttachmentImporters: ViewModifier {
    @Binding var photos: Bool
    @Binding var files: Bool
    @Binding var importing: Int
    let onImport: (ImportedAttachment) -> Void
    @State private var photoItems: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $photos, selection: $photoItems, maxSelectionCount: 6, matching: .images)
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                photoItems = []
                Task { await importPhotos(items) }
            }
            .fileImporter(
                isPresented: $files,
                allowedContentTypes: [.pdf, .image, .plainText, .text, .data],
                allowsMultipleSelection: true
            ) { result in
                guard case .success(let urls) = result else { return }
                Task { await importFiles(urls) }
            }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        importing += items.count
        for item in items {
            defer { importing -= 1 }
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            if let attachment = await AttachmentStore.importImage(data, fileExtension: fileExtension) {
                onImport(attachment)
            }
        }
    }

    private func importFiles(_ urls: [URL]) async {
        importing += urls.count
        for url in urls {
            defer { importing -= 1 }
            if let attachment = await AttachmentStore.importFile(at: url) {
                onImport(attachment)
            }
        }
    }
}

extension View {
    func attachmentImporters(
        photos: Binding<Bool>, files: Binding<Bool>, importing: Binding<Int>,
        onImport: @escaping (ImportedAttachment) -> Void
    ) -> some View {
        modifier(AttachmentImporters(photos: photos, files: files, importing: importing, onImport: onImport))
    }
}

/// Un adjunto en una lista: icono, nombre y cuánto texto se ha podido leer.
struct AttachmentLabel: View {
    let name: String
    let kind: AttachmentKind
    let text: String

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: kind.symbol)
                .font(.title3)
                .foregroundStyle(Theme.orange)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .lineLimit(1)
                Text(text.isEmpty ? "Sin texto legible" : "\(text.count) caracteres leídos")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Selector de dificultad de 1 a 5 con su significado debajo.
struct DifficultyField: View {
    @Binding var difficulty: Int

    static func label(_ value: Int) -> String {
        switch value {
        case 1: "Mecánica"
        case 2: "Sencilla"
        case 3: "Normal"
        case 4: "Exigente"
        default: "Muy exigente"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            LabeledContent("Dificultad", value: Self.label(difficulty))
            Picker("Dificultad", selection: $difficulty) {
                ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

/// Resultado de "Estimar con IA" para enseñarlo en el formulario.
struct EstimateSummary: View {
    let estimate: ComplexityEstimate

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label {
                Text("\(FocusStats.format(TimeInterval(estimate.estimatedMinutes * 60))) · \(DifficultyField.label(estimate.difficulty).lowercased())")
                    .font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: "sparkles").foregroundStyle(Theme.orange)
            }
            Text(estimate.reasoning)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, Space.xs)
    }
}

extension ComplexityEstimate {
    /// Los pasos como notas de la tarea.
    var stepsText: String {
        steps.map { "• \($0)" }.joined(separator: "\n")
    }
}
