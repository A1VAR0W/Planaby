import SwiftUI

/// Horario en el que Planaby puede colocar bloques de trabajo de un modo.
struct ModeScheduleView: View {
    let mode: PlanMode
    @Environment(ModeController.self) private var modes
    @State private var availability: Availability

    init(mode: PlanMode) {
        self.mode = mode
        _availability = State(initialValue: ModeController.shared.availability(for: mode))
    }

    /// Lunes primero.
    private static let weekdays: [(id: Int, name: String)] = {
        let symbols = Calendar.current.shortStandaloneWeekdaySymbols
        return [2, 3, 4, 5, 6, 7, 1].map { ($0, symbols[$0 - 1].capitalized) }
    }()

    var body: some View {
        Form {
            Section {
                HStack(spacing: Space.xs) {
                    ForEach(Self.weekdays, id: \.id) { day in
                        let isOn = availability.weekdays.contains(day.id)
                        Button {
                            if isOn { availability.weekdays.remove(day.id) } else { availability.weekdays.insert(day.id) }
                        } label: {
                            Text(String(day.name.prefix(2)))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isOn ? Color.black : Color.white)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(isOn ? mode.tint : Theme.surface, in: .circle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(day.name)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                DatePicker("Desde", selection: minuteBinding(\.startMinute), displayedComponents: .hourAndMinute)
                DatePicker("Hasta", selection: minuteBinding(\.endMinute), displayedComponents: .hourAndMinute)
            } header: {
                Text("Días y horas")
            } footer: {
                if availability.endMinute <= availability.startMinute {
                    Text("La hora de fin tiene que ser posterior a la de inicio.")
                        .foregroundStyle(Theme.orange)
                }
            }

            Section {
                Stepper(value: $availability.maxBlockMinutes, in: 15...240, step: 15) {
                    LabeledContent("Bloque máximo", value: "\(availability.maxBlockMinutes) min")
                }
                Stepper(value: $availability.minBlockMinutes, in: 10...availability.maxBlockMinutes, step: 5) {
                    LabeledContent("Bloque mínimo", value: "\(availability.minBlockMinutes) min")
                }
                Stepper(value: $availability.breakMinutes, in: 0...60, step: 5) {
                    LabeledContent("Pausa entre bloques", value: "\(availability.breakMinutes) min")
                }
                Stepper(value: $availability.dailyCapMinutes, in: 30...720, step: 30) {
                    LabeledContent("Máximo al día", value: FocusStats.format(TimeInterval(availability.dailyCapMinutes * 60)))
                }
            } header: {
                Text("Bloques")
            } footer: {
                Text("La IA y las plantillas reparten las tareas de \(mode.title) solo dentro de este horario.")
            }
        }
        .navigationTitle("Horario de \(mode.title)")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: availability) {
            if availability.minBlockMinutes > availability.maxBlockMinutes {
                availability.minBlockMinutes = availability.maxBlockMinutes
                return
            }
            if availability.endMinute > availability.startMinute {
                modes.setAvailability(availability, for: mode)
            }
        }
    }

    private func minuteBinding(_ keyPath: WritableKeyPath<Availability, Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(byAdding: .minute, value: availability[keyPath: keyPath], to: Calendar.current.startOfDay(for: .now)) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                availability[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}
