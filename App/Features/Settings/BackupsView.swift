import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Ajustes › Copias de seguridad: las copias diarias, hacer una ahora, exportarla a Archivos o
/// iCloud Drive y restaurar.
struct BackupsView: View {
    @Environment(\.modelContext) private var context
    @State private var backups: [URL] = []
    @State private var exporting: BackupDocument?
    @State private var importing = false
    @State private var restoring: URL?
    @State private var message: String?

    var body: some View {
        Form {
            if let note = PlanabyStore.recoveryNote {
                Section {
                    Label(note, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.orange)
                }
            }

            Section {
                Button("Hacer una copia ahora", systemImage: "externaldrive.badge.plus") {
                    do {
                        try BackupService.writeBackup(context: context)
                        message = "Copia guardada."
                    } catch {
                        message = "No se pudo guardar la copia: \(error.localizedDescription)"
                    }
                    reload()
                }
                Button("Exportar a Archivos o iCloud Drive", systemImage: "square.and.arrow.up") {
                    if let data = try? JSONEncoder().encode(BackupService.makeBackup(context: context)) {
                        exporting = BackupDocument(data: data)
                    }
                }
                Button("Restaurar desde un archivo", systemImage: "square.and.arrow.down") { importing = true }
            } footer: {
                Text("Planaby guarda todo al cerrarse y, cada día que la usas, una copia completa (tareas, calendario, adjuntos, sesiones, ajustes y conversación) en Archivos › En mi iPhone › Planaby. Al actualizar la app no se pierde nada; exporta una copia a iCloud Drive si vas a borrarla o reinstalarla.")
            }

            Section("En este iPhone") {
                if backups.isEmpty {
                    Text("Todavía no hay copias.")
                        .foregroundStyle(Theme.secondaryText)
                }
                ForEach(backups, id: \.self) { url in
                    Button {
                        restoring = url
                    } label: {
                        LabeledContent {
                            Text(size(of: url))
                                .monospacedDigit()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.deletingPathExtension().lastPathComponent)
                                Text(BackupService.modified(url).formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityHint("Restaurar esta copia")
                }
            }
        }
        .navigationTitle("Copias de seguridad")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("Vale", role: .cancel) {}
        }
        .confirmationDialog(
            "¿Restaurar esta copia?",
            isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }),
            titleVisibility: .visible,
            presenting: restoring
        ) { url in
            Button("Restaurar y sustituir lo actual", role: .destructive) { restore(url) }
        } message: { _ in
            Text("Se sustituyen tus tareas, calendario, sesiones y ajustes por los de la copia. Antes se guarda una copia de lo que tienes ahora.")
        }
        .fileExporter(
            isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
            document: exporting,
            contentType: .json,
            defaultFilename: "Planaby \(Date.now.formatted(.iso8601.year().month().day()))"
        ) { result in
            if case .failure(let error) = result { message = "No se pudo exportar: \(error.localizedDescription)" }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { restoring = url }
        }
    }

    private func reload() {
        backups = BackupService.savedBackups()
    }

    private func restore(_ url: URL) {
        do {
            try BackupService.restore(from: url, context: context)
            message = "Copia restaurada. Cierra Planaby del todo y vuelve a abrirla para aplicar también los ajustes."
        } catch {
            message = error.localizedDescription
        }
        reload()
    }

    private func size(of url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
