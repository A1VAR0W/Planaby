import SwiftUI

/// Apps permitidas durante la concentración. Al tocar una, Planaby la abre y la salida queda
/// autorizada: el tiempo sigue corriendo, no llegan avisos de «vuelve» y al volver no se apunta
/// nada. Solo si se pasa del límite elegido vuelve a contar como distracción.
struct AllowedAppsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(AllowedApps.Keys.chosen) private var chosenRaw = ""
    @AppStorage(AllowedApps.Keys.limit) private var limit = AllowedApps.defaultLimit
    @State private var custom = AllowedApps.custom()
    @State private var failed: AllowedApp?
    @State private var manual: AllowedApp?

    private var apps: [AllowedApp] {
        let ids = Set(chosenRaw.split(separator: ",").map(String.init))
        return AllowedApps.catalog.filter { ids.contains($0.id) } + custom
    }

    var body: some View {
        List {
            if apps.isEmpty {
                Section {
                    Text("Todavía no has elegido ninguna. Marca las apps que necesitas para trabajar (Teams, el correo, Notas…) y podrás abrirlas desde aquí sin que cuente como distracción.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            } else {
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Space.s)], spacing: Space.s) {
                        ForEach(apps) { app in
                            Button { open(app) } label: {
                                VStack(spacing: Space.xs) {
                                    Image(systemName: app.symbol)
                                        .font(.title2)
                                        .foregroundStyle(Theme.orange)
                                        .frame(height: 30)
                                    Text(app.name)
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity, minHeight: 76)
                                .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 16))
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Abrir \(app.name)")
                        }
                    }
                    .padding(.vertical, Space.xs)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text(limit > 0
                        ? "El tiempo sigue corriendo y no cuenta como distracción durante \(limit) min. Si te pasas, vuelven los avisos."
                        : "El tiempo sigue corriendo y no cuenta como distracción.")
                }
            }

            Section {
                Button {
                    LeaveGuard.shared.allow("otra app")
                    manual = AllowedApp(id: "manual", name: "otra app", url: "")
                } label: {
                    Label("Voy a otra app permitida", systemImage: "arrow.up.forward.app")
                }
                NavigationLink {
                    AllowedAppsSettingsView()
                } label: {
                    Label("Elegir apps permitidas", systemImage: "slider.horizontal.3")
                }
            } footer: {
                Text("«Voy a otra app permitida» sirve para cualquier app que no esté en la lista: tócalo y sal de Planaby en los próximos 20 segundos.")
            }
        }
        .navigationTitle("Apps permitidas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cerrar", systemImage: "xmark") { dismiss() }
            }
        }
        .onAppear { custom = AllowedApps.custom() }
        .alert("No se pudo abrir \(failed?.name ?? "")", isPresented: Binding(get: { failed != nil }, set: { if !$0 { failed = nil } })) {
            Button("Vale") {}
        } message: {
            Text("Puede que no esté instalada. La salida sigue autorizada 20 segundos: ábrela tú desde la pantalla de inicio.")
        }
        .alert("Salida autorizada", isPresented: Binding(get: { manual != nil }, set: { if !$0 { manual = nil } })) {
            Button("Vale") { dismiss() }
        } message: {
            Text("Sal de Planaby en los próximos 20 segundos y abre la app que necesites. El tiempo sigue corriendo.")
        }
    }

    private func open(_ app: AllowedApp) {
        LeaveGuard.shared.allow(app.name)
        guard !app.url.isEmpty, let url = URL(string: app.url) else {
            manual = app
            return
        }
        openURL(url) { opened in
            if opened { dismiss() } else { failed = app }
        }
    }
}

/// Ajustes: qué apps se permiten, cuánto rato y las añadidas a mano.
struct AllowedAppsSettingsView: View {
    @AppStorage(AllowedApps.Keys.chosen) private var chosenRaw = ""
    @AppStorage(AllowedApps.Keys.limit) private var limit = AllowedApps.defaultLimit
    @State private var custom = AllowedApps.custom()
    @State private var newName = ""
    @State private var newScheme = ""

    private var chosen: Set<String> { Set(chosenRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        Form {
            Section {
                Text("Las apps que necesitas mientras te concentras. Ábrelas desde «Apps permitidas» en la pantalla de Enfoque: el tiempo sigue corriendo y no cuenta como distracción. Salir a cualquier otra app sí avisa.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }

            Section {
                Picker(selection: $limit) {
                    ForEach(AllowedApps.limitOptions, id: \.self) { minutes in
                        Text(minutes == 0 ? "Sin límite" : "\(minutes) min").tag(minutes)
                    }
                } label: {
                    Label("Tiempo permitido", systemImage: "hourglass")
                }
            } footer: {
                Text(limit == 0 ? "Puedes estar el rato que haga falta." : "Pasado ese rato vuelven los avisos, y lo que sobre cuenta como distracción.")
            }

            Section("Apps") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Space.s)], spacing: Space.s) {
                    ForEach(AllowedApps.catalog) { app in
                        let isOn = chosen.contains(app.id)
                        Button { toggle(app) } label: {
                            HStack(spacing: Space.xs) {
                                Image(systemName: isOn ? "checkmark.circle.fill" : app.symbol)
                                    .foregroundStyle(isOn ? Theme.orange : Theme.secondaryText)
                                Text(app.name)
                                    .font(.footnote.weight(.medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, Space.s)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(isOn ? Theme.orange.opacity(0.16) : Color.white.opacity(0.06), in: .rect(cornerRadius: 14))
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(app.name)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
                .padding(.vertical, Space.xs)
            }

            Section {
                ForEach(custom) { app in
                    LabeledContent(app.name, value: app.url.isEmpty ? "Se abre a mano" : app.url)
                }
                .onDelete { offsets in
                    custom.remove(atOffsets: offsets)
                    AllowedApps.saveCustom(custom)
                }
                TextField("Nombre de la app", text: $newName)
                TextField("Esquema (opcional), p. ej. miapp://", text: $newScheme)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("Añadir") { add() }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("Otra app")
            } footer: {
                Text("Si no sabes el esquema, déjalo vacío: al tocarla, Planaby autoriza la salida y la abres tú.")
            }
        }
        .navigationTitle("Apps permitidas")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ app: AllowedApp) {
        var ids = chosen
        if ids.contains(app.id) { ids.remove(app.id) } else { ids.insert(app.id) }
        chosenRaw = AllowedApps.catalog.map(\.id).filter(ids.contains).joined(separator: ",")
    }

    private func add() {
        guard let app = AllowedApps.makeCustom(name: newName, scheme: newScheme), !custom.contains(where: { $0.id == app.id }) else { return }
        custom.append(app)
        AllowedApps.saveCustom(custom)
        newName = ""
        newScheme = ""
    }
}
