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
                Text("Días y horario habitual")
            } footer: {
                if availability.endMinute <= availability.startMinute {
                    Text("La hora de fin tiene que ser posterior a la de inicio.")
                        .foregroundStyle(Theme.orange)
                }
            }

            specialDaysSection

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
            if availability.isValid {
                modes.setAvailability(availability, for: mode)
            }
        }
    }

    // MARK: - Días con otro horario

    private var specialDays: [(id: Int, name: String)] {
        Self.weekdays.filter { availability.dayHours?[$0.id] != nil }
    }

    private var specialDaysSection: some View {
        let candidates = Self.weekdays.filter { availability.weekdays.contains($0.id) && availability.dayHours?[$0.id] == nil }
        return Section {
            ForEach(specialDays, id: \.id) { day in
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack {
                        Text(Self.fullName(day.id)).font(.body.weight(.semibold))
                        if !availability.weekdays.contains(day.id) {
                            Text("· día no activo")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Button("Quitar", systemImage: "minus.circle.fill") {
                            withAnimation(.smooth) { setHours(nil, for: day.id) }
                        }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 44, height: 44)
                        .buttonStyle(.plain)
                        .accessibilityLabel("Quitar el horario del \(Self.fullName(day.id))")
                    }
                    DatePicker("Desde", selection: dayBinding(day.id, \.startMinute), displayedComponents: .hourAndMinute)
                    DatePicker("Hasta", selection: dayBinding(day.id, \.endMinute), displayedComponents: .hourAndMinute)
                    if let hours = availability.dayHours?[day.id], hours.endMinute <= hours.startMinute {
                        Text("La hora de fin tiene que ser posterior a la de inicio.")
                            .font(.footnote)
                            .foregroundStyle(Theme.orange)
                    }
                }
            }
            if !candidates.isEmpty {
                Menu {
                    ForEach(candidates, id: \.id) { day in
                        Button(Self.fullName(day.id)) {
                            withAnimation(.smooth) {
                                setHours(.init(startMinute: availability.startMinute, endMinute: availability.endMinute), for: day.id)
                            }
                        }
                    }
                } label: {
                    Label("Añadir día con otro horario", systemImage: "plus")
                }
            }
        } header: {
            Text("Días con otro horario")
        } footer: {
            Text("Por ejemplo, los viernes de 8:00 a 15:00. Ese día Planaby solo pondrá bloques dentro de ese horario.")
        }
    }

    private static func fullName(_ weekday: Int) -> String {
        Calendar.current.standaloneWeekdaySymbols[weekday - 1].capitalized
    }

    private func setHours(_ hours: Availability.DayHours?, for weekday: Int) {
        var all = availability.dayHours ?? [:]
        all[weekday] = hours
        availability.dayHours = all.isEmpty ? nil : all
    }

    private func dayBinding(_ weekday: Int, _ keyPath: WritableKeyPath<Availability.DayHours, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = availability.hours(onWeekday: weekday)[keyPath: keyPath]
                return Calendar.current.date(byAdding: .minute, value: minutes, to: Calendar.current.startOfDay(for: .now)) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                var hours = availability.hours(onWeekday: weekday)
                hours[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                setHours(hours, for: weekday)
            }
        )
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
