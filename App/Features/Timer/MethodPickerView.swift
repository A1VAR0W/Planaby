import SwiftUI

struct MethodPickerView: View {
    @Environment(MethodLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var editing: FocusMethod?

    var body: some View {
        List {
            Section {
                ForEach(FocusMethod.builtIns) { row($0) }
            }
            Section("Tus plantillas") {
                ForEach(library.custom) { method in
                    row(method)
                        .swipeActions {
                            Button("Borrar", systemImage: "trash", role: .destructive) { library.delete(method) }
                            Button("Editar", systemImage: "slider.horizontal.3") { editing = method }
                        }
                }
                Button("Nueva plantilla", systemImage: "plus") { editing = .newCustom() }
            }
        }
        .navigationTitle("Método")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Listo", systemImage: "checkmark") { dismiss() }
            }
        }
        .sheet(item: $editing) { method in
            NavigationStack { CustomMethodEditor(method: method) }
        }
    }

    private func row(_ method: FocusMethod) -> some View {
        Button {
            library.selectedID = method.id
            dismiss()
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(method.name).font(.body.weight(.medium))
                    Text(method.summary).font(.footnote).foregroundStyle(.secondary)
                    Text(method.detail).font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
                if method.id == library.selectedID {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.focus)
                }
            }
            .padding(.vertical, 4)
            .foregroundStyle(.primary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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
            }

            Section("Concentración") {
                Toggle("Sin límite (estilo Flowtime)", isOn: openEnded)
                if let focus = method.focusMinutes {
                    Stepper("\(focus) min", value: Binding(get: { focus }, set: { method.focusMinutes = $0 }), in: 1...240)
                }
            }

            Section("Descansos") {
                if let ratio = method.flowBreakRatio {
                    Stepper(
                        "\(Int((ratio * 100).rounded())) % de lo trabajado",
                        value: Binding(get: { ratio }, set: { method.flowBreakRatio = $0 }),
                        in: 0.05...0.5, step: 0.05
                    )
                } else {
                    Stepper("Corto · \(method.shortBreakMinutes) min", value: $method.shortBreakMinutes, in: 1...60)
                }
                Stepper(
                    method.cyclesBeforeLongBreak == 0 ? "Sin descanso largo" : "Largo cada \(method.cyclesBeforeLongBreak) ciclos",
                    value: $method.cyclesBeforeLongBreak, in: 0...8
                )
                if method.cyclesBeforeLongBreak > 0 {
                    Stepper("Largo · \(method.longBreakMinutes) min", value: $method.longBreakMinutes, in: 5...90)
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
