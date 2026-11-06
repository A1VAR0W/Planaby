import SwiftUI

/// Fecha, hora de inicio y hora de fin de un evento, para cualquier formulario. La duración no
/// se escribe: se calcula y se enseña debajo, junto con lo que coincide en el calendario.
///
/// - Al cambiar el día se conservan las horas (y los días que dura).
/// - Al cambiar el inicio, el fin se queda donde estaba mientras siga siendo posterior; si no,
///   se mueve con él para no perder la duración.
/// - Al cambiar el fin, el inicio no se toca. Si queda antes del inicio se avisa, con un atajo
///   para que termine al día siguiente (nunca se cruza la medianoche sin pedirlo).
struct EventTimeFields: View {
    @Binding var start: Date
    @Binding var end: Date
    /// Lo que coincide con estas horas (lo calcula quien enseña el formulario).
    var conflicts: [EventConflict] = []
    /// Puede terminar otro día (eventos de noche o de varios días).
    var allowsSeveralDays = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var times: EventTimes { EventTimes(start: start, end: end) }
    private var span: Int { EventSchedule.daySpan(times) }

    var body: some View {
        DatePicker("Fecha", selection: dayBinding, displayedComponents: .date)
        DatePicker("Inicio", selection: startBinding, displayedComponents: .hourAndMinute)
        DatePicker("Fin", selection: endBinding, displayedComponents: .hourAndMinute)
        if allowsSeveralDays {
            Toggle("Termina otro día", isOn: spansBinding)
            if span > 0 {
                DatePicker(
                    "Día de fin", selection: endDayBinding,
                    in: Calendar.current.startOfDay(for: start)..., displayedComponents: .date
                )
            }
        }
        status
            .animation(Motion.adaptive(Motion.quick, reduceMotion: reduceMotion), value: times)
        ForEach(conflicts.prefix(3)) { conflict in
            Label {
                Text("Coincide con «\(conflict.title)» · \(ProposalFormat.dayName(conflict.interval.start)) \(EventSchedule.rangeText(EventTimes(start: conflict.interval.start, end: conflict.interval.end)))")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.footnote)
            .foregroundStyle(Theme.orange)
        }
        if conflicts.count > 3 {
            Text("y \(conflicts.count - 3) más a la vez")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    @ViewBuilder
    private var status: some View {
        if let issue = EventSchedule.issue(times) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Label(issue.message, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.orange)
                if issue == .endNotAfterStart, allowsSeveralDays, span == 0 {
                    Button("Termina al día siguiente") { spansBinding.wrappedValue = true }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.orange)
                        .buttonStyle(.borderless)
                }
            }
        } else {
            LabeledContent("Duración") {
                Text(span > 0 ? "\(ProposalFormat.minutes(times.minutes)) · termina \(ProposalFormat.dayName(end))" : ProposalFormat.minutes(times.minutes))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Enlaces con las reglas de `EventSchedule`

    private var dayBinding: Binding<Date> {
        Binding(get: { start }, set: { day in apply(EventSchedule.moving(times, toDay: day)) })
    }

    private var startBinding: Binding<Date> {
        Binding(get: { start }, set: { time in
            apply(EventSchedule.settingStart(EventSchedule.minuteOfDay(time), of: times, keepEnd: true))
        })
    }

    private var endBinding: Binding<Date> {
        Binding(get: { end }, set: { time in
            // El fin va el día en que ya terminaba (el del inicio si era el mismo).
            end = EventSchedule.end(atTimeOf: time, onDay: span > 0 ? end : start)
        })
    }

    private var spansBinding: Binding<Bool> {
        Binding(get: { span > 0 }, set: { spans in
            let calendar = Calendar.current
            let day = calendar.date(byAdding: .day, value: spans ? 1 : 0, to: calendar.startOfDay(for: start)) ?? start
            end = EventSchedule.end(atTimeOf: end, onDay: day)
        })
    }

    private var endDayBinding: Binding<Date> {
        Binding(get: { end }, set: { day in end = EventSchedule.end(atTimeOf: end, onDay: day) })
    }

    private func apply(_ new: EventTimes) {
        start = new.start
        end = new.end
    }
}
