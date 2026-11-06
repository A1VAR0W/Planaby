import SwiftUI

/// Remitentes prioritarios y lo que Planaby ha aprendido de tus correcciones en la bandeja.
struct SenderRulesView: View {
    @State private var rules = MessageTriage.rules
    @State private var newSender = ""

    var body: some View {
        Form {
            Section {
                ForEach(rules.prioritySenders, id: \.self) { sender in
                    Text(sender)
                }
                .onDelete { rules.prioritySenders.remove(atOffsets: $0) }
                HStack {
                    TextField("Nombre, teléfono o correo", text: $newSender)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(add)
                    Button("Añadir", action: add)
                        .disabled(newSender.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Siempre importantes")
            } footer: {
                Text("Sus mensajes nunca se quedan en «Puede esperar» ni en «Ruido». Si escriben «urgente», sí se tratan como urgentes.")
            }

            Section {
                if rules.overrides.isEmpty {
                    Text("Cuando muevas un mensaje a otra categoría en la bandeja, los siguientes de esa persona irán ahí directamente.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    ForEach(rules.overrides.keys.sorted(), id: \.self) { sender in
                        LabeledContent(sender, value: MessageCategory(rawValue: rules.overrides[sender] ?? "")?.title ?? "")
                    }
                    .onDelete { offsets in
                        let keys = rules.overrides.keys.sorted()
                        for index in offsets { rules.overrides[keys[index]] = nil }
                    }
                }
            } header: {
                Text("Aprendido de tus correcciones")
            } footer: {
                Text("Desliza para olvidar una regla. Sin estas reglas, decide Apple Intelligence; un mensaje que solo dice «urgente», sin motivo ni plazo, se queda en «Importante».")
            }
        }
        .navigationTitle("Remitentes")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: rules) { _, new in MessageTriage.rules = new }
    }

    private func add() {
        let clean = newSender.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty, !rules.prioritySenders.contains(clean) else { return }
        rules.prioritySenders.append(clean)
        newSender = ""
    }
}
