import SwiftUI

/// Ajustes › Plan › IA de planificación: el modelo local (descargar, elegir, activar y borrar).
/// Sin él, o si falla, se planifica con Apple Intelligence.
struct LocalModelView: View {
    @State private var removing: LocalModelChoice?

    var body: some View {
        @Bindable var model = LocalModel.shared
        let selectedInstalled = model.installed.contains(model.choice)

        Form {
            if let problem = model.problem {
                Section {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.orange)
                }
            }

            Section {
                Toggle(isOn: $model.enabled) {
                    Label("Usar la IA local", systemImage: "cpu")
                }
                .disabled(!selectedInstalled)
                if model.phase == .loading || model.phase == .thinking {
                    HStack(spacing: Space.m) {
                        SunsetLoader(phase: .current, size: 44)
                        Text(model.phase == .loading ? "Cargando \(model.choice.title)…" : "Pensando…")
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            } footer: {
                Text(status(model))
            }

            Section {
                ForEach(LocalModelChoice.allCases) { choice in
                    row(choice, model: model)
                }
            } header: {
                Text("Modelo")
            } footer: {
                Text("Qwen3.5 es un modelo abierto que corre en el propio iPhone. Entiende mejor que Apple Intelligence las peticiones largas o con varias cosas, y ve todo tu plan a la vez. Cada petición tarda unos segundos más.")
            }

            Section {
                if model.phase == .downloading {
                    // El sol del icono amanece a medida que se descarga.
                    SunsetLoader(phase: .progress(model.downloadFraction), size: 120)
                        .frame(maxWidth: .infinity)
                    ProgressView(value: model.downloadFraction) {
                        Text("Descargando \(model.choice.title)…")
                    } currentValueLabel: {
                        Text(model.downloadFraction.formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit()
                    }
                    Button("Cancelar la descarga", systemImage: "xmark.circle", role: .cancel) {
                        model.cancelDownload()
                    }
                } else if selectedInstalled {
                    Button("Borrar \(model.choice.title)", systemImage: "trash", role: .destructive) {
                        removing = model.choice
                    }
                } else {
                    Button("Descargar \(model.choice.title) (\(model.choice.sizeText))", systemImage: "arrow.down.circle") {
                        model.download()
                    }
                }
            } footer: {
                Text("Se descarga una vez de Hugging Face. Usa Wi-Fi y mantén Planaby abierta hasta que termine (la pantalla no se apaga mientras tanto); si se corta, al volver a pulsar sigue donde iba. Después funciona sin conexión y nada de lo que escribes sale del iPhone. Si Planaby se cierra al usarlo (falta de memoria), se desactiva sola y te lo dice: entonces prueba el 2B.")
            }
        }
        .navigationTitle("IA de planificación")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "¿Borrar el modelo?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible,
            presenting: removing
        ) { choice in
            Button("Borrar \(choice.title)", role: .destructive) { model.remove(choice) }
        } message: { choice in
            Text("Se liberan unos \(choice.sizeText). Puedes volver a descargarlo cuando quieras.")
        }
    }

    private func row(_ choice: LocalModelChoice, model: LocalModel) -> some View {
        let installed = model.installed.contains(choice)
        return Button {
            model.choice = choice
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(choice.title)
                        .foregroundStyle(.primary)
                    Text(choice.detail)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    Text(installed ? "Descargado · \(choice.sizeText)" : choice.sizeText)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(installed ? Theme.orange : Theme.secondaryText)
                }
                Spacer()
                if model.choice == choice {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.orange)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(model.phase == .downloading)
        .accessibilityAddTraits(model.choice == choice ? .isSelected : [])
    }

    private func status(_ model: LocalModel) -> String {
        if model.isActive {
            switch model.phase {
            case .loading: return "Cargando \(model.choice.title)…"
            case .thinking: return "\(model.choice.title) está pensando…"
            default:
                let memory = model.isReady
                    ? " Ahora está cargado; se suelta tras 3 minutos sin usarlo, al empezar a concentrarte o al salir de Planaby."
                    : " Se carga al empezar a escribir o dictar, no antes."
                return "Planaby planifica con \(model.choice.title), en el iPhone. Si alguna vez falla, lo intenta con Apple Intelligence." + memory
            }
        }
        let apple = AIProvider.unavailableReason == nil
            ? "Mientras, planifica con Apple Intelligence."
            : "Sin ella ni Apple Intelligence, quedan las plantillas."
        if model.installed.contains(model.choice) {
            return "Desactivada. " + apple
        }
        return "Descarga un modelo para activarla. " + apple
    }
}
