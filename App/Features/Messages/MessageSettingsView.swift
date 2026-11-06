import SwiftUI

/// Ajustes › Filtro de mensajes: avisos, la automatización de Mensajes y la cuenta de correo.
struct MessageSettingsView: View {
    @Environment(\.openURL) private var openURL
    @AppStorage(MessageTriage.Keys.notifyLevel) private var notifyLevel = 1
    @State private var host = MailAccount.presets[0].host
    @State private var username = ""
    @State private var password = ""
    @State private var connecting = false
    @State private var connectError: String?
    @State private var confirmingDisconnect = false
    private let mail = MailInbox.shared

    var body: some View {
        Form {
            Section {
                Picker(selection: $notifyLevel) {
                    Text("Solo lo urgente").tag(0)
                    Text("Urgente e importante").tag(1)
                } label: {
                    Label("Avisarme de", systemImage: "bell.badge")
                }
                NavigationLink {
                    SenderRulesView()
                } label: {
                    Label("Remitentes prioritarios", systemImage: "person.crop.circle.badge.checkmark")
                }
            } footer: {
                Text("Lo importante no te avisa mientras te concentras: al terminar la sesión recibes un resumen. Lo que puede esperar y el ruido nunca avisan. Para que Mensajes y Correo no te interrumpan, en Ajustes de iOS › Concentración › (p. ej. Trabajo) silencia esas apps y permite Planaby.")
            }

            Section {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Step(number: 1, text: "Atajos › Automatización › Nueva › Mensaje. Elige remitentes (o cualquiera) y «Ejecutar inmediatamente».")
                        Step(number: 2, text: "Añade la acción de Planaby «Filtrar mensaje»: en Mensaje pon la Entrada del atajo y en Remitente, el remitente del mensaje.")
                        Step(number: 3, text: "Listo: Apple Intelligence lo clasifica en el iPhone y Planaby solo te avisa si importa.")
                    }
                    .padding(.vertical, Space.xs)
                    Button("Abrir Atajos") {
                        if let url = URL(string: "shortcuts://") { openURL(url) }
                    }
                } label: {
                    Label("iMessage y SMS", systemImage: "message")
                }
            } footer: {
                Text("iOS no deja a otras apps leer tus mensajes: los pasa la automatización, uno a uno, y nada sale del iPhone.")
            }

            if let account = mail.account {
                Section {
                    LabeledContent("Cuenta", value: account.username)
                    LabeledContent("Servidor", value: account.host)
                    LabeledContent("Última comprobación", value: mail.lastCheck?.formatted(.relative(presentation: .named)) ?? "Todavía no")
                    if let error = mail.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.orange)
                    }
                    Button("Desconectar", role: .destructive) { confirmingDisconnect = true }
                } header: {
                    Text("Correo")
                } footer: {
                    Text("Planaby mira los correos sin leer al abrirse (como mucho cada 10 minutos) y al deslizar en la bandeja, sin marcarlos como leídos. Para comprobar también con la app cerrada: Atajos › Automatización › Hora del día › cada hora › «Comprobar correo».")
                }
            } else {
                Section {
                    Picker("Proveedor", selection: $host) {
                        ForEach(MailAccount.presets, id: \.host) { preset in
                            Text(preset.name).tag(preset.host)
                        }
                        Text("Otro").tag("")
                    }
                    if !MailAccount.presets.contains(where: { $0.host == host }) {
                        TextField("Servidor IMAP (p. ej. imap.ejemplo.com)", text: $host)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                    TextField("Correo", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                    SecureField("Contraseña de aplicación", text: $password)
                        .textContentType(.password)
                    if let connectError {
                        Label(connectError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.orange)
                    }
                    Button {
                        Task { await connect() }
                    } label: {
                        HStack(spacing: Space.s) {
                            if connecting { ProgressView() }
                            Text(connecting ? "Conectando…" : "Conectar")
                        }
                    }
                    .disabled(connecting || host.isEmpty || username.isEmpty || password.isEmpty)
                } header: {
                    Text("Correo (IMAP)")
                } footer: {
                    Text("Usa una contraseña de aplicación, no la normal: en Gmail, Cuenta de Google › Seguridad › Contraseñas de aplicaciones; en iCloud, account.apple.com › Contraseñas específicas de apps. Se guarda en el Llavero del iPhone. Las cuentas de Microsoft 365 del trabajo suelen tener IMAP bloqueado.")
                }
            }
        }
        .navigationTitle("Filtro de mensajes")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("¿Desconectar el correo?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
            Button("Desconectar", role: .destructive) { mail.disconnect() }
        } message: {
            Text("Se borra la contraseña del Llavero. Los correos ya filtrados siguen en la bandeja.")
        }
    }

    private func connect() async {
        connecting = true
        connectError = nil
        defer { connecting = false }
        do {
            try await mail.connect(host: host, username: username, password: password)
            password = ""
            await NotificationAccess.requestIfNeeded()
        } catch {
            connectError = error.localizedDescription
        }
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
