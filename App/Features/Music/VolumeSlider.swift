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

    var symbol: String { Self.symbol(for: level) }

    /// Silenciado, bajo, medio o alto.
    nonisolated static func symbol(for level: Float) -> String {
        switch level {
        case ..<0.01: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }

    var percentText: String { "\(Int((level * 100).rounded())) %" }
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

/// Botón del altavoz del modo escritorio. Al tocarlo nace hacia arriba, desde el propio botón,
/// una cápsula vertical con el volumen real; otro toque (o tocar fuera) la recoge.
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
            Image(systemName: volume.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isOpen ? tint : ink.opacity(0.9))
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .frame(width: Self.buttonSize, height: Self.buttonSize)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(isOpen ? "Ocultar el volumen" : "Volumen")
        .accessibilityValue(volume.percentText)
        // La cápsula se apoya justo encima del botón y crece desde él.
        .overlay(alignment: .bottom) {
            if isOpen {
                VolumeCapsule(tint: tint, ink: ink, volume: volume)
                    .padding(.bottom, Self.buttonSize + Space.s)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .scale(scale: 0.2, anchor: .bottom).combined(with: .opacity)
                    )
            }
        }
        .onAppear { volume.start() }
    }

    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.18)
    }
}

/// Cápsula flotante: cristal oscuro, el porcentaje arriba y el control vertical del sistema.
private struct VolumeCapsule: View {
    let tint: Color
    let ink: Color
    let volume: SystemVolume

    var body: some View {
        VStack(spacing: Space.s) {
            Text(volume.percentText)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(ink.opacity(0.75))
                .contentTransition(.numericText())
                .accessibilityHidden(true)
            SystemVolumeView(tint: UIColor(tint), track: UIColor(ink.opacity(0.16)), vertical: true)
                .frame(width: 44)
                .frame(maxHeight: .infinity)
        }
        .padding(.vertical, Space.m)
        .frame(width: 56, height: 196)
        .background(Color.black.opacity(0.55), in: .capsule)
        .glassEffect(.regular, in: .capsule)
        .overlay(Capsule().strokeBorder(ink.opacity(0.12)))
        .shadow(color: .black.opacity(0.45), radius: 16, y: 6)
        // Un toque dentro no cuenta como «tocar fuera» (que la cierra).
        .contentShape(.capsule)
        .onTapGesture {}
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Volumen")
    }
}

// MARK: - Control del sistema

/// `MPVolumeView` con el aspecto de Planaby. En vertical va dentro de un contenedor que lo gira
/// −90°: UIKit respeta el giro al tocar y arrastrar, y abajo queda el mínimo.
private struct SystemVolumeView: UIViewRepresentable {
    let tint: UIColor
    let track: UIColor
    let vertical: Bool

    func makeUIView(context: Context) -> VolumeHost {
        VolumeHost(vertical: vertical)
    }

    func updateUIView(_ host: VolumeHost, context: Context) {
        let view = host.volume
        view.tintColor = tint
        let thickness: CGFloat = vertical ? 6 : 4
        view.setMinimumVolumeSliderImage(Self.capsule(tint, thickness: thickness), for: .normal)
        view.setMaximumVolumeSliderImage(Self.capsule(track, thickness: thickness), for: .normal)
        view.setVolumeThumbImage(Self.thumb(vertical ? .white : tint, size: vertical ? 22 : 18), for: .normal)
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
