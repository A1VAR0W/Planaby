import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

// El volumen real de salida del iPhone (el mismo que los botones laterales) con el control oficial
// de Apple, `MPVolumeView`. Sirve para Spotify y cualquier otro audio, por el altavoz, auriculares
// Bluetooth o AirPlay cuando el dispositivo de salida lo admite, y se mueve solo con los botones
// físicos. El SDK de Spotify (App Remote) no permite cambiar el volumen, y aquí no se toca nada
// privado de UIKit: el aspecto se cambia con la API pública (imágenes de pista y miniatura) y la
// vertical es una rotación de la vista. En el simulador iOS no aparece el control.

/// Nivel de volumen del sistema, solo para elegir el icono del altavoz (bajo, alto o silenciado).
/// Lo informa iOS por KVO (`AVAudioSession.outputVolume`); nunca se escribe desde aquí.
@Observable
@MainActor
final class SystemVolume {
    static let shared = SystemVolume()

    private(set) var level: Float = AVAudioSession.sharedInstance().outputVolume
    @ObservationIgnored private var observation: NSKeyValueObservation?

    private init() {}

    /// Empieza a escuchar los cambios. La sesión «ambient» con mezcla no interrumpe ni baja a
    /// Spotify; activarla es lo que hace que iOS informe del volumen al momento.
    func start() {
        let session = AVAudioSession.sharedInstance()
        // Mientras se dicta la sesión es de grabación: no se toca.
        if session.category != .playAndRecord, session.category != .record {
            try? session.setCategory(.ambient, options: [.mixWithOthers])
            try? session.setActive(true)
        }
        level = session.outputVolume
        guard observation == nil else { return }
        // `@Sendable`: iOS puede avisar desde otro hilo; el valor se pasa al principal.
        observation = session.observe(\.outputVolume, options: [.new]) { @Sendable _, change in
            guard let value = change.newValue else { return }
            Task { @MainActor in SystemVolume.shared.level = value }
        }
    }

    var symbol: String { VolumeLevel.symbol(for: level) }
    var percentText: String { VolumeLevel.text(for: level) }
    var isMuted: Bool { VolumeLevel.isMuted(level) }
}

// MARK: - Horizontal (Ahora suena, en vertical)

/// Barra horizontal clásica bajo los controles de «Ahora suena» con el iPhone en vertical.
struct VolumeSlider: View {
    let tint: Color
    let ink: Color

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(ink.opacity(0.55))
                .accessibilityHidden(true)
            SystemVolumeView(tint: UIColor(tint), track: UIColor(ink.opacity(0.18)), vertical: false)
                .frame(height: 34)
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(ink.opacity(0.55))
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Vertical (modo escritorio)

/// Botón del altavoz del modo escritorio: un círculo de cristal oscuro con un arco naranja que
/// enseña el nivel. Al tocarlo, el icono hace un pequeño gesto y nace hacia arriba, desde el
/// propio botón, una cápsula vertical con el volumen real; otro toque (o tocar fuera) la recoge
/// con el mismo movimiento al revés. No mueve nada de lo que hay alrededor: va superpuesta.
struct DeskVolumeControl: View {
    @Binding var isOpen: Bool
    let tint: Color
    let ink: Color
    /// Mantiene visible la barra del escritorio mientras se usa.
    let onInteract: () -> Void
    @State private var volume = SystemVolume.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let buttonSize: CGFloat = 44

    var body: some View {
        Button {
            onInteract()
            if !isOpen { volume.start() }
            withAnimation(Self.animation(reduceMotion: reduceMotion)) { isOpen.toggle() }
        } label: {
            VolumeButtonFace(level: volume.level, symbol: volume.symbol, isOpen: isOpen, tint: tint, ink: ink, reduceMotion: reduceMotion)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.9))
        .accessibilityLabel(isOpen ? "Ocultar el volumen" : "Volumen")
        .accessibilityValue(VolumeLevel.spokenText(for: volume.level))
        .accessibilityHint(isOpen ? "" : "Muestra el volumen del iPhone")
        .sensoryFeedback(.selection, trigger: isOpen)
        // La cápsula se apoya justo encima del botón y crece desde él.
        .overlay(alignment: .bottom) {
            if isOpen {
                VolumeCapsule(tint: tint, ink: ink, volume: volume, reduceMotion: reduceMotion)
                    .padding(.bottom, Self.buttonSize + Space.s)
                    .transition(Self.capsuleTransition(reduceMotion: reduceMotion))
            }
        }
        .onAppear { volume.start() }
    }

