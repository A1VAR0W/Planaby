import SwiftUI

/// Ajustes › Calendarios externos: qué calendarios de iOS (Outlook, Teams, iCloud…) tiene en
/// cuenta Planaby y a qué plan pertenece cada uno.
struct ExternalCalendarsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    private let external = ExternalCalendars.shared

    var body: some View {
        Form {
            switch external.status {
            case .fullAccess:
                calendarSections
            case .notDetermined:
                Section {
                    Button("Permitir acceso a los calendarios", systemImage: "calendar.badge.plus") {
                        external.requestAccess()
                    }
                } footer: {
                    Text("Planaby solo lee tus calendarios: no cambia ni borra nada en ellos.")
                }
            default:
                Section {
                    Button("Abrir Ajustes de iOS", systemImage: "gear") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                } footer: {
                    Text("Planaby no tiene acceso completo a los calendarios. Actívalo en Ajustes › Apps › Planaby › Calendarios.")
                }
            }

            Section("Cómo añadir Outlook o Teams") {
                Label("Ajustes de iOS › Apps › Calendario › Cuentas de calendario › Añadir cuenta › Microsoft Exchange (o Outlook.com).", systemImage: "1.circle")
                Label("Si tu empresa no lo permite: en la app Outlook, Ajustes › tu cuenta › activa «Sincronizar calendarios».", systemImage: "2.circle")
                Label("Las reuniones de Teams están en tu calendario de Outlook, así que aparecen solas.", systemImage: "video")
            }
            .font(.subheadline)
            .foregroundStyle(Theme.secondaryText)
        }
        .navigationTitle("Calendarios externos")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { external.refreshStatus() }
        }
    }

    @ViewBuilder
    private var calendarSections: some View {
        let groups = Dictionary(grouping: external.calendars, by: \.sourceTitle).sorted { $0.key < $1.key }
        if groups.isEmpty {
            Section {
                Text("No hay calendarios en este iPhone.")
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        ForEach(groups, id: \.key) { group in
            Section {
                ForEach(group.value) { calendar in
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
                            Text(calendar.title)
                        } icon: {
                            Circle().fill(calendar.color).frame(width: 12, height: 12)
                        }
                    }
                }
            } header: {
                Text(group.key.isEmpty ? "Otros" : group.key)
            }
        }
        Section {
        } footer: {
            Text("Los eventos de los calendarios elegidos se ven en la agenda (en modo Normal, solo los del plan Normal) y Planaby no coloca bloques encima. Los marcados como «libre» y las invitaciones rechazadas no cuentan.")
        }
    }
}
