import SwiftUI

/// Configurar el bloqueo en tres pasos: elegir las apps aquí, crear una sola automatización en
/// Atajos (la acción de Planaby ya lleva la app puesta) y comprobar que funciona.
///
/// iOS no deja que una app cree automatizaciones por su cuenta, así que el paso de Atajos
/// lo tiene que hacer la persona; aquí se reduce a tocar, sin escribir nada.
struct BlockSetupView: View {
    @AppStorage(FrictionGuard.Keys.apps) private var appsRaw = ""
    @AppStorage(FrictionGuard.Keys.lastTrigger) private var lastTrigger: Double = 0
    @AppStorage(FrictionGuard.Keys.enabled) private var blocksApps = true
    @AppStorage(FrictionGuard.Keys.scope) private var frictionScope = FrictionScope.focus.rawValue
    @AppStorage(FrictionGuard.Keys.pauseSeconds) private var pauseSeconds = FrictionGuard.defaultPauseSeconds
    @AppStorage(FrictionGuard.Keys.passMinutes) private var passMinutes = FrictionGuard.defaultPassMinutes
    @Environment(\.openURL) private var openURL

    private var chosen: [BlockableApp] {
        appsRaw.split(separator: ",").compactMap { BlockableApp(rawValue: String($0)) }
    }

    private var names: String {
        let list = chosen.map(\.name)
        guard list.count > 1 else { return list.first ?? "las apps que te distraen" }
        return list.dropLast().joined(separator: ", ") + " y " + (list.last ?? "")
    }

    /// La acción que hay que tocar en Atajos.
    private var actionName: String {
        chosen.count == 1 ? "Bloquear \(chosen[0].name)" : "Bloquear la app que se abre"
    }

    var body: some View {
        Form {
            Section {
                Text("Opcional. Sin esto Planaby ya te avisa si sales de la app mientras te concentras. Con una automatización de Atajos, además, te frena con una pausa para respirar al abrir las apps que elijas.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Space.s)], spacing: Space.s) {
                    ForEach(BlockableApp.choosable) { app in
                        chip(app)
                    }
                }
                .padding(.vertical, Space.xs)
            } header: {
                Text("1 · Qué apps te distraen")
            } footer: {
                Text("Si la tuya no está, elige cualquiera y en Atajos marca la tuya: Planaby te frenará igual.")
            }

            Section {
                VStack(alignment: .leading, spacing: Space.s) {
                    Step(number: 1, text: "Pulsa «Abrir Atajos», ve a la pestaña «Automatización» y toca «+».")
                    Step(number: 2, text: "Elige «App», marca \(names), deja «Se abre» y elige «Ejecutar inmediatamente». Pulsa «Siguiente».")
                    Step(number: 3, text: "Toca «Nueva automatización en blanco», busca «Bloquear» y toca «\(actionName)» de Planaby. No hay que escribir nada más.")
                }
                .padding(.vertical, Space.xs)
                Button {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                } label: {
                    Label("Abrir Atajos", systemImage: "arrow.up.forward.app")
                        .font(.headline)
                }
                .disabled(chosen.isEmpty)
            } header: {
                Text("2 · Una automatización, una sola vez")
            } footer: {
                Text("iOS no permite que una app cree la automatización por ti; con estos toques queda hecha para siempre. Después el bloqueo se enciende y apaga con el interruptor «Bloquear apps».")
            }

            Section {
                if lastTrigger > 0 {
                    Label {
                        Text("Funciona · última vez \(Date(timeIntervalSince1970: lastTrigger).formatted(.relative(presentation: .named)))")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.orange)
                    }
                } else {
                    Label("Aún no ha llegado ningún aviso de Atajos.", systemImage: "hourglass")
                        .foregroundStyle(Theme.secondaryText)
                }
                if let app = chosen.first, let url = FrictionGuard.url(for: app.name) {
                    Button("Probar abriendo \(app.name)") { openURL(url) }
                }
                if !blocksApps {
                    Label("«Bloquear apps» está apagado: la automatización llega, pero no te frena.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.orange)
                }
            } header: {
                Text("3 · Comprobar")
            } footer: {
                Text("Abre una de las apps elegidas y vuelve aquí: si aparece «Funciona», ya está. Planaby solo te frena cuando toca según «Cuándo» (por ejemplo, solo concentrándote).")
            }

            Section {
                Toggle("Frenar al abrirlas", isOn: $blocksApps)
                Picker("Cuándo", selection: $frictionScope) {
                    ForEach(FrictionScope.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .disabled(!blocksApps)
                Picker("Respirar", selection: $pauseSeconds) {
                    ForEach([5, 10, 20, 30], id: \.self) { Text("\($0) s").tag($0) }
                }
                Picker("Si la abres igualmente", selection: $passMinutes) {
                    ForEach([1, 5, 10, 15, 30], id: \.self) { Text("\($0) min").tag($0) }
                }
            } header: {
                Text("Cómo frena")
            } footer: {
                Text("Si la abres igualmente, durante ese rato no te vuelve a frenar ni te avisa por salir.")
            }
        }
        .navigationTitle("Frenar apps")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chip(_ app: BlockableApp) -> some View {
        let selected = chosen.contains(app)
        return Button {
            var list = chosen
            if selected { list.removeAll { $0 == app } } else { list.append(app) }
            appsRaw = list.map(\.rawValue).joined(separator: ",")
        } label: {
            Text(app.name)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.black : Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(selected ? Theme.orange : Theme.surface, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: selected)
    }
}

private struct Step: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text("\(number)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.black)
                .frame(width: 20, height: 20)
                .background(Theme.orange, in: .circle)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}
