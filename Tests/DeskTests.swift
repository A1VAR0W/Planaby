import Foundation
import Testing

private func input(
    enabled: Bool = true, trigger: DeskTrigger = .charger, focusName: String? = nil, configured: String = "Trabajo",
    filter: Bool = true, charging: Bool? = true, landscape: Bool? = true
) -> DeskLaunchInput {
    DeskLaunchInput(
        enabled: enabled, trigger: trigger, currentFocusName: focusName, configuredFocus: configured,
        filterSaysActive: filter, charging: charging, landscape: landscape
    )
}

@Suite("Apertura del modo escritorio")
struct DeskLaunchTests {
    // La tabla de decisión: solo se abre con Concentración + cargando + horizontal.
    @Test func decisionTable() {
        #expect(DeskLaunchPolicy.decide(input()) == .open)
        #expect(DeskLaunchPolicy.decide(input(landscape: false)) == .skip(.portrait))
        #expect(DeskLaunchPolicy.decide(input(charging: false)) == .skip(.notCharging))
        #expect(DeskLaunchPolicy.decide(input(filter: false)) == .skip(.focusOff))
        #expect(DeskLaunchPolicy.decide(input(filter: false, charging: false, landscape: false)) == .skip(.focusOff))
        #expect(DeskLaunchPolicy.decide(input(enabled: false)) == .skip(.disabled))
        #expect(DeskLaunchPolicy.decide(input(landscape: nil)) == .skip(.unknownOrientation))
    }

    @Test func planabyWorkPlanIsNotTheSystemFocus() {
        // El plan Trabajo elegido a mano no enciende el filtro: sin Concentración del iPhone no se abre.
        #expect(DeskLaunchPolicy.decide(input(focusName: "", filter: false)) == .skip(.focusOff))
    }

    @Test func focusNameFromShortcutsWins() {
        #expect(DeskLaunchPolicy.decide(input(focusName: "Trabajo", filter: false)) == .open)
        #expect(DeskLaunchPolicy.decide(input(focusName: "Work", filter: false)) == .open)
        #expect(DeskLaunchPolicy.decide(input(focusName: "trabajo ", filter: false)) == .open)
        #expect(DeskLaunchPolicy.decide(input(focusName: "Dormir", filter: true)) == .skip(.focusOff))
        #expect(DeskLaunchPolicy.decide(input(focusName: "Estudio", configured: "Estudio", filter: false)) == .open)
    }

    @Test func focusTriggerAssumesTheFocusIsOn() {
        #expect(DeskLaunchPolicy.decide(input(trigger: .focusOn, filter: false)) == .open)
        #expect(DeskLaunchPolicy.decide(input(trigger: .focusOn, filter: false, charging: false)) == .skip(.notCharging))
    }

    @Test func chargerTriggerImpliesCharging() {
        #expect(DeskLaunchPolicy.decide(input(trigger: .charger, charging: nil)) == .open)
        #expect(DeskLaunchPolicy.decide(input(trigger: .manual, charging: nil)) == .skip(.notCharging))
    }

    @Test func gravityToOrientation() {
        #expect(DeskLaunchPolicy.landscape(fromGravityX: -0.98, y: 0.05, z: -0.1) == true)
        #expect(DeskLaunchPolicy.landscape(fromGravityX: 0.02, y: -0.99, z: -0.1) == false)
        #expect(DeskLaunchPolicy.landscape(fromGravityX: 0.05, y: 0.02, z: -0.99) == nil)
        #expect(DeskLaunchPolicy.landscape(fromGravityX: 0.5, y: 0.5, z: 0.2) == nil)
    }

    @Test func systemFocusStateIsSeparate() throws {
        let defaults = try #require(UserDefaults(suiteName: "planaby.tests.\(UUID().uuidString)"))
        #expect(!SystemFocusState.isOn(defaults: defaults))
        SystemFocusState.set(active: true, opensDesk: false, defaults: defaults)
        #expect(SystemFocusState.isOn(defaults: defaults))
        #expect(!SystemFocusState.isActive(defaults: defaults))
        SystemFocusState.set(active: true, opensDesk: true, defaults: defaults)
        #expect(SystemFocusState.isActive(defaults: defaults))
        SystemFocusState.set(active: false, opensDesk: false, defaults: defaults)
        #expect(!SystemFocusState.isOn(defaults: defaults))
        #expect(SystemFocusState.focusName(defaults: defaults) == "Trabajo")
        #expect(SystemFocusState.autoOpenEnabled(defaults: defaults))
    }

