import SwiftUI

/// Ajustes › Calendarios externos. Lo principal es suscribirse al enlace de Outlook (incluye las
/// reuniones de Teams): Planaby lo descarga directamente, sin tocar el Calendario de iOS.
struct ExternalCalendarsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var adding = false
    @State private var showsDeviceCalendars = false
    private let external = ExternalCalendars.shared

    var body: some View {
        Form {
            Section {
                ForEach(external.subscriptions) { subscription in
                    NavigationLink {
                        SubscriptionEditor(subscription: subscription)
                    } label: {
                        SubscriptionRow(subscription: subscription, color: external.color(for: subscription))
                    }
                }
                .onDelete { offsets in
                    offsets.map { external.subscriptions[$0] }.forEach(external.remove)
                }
                Button("Añadir calendario de Outlook", systemImage: "plus") { adding = true }
                if !external.subscriptions.isEmpty {
                    Button {
                        Task { await external.syncAll() }
                    } label: {
                        HStack {
                            Label("Actualizar ahora", systemImage: "arrow.clockwise")
                            Spacer()
                            if external.isSyncing { ProgressView() }
                        }
                    }
                    .disabled(external.isSyncing)
                }
            } header: {
                Text("Outlook y Teams")
            } footer: {
                Text("Planaby descarga tu calendario directamente de Microsoft al abrirse (como mucho cada 15 minutos) y guarda una copia en el iPhone. No se añade nada al Calendario de iOS y Planaby no escribe en Outlook.")
            }

            Section {
                HowToStep(number: 1, text: "Entra en outlook.office.com desde un navegador (también vale en el ordenador).")
                HowToStep(number: 2, text: "Configuración (⚙) › Calendario › Calendarios compartidos.")
                HowToStep(number: 3, text: "En «Publicar un calendario», elige Calendario y «Puede ver todos los detalles» (o «Puede ver cuándo estoy ocupado» si prefieres no compartir títulos), y pulsa Publicar.")
                HowToStep(number: 4, text: "Copia el enlace ICS y pégalo en «Añadir calendario de Outlook».")
            } header: {
                Text("Cómo conseguir el enlace")
            } footer: {
                Text("Las reuniones de Teams están en ese calendario, así que llegan solas. Si no aparece «Publicar un calendario», tu empresa lo tiene desactivado. Trata el enlace como una contraseña: quien lo tenga puede ver tu calendario; en Outlook puedes dejar de publicarlo cuando quieras.")
            }

            Section {
                DisclosureGroup("Calendarios del iPhone (opcional)", isExpanded: $showsDeviceCalendars) {
                    deviceCalendars
                }
            } footer: {
                Text("Solo si ya tienes otros calendarios en el Calendario de iOS y quieres que Planaby también los tenga en cuenta.")
            }
        }
        .navigationTitle("Calendarios externos")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await external.syncAll() }
        .sheet(isPresented: $adding) {
            NavigationStack { AddSubscriptionView() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { external.refreshStatus() }
        }
    }

    @ViewBuilder
    private var deviceCalendars: some View {
        switch external.status {
        case .fullAccess:
            if external.calendars.isEmpty {
                Text("No hay calendarios en este iPhone.")
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(external.calendars) { calendar in
                Picker(selection: Binding(
                    get: { external.mode(for: calendar.id)?.rawValue ?? "" },
                    set: { external.setMode(PlanMode(rawValue: $0), for: calendar.id) }
                )) {
                    Text("No usar").tag("")
                    ForEach(PlanMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading) {
                            Text(calendar.title)
                            if !calendar.sourceTitle.isEmpty {
                                Text(calendar.sourceTitle)
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    } icon: {
                        Circle().fill(calendar.color).frame(width: 12, height: 12)
                    }
                }
            }
        case .notDetermined:
            Button("Permitir acceso a los calendarios", systemImage: "calendar.badge.plus") {
                external.requestAccess()
            }
        default:
            Button("Dar acceso en Ajustes de iOS", systemImage: "gear") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        }
    }
}

private struct SubscriptionRow: View {
    let subscription: CalendarSubscription
    let color: Color

    var body: some View {
        HStack(spacing: Space.m) {
            Circle().fill(color).frame(width: 12, height: 12)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(subscription.name)
                if let error = subscription.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.orange)
                        .lineLimit(2)
                } else {
                    Text("\(subscription.mode.title) · \(subscription.lastSync.map { "actualizado \($0.formatted(.relative(presentation: .named)))" } ?? "sin actualizar")")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HowToStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Text("\(number)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.orange)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
        }
    }
}

/// Pegar el enlace, ponerle nombre y elegir plan. Se descarga una vez para comprobarlo.
private struct AddSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Outlook"
    @State private var link = ""
    @State private var mode = PlanMode.work
    @State private var isChecking = false
    @State private var problem: String?

    var body: some View {
        Form {
            Section {
                TextField("https://outlook.office365.com/…/calendar.ics", text: $link, axis: .vertical)
                    .lineLimit(1...4)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                PasteButton(payloadType: String.self) { strings in
                    if let first = strings.first { link = first.trimmingCharacters(in: .whitespacesAndNewlines) }
                }
            } header: {
                Text("Enlace ICS")
            } footer: {
                if let problem {
                    Text(problem).foregroundStyle(Theme.orange)
                }
            }

            Section {
                TextField("Nombre", text: $name)
                ModeField(mode: $mode)
            } footer: {
                Text("En modo Normal solo se ven los calendarios del plan Normal, pero todos cuentan como ocupados al planificar.")
            }
        }
        .navigationTitle("Calendario de Outlook")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar", systemImage: "xmark") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isChecking {
                    ProgressView()
                } else {
                    Button("Añadir") { Task { await add() } }
                        .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func add() async {
        isChecking = true
        problem = nil
        defer { isChecking = false }
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        do {
            _ = try await ExternalCalendars.shared.addSubscription(
                name: cleanName.isEmpty ? "Outlook" : cleanName, url: link, mode: mode
            )
            dismiss()
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// Cambiar nombre o plan de una suscripción, o quitarla.
private struct SubscriptionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var subscription: CalendarSubscription
    @State private var confirmingRemove = false
    private let external = ExternalCalendars.shared

    var body: some View {
        Form {
            Section {
                TextField("Nombre", text: $subscription.name)
                ModeField(mode: $subscription.mode)
            }
            Section {
                LabeledContent("Última descarga", value: subscription.lastSync?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                if let error = subscription.lastError {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(Theme.orange)
                }
                LabeledContent("Servidor", value: URL(string: subscription.url)?.host() ?? "—")
            }
            Section {
                Button("Dejar de usar este calendario", systemImage: "trash", role: .destructive) {
                    confirmingRemove = true
                }
            }
        }
        .navigationTitle(subscription.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: subscription) {
            external.update(subscription)
        }
        .confirmationDialog("¿Dejar de usar «\(subscription.name)»?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Quitar", role: .destructive) {
                external.remove(subscription)
                dismiss()
            }
        } message: {
            Text("Se borra la copia guardada en el iPhone. Tu calendario de Outlook no cambia.")
        }
    }
}
