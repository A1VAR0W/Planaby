import SwiftUI
import UIKit

/// Ajustes › Avisos de concentración: cuándo y cómo avisa Planaby al cambiar de fase, y por qué
/// un aviso podría no sonar (una opción, un permiso o una regla de iOS).
struct AlertSettingsView: View {
    @Environment(FocusTimer.self) private var timer
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AlertPreferences.Keys.style, store: AppGroup.defaults) private var styleRaw = AlertStyle.sound.rawValue
    @AppStorage(AlertPreferences.Keys.soundSet, store: AppGroup.defaults) private var soundRaw = AlertSoundSet.soft.rawValue
    @AppStorage(AlertPreferences.Keys.breakStart, store: AppGroup.defaults) private var breakStart = true
    @AppStorage(AlertPreferences.Keys.breakEnd, store: AppGroup.defaults) private var breakEnd = true
    @AppStorage(AlertPreferences.Keys.respectMusic, store: AppGroup.defaults) private var respectMusic = false
    @AppStorage(AlertPreferences.Keys.overlay, store: AppGroup.defaults) private var overlay = true
    @AppStorage(AlertPreferences.Keys.duckMusic, store: AppGroup.defaults) private var duckMusic = true
    @State private var status: PhaseAlertPlayer.NotificationStatus?
    @State private var testScheduled = false

    private var style: AlertStyle { AlertStyle(rawValue: styleRaw) ?? .sound }

    var body: some View {
        Form {
            Section {
                Toggle("Al empezar el descanso", isOn: $breakStart)
                Toggle("Al volver a concentrarte", isOn: $breakEnd)
            } header: {
                Text("Cuándo")
            }

            Section {
                Picker("Aviso", selection: $styleRaw) {
                    ForEach(AlertStyle.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if style == .sound {
                    Picker("Sonido", selection: $soundRaw) {
                        ForEach(AlertSoundSet.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Button {
                        PhaseAlertPlayer.shared.preview(AlertSoundSet(rawValue: soundRaw) ?? .soft)
                    } label: {
                        Label("Escuchar", systemImage: "play.circle")
                    }
                }
            } header: {
                Text("Cómo")
            } footer: {
                Text("Con «Solo vibración» o «Solo visual» la notificación llega sin sonido: iOS solo vibra con los avisos que suenan.")
            }

            Section {
                Toggle("Sonar aunque haya música", isOn: Binding(get: { !respectMusic }, set: { respectMusic = !$0 }))
                    .disabled(style != .sound)
                Toggle("Bajar la música mientras suena", isOn: $duckMusic)
                    .disabled(style != .sound || respectMusic)
                Toggle("Tarjeta al cambiar de fase", isOn: $overlay)
            } header: {
                Text("Con Planaby abierta")
            } footer: {
                Text("La música (Spotify, Apple Music…) baja un momento, suena el aviso y vuelve sola a su volumen: nunca se para ni se cambia el volumen del iPhone. Si desactivas «Sonar aunque haya música», con música solo vibra y enseña la tarjeta. Con la app delante no llega además la notificación, para no avisarte dos veces.")
            }

            Section {
                diagnosis
                Button {
                    PhaseAlertPlayer.scheduleTest()
                    testScheduled = true
                } label: {
                    Label(testScheduled ? "Llegará en 5 s: bloquea el iPhone" : "Probar notificación en 5 s", systemImage: "bell.badge")
                }
                .disabled(status?.authorized == false)
                if let outcome = PhaseAlertPlayer.shared.lastOutcome {
                    LabeledContent("Último aviso", value: outcome.text)
                        .font(.footnote)
                }
            } header: {
                Text("Si no suena")
            } footer: {
                Text("Reglas de iOS que Planaby no puede saltarse: en modo silencio solo vibra; una Concentración de iOS (por ejemplo Trabajo) silencia las notificaciones salvo que permitas Planaby en ella; y el volumen de los avisos es el del iPhone.")
            }
        }
        .navigationTitle("Avisos de concentración")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: [styleRaw, soundRaw]) { timer.sync() }
        .onChange(of: [breakStart, breakEnd]) { timer.sync() }
        .task(id: scenePhase) { status = await PhaseAlertPlayer.notificationStatus() }
    }

    /// Permisos: separa lo que depende de Planaby de lo que se cambia en los Ajustes del iPhone.
    @ViewBuilder
    private var diagnosis: some View {
        if let status {
            if !status.authorized {
                problem("Notificaciones desactivadas para Planaby", detail: "Con la app cerrada no avisará.", openSettings: true)
            } else if style == .sound, !status.soundsAllowed {
                problem("Sonidos desactivados para Planaby", detail: "Las notificaciones llegan, pero sin sonido.", openSettings: true)
            } else {
                Label("Notificaciones y sonidos permitidos", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }
            if status.authorized, !status.lockScreen {
                problem("No se ven en la pantalla bloqueada", detail: "Actívalo en Ajustes › Notificaciones › Planaby.", openSettings: true)
            }
        }
    }

    private func problem(_ title: String, detail: String, openSettings: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.orange)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if openSettings {
                Button("Abrir los Ajustes del iPhone") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.footnote.weight(.semibold))
            }
        }
    }
}
