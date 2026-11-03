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

    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var form: PlanForm?
    @State private var showingChat = false
    @State private var showingReorganize = false
    @State private var openTask: PlanTask?
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
                WeekStrip(selectedDay: $selectedDay) { day in
                    !rows(on: day, visible: visible).isEmpty
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
                                    timer.start(library.selected, task: entry.event.task?.title ?? entry.event.title)
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
                        withAnimation(.smooth) { selectedDay = Calendar.current.startOfDay(for: .now) }
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
            Button { showingChat = true } label: {
                Label("Planificar con IA", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, Space.s)
                    .frame(minHeight: 36)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.orange)
            .padding(.bottom, Space.s)
        }
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
        let outside = external.events(in: DateInterval(start: day, end: end))
            .filter { visible.contains($0.mode) }
            .map(DayRow.external)
        return (entries(on: day, visible: visible).map(DayRow.local) + outside)
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
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

/// Semana de lunes a domingo con flechas para cambiar de semana.
private struct WeekStrip: View {
    @Binding var selectedDay: Date
    let hasEntries: (Date) -> Bool

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    var body: some View {
        let week = days(around: selectedDay)
        VStack(spacing: Space.s) {
            HStack {
                Text(selectedDay.formatted(.dateTime.month(.wide).year()).capitalized)
                    .font(.headline)
                Spacer()
                Button { shift(by: -7) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Semana anterior")
                Button { shift(by: 7) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Semana siguiente")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.orange)

            HStack(spacing: 0) {
                ForEach(week, id: \.self) { day in
                    DayCell(
                        day: day,
                        isSelected: calendar.isDate(day, inSameDayAs: selectedDay),
                        isToday: calendar.isDateInToday(day),
                        hasEntries: hasEntries(day)
                    ) {
                        withAnimation(.smooth(duration: 0.25)) { selectedDay = day }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .sensoryFeedback(.selection, trigger: selectedDay)
    }

    private func days(around day: Date) -> [Date] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func shift(by days: Int) {
        guard let day = calendar.date(byAdding: .day, value: days, to: selectedDay) else { return }
        withAnimation(.smooth(duration: 0.25)) { selectedDay = day }
    }
}

private struct DayCell: View {
    let day: Date
    let isSelected: Bool
    let isToday: Bool
    let hasEntries: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.xs) {
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.secondaryText)
                Text(day.formatted(.dateTime.day()))
                    .font(.system(.body, design: .rounded).weight(isSelected || isToday ? .semibold : .regular).monospacedDigit())
                    .foregroundStyle(isSelected ? Color.black : (isToday ? Theme.orange : Color.white))
                    .frame(width: 40, height: 40)
                    .background(isSelected ? Theme.orange : Color.clear, in: .circle)
                Circle()
                    .fill(hasEntries ? Theme.orange.opacity(isSelected ? 0 : 0.8) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityValue(hasEntries ? "Con planes" : "Libre")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