    static func animation(reduceMotion: Bool) -> Animation {
        Motion.adaptive(.spring(duration: 0.38, bounce: 0.16), reduceMotion: reduceMotion)
    }

    /// Crece desde el botón (abajo) y se recoge hacia él. Con «Reducir movimiento», fundido.
    private static func capsuleTransition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .scale(scale: 0.15, anchor: .bottom).combined(with: .opacity).combined(with: .offset(y: 12)),
            removal: .scale(scale: 0.15, anchor: .bottom).combined(with: .opacity).combined(with: .offset(y: 12))
                .animation(.spring(duration: 0.28, bounce: 0))
        )
    }
}

/// La cara del botón: fondo oscuro translúcido, borde fino, el altavoz y un arco naranja con el
/// nivel (gris si no hay sonido). Abierta, el borde se tiñe.
private struct VolumeButtonFace: View {
    let level: Float
    let symbol: String
    let isOpen: Bool
    let tint: Color
    let ink: Color
    let reduceMotion: Bool

    var body: some View {
        let muted = VolumeLevel.isMuted(level)
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.55))
                .background(.ultraThinMaterial, in: .circle)
            Circle()
                .strokeBorder(isOpen ? tint.opacity(0.7) : ink.opacity(0.14), lineWidth: 1)
            // El nivel, como un arco que empieza abajo a la izquierda.
            Circle()
                .trim(from: 0, to: CGFloat(VolumeLevel.clamped(level)) * 0.75)
                .stroke(muted ? ink.opacity(0.25) : tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(135))
                .padding(3)
                .animation(Motion.adaptive(Motion.quick, reduceMotion: reduceMotion), value: level)
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isOpen ? tint : ink.opacity(muted ? 0.55 : 0.9))
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .symbolEffect(.bounce.up, options: .nonRepeating, value: isOpen)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }
}

/// Cápsula flotante: cristal negro translúcido, el porcentaje discreto arriba, el control
/// vertical del sistema en el centro (relleno naranja desde abajo) y el altavoz abajo.
private struct VolumeCapsule: View {
    let tint: Color
    let ink: Color
    let volume: SystemVolume
    let reduceMotion: Bool
    @State private var shown = false

