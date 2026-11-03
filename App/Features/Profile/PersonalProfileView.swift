import Charts
import SwiftData
import SwiftUI

/// Ajustes › Tu ritmo: lo que Planaby sabe de la persona (test + historial) y cómo lo usa.
struct PersonalProfileView: View {
    @Environment(\.modelContext) private var context
    @State private var showsTest = false
    private let personal = PersonalProfile.shared

    var body: some View {
        let energy = personal.energyByHour
        let profile = personal.profile

        Form {
            Section {
                Chart(6..<24, id: \.self) { hour in
                    BarMark(x: .value("Hora", hour), y: .value("Energía", energy[hour]))
                        .foregroundStyle(Theme.orange.opacity(0.25 + 0.75 * min(1, energy[hour])))
                        .cornerRadius(3)
                }
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: [6, 9, 12, 15, 18, 21]) { value in
                        AxisValueLabel { Text("\(value.as(Int.self) ?? 0) h") }
                    }
                }
                .frame(height: 150)
                .padding(.vertical, Space.s)
                .accessibilityLabel("Energía por hora")
                .accessibilityValue("Mejores horas: \(personal.bestHoursText)")
                LabeledContent("Mejores horas", value: personal.bestHoursText)
            } header: {
                Text("Energía a lo largo del día")
            } footer: {
                Text(personal.learnedSessions > 0
                     ? "Mezcla tus respuestas con \(personal.learnedSessions) sesiones de los últimos 30 días."
                     : "Sale de tus respuestas. Con el uso se ajustará a tus sesiones reales.")
            }

            Section("Preferencias") {
                LabeledContent("Bloques de hasta", value: "\(profile.blockMinutes) min")
                LabeledContent("Empiezas", value: profile.hardFirst ? "Por lo difícil" : "Por lo sencillo")
                LabeledContent("Te cuesta más", value: profile.lows.isEmpty
                    ? "Ninguna franja"
                    : profile.lows.sorted { $0.hours.lowerBound < $1.hours.lowerBound }.map(\.title).joined(separator: ", "))
            }

            Section {
                LabeledContent("Tareas medidas", value: "\(personal.estimateSamples)")
                LabeledContent("Tiempo real / estimado", value: personal.estimateSamples > 0
                    ? personal.estimateRatio.formatted(.percent.precision(.fractionLength(0)))
                    : "—")
            } header: {
                Text("Estimaciones")
            } footer: {
                Text(personal.estimateNote ?? "Cuando empiezas a concentrarte desde un bloque, Planaby apunta cuánto tardas de verdad en cada tarea y corrige las próximas estimaciones.")
            }

            Section {
                Button(profile.isCompleted ? "Repetir el test" : "Hacer el test", systemImage: "waveform.path.ecg") {
                    showsTest = true
                }
            }
        }
        .navigationTitle("Tu ritmo")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { personal.refresh(context: context) }
        .fullScreenCover(isPresented: $showsTest) {
            FocusProfileTestView()
        }
    }
}
