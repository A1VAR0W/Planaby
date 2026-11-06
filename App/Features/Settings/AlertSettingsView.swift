import SwiftUI

/// Ajustes › Avisos de concentración: cuándo y cómo avisa Planaby al cambiar de fase.
struct AlertSettingsView: View {
    @Environment(FocusTimer.self) private var timer
    @AppStorage(AlertPreferences.Keys.style, store: AppGroup.defaults) private var styleRaw = AlertStyle.sound.rawValue
    @AppStorage(AlertPreferences.Keys.soundSet, store: AppGroup.defaults) private var soundRaw = AlertSoundSet.soft.rawValue
    @AppStorage(AlertPreferences.Keys.breakStart, store: AppGroup.defaults) private var breakStart = true
    @AppStorage(AlertPreferences.Keys.breakEnd, store: AppGroup.defaults) private var breakEnd = true
    @AppStorage(AlertPreferences.Keys.respectMusic, store: AppGroup.defaults) private var respectMusic = true
    @AppStorage(AlertPreferences.Keys.overlay, store: AppGroup.defaults) private var overlay = true

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
                Text("Los sonidos respetan el modo silencio del iPhone. Con Planaby cerrado avisa la notificación; con «Solo vibración» o «Solo visual» llega sin sonido, porque iOS solo vibra con los avisos que suenan.")
            }

            Section {
                Toggle("Tarjeta al cambiar de fase", isOn: $overlay)
                Toggle("No sonar si hay música", isOn: $respectMusic)
                    .disabled(style != .sound)
            } header: {
                Text("Con Planaby abierto")
            } footer: {
                Text("Con la app delante no llega la notificación: aparece una tarjeta con el siguiente paso, para no avisarte dos veces. Si suena Spotify u otra música, solo vibra.")
            }
        }
        .navigationTitle("Avisos de concentración")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: [styleRaw, soundRaw]) { timer.sync() }
        .onChange(of: [breakStart, breakEnd]) { timer.sync() }
    }
}
