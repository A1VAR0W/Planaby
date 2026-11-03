import SwiftUI

/// Carátula de lo que suena en Spotify. De noche se tiñe de rojo tenue, como StandBy.
struct ArtworkView: View {
    let url: URL?
    var image: UIImage?
    var night = false
    var cornerRadius: CGFloat = 20

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        ZStack {
                            Theme.surface
                            Image(systemName: "music.note")
                                .font(.system(size: 40, weight: .light))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .saturation(night ? 0 : 1)
        .colorMultiply(night ? Theme.night : .white)
        .opacity(night ? 0.7 : 1)
        .accessibilityHidden(true)
    }
}

/// Barra de progreso de la canción con los tiempos.
struct TrackProgress: View {
    let position: TimeInterval
    let duration: TimeInterval
    let tint: Color
    let ink: Color

    var body: some View {
        VStack(spacing: Space.xs) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(ink.opacity(0.15))
                    Capsule()
                        .fill(tint)
                        .frame(width: duration > 0 ? proxy.size.width * min(1, position / duration) : 0)
                }
            }
            .frame(height: 4)
            HStack {
                Text(Self.time(position))
                Spacer()
                Text("-" + Self.time(max(0, duration - position)))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(ink.opacity(0.6))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progreso de la canción")
        .accessibilityValue("\(Self.time(position)) de \(Self.time(duration))")
    }

    static func time(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Anterior · reproducir/pausar · siguiente.
struct PlaybackControls: View {
    let tint: Color
    let ink: Color
    var large = false
    private let spotify = SpotifyController.shared

    var body: some View {
        HStack(spacing: large ? Space.xl : Space.l) {
            Button { Task { await spotify.previous() } } label: {
                Image(systemName: "backward.fill").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Canción anterior")
            Button { Task { await spotify.togglePlay() } } label: {
                Image(systemName: spotify.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: large ? 34 : 26, weight: .semibold))
                    .frame(width: large ? 64 : 52, height: large ? 64 : 52)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(spotify.isPlaying ? "Pausar música" : "Reproducir música")
            Button { Task { await spotify.next() } } label: {
                Image(systemName: "forward.fill").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Canción siguiente")
        }
        .font(.system(size: large ? 24 : 20, weight: .semibold))
        .foregroundStyle(ink)
        .buttonStyle(.plain)
        .tint(tint)
        .sensoryFeedback(.selection, trigger: spotify.isPlaying)
    }
}

/// Modo escritorio con música: carátula grande a la izquierda y, a la derecha, la canción,
/// sus controles y el temporizador en pequeño.
struct DeskNowPlaying: View {
    let state: TimerState?
    let date: Date
    let tint: Color
    let ink: Color
    let night: Bool
    private let spotify = SpotifyController.shared

    var body: some View {
        HStack(spacing: Space.xl) {
            ArtworkView(url: spotify.track?.artworkURL, image: spotify.artwork, night: night, cornerRadius: 24)
                .frame(maxHeight: .infinity)
                .shadow(color: .black.opacity(0.5), radius: 20, y: 8)

            VStack(alignment: .leading, spacing: Space.m) {
                if let state {
                    HStack(spacing: Space.s) {
                        Eyebrow(text: state.isPaused ? "En pausa" : state.phase.title, color: tint)
                        Text(state.clockText(at: date))
                            .font(.system(.title2, design: .rounded).weight(.light).monospacedDigit())
                            .foregroundStyle(ink.opacity(0.85))
                            .contentTransition(.numericText(countsDown: true))
                    }
                } else {
                    Text(date, format: .dateTime.hour().minute())
                        .font(.system(.title2, design: .rounded).weight(.light).monospacedDigit())
                        .foregroundStyle(ink.opacity(0.85))
                }

                if let track = spotify.track {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(track.title)
                            .font(.title.weight(.semibold))
                            .foregroundStyle(ink)
                            .lineLimit(2)
                        Text(track.artists)
                            .font(.title3)
                            .foregroundStyle(ink.opacity(0.65))
                            .lineLimit(1)
                    }
                    TrackProgress(position: spotify.position(at: date), duration: track.duration, tint: tint, ink: ink)
                    PlaybackControls(tint: tint, ink: ink, large: true)
                        .frame(maxWidth: .infinity)
                } else {
                    Text(spotify.isConnected ? "Nada sonando en Spotify" : "Conecta Spotify en Ajustes › Música")
                        .font(.title3)
                        .foregroundStyle(ink.opacity(0.65))
                    if spotify.isConnected {
                        Button("Poner música", systemImage: "play.fill") { spotify.wakeSpotify() }
                            .buttonStyle(.glass)
                            .tint(tint)
                    }
                }
                if let error = spotify.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(ink.opacity(0.55))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Space.s)
        .task {
            await spotify.connectRemote()
            await spotify.watch()
        }
    }
}

/// Pastilla de Enfoque: carátula, canción y reproducir/pausar. Al tocarla, la vista completa.
struct MiniPlayer: View {
    let onOpen: () -> Void
    private let spotify = SpotifyController.shared

    var body: some View {
        HStack(spacing: Space.s) {
            Button(action: onOpen) {
                HStack(spacing: Space.s) {
                    ArtworkView(url: spotify.track?.artworkURL, image: spotify.artwork, cornerRadius: 8)
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(spotify.track?.title ?? "Spotify")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(spotify.track?.artists ?? "Nada sonando")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 130, alignment: .leading)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(spotify.track.map { "\($0.title), de \($0.artists)" } ?? "Spotify")
            .accessibilityHint("Abre el reproductor")

            Button { Task { await spotify.togglePlay() } } label: {
                Image(systemName: spotify.isPlaying ? "pause.fill" : "play.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(spotify.isPlaying ? "Pausar música" : "Reproducir música")
        }
        .padding(.leading, Space.xs + 2)
        .padding(.trailing, Space.xs)
        .frame(minHeight: 44)
        .glassEffect(.regular.interactive(), in: .capsule)
        .task {
            await spotify.connectRemote()
            await spotify.watch()
        }
    }
}

/// Reproductor completo en vertical (hoja desde Enfoque).
struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(MusicLinks.Keys.focus) private var focusMusic = ""
    @AppStorage(MusicLinks.Keys.rest) private var restMusic = ""
    private let spotify = SpotifyController.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: Space.l) {
                ArtworkView(url: spotify.track?.artworkURL, image: spotify.artwork, cornerRadius: 24)
                    .padding(.horizontal, Space.m)
                    .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
                    .animation(.smooth, value: spotify.track?.artworkURL)

                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(spotify.track?.title ?? "Nada sonando")
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                    Text(spotify.track?.artists ?? (spotify.deviceName.map { "En \($0)" } ?? "Spotify"))
                        .font(.body)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let track = spotify.track {
                    TrackProgress(position: spotify.position(at: context.date), duration: track.duration, tint: Theme.orange, ink: .white)
                }

                PlaybackControls(tint: Theme.orange, ink: .white, large: true)

                HStack(spacing: Space.s) {
                    if MusicLinks.url(from: focusMusic) != nil {
                        Button("Concentración", systemImage: "headphones") { MusicLinks.open(for: .focus) }
                    }
                    if MusicLinks.url(from: restMusic) != nil {
                        Button("Descanso", systemImage: "cup.and.saucer") { MusicLinks.open(for: .shortBreak) }
                    }
                    Button("Shuffle", systemImage: "shuffle") { Task { await spotify.toggleShuffle() } }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(spotify.shuffle ? Theme.orange : Color.white)
                        .accessibilityLabel(spotify.shuffle ? "Desactivar aleatorio" : "Activar aleatorio")
                }
                .buttonStyle(.glass)
                .font(.subheadline.weight(.medium))

                if let error = spotify.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.l)
        }
        .background(Color.black)
        .navigationTitle(spotify.deviceName.map { "Spotify · \($0)" } ?? "Spotify")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cerrar", systemImage: "xmark") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Abrir Spotify", systemImage: "arrow.up.forward.app") {
                    if let url = URL(string: spotify.track?.uri ?? "spotify:") { UIApplication.shared.open(url) }
                }
            }
        }
        .task { await spotify.watch() }
    }
}
