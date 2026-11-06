import SwiftUI

/// Ajustes › Filtro de mensajes › Apps de trabajo: qué se ve concentrándose y qué espera al descanso.
struct CommAppsSettingsView: View {
    @State private var comms = CommsCenter.shared

    private let apps: [CommApp] = [.teams, .outlook, .gmail, .mail, .whatsapp, .messages, .instagram]

    var body: some View {
        Form {
            Section {
                ForEach(apps) { app in
                    Toggle(isOn: Binding(
                        get: { comms.settings.workApps.contains(app) },
                        set: { on in
                            if on {
                                comms.settings.workApps.insert(app)
                                comms.settings.focusExceptions.remove(app)
                            } else {
                                comms.settings.workApps.remove(app)
                            }
                        }
                    )) {
                        Label(app.title, systemImage: app.symbol)
                    }
                }
            } header: {
                Text("Apps de trabajo")
            } footer: {
                Text("Concentrándote solo verás lo urgente e importante de estas apps, en una línea discreta. Por defecto, Teams y Outlook.")
            }

            Section {
                ForEach(apps.filter { !comms.settings.workApps.contains($0) }) { app in
                    Toggle(isOn: Binding(
                        get: { comms.settings.focusExceptions.contains(app) },
                        set: { on in
                            if on { comms.settings.focusExceptions.insert(app) } else { comms.settings.focusExceptions.remove(app) }
                        }
                    )) {
                        Label(app.title, systemImage: app.symbol)
                    }
                }
                Toggle(isOn: $comms.settings.priorityUrgentBypass) {
                    Label("Lo urgente de remitentes prioritarios", systemImage: "person.crop.circle.badge.exclamationmark")
                }
            } header: {
                Text("Excepciones durante la concentración")
            } footer: {
                Text("Lo personal se guarda hasta el descanso salvo estas excepciones. Cuenta como concentración una sesión de Planaby en marcha o, sin sesión, la Concentración del iPhone con el filtro de Planaby (no el plan Trabajo elegido a mano).")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle("Apps de trabajo")
        .navigationBarTitleDisplayMode(.inline)
    }
}