    @Test func intentLogKeepsTheLastRun() throws {
        let defaults = try #require(UserDefaults(suiteName: "planaby.tests.\(UUID().uuidString)"))
        #expect(IntentLog.last(.deskCharger, defaults: defaults) == nil)
        let date = Date(timeIntervalSince1970: 5_000)
        IntentLog.record(.deskKind(for: .charger), result: "Abierto", now: date, defaults: defaults)
        #expect(IntentLog.last(.deskCharger, defaults: defaults) == IntentLog.Entry(date: date, result: "Abierto"))
        #expect(IntentLog.last(.deskFocus, defaults: defaults) == nil)
    }
}

@Suite("Presentación común")
struct DeskPresentationTests {
    let start = Date(timeIntervalSince1970: 2_000_000)

    @Test func focusLayout() {
        var state = TimerState(method: .pomodoro, at: start, taskTitle: "Informe")
        state.catchUp(to: start.addingTimeInterval(60))
        let comms = CommsSnapshot(updated: start, focusVisible: 2, pending: 4, urgent: 0, byApp: [:])
        let presentation = DeskPresentation(state: state, comms: comms, agenda: [], now: start.addingTimeInterval(60))
        #expect(presentation.layout == .focus)
        #expect(presentation.taskTitle == "Informe")
        #expect(presentation.commsText == "2 comunicaciones laborales importantes")
        #expect(presentation.commsCount == 2)
        #expect(presentation.nextPhaseText?.hasPrefix("Después: Descanso") == true)
        #expect(presentation.range != nil)
        #expect(abs(presentation.progress(at: start.addingTimeInterval(12.5 * 60)) - 0.5) < 0.001)
    }

    @Test func restLayout() {
        var state = TimerState(method: .pomodoro, at: start)
        state.skip(at: start.addingTimeInterval(60))
        let comms = CommsSnapshot(updated: start, focusVisible: 1, pending: 3, urgent: 0, byApp: [:])
        let presentation = DeskPresentation(state: state, comms: comms, agenda: [], now: start.addingTimeInterval(61))
        #expect(presentation.layout == .rest)
        #expect(presentation.commsText == "Mientras trabajabas: 3 pendientes")
        #expect(presentation.commsCount == 3)
    }

    @Test func idleLayoutShowsNextItem() {
        let soon = AgendaItem(
            title: "Reunión", start: start.addingTimeInterval(1_800), end: start.addingTimeInterval(3_600),
            modeRaw: "work", kindRaw: "event", isAllDay: false
        )
        let past = AgendaItem(
            title: "Ya pasó", start: start.addingTimeInterval(-7_200), end: start.addingTimeInterval(-3_600),
            modeRaw: "work", kindRaw: "event", isAllDay: false
        )
        let comms = CommsSnapshot(updated: start, focusVisible: 0, pending: 1, urgent: 0, byApp: [:])
        let presentation = DeskPresentation(state: nil, comms: comms, agenda: [past, soon], now: start)
        #expect(presentation.layout == .idle)
        #expect(presentation.stateTitle == "Sin sesión")
        #expect(presentation.nextItemTitle == "Reunión")
        #expect(presentation.commsText == "1 pendiente")
        #expect(presentation.range == nil)
    }

    @Test func pausedClockIsFrozen() {
        var state = TimerState(method: .pomodoro, at: start)
        state.pause(at: start.addingTimeInterval(5 * 60))
        let presentation = DeskPresentation(state: state, comms: .empty, agenda: [], now: start.addingTimeInterval(9 * 60))
        #expect(presentation.isPaused)
        #expect(presentation.stateTitle == "En pausa")
        #expect(presentation.range == nil)
        #expect(presentation.staticClock(at: start.addingTimeInterval(9 * 60)) == TimerState.format(20 * 60))
        #expect(presentation.commsText == nil)
    }
}
