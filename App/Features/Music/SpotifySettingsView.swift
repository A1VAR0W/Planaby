import AuthenticationServices
import SwiftUI

/// Ajustes › Música › Spotify: crear la app gratuita de Spotify, pegar su Client ID y conectar.
struct SpotifySettingsView: View {
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.openURL) private var openURL
    @AppStorage(SpotifyController.Keys.clientID) private var clientID = ""
    @State private var connecting = false
    @State private var error: String?
    private let spotify = SpotifyController.shared

    var body: some View {
        Form {
            if spotify.isConnected {
                Section {
                    LabeledContent("Cuenta", value: spotify.accountName ?? "Conectada")
                    LabeledContent("App de Spotify", value: spotify.isRemoteConnected ? "Conectada" : "Sin conectar")
                    if spotify.needsReconnect {
                        Label("Desconecta y vuelve a conectar para controlar la app de Spotify con tu cuenta gratuita.", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(Theme.orange)
                    }
                    if !spotify.isRemoteConnected {
                        Button("Conectar con la app de Spotify") { spotify.wakeSpotify() }
                    }
                    if let track = spotify.track {
                        LabeledContent("Suena", value: "\(track.title) · \(track.artists)")
                    }
                    if let error = spotify.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.orange)
                    }
                    Button("Desconectar", role: .destructive) { spotify.disconnect() }
                } footer: {
                    Text("En Enfoque verás lo que suena con su carátula, y en el modo escritorio el botón ♪ lo pone a pantalla completa. Planaby controla la app de Spotify del iPhone (también con cuenta gratuita); si Spotify estaba cerrado, se abre un instante para despertarlo y vuelve a Planaby.")
                }
                .task { await spotify.refresh() }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Step(number: 1, text: "Abre developer.spotify.com/dashboard con tu cuenta de Spotify y pulsa «Create app».")
                        Step(number: 2, text: "Nombre: Planaby. En Redirect URIs añade exactamente: \(SpotifyController.redirectURI)")
                        Step(number: 3, text: "Marca «Web API» y «iOS». En iOS, Bundle ID: com.alvaro.planaby. Acepta y guarda.")
                        Step(number: 4, text: "En Settings copia el «Client ID» y pégalo aquí debajo.")
                    }
                    .padding(.vertical, Space.xs)
                    Button("Abrir el panel de Spotify") {
                        if let url = URL(string: "https://developer.spotify.com/dashboard") { openURL(url) }
                    }
                    Button("Copiar la Redirect URI") { UIPasteboard.general.string = SpotifyController.redirectURI }
                } header: {
                    Text("Una sola vez")
                } footer: {
                    Text("Es gratis y no usa ningún App ID de tu cuenta de Apple. El Client ID no es secreto; la sesión se guarda en el Llavero del iPhone.")
                }

                Section {
                    TextField("Client ID", text: $clientID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.orange)
                    }
                    Button {
                        Task { await connect() }
                    } label: {
                        HStack(spacing: Space.s) {
                            if connecting { ProgressView() }
                            Text(connecting ? "Conectando…" : "Conectar con Spotify")
                        }
                    }
                    .disabled(connecting || clientID.trimmingCharacters(in: .whitespaces).count < 20)
                }
            }
        }
        .navigationTitle("Spotify")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func connect() async {
        guard let url = spotify.authorizationURL() else { return }
        connecting = true
        error = nil
        defer { connecting = false }
        do {
            let callback = try await webAuthenticationSession.authenticate(
                using: url, callbackURLScheme: SpotifyController.redirectScheme, preferredBrowserSession: .ephemeral
            )
            try await spotify.finishLogin(callback: callback)
        } catch let failure as ASWebAuthenticationSessionError where failure.code == .canceledLogin {
            return
        } catch {
            self.error = error.localizedDescription
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
                .textSelection(.enabled)
        }
    }
}
