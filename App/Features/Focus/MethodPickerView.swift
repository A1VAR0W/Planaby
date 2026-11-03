import SwiftUI

/// Lista de métodos. En la hoja de Enfoque elige y se cierra; desde Ajustes sirve para gestionarlos.
struct MethodPickerView: View {
    var dismissesOnSelect = true
    @Environment(MethodLibrary.self) private var library
    @Environment(FocusTimer.self) private var timer
    @Environment(\.dismiss) private var dismiss
    @State private var editing: FocusMethod?
    @State private var deleting: FocusMethod?

    var body: some View {
        List {
            Section {
                ForEach(FocusMethod.builtIns) { row($0) }
            } header: {
                Text("Métodos")
            } footer: {
                if timer.state != nil {
                    Text("Cambiar de método no reinicia la sesión: el bloque actual se ajusta a la nueva duración.")
                }
            }

            Section {
                ForEach(library.custom) { method in
                    row(method)
                        .swipeActions {
                            Button("Borrar", systemImage: "trash", role: .destructive) { deleting = method }
                            Button("Editar", systemImage: "slider.horizontal.3") { editing = method }
                                .tint(Theme.amber)
                        }
                        .contextMenu {
                            Button("Editar", systemImage: "slider.horizontal.3") { editing = method }
                            Button("Borrar", systemImage: "trash", role: .destructive) { deleting = method }
                        }
                }
                Button {
                    editing = .newCustom()
                } label: {
                    Label("Nueva plantilla", systemImage: "plus.circle.fill")
                        .foregroundStyle(Theme.orange)
                }
            } header: {
                Text("Tus plantillas")
            } footer: {
                if !library.custom.isEmpty {
                    Text("Desliza a la izquierda o mantén pulsada una plantilla para editarla o borrarla.")
                }
            }
        }
        .navigationTitle("Métodos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if dismissesOnSelect {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .sheet(item: $editing) { method in
            NavigationStack { CustomMethodEditor(method: method) }
        }
        .confirmationDialog(
            "¿Borrar «\(deleting?.name ?? "")»?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { method in
            Button("Borrar plantilla", role: .destructive) { library.delete(method) }
        } message: { _ in
            Text("Tu historial no se modifica.")
        }
        .sensoryFeedback(.selection, trigger: library.selectedID)
    }

    private func row(_ method: FocusMethod) -> some View {
        let isSelected = method.id == library.selectedID
        return Button {
            timer.select(method)
            if dismissesOnSelect { dismiss() }
        } label: {
            HStack(spacing: Space.m) {
                Text(method.focusMinutes.map { "\($0)" } ?? "∞")
                    .font(.system(.title3, design: .rounded).weight(.medium).monospacedDigit())
                    .foregroundStyle(isSelected ? Color.black : Theme.orange)
                    .frame(width: 48, height: 48)
                    .background(isSelected ? Theme.orange : Theme.orange.opacity(0.14), in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(method.name).font(.body.weight(.medium))
                    Text(method.summary).font(.footnote).foregroundStyle(Theme.secondaryText)
                    Text(method.detail).font(.caption).foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: Space.s)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.orange)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, Space.xs)
            .foregroundStyle(.primary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct CustomMethodEditor: View {
    @Environment(MethodLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State var method: FocusMethod

    var body: some View {
        Form {
            Section {
                TextField("Nombre", text: $method.name)
            } header: {
                Text("Nombre")
            } footer: {
                Text(method.detail)
            }

            Section("Concentración") {
                Toggle("Sin límite (estilo Flowtime)", isOn: openEnded)
                if let focus = method.focusMinutes {
                    Stepper(value: Binding(get: { focus }, set: { method.focusMinutes = $0 }), in: 1...240) {
                        LabeledContent("Duración", value: "\(focus) min")
                    }
                }
            }

            Section("Descansos") {
                if let ratio = method.flowBreakRatio {
                    Stepper(value: Binding(get: { ratio }, set: { method.flowBreakRatio = $0 }), in: 0.05...0.5, step: 0.05) {
                        LabeledContent("Descanso", value: "\(Int((ratio * 100).rounded())) % de lo trabajado")
                    }
                } else {
                    Stepper(value: $method.shortBreakMinutes, in: 1...60) {
                        LabeledContent("Descanso corto", value: "\(method.shortBreakMinutes) min")
                    }
                }
                Stepper(value: $method.cyclesBeforeLongBreak, in: 0...8) {
                    LabeledContent(
                        "Descanso largo",
                        value: method.cyclesBeforeLongBreak == 0 ? "Nunca" : "Cada \(method.cyclesBeforeLongBreak) ciclos"
                    )
                }
                if method.cyclesBeforeLongBreak > 0 {
                    Stepper(value: $method.longBreakMinutes, in: 5...90) {
                        LabeledContent("Duración del largo", value: "\(method.longBreakMinutes) min")
                    }
                }
            }
        }
        .navigationTitle(method.name.isEmpty ? "Nueva plantilla" : method.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar", systemImage: "xmark") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", systemImage: "checkmark") {
                    if method.name.trimmingCharacters(in: .whitespaces).isEmpty { method.name = "Mi plantilla" }
                    library.save(method)
                    dismiss()
                }
            }
        }
    }

    private var openEnded: Binding<Bool> {
        Binding(
            get: { method.focusMinutes == nil },
            set: { isOpen in
                method.focusMinutes = isOpen ? nil : 25
                method.flowBreakRatio = isOpen ? 0.2 : nil
            }
        )
    }
}
