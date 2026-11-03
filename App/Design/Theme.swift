import SwiftUI

enum Theme {
    static let focus = Color(red: 1.0, green: 0.42, blue: 0.29)
    static let shortBreak = Color(red: 0.36, green: 0.82, blue: 0.64)
    static let longBreak = Color(red: 0.47, green: 0.58, blue: 1.0)

    static func clock(_ size: CGFloat) -> Font {
        .system(size: size, weight: .thin, design: .rounded).monospacedDigit()
    }

    static let eyebrow = Font.caption.weight(.semibold)
}

extension PhaseKind {
    var tint: Color {
        switch self {
        case .focus: Theme.focus
        case .shortBreak: Theme.shortBreak
        case .longBreak: Theme.longBreak
        }
    }
}

/// Fondo neutro con un halo muy suave del color de la fase.
struct PhaseBackground: View {
    let tint: Color

    var body: some View {
        ZStack {
            Color(.systemBackground)
            RadialGradient(colors: [tint.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 560)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: tint)
    }
}

struct Eyebrow: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text.uppercased())
            .font(Theme.eyebrow)
            .tracking(2)
            .foregroundStyle(color)
    }
}

struct RoundButton: View {
    let label: String
    let systemImage: String
    var prominent = false
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        let size: CGFloat = prominent ? 84 : 60
        let button = Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: prominent ? 30 : 20, weight: .medium))
                .frame(width: size, height: size)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)

        if prominent {
            button.buttonStyle(.glassProminent).tint(tint)
        } else {
            button.buttonStyle(.glass)
        }
    }
}

struct ProgressRing: View {
    let progress: Double
    let tint: Color
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.07), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
        }
    }
}
