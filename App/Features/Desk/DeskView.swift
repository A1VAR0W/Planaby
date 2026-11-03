import Combine
import SwiftUI

/// Modo escritorio: con el iPhone en horizontal. Mientras carga, la pantalla no se apaga;
/// de noche todo pasa a rojo tenue, como StandBy.
struct DeskView: View {
    @Environment(FocusTimer.self) private var timer
    @Environment(MethodLibrary.self) private var library
    @State private var isCharging = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let ink = Self.isNight(context.date) ? Theme.night : Color.white
            HStack(alignment: .center, spacing: 40) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(Theme.clock(120))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        if isCharging {
                            Image(systemName: "bolt.fill").font(.caption)
                        }
                    }
                    .font(.title3)
                    .opacity(0.6)
                }
                .foregroundStyle(ink)

                Spacer(minLength: 0)

                if let state = timer.state {
                    session(state, at: context.date, ink: ink)
                } else {
                    Button { timer.start(library.selected) } label: {
                        Label("Empezar \(library.selected.name)", systemImage: "play.fill")
                            .font(.headline)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Self.isNight(context.date) ? Theme.night : Theme.focus)
                }
            }
            .padding(.horizontal, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
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

    private func session(_ state: TimerState, at date: Date, ink: Color) -> some View {
        let tint = Self.isNight(date) ? Theme.night : state.phase.tint
        return Button { timer.togglePause() } label: {
            ZStack {
                ProgressRing(progress: state.progress(at: date), tint: tint, lineWidth: 3)
                VStack(spacing: 4) {
                    Eyebrow(text: state.isPaused ? "En pausa" : state.phase.title, color: tint)
                    Text(state.clockText(at: date))
                        .font(Theme.clock(52))
                        .foregroundStyle(ink)
                }
            }
            .frame(width: 220, height: 220)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.isPaused ? "Reanudar" : "Pausar")
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
