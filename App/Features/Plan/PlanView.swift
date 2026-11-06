import SwiftData
import SwiftUI

/// Pestaña Plan: semana, agenda del día y tareas pendientes del modo actual.
/// En modo Trabajo se ven los dos planes; en Normal, solo el personal.
struct PlanView: View {
    @Environment(ModeController.self) private var modes
    @Environment(PlanInbox.self) private var inbox
    @Environment(FocusTimer.self) private var timer
    @Environment(MethodLibrary.self) private var library
    @Environment(\.modelContext) private var context
    @Query(sort: \CalendarEvent.start) private var events: [CalendarEvent]
    @Query(filter: #Predicate<PlanTask> { !$0.isDone }, sort: \PlanTask.deadline) private var tasks: [PlanTask]
    @Query(filter: #Predicate<CapturedTask> { $0.statusRaw == "pending" }, sort: \CapturedTask.created, order: .reverse)
    private var captures: [CapturedTask]

    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var form: PlanForm?
    @State private var showingChat = false
    @State private var showingReorganize = false
    @State private var openTask: PlanTask?
    @State private var voice: VoiceTaskFlow?
    private let external = ExternalCalendars.shared
    @State private var deletingEvent: CalendarEvent?
    @State private var deletingTask: PlanTask?

    var body: some View {
        let visible = modes.mode.visibleModes
        let _ = external.revision
        let dayRows = rows(on: selectedDay, visible: visible)
        let pendingTasks = tasks.filter { visible.contains($0.mode) }

        List {
            Section {
                CalendarHeader(selectedDay: $selectedDay) { day in
                    markers(on: day, visible: visible)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                if dayRows.isEmpty {
                    EmptyDay()
                } else {
                    ForEach(dayRows) { row in
                        switch row {
                        case .external(let event):
                            ExternalAgendaRow(event: event)
                        case .local(let entry):
                            AgendaRow(entry: entry) {
                                Task {
                                    await NotificationAccess.requestIfNeeded()
                                    timer.start(library.selected, task: entry.event.task?.title ?? entry.event.title, taskID: entry.event.task?.stableID)
                                }
                            }
                            .contentShape(.rect)
                            .onTapGesture { form = .edit(entry.event) }
                            .swipeActions {
                                Button("Borrar", systemImage: "trash", role: .destructive) { deletingEvent = entry.event }
                                Button("Editar", systemImage: "pencil") { form = .edit(entry.event) }
                                    .tint(Theme.amber)
                            }
                        }
                    }
                }
            } header: {
                DayHeader(day: selectedDay, mode: modes.mode)
            }

            // Lo apuntado con la captura rápida, de los dos planes (cada una dice el suyo).
            let unsorted = captures.filter { CaptureRules.isPending($0.entry, now: .now) }
            if !unsorted.isEmpty || captures.contains(where: { $0.status == .pending }) {
                Section {
                    ForEach(unsorted.prefix(5)) { capture in
                        Button { voice = CaptureCenter.planningFlow(for: capture) } label: {
                            CaptureRow(capture: capture)
                        }
                        .buttonStyle(.plain)
                        .modifier(CaptureActions(capture: capture) { voice = CaptureCenter.planningFlow(for: $0) })
                    }
                    NavigationLink {
                        CaptureInboxView()
                    } label: {
                        Text(unsorted.count > 5 ? "Ver las \(unsorted.count)" : "Ver todo lo apuntado")
                            .font(.subheadline)
                    }
                } header: {
                    Text(unsorted.isEmpty ? "Por organizar" : "Por organizar · \(unsorted.count)")
                } footer: {
                    Text("Toca una para planificarla. Nada entra en el calendario sin que lo confirmes.")
                }
            }

            if !pendingTasks.isEmpty {
                Section("Tareas") {
                    ForEach(pendingTasks) { task in
                        TaskRow(task: task)
                            .contentShape(.rect)
                            .onTapGesture { openTask = task }
                            .accessibilityAddTraits(.isButton)
                            .swipeActions(edge: .leading) {
                                Button("Hecha", systemImage: "checkmark") {
                                    TaskActions.complete(task, context: context)
                                }
                                .tint(Theme.orange)
                            }
                            .swipeActions {
                                Button("Borrar", systemImage: "trash", role: .destructive) { deletingTask = task }
                            }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .refreshable { await external.syncAll() }
        .background(Color.black)
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ModePicker()
            }
            ToolbarItem(placement: .topBarLeading) {
                if !Calendar.current.isDateInToday(selectedDay) {
                    Button("Hoy") {
                        withAnimation(Motion.standard) { selectedDay = Calendar.current.startOfDay(for: .now) }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reorganizar", systemImage: "arrow.up.arrow.down") { showingReorganize = true }
                    .disabled(tasks.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Evento", systemImage: "calendar") { form = .newEvent(selectedDay, .event) }
                    Button("Tarea con fecha límite", systemImage: "square.stack.3d.up") { form = .newTask }
                    Button("Hábito", systemImage: "repeat") { form = .newEvent(selectedDay, .habit) }
                } label: {
                    Label("Añadir", systemImage: "plus")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            // Un solo botón de IA: escribir (a la izquierda) o hablar (el micrófono, a la derecha).
            HStack(spacing: 0) {
                Button { showingChat = true } label: {
                    Label("Planificar con IA", systemImage: "sparkles")
                        .font(.headline)
                        .padding(.leading, Space.l)
                        .padding(.trailing, Space.m)
                        .frame(minHeight: 48)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)

                Rectangle()
                    .fill(Color.black.opacity(0.25))
                    .frame(width: 1, height: 24)
                    .accessibilityHidden(true)

                Button { voice = VoiceTaskFlow() } label: {
                    Image(systemName: "mic.fill")
                        .font(.headline)
                        .frame(width: 52, height: 48)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Añadir por voz")
                .accessibilityHint("Dicta una tarea o una cita")
            }
            .foregroundStyle(.black)
            .glassEffect(.regular.tint(Theme.orange).interactive(), in: .capsule)
            .padding(.bottom, Space.s)
        }
        .voiceTaskSheet($voice)
        .sheet(item: $form) { form in
            NavigationStack {
                switch form {
                case .newEvent(let day, let kind):
                    EventForm(event: nil, day: day, kind: kind)
                case .edit(let event):
                    EventForm(event: event, day: event.start, kind: event.kind)
                case .newTask:
                    TaskForm()
                }
            }
        }
        .sheet(isPresented: $showingChat) {
            NavigationStack { PlanChatView() }
        }
        .sheet(isPresented: $showingReorganize) {
            NavigationStack { ReorganizeView() }
        }
        .navigationDestination(item: $openTask) { task in
            TaskDetailView(task: task)
        }
        .confirmationDialog(
            "¿Borrar «\(deletingEvent?.title ?? "")»?",
            isPresented: Binding(get: { deletingEvent != nil }, set: { if !$0 { deletingEvent = nil } }),
            titleVisibility: .visible,
            presenting: deletingEvent
        ) { event in
            Button(event.recurrence == .none ? "Borrar" : "Borrar todas las repeticiones", role: .destructive) {
                context.delete(event)
                try? context.save()
                ReminderScheduler.shared.reschedule()
            }
        }
        .confirmationDialog(
            "¿Borrar la tarea «\(deletingTask?.title ?? "")»?",
            isPresented: Binding(get: { deletingTask != nil }, set: { if !$0 { deletingTask = nil } }),
            titleVisibility: .visible,
            presenting: deletingTask
        ) { task in
            Button("Borrar tarea y sus bloques", role: .destructive) {
                TaskActions.delete(task, context: context)
            }
        }
        .onChange(of: inbox.pending, initial: true) { _, pending in
            if pending != nil { showingChat = true }
        }
        .onAppear {
            external.refreshStatus()
            external.syncIfNeeded()
        }
    }

    /// Lo del día: eventos de Planaby y de los calendarios externos, por hora (todo el día primero).
    private func rows(on day: Date, visible: Set<PlanMode>) -> [DayRow] {
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: day) else { return [] }
        // Los calendarios externos (los del iPhone van a Normal) solo se ven en su propio plan:
        // en Trabajo no aparecen los eventos personales del iPhone.
        let mode = modes.mode
        let outside = external.events(in: DateInterval(start: day, end: end))
            .filter { $0.mode == mode }
            .map(DayRow.external)
        return (entries(on: day, visible: visible).map(DayRow.local) + outside)
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }

    /// Colores de los puntos de un día (como mucho tres, uno por plan o calendario).
    private func markers(on day: Date, visible: Set<PlanMode>) -> [Color] {
        var colors: [Color] = []
        for row in rows(on: day, visible: visible) {
            let color: Color
            switch row {
            case .local(let entry): color = entry.event.mode.tint
            case .external(let event): color = event.color
            }
            if !colors.contains(color) { colors.append(color) }
            if colors.count == 3 { break }
        }
        return colors
    }

    private func entries(on day: Date, visible: Set<PlanMode>) -> [AgendaEntry] {
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: day) else { return [] }
        let range = DateInterval(start: day, end: end)
        return events
            .filter { visible.contains($0.mode) }
            .flatMap { event in event.occurrences(in: range).map { AgendaEntry(event: event, interval: $0) } }
            .sorted { $0.interval.start < $1.interval.start }
    }
}

/// Formularios que se abren desde la pestaña Plan.
enum PlanForm: Identifiable {
    case newEvent(Date, EventKind)
    case edit(CalendarEvent)
    case newTask

    var id: String {
        switch self {
        case .newEvent(let day, let kind): "new-\(kind.rawValue)-\(day.timeIntervalSinceReferenceDate)"
        case .edit(let event): "edit-\(event.persistentModelID.hashValue)"
        case .newTask: "task"
        }
    }
}

/// Fila de la agenda: de Planaby o de otro calendario.
enum DayRow: Identifiable {
    case local(AgendaEntry)
    case external(ExternalEvent)

    var id: String {
        switch self {
        case .local(let entry): entry.id
        case .external(let event): "ext-\(event.id)"
        }
    }

    var start: Date {
        switch self {
        case .local(let entry): entry.interval.start
        case .external(let event): event.start
        }
    }

    var isAllDay: Bool {
        if case .external(let event) = self { return event.isAllDay }
        return false
    }
}

/// Una aparición de un evento en un día concreto.
struct AgendaEntry: Identifiable {
    let event: CalendarEvent
    let interval: DateInterval
    var id: String { "\(event.persistentModelID.hashValue)-\(interval.start.timeIntervalSinceReferenceDate)" }
}

// MARK: - Piezas

/// Selector de modo: Trabajo o Normal.
struct ModePicker: View {
    @Environment(ModeController.self) private var modes

    var body: some View {
        Picker("Modo", selection: Binding(get: { modes.mode }, set: { modes.set($0) })) {
            ForEach(PlanMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 200)
        .sensoryFeedback(.selection, trigger: modes.mode)
        .accessibilityHint("En modo Normal se silencian los recordatorios de Trabajo")
    }
}

private struct DayHeader: View {
    let day: Date
    let mode: PlanMode

    var body: some View {
        HStack {
            Text(Calendar.current.isDateInToday(day) ? "Hoy" : day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            Spacer()
            if mode == .personal {
                Label("Trabajo en silencio", systemImage: "bell.slash")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

private struct EmptyDay: View {
    var body: some View {
        VStack(spacing: Space.xs) {
            Image(systemName: "sun.max")
                .font(.title2)
                .foregroundStyle(Theme.orange)
                .accessibilityHidden(true)
            Text("Día libre").font(.headline)
            Text("Añade algo con + o pide a la IA que te organice.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.l)
    }
}

/// Semana o mes entero (como el Calendario del iPhone): se cambia tocando el nombre del mes.
/// Las flechas y el deslizamiento lateral pasan de semana o de mes.
private struct CalendarHeader: View {
    @Binding var selectedDay: Date
    let markers: (Date) -> [Color]
    @AppStorage(Preferences.planShowsMonth) private var showsMonth = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    var body: some View {
        VStack(spacing: Space.s) {
            HStack {
                Button {
                    withAnimation(reduceMotion ? nil : Motion.standard) { showsMonth.toggle() }
                } label: {
                    HStack(spacing: Space.xs) {
                        Text(selectedDay.formatted(.dateTime.month(.wide).year()).capitalized)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .rotationEffect(.degrees(showsMonth ? 180 : 0))
                    }
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .accessibilityLabel(selectedDay.formatted(.dateTime.month(.wide).year()))
                .accessibilityHint(showsMonth ? "Ver solo la semana" : "Ver el mes entero")
                Spacer()
                Button { shift(by: -1) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .accessibilityLabel(showsMonth ? "Mes anterior" : "Semana anterior")
                Button { shift(by: 1) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }
                .accessibilityLabel(showsMonth ? "Mes siguiente" : "Semana siguiente")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.orange)

            if showsMonth {
                weekdayLabels
                VStack(spacing: Space.xs) {
                    ForEach(monthWeeks(of: selectedDay), id: \.self) { week in
                        row(week, showsWeekday: false)
                    }
                }
                .transition(.opacity)
            } else {
                row(week(of: selectedDay), showsWeekday: true)
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .contentShape(.rect)
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let dx = value.translation.width
                    guard abs(dx) > abs(value.translation.height) * 1.5, abs(dx) > 50 else { return }
                    shift(by: dx < 0 ? 1 : -1)
                }
        )
        .sensoryFeedback(.selection, trigger: selectedDay)
    }

    private var weekdayLabels: some View {
        HStack(spacing: 0) {
            ForEach(week(of: selectedDay), id: \.self) { day in
                Text(day.formatted(.dateTime.weekday(.narrow)).uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func row(_ days: [Date], showsWeekday: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                DayCell(
                    day: day,
                    isSelected: calendar.isDate(day, inSameDayAs: selectedDay),
                    isToday: calendar.isDateInToday(day),
                    isOutside: showsMonth && !calendar.isDate(day, equalTo: selectedDay, toGranularity: .month),
                    showsWeekday: showsWeekday,
                    markers: markers(day)
                ) {
                    withAnimation(Motion.quick) { selectedDay = day }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func week(of day: Date) -> [Date] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// Semanas (de lunes a domingo) que tocan el mes: de 4 a 6 filas.
    private func monthWeeks(of day: Date) -> [[Date]] {
        guard let month = calendar.dateInterval(of: .month, for: day),
              var cursor = calendar.dateInterval(of: .weekOfYear, for: month.start)?.start else { return [] }
        var weeks: [[Date]] = []
        while cursor < month.end {
            weeks.append(week(of: cursor))
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        return weeks
    }

    private func shift(by step: Int) {
        var target: Date?
        if showsMonth {
            // Al cambiar de mes se elige el día 1 (u hoy, si es el mes actual).
            let moved = calendar.date(byAdding: .month, value: step, to: selectedDay) ?? selectedDay
            if calendar.isDate(moved, equalTo: .now, toGranularity: .month) {
                target = calendar.startOfDay(for: .now)
            } else {
                target = calendar.dateInterval(of: .month, for: moved)?.start
            }
        } else {
            target = calendar.date(byAdding: .day, value: 7 * step, to: selectedDay)
        }
        guard let target else { return }
        withAnimation(Motion.quick) { selectedDay = target }
    }
}

private struct DayCell: View {
    let day: Date
    let isSelected: Bool
    let isToday: Bool
    let isOutside: Bool
    let showsWeekday: Bool
    let markers: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                if showsWeekday {
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.secondaryText)
                }
                Text(day.formatted(.dateTime.day()))
                    .font(.system(.body, design: .rounded).weight(isSelected || isToday ? .semibold : .regular).monospacedDigit())
                    .foregroundStyle(numberColor)
                    .frame(width: 38, height: 38)
                    .background(isSelected ? Theme.orange : Color.clear, in: .circle)
                HStack(spacing: 3) {
                    ForEach(markers.indices, id: \.self) { index in
                        Circle()
                            .fill(markers[index].opacity(isOutside ? 0.4 : 0.9))
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityValue(markers.isEmpty ? "Libre" : "Con planes")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var numberColor: Color {
        if isSelected { return .black }
        if isToday { return Theme.orange }
        return isOutside ? Theme.secondaryText.opacity(0.6) : .white
    }
}

private struct AgendaRow: View {
    let entry: AgendaEntry
    let onStart: () -> Void

    var body: some View {
        let event = entry.event
        let now = Date.now
        let canStart = event.kind == .workBlock
            && entry.interval.end > now
            && entry.interval.start.timeIntervalSince(now) < 30 * 60

        HStack(spacing: Space.m) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.interval.start, format: .dateTime.hour().minute())
                    .font(.subheadline.monospacedDigit().weight(.medium))
                Text(entry.interval.end, format: .dateTime.hour().minute())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(minWidth: 48, alignment: .trailing)

            Capsule()
                .fill(event.mode.tint)
                .frame(width: 4)
                .padding(.vertical, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Label {
                    Text(caption)
                } icon: {
                    Image(systemName: event.kind.symbol)
                }
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            }

            Spacer(minLength: 0)

            if canStart {
                Button("Empezar", systemImage: "play.fill", action: onStart)
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(event.mode.tint)
                    .foregroundStyle(.black)
                    .accessibilityLabel("Empezar a concentrarme en \(event.title)")
            }
        }
        .padding(.vertical, Space.xs)
    }

    private var caption: String {
        var parts = [entry.event.mode.title]
        // La duración sale del inicio y el fin; si termina otro día, se dice cuál.
        let times = EventTimes(start: entry.interval.start, end: entry.interval.end)
        if EventSchedule.daySpan(times) > 0 {
            parts.append("hasta \(ProposalFormat.dayTime.string(from: times.end))")
        } else if times.minutes > 0 {
            parts.append(ProposalFormat.minutes(times.minutes))
        }
        switch entry.event.kind {
        case .workBlock: parts.append("bloque de trabajo")
        case .habit: parts.append("hábito")
        case .event: break
        }
        if entry.event.recurrence != .none { parts.append(entry.event.recurrence.title.lowercased()) }
        if let minutes = entry.event.reminderMinutes { parts.append(minutes == 0 ? "aviso a la hora" : "aviso \(minutes) min antes") }
        return parts.joined(separator: " · ")
    }
}

/// Evento de Outlook, Teams u otro calendario: solo lectura, con el color de su calendario.
struct ExternalAgendaRow: View {
    let event: ExternalEvent

    var body: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .trailing, spacing: 2) {
                if event.isAllDay {
                    Text("Todo el día")
                        .font(.caption.weight(.medium))
                } else {
                    Text(event.start, format: .dateTime.hour().minute())
                        .font(.subheadline.monospacedDigit().weight(.medium))
                    Text(event.end, format: .dateTime.hour().minute())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(minWidth: 48, alignment: .trailing)

            Capsule()
                .fill(event.color)
                .frame(width: 4)
                .padding(.vertical, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(event.isBusy ? Color.white : Theme.secondaryText)
                    .lineLimit(2)
                Label {
                    Text([event.sourceTitle, event.calendarTitle, event.isBusy ? nil : "libre"]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                } icon: {
                    Image(systemName: "calendar.badge.clock")
                }
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.xs)
        .accessibilityElement(children: .combine)
    }
}

private struct TaskRow: View {
    let task: PlanTask

    var body: some View {
        let estimate = max(1, task.estimatedMinutes)
        HStack(spacing: Space.m) {
            ZStack {
                ProgressRing(progress: min(1, Double(task.completedMinutes) / Double(estimate)), tint: task.mode.tint, lineWidth: 3, glows: false)
                Image(systemName: task.mode.symbol)
                    .font(.caption2)
                    .foregroundStyle(task.mode.tint)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.xs) {
                    Text(task.title).font(.body.weight(.medium)).lineLimit(1)
                    if task.priority == 2 {
                        Image(systemName: "exclamationmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.orange)
                            .accessibilityLabel("Prioridad alta")
                    }
                }
                Text("Entrega \(task.deadline.formatted(.relative(presentation: .named))) · \(FocusStats.format(TimeInterval(task.completedMinutes * 60))) de \(FocusStats.format(TimeInterval(task.estimatedMinutes * 60)))")
                    .font(.caption)
                    .foregroundStyle(task.deadline < .now ? Theme.orange : Theme.secondaryText)
            }
        }
        .padding(.vertical, Space.xs)
        .accessibilityElement(children: .combine)
    }
}