    var body: some View {
        let muted = volume.isMuted
        VStack(spacing: Space.s) {
            Text(volume.percentText)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(ink.opacity(muted ? 0.5 : 0.75))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .animation(Motion.adaptive(Motion.quick, reduceMotion: reduceMotion), value: volume.percentText)
                .accessibilityHidden(true)
            SystemVolumeView(
                tint: UIColor(muted ? ink.opacity(0.3) : tint), track: UIColor(ink.opacity(0.12)),
                vertical: true, thumb: UIColor(white: 1, alpha: 0.95)
            )
            .frame(width: 44)
            .frame(maxHeight: .infinity)
            Image(systemName: volume.symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(muted ? ink.opacity(0.45) : tint)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .frame(height: 18)
                .accessibilityHidden(true)
        }
        // El nivel aparece un instante después de que la cápsula empiece a crecer.
        .opacity(shown ? 1 : 0)
        .padding(.vertical, Space.m)
        .frame(width: 60, height: 216)
        .background(Color.black.opacity(0.6), in: .capsule)
        .background(.ultraThinMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(ink.opacity(0.12)))
        .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
        // Un toque dentro no cuenta como «tocar fuera» (que la cierra).
        .contentShape(.capsule)
        .onTapGesture {}
        .onAppear {
            withAnimation(reduceMotion ? Motion.reduced : Motion.quick.delay(0.08)) { shown = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Volumen")
        .accessibilityValue(VolumeLevel.spokenText(for: volume.level))
    }
}

// MARK: - Control del sistema

/// `MPVolumeView` con el aspecto de Planaby. En vertical va dentro de un contenedor que lo gira
/// −90°: UIKit respeta el giro al tocar y arrastrar, y abajo queda el mínimo.
private struct SystemVolumeView: UIViewRepresentable {
    let tint: UIColor
    let track: UIColor
    let vertical: Bool
    /// En vertical, el tirador es una barrita blanca de lado a lado de la pista.
    var thumb: UIColor? = nil

    func makeUIView(context: Context) -> VolumeHost {
        VolumeHost(vertical: vertical)
    }

    func updateUIView(_ host: VolumeHost, context: Context) {
        let view = host.volume
        view.tintColor = tint
        // En vertical, una pista gruesa que se rellena desde abajo, como una cápsula.
        let thickness: CGFloat = vertical ? 22 : 4
        view.setMinimumVolumeSliderImage(Self.capsule(tint, thickness: thickness), for: .normal)
        view.setMaximumVolumeSliderImage(Self.capsule(track, thickness: thickness), for: .normal)
        if vertical {
            view.setVolumeThumbImage(Self.handle(thumb ?? .white, across: thickness + 6), for: .normal)
        } else {
            view.setVolumeThumbImage(Self.thumb(tint, size: 18), for: .normal)
        }
    }

    /// Tirador de la versión vertical: en coordenadas del control (que va girado) es estrecho a
    /// lo largo de la pista y ancho a través de ella, así queda como una barrita horizontal.
    private static func handle(_ color: UIColor, across: CGFloat) -> UIImage {
        let size = CGSize(width: 12, height: across + 4)
        return UIGraphicsImageRenderer(size: size).image { context in
            context.cgContext.setShadow(offset: .zero, blur: 3, color: UIColor.black.withAlphaComponent(0.4).cgColor)
            color.setFill()
            UIBezierPath(roundedRect: CGRect(x: 3, y: 2, width: 6, height: across), cornerRadius: 3).fill()
        }
    }

    /// Pista redondeada y estirable.
    private static func capsule(_ color: UIColor, thickness: CGFloat) -> UIImage {
        let size = CGSize(width: thickness * 2 + 1, height: thickness)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            color.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: thickness / 2).fill()
        }
        return image.resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: thickness, bottom: 0, right: thickness))
    }

    private static func thumb(_ color: UIColor, size side: CGFloat) -> UIImage {
        let size = CGSize(width: side + 4, height: side + 4)
        return UIGraphicsImageRenderer(size: size).image { context in
            context.cgContext.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: UIColor.black.withAlphaComponent(0.35).cgColor)
            color.setFill()
            UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: side, height: side)).fill()
        }
    }
}

/// Contenedor del control: en vertical lo gira y lo centra; en horizontal lo deja tal cual.
final class VolumeHost: UIView {
    let volume = CenteredVolumeView(frame: .zero)
    private let vertical: Bool

    init(vertical: Bool) {
        self.vertical = vertical
        super.init(frame: .zero)
        addSubview(volume)
        if vertical { volume.transform = CGAffineTransform(rotationAngle: -.pi / 2) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Con el giro, el ancho del control es el alto del contenedor.
        volume.bounds = vertical
            ? CGRect(x: 0, y: 0, width: bounds.height, height: bounds.width)
            : bounds
        volume.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }
}

/// `MPVolumeView` con la pista centrada en su alto (método público pensado para subclases), para
/// que al girarla quede en el centro de la cápsula.
final class CenteredVolumeView: MPVolumeView {
    override func volumeSliderRect(forBounds bounds: CGRect) -> CGRect {
        let base = super.volumeSliderRect(forBounds: bounds)
        return CGRect(x: bounds.minX, y: bounds.midY - base.height / 2, width: bounds.width, height: base.height)
    }
}
