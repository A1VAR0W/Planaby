import Combine
import SwiftUI

/// Modo escritorio con el iPhone en horizontal: una sola cifra grande sobre negro y un halo que respira.
/// Tocar empieza o pausa; mantener pulsado ofrece saltar fase o terminar. Mientras carga, la
/// pantalla no se apaga, y de noche todo pasa a rojo tenue, como StandBy.
struct DeskView: View {
    @Environment(FocusTimer.self) private var timer
    @Environment(MethodLibrary.self) private var library
    @State private var isCharging = false
    @State private var showingActions = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let night = Self.isNight(context.date)
            let state = timer.state
            let tint = night ? Theme.night : (state?.phase.tint ?? Theme.orange)
            let ink = night ? Theme.night : Color.white

            ZStack {
                Color.black
                BreathingGlow(tint: tint, strength: night ? 0.10 : (state?.phase.isBreak == true ? 0.30 : 0.18))

                VStack(spacing: 6) {
                    if let state {
                        Eyebrow(text: state.isPaused ? "En pausa" : state.phase.title, color: tint)
                        Text(state.clockText(at: context.date))
                            .font(Theme.clock(150))
                            .foregroundStyle(ink.opacity(state.isPaused ? 0.5 : 1))
                            .contentTransition(.numericText(countsDown: true))
                        Group {
                            if state.phase.isBreak && !state.isPaused {
                                BreathingHint(tint: tint)
                            } else {
                                Text("\(context.date.formatted(date: .omitted, time: .shortened)) · \(state.method.name)")
                                    .font(.footnote)
                                    .foregroundStyle(ink.opacity(0.4))
                            }
                        }
                    } else {
                        Text(context.date, format: .dateTime.hour().minute())
                            .font(Theme.clock(170))
                            .foregroundStyle(ink)
                        Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.title3)
                            .foregroundStyle(ink.opacity(0.4))
                        Text("Toca para empezar · \(library.selected.name)")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(tint.opacity(0.8))
                            .padding(.top, 10)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)

                VStack {
                    HStack {
                        Spacer()
                        if isCharging {
                            Image(systemName: "bolt.fill")
                                .font(.caption)
                                .foregroundStyle(ink.opacity(0.35))
                        }
                    }
                    Spacer()
                    if let state, state.phaseEnd != nil {
                        ProgressLine(progress: state.progress(at: context.date), tint: tint)
                    }
                }
                .padding(.horizontal, 64)
                .padding(.vertical, 28)
            }
        }
        .ignoresSafeArea()
        .contentShape(.rect)
        .onTapGesture {
            if timer.state == nil { timer.start(library.selected) } else { timer.togglePause() }
        }
        .onLongPressGesture {
            if timer.state != nil { showingActions = true }
        }
        .confirmationDialog("Sesión", isPresented: $showingActions) {
            Button("Saltar fase") { timer.skip() }
            Button("Terminar sesión", role: .destructive) { timer.stop() }
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: timer.state?.isPaused)
        .environment(\.colorScheme, .dark)
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            updateCharging()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            updateCharging()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func updateCharging() {
        let batteryState = UIDevice.current.batteryState
        isCharging = batteryState == .charging || batteryState == .full
        UIApplication.shared.isIdleTimerDisabled = isCharging
    }

    private static func isNight(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 22 || hour < 7
    }
}

/// Línea de progreso finísima en la parte inferior.
private struct ProgressLine: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * progress)
                    .shadow(color: tint.opacity(0.6), radius: 6)
                    .animation(.linear(duration: 1), value: progress)
            }
        }
        .frame(height: 3)
    }
}
