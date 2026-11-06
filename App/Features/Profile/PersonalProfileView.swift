import Charts
import SwiftData
import SwiftUI

/// Ajustes › Tu ritmo: lo que Planaby sabe de la persona (test + historial) y cómo lo usa.
struct PersonalProfileView: View {
    @Environment(\.modelContext) private var context
    @State private var showsTest = false
    @State private var coordinator = AdaptiveFocusCoordinator.shared
    @State private var learnedMode: PlanMode = ModeController.shared.mode
    @State private var confirmingReset = false
    @AppStorage("askFocusRating") private var asksRating = true
    @Query(sort: \FocusSessionRecord.start, order: .reverse) private var sessions: [FocusSessionRecord]
    @Query(sort: \DistractionRecord.date, order: .reverse) private var distractions: [DistractionRecord]
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

            learnedSection

            Section {
                Toggle("Sugerencias adaptativas", isOn: Binding(get: { coordinator.isEnabled }, set: { coordinator.isEnabled = $0 }))
                Toggle("Preguntar cómo te has concentrado", isOn: $asksRating)
                Button("Reiniciar lo aprendido", systemImage: "arrow.counterclockwise", role: .destructive) {
                    confirmingReset = true
                }
            } header: {
                Text("Adaptación")
            } footer: {
                Text("Las sugerencias aparecen de una en una en Enfoque y nunca cambian nada sin que pulses «Probar». La pregunta al terminar es opcional y solo sale en sesiones de 10 minutos o más.")
            }

            Section {
                Button(profile.isCompleted ? "Repetir el test" : "Hacer el test", systemImage: "waveform.path.ecg") {
                    showsTest = true
                }
            }
        }
        .confirmationDialog("¿Reiniciar lo aprendido?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reiniciar", role: .destructive) { coordinator.resetLearning() }
        } message: {
            Text("Planaby empezará a aprender desde hoy. Tu historial y tus estadísticas no se borran.")
        }
        .navigationTitle("Tu ritmo")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { personal.refresh(context: context) }
        .fullScreenCover(isPresented: $showsTest) {
            FocusProfileTestView()
        }
    }

    /// Lo que el motor ha sacado del historial, por plan: muestras, horas y métodos.
    private var learnedSection: some View {
        let report = coordinator.report(
            sessions: Array(sessions.prefix(200)), distractions: Array(distractions.prefix(300)), mode: learnedMode
        )
        return Section {
            Picker("Plan", selection: $learnedMode) {
                Text("Trabajo").tag(PlanMode.work)
                Text("Normal").tag(PlanMode.personal)
            }
            .pickerStyle(.segmented)
            LabeledContent("Sesiones analizadas", value: "\(report.sampleCount)")
            if let hour = report.bestHours.first {
                LabeledContent("Terminas mejor", value: "\(hour):00–\(hour + 2):00")
            }
            if let hour = report.interruptionHour {
                LabeledContent("Más distracciones", value: "hacia las \(hour):00")
            }
            ForEach(report.methodStats.prefix(3)) { stat in
                let name = MethodLibrary.shared.all.first { $0.id == stat.methodID }?.name ?? stat.methodID
                LabeledContent(name, value: "\(stat.sessions) · \(stat.completionRate.formatted(.percent.precision(.fractionLength(0)))) completadas")
            }
            if report.recommendations.isEmpty {
                Text(report.sampleCount < 5
                     ? "Hacen falta al menos 5 sesiones en este plan para sugerir algo."
                     : "Con lo que hay, no cambiaría nada: tu ritmo actual te funciona.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(report.recommendations) { recommendation in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recommendation.title).font(.subheadline.weight(.semibold))
                        Text(recommendation.reason).font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        } header: {
            Text("Lo aprendido")
        } footer: {
            Text((coordinator.resetDate.map { "Desde el \($0.formatted(date: .long, time: .omitted)). " } ?? "")
                 + "Solo mira los últimos 45 días. Trabajo y Normal se aprenden por separado; una sesión larga no cuenta como buena si se interrumpe mucho.")
        }
    }
}
