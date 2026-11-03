import Charts
import SwiftUI

/// Test de ritmo: cuándo se concentra mejor la persona, cuánto aguanta, cómo prefiere empezar y
/// su horario. Con eso Planaby coloca lo exigente en sus mejores horas y ajusta el método.
struct FocusProfileTestView: View {
    /// Se abrió solo al estrenar la app (muestra "Ahora no").
    var isFirstRun = false
    @Environment(\.dismiss) private var dismiss
    @Environment(ModeController.self) private var modes
    @Environment(MethodLibrary.self) private var library

    @State private var step = 0
    @State private var profile = PersonalProfile.shared.profile
    @State private var work = ModeController.shared.availability(for: .work)
    @State private var personal = ModeController.shared.availability(for: .personal)

    private static let lastStep = 6

    /// Opciones de duración: minutos de bloque y método que se elige con ellas.
    private static let blockOptions: [(minutes: Int, title: String, detail: String, method: String, rest: Int)] = [
        (25, "Unos 25 minutos", "Me disperso pronto, mejor ratos cortos. Pomodoro 25/5.", "pomodoro", 5),
        (50, "Unos 50 minutos", "Aguanto bien una hora con un descanso. Hora redonda 50/10.", "50-10", 10),
        (90, "Hora y media o más", "Cuando entro en faena, me cuesta parar. Ultradiano 90/20.", "ultradian", 20),
        (60, "Depende del día", "Prefiero parar cuando lo note. Flowtime.", "flowtime", 15),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    page
                }
                .padding(Space.m)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: step)
    }

    // MARK: - Estructura

    private var header: some View {
        HStack(spacing: Space.m) {
            if step > 0 {
                Button {
                    withAnimation(.smooth) { step -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Atrás")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            ProgressView(value: Double(step), total: Double(Self.lastStep))
                .tint(Theme.orange)
                .accessibilityLabel("Paso \(step + 1) de \(Self.lastStep + 1)")
            Button {
                if isFirstRun { PersonalProfile.shared.markOffered() }
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Cerrar")
        }
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, Space.s)
    }

    private var footer: some View {
        VStack(spacing: Space.s) {
            Button {
                if step == Self.lastStep {
                    finish()
                } else {
                    withAnimation(.smooth) { step += 1 }
                }
            } label: {
                Text(primaryTitle)
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.orange)
            .controlSize(.large)
            .disabled(!canContinue)

            if step == 0 && isFirstRun {
                Button("Ahora no") {
                    PersonalProfile.shared.markOffered()
                    dismiss()
                }
                .foregroundStyle(Theme.secondaryText)
                .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.bottom, Space.s)
    }

    private var primaryTitle: String {
        switch step {
        case 0: "Empezar"
        case Self.lastStep: "Guardar mi ritmo"
        default: "Siguiente"
        }
    }

    private var canContinue: Bool {
        switch step {
        case 1: !profile.peaks.isEmpty
        case 5: !work.weekdays.isEmpty && work.endMinute > work.startMinute && personal.endMinute > personal.startMinute
        default: true
        }
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case 0: welcome
        case 1: periodsPage(
            title: "¿Cuándo te concentras mejor?",
            detail: "Elige todas las franjas en las que sueles rendir más. Ahí irá lo que más cabeza pide.",
            selection: $profile.peaks, disabled: [])
        case 2: periodsPage(
            title: "¿Y cuándo te cuesta más?",
            detail: "Ahí Planaby pondrá lo mecánico o lo dejará libre. Puedes no elegir ninguna.",
            selection: $profile.lows, disabled: profile.peaks)
        case 3: blockPage
        case 4: orderPage
        case 5: schedulePage
        default: resultPage
        }
    }

    // MARK: - Páginas

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 44))
                .foregroundStyle(Theme.orange)
                .padding(.top, Space.xl)
                .accessibilityHidden(true)
            Text("Conozcamos tu ritmo")
                .font(.largeTitle.weight(.bold))
            Text("Cinco preguntas rápidas para saber cuándo te concentras mejor. Con ellas, Planaby colocará lo difícil en tus mejores horas, elegirá la duración de tus bloques y replanificará pensando en ti.")
                .font(.body)
                .foregroundStyle(Theme.secondaryText)
            Label("Con el uso, Planaby también aprende de tus sesiones reales y de lo que tardas de verdad en cada tarea.", systemImage: "sparkles")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, Space.s)
        }
    }

    private func periodsPage(title: String, detail: String, selection: Binding<Set<DayPeriod>>, disabled: Set<DayPeriod>) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Heading(title: title, detail: detail)
            ForEach(DayPeriod.allCases) { period in
                let isOn = selection.wrappedValue.contains(period)
                let isDisabled = disabled.contains(period)
                ChoiceCard(
                    symbol: period.symbol, title: period.title, detail: period.rangeText,
                    isSelected: isOn, multiple: true
                ) {
                    if isOn { selection.wrappedValue.remove(period) } else { selection.wrappedValue.insert(period) }
                }
                .disabled(isDisabled)
                .opacity(isDisabled ? 0.4 : 1)
            }
        }
        .onAppear {
            // Una franja no puede ser a la vez la mejor y la peor.
            profile.lows.subtract(profile.peaks)
        }
    }

    private var blockPage: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Heading(title: "¿Cuánto aguantas concentrado de un tirón?", detail: "Será la duración máxima de tus bloques y tu método de Enfoque.")
            ForEach(Self.blockOptions, id: \.method) { option in
                ChoiceCard(
                    symbol: "timer", title: option.title, detail: option.detail,
                    isSelected: profile.blockMinutes == option.minutes, multiple: false
                ) {
                    profile.blockMinutes = option.minutes
                }
            }
        }
    }

    private var orderPage: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Heading(title: "¿Cómo prefieres empezar?", detail: "Así reparto lo ligero alrededor de lo difícil.")
            ChoiceCard(
                symbol: "mountain.2.fill", title: "Por lo difícil",
                detail: "Me quito lo gordo con la cabeza fresca y lo fácil va después.",
                isSelected: profile.hardFirst, multiple: false
            ) { profile.hardFirst = true }
            ChoiceCard(
                symbol: "figure.walk", title: "Calentando con algo fácil",
                detail: "Me cuesta arrancar; prefiero coger ritmo con tareas sencillas.",
                isSelected: !profile.hardFirst, multiple: false
            ) { profile.hardFirst = false }
        }
    }

    private var schedulePage: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Heading(title: "Tu horario", detail: "Planaby solo pondrá bloques dentro de estas franjas. Puedes cambiarlas en Ajustes.")

            VStack(alignment: .leading, spacing: Space.m) {
                Label("Trabajo o estudios", systemImage: PlanMode.work.symbol)
                    .font(.headline)
                WeekdayPicker(weekdays: $work.weekdays)
                HourRange(start: $work.startMinute, end: $work.endMinute)
            }
            .card()

            VStack(alignment: .leading, spacing: Space.m) {
                Label("Tiempo personal", systemImage: PlanMode.personal.symbol)
                    .font(.headline)
                HourRange(start: $personal.startMinute, end: $personal.endMinute)
            }
            .card()
        }
    }

    private var resultPage: some View {
        let energy = profile.energyByHour
        return VStack(alignment: .leading, spacing: Space.m) {
            Heading(title: "Tu ritmo", detail: summary)
            Chart(6..<24, id: \.self) { hour in
                BarMark(x: .value("Hora", hour), y: .value("Energía", energy[hour]))
                    .foregroundStyle(Theme.orange.opacity(0.25 + 0.75 * energy[hour]))
                    .cornerRadius(3)
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: [6, 9, 12, 15, 18, 21]) { value in
                    AxisValueLabel { Text("\(value.as(Int.self) ?? 0) h") }
                }
            }
            .frame(height: 160)
            .card()
            .accessibilityLabel("Energía por hora")
            .accessibilityValue("Mejores franjas: \(profile.peaks.sorted { $0.hours.lowerBound < $1.hours.lowerBound }.map(\.title).joined(separator: ", "))")
        }
    }

    private var summary: String {
        let peaks = profile.peaks.sorted { $0.hours.lowerBound < $1.hours.lowerBound }.map { $0.title.lowercased() }
        let method = Self.blockOptions.first { $0.minutes == profile.blockMinutes }
        var text = "Lo exigente irá por la \(peaks.joined(separator: " y ")), en bloques de hasta \(profile.blockMinutes) min"
        text += profile.hardFirst ? ", empezando por lo difícil." : ", calentando primero con lo sencillo."
        if let method, let name = library.all.first(where: { $0.id == method.method })?.name {
            text += " Tu método de Enfoque pasa a ser \(name)."
        }
        return text
    }

    // MARK: - Guardar

    private func finish() {
        let option = Self.blockOptions.first { $0.minutes == profile.blockMinutes }
        var saved = profile
        saved.isCompleted = true
        saved.wasOffered = true
        PersonalProfile.shared.save(saved)

        for (mode, chosen) in [(PlanMode.work, work), (.personal, personal)] {
            var availability = chosen
            availability.maxBlockMinutes = profile.blockMinutes
            availability.minBlockMinutes = min(availability.minBlockMinutes, profile.blockMinutes)
            availability.breakMinutes = option?.rest ?? availability.breakMinutes
            modes.setAvailability(availability, for: mode)
        }
        if let method = option?.method, library.all.contains(where: { $0.id == method }) {
            library.selectedID = method
        }
        dismiss()
    }
}

