import SwiftUI

/// Apps permitidas durante la concentración. Al tocar una, Planaby da un pase y la abre: el
/// tiempo sigue corriendo, no llegan avisos de «vuelve» y al volver no se apunta nada mientras
/// dure el pase. iOS no dice qué app se usa: lo que se sabe es que la salida estaba autorizada.
struct AllowedAppsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(ModeController.self) private var modes
    @AppStorage(AllowedApps.Keys.limit) private var storedLimit = AllowedApps.defaultLimit
    /// Duración de este pase (empieza en la de Ajustes; cambiarla aquí vale solo para esta vez).
    @State private var minutes = AllowedApps.limit()
    @State private var apps: [AllowedApp] = []
    @State private var failed: AllowedApp?
    @State private var manual: AllowedApp?

    var body: some View {
        List {
            Section {
                Picker("Durante", selection: $minutes) {
                    ForEach(AllowedApps.limitOptions, id: \.self) { option in
                        Text(option == 0 ? "Sesión" : "\(option) min").tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } header: {
                Text("Cuánto rato")
            } footer: {
                Text(minutes > 0
                    ? "Durante \(minutes) min el tiempo sigue corriendo y salir no cuenta como distracción. Después vuelven los avisos."
                    : "Hasta que termine esta sesión, salir de Planaby no cuenta como distracción ni avisa.")
            }

            if apps.isEmpty {
                Section {
                    Text("No hay apps permitidas en el plan \(modes.mode.title). Elige las que necesitas (Teams, el correo, Notas…) y podrás abrirlas desde aquí.")
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
                } header: {
                    Text("Plan \(modes.mode.title)")
                }
            }

            Section {
                Button {
                    LeaveGuard.shared.allow("otra app", minutes: minutes)
                    manual = AllowedApp(id: "manual", name: "otra app", url: "")
                } label: {
                    Label("Voy a otra app de trabajo", systemImage: "arrow.up.forward.app")
                }
                NavigationLink {
                    AllowedAppsSettingsView()
                } label: {
                    Label("Elegir apps permitidas", systemImage: "slider.horizontal.3")
                }
            } footer: {
                Text("Planaby no puede ver qué app abres: autoriza la salida y confía en ti. Si sales sin pasar por aquí, avisa como siempre.")
            }
        }
        .navigationTitle("Apps permitidas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cerrar", systemImage: "xmark") { dismiss() }
            }
        }
        .onAppear { apps = AllowedApps.chosen(modes.mode) }
        .alert("No se pudo abrir \(failed?.name ?? "")", isPresented: Binding(get: { failed != nil }, set: { if !$0 { failed = nil } })) {
            Button("Vale") { dismiss() }
        } message: {
            Text("Puede que no esté instalada o que iOS no deje abrirla desde aquí. La salida sigue autorizada \(durationText): ábrela tú desde la pantalla de inicio.")
        }
        .alert("Salida autorizada", isPresented: Binding(get: { manual != nil }, set: { if !$0 { manual = nil } })) {
            Button("Vale") { dismiss() }
        } message: {
            Text("Sal de Planaby y abre la app que necesites. Tienes permiso \(durationText) y el tiempo sigue corriendo.")
        }
    }

    private var durationText: String {
        minutes > 0 ? "durante \(minutes) min" : "hasta terminar la sesión"
    }

    private func open(_ app: AllowedApp) {
        LeaveGuard.shared.allow(app.name, minutes: minutes)
        guard !app.url.isEmpty, let url = URL(string: app.url) else {
            manual = app
            return
        }
        openURL(url) { opened in
            if opened { dismiss() } else { failed = app }
        }
    }
}

/// El pase en vigor, a la vista en Enfoque: qué se autorizó, hasta cuándo, y cómo terminarlo.
struct AllowedPassChip: View {
    private var guardian: LeaveGuard { .shared }

    var body: some View {
        // Basta con mirar de vez en cuando: solo cambia al caducar.
        TimelineView(.periodic(from: .now, by: 20)) { context in
            chip(at: context.date)
        }
    }

    @ViewBuilder
    private func chip(at now: Date) -> some View {
        if let pass = guardian.currentPass(at: now) {
            HStack(spacing: Space.xs) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(Theme.orange)
                Text(Self.text(pass))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Button("Terminar") { guardian.endPass() }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.orange)
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Terminar la salida permitida")
            }
            .padding(.leading, Space.m)
            .padding(.trailing, Space.xs)
            .background(Color.white.opacity(0.07), in: .capsule)
            .transition(.opacity)
            .accessibilityElement(children: .contain)
        }
    }

    static func text(_ pass: AllowedPass) -> String {
        let name = pass.app == "otra app" ? "Salida permitida" : "\(pass.app) permitido"
        guard let expiry = pass.expiry else { return name + " esta sesión" }
        return name + " hasta las " + expiry.formatted(date: .omitted, time: .shortened)
    }
}

/// Ajustes: qué apps se permiten en cada plan, cuánto rato y las añadidas a mano.
struct AllowedAppsSettingsView: View {
    @Environment(ModeController.self) private var modes
    @AppStorage(AllowedApps.Keys.limit) private var limit = AllowedApps.defaultLimit
    @State private var mode: PlanMode = .work
    @State private var chosen: Set<String> = []
    @State private var custom = AllowedApps.custom()
    @State private var newName = ""
    @State private var newScheme = ""

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
                        Text(AllowedApps.limitTitle(minutes)).tag(minutes)
                    }
                } label: {
                    Label("Tiempo permitido", systemImage: "hourglass")
                }
            } footer: {
                Text(limit == 0
                    ? "Una vez autorizada la salida, ya no se avisa ni se apunta nada hasta que acabe la sesión."
                    : "Pasado ese rato vuelven los avisos, y lo que sobre cuenta como distracción. Al abrir una app puedes elegir otro rato para esa vez.")
            }

            Section {
                Picker("Plan", selection: $mode) {
                    ForEach(PlanMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Space.s)], spacing: Space.s) {
                    ForEach(AllowedApps.catalog + custom) { app in
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
            } header: {
                Text("Apps de cada plan")
            } footer: {
                Text("Cada plan tiene las suyas: en Enfoque se enseñan las del plan en el que estés.")
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
        .onAppear {
            mode = modes.mode
            chosen = AllowedApps.chosenIDs(mode)
        }
        .onChange(of: mode) { _, new in chosen = AllowedApps.chosenIDs(new) }
    }

    private func toggle(_ app: AllowedApp) {
        if chosen.contains(app.id) { chosen.remove(app.id) } else { chosen.insert(app.id) }
        AllowedApps.setChosen(chosen, for: mode)
    }

    private func add() {
        guard let app = AllowedApps.makeCustom(name: newName, scheme: newScheme), !custom.contains(where: { $0.id == app.id }) else { return }
        custom.append(app)
        AllowedApps.saveCustom(custom)
        // Lo que se añade se permite ya en el plan que se está viendo.
        chosen.insert(app.id)
        AllowedApps.setChosen(chosen, for: mode)
        newName = ""
        newScheme = ""
    }
}