// MARK: - Piezas

private struct Heading: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(title)
                .font(.title2.weight(.bold))
                .padding(.top, Space.m)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct ChoiceCard: View {
    let symbol: String
    let title: String
    let detail: String
    let isSelected: Bool
    let multiple: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.m) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.orange : Theme.secondaryText)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? (multiple ? "checkmark.square.fill" : "checkmark.circle.fill") : (multiple ? "square" : "circle"))
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.orange : Theme.secondaryText)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            .padding(Space.m)
            .frame(minHeight: 64)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(isSelected ? Theme.orange.opacity(0.7) : Color.clear, lineWidth: 1.5)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

/// Días de la semana de lunes a domingo (valores de `Calendar`: 1 = domingo).
struct WeekdayPicker: View {
    @Binding var weekdays: Set<Int>
    private static let order = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let names = Calendar.current.standaloneWeekdaySymbols
        HStack(spacing: Space.xs) {
            ForEach(Self.order, id: \.self) { day in
                let isOn = weekdays.contains(day)
                Button {
                    if isOn { weekdays.remove(day) } else { weekdays.insert(day) }
                } label: {
                    Text(symbols[day - 1].uppercased())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isOn ? Color.black : Color.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isOn ? Theme.orange : Theme.surface, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(names[day - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

/// Franja horaria en minutos desde medianoche.
struct HourRange: View {
    @Binding var start: Int
    @Binding var end: Int

    var body: some View {
        VStack(spacing: Space.s) {
            DatePicker("Desde", selection: binding($start), displayedComponents: .hourAndMinute)
            DatePicker("Hasta", selection: binding($end), displayedComponents: .hourAndMinute)
            if end <= start {
                Text("La hora de fin debe ser posterior a la de inicio.")
                    .font(.footnote)
                    .foregroundStyle(Theme.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func binding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}
