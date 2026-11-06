import Foundation
import Testing

/// Raíz del repositorio, para comprobar recursos que van en la app (sonidos e icono).
private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

@Suite("Escritorio, avisos e icono")
struct DeskAndAlertsTests {
    @Test func panelsForEachCombination() {
        #expect(DeskPanels(music: false, tasks: false) == .clock)
        #expect(DeskPanels(music: true, tasks: false) == .music)
        #expect(DeskPanels(music: false, tasks: true) == .clockAndTasks)
        #expect(DeskPanels(music: true, tasks: true) == .musicAndTasks)
    }

    @Test func halvesAreEqualAndFillTheWidth() {
        let half = DeskPanels.halfWidth(total: 780, spacing: 16)
        #expect(half == 382)
        #expect(half * 2 + 16 == 780)
        #expect(DeskPanels.halfWidth(total: 10, spacing: 16) == 0)
    }

    // MARK: - Avisos con música

    @Test func alertDucksMusicByDefaultAndNeverSkipsWithoutMusic() {
        // Sin música: suena mezclado, sin tocar nada.
        #expect(AlertPreferences.musicHandling(otherAudioPlaying: false, respectsMusic: true, ducksMusic: true) == .mix)
        // Con música: por defecto baja la música un momento.
        #expect(AlertPreferences.musicHandling(otherAudioPlaying: true, respectsMusic: false, ducksMusic: true) == .duck)
        #expect(AlertPreferences.musicHandling(otherAudioPlaying: true, respectsMusic: false, ducksMusic: false) == .mix)
        // «Sonar aunque haya música» desactivado: no suena (solo vibra y tarjeta).
        #expect(AlertPreferences.musicHandling(otherAudioPlaying: true, respectsMusic: true, ducksMusic: true) == .skip)
    }

    @Test func phaseCardSaysHowLongYouWorkedAndTheBreak() {
        #expect(PhaseAlertText.title(finished: .focus, next: .shortBreak) == "¡Sesión completada!")
        #expect(PhaseAlertText.message(finished: .focus, finishedDuration: 25 * 60, next: .shortBreak, nextDuration: 5 * 60)
            == "Has trabajado durante 25 minutos. Comienza tu descanso de 5 minutos.")
        #expect(PhaseAlertText.message(finished: .focus, finishedDuration: 50 * 60, next: .longBreak, nextDuration: 15 * 60)
            == "Has trabajado durante 50 minutos. Comienza tu descanso largo de 15 minutos.")
        #expect(PhaseAlertText.title(finished: .shortBreak, next: .focus) == "Descanso terminado")
        #expect(PhaseAlertText.message(finished: .shortBreak, finishedDuration: 300, next: .focus, nextDuration: 60)
            == "Vuelve la concentración: 1 minuto.")
        #expect(PhaseAlertText.message(finished: .shortBreak, finishedDuration: 300, next: .focus, nextDuration: nil)
            == "Vuelve la concentración, sin límite de tiempo.")
    }

    // MARK: - Live Activity

    @Test func activityTextsMatchTheDesk() {
        #expect(ActivityText.eyebrow(phase: .focus, isPaused: false, isFinished: false) == "Concentración")
        #expect(ActivityText.eyebrow(phase: .shortBreak, isPaused: true, isFinished: false) == "En pausa")
        #expect(ActivityText.eyebrow(phase: .focus, isPaused: false, isFinished: true) == "Fase completada")
        #expect(ActivityText.status(phase: .focus, isPaused: false, progress: 0.75) == "Concentración · 75 %")
        #expect(ActivityText.status(phase: .focus, isPaused: true, progress: 1.4) == "En pausa · 100 %")
        #expect(ActivityText.status(phase: .focus, isPaused: false, progress: nil) == "Concentración")
        #expect(ActivityText.detail(phase: .focus, task: "Informe de incentivos", method: "Pomodoro", isFinished: false, next: .shortBreak)
            == "Informe de incentivos")
        #expect(ActivityText.detail(phase: .focus, task: "  ", method: "Pomodoro", isFinished: false, next: .shortBreak) == "Pomodoro")
        #expect(ActivityText.detail(phase: .shortBreak, task: "Informe", method: "Pomodoro", isFinished: false, next: .focus)
            == "Levántate, respira y mira lejos")
        #expect(ActivityText.detail(phase: .focus, task: nil, method: "Pomodoro", isFinished: true, next: .shortBreak)
            == "Toca para empezar el descanso")
        #expect(ActivityText.next(.shortBreak) == "Luego: Descanso")
    }

    // MARK: - Captura con detalles

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func captureDetailsDeadlineIsTheEveningOfTheChosenDay() {
        let morning = date(6, 10)
        let details = CaptureDetails(mode: .work, now: morning, calendar: calendar)
        #expect(details.mode == .work)
        #expect(details.priority == 1)
        #expect(details.minutes == 30)
        #expect(details.deadline == date(6, 20))
        // Otro día: a las 20:00 de ese día.
        #expect(CaptureDetails.resolve(day: date(9, 8), now: morning, calendar: calendar) == date(9, 20))
        // Hoy pasadas las 20:00: al final del día, nunca en el pasado.
        #expect(CaptureDetails.resolve(day: date(6, 9), now: date(6, 21, 30), calendar: calendar) == date(6, 23, 59))
        // Un día anterior se mueve a hoy.
        #expect(CaptureDetails.resolve(day: date(2, 9), now: morning, calendar: calendar) == date(6, 20))
    }

    @Test func captureDetailsLabels() {
        #expect(CaptureDetails.priorityTitle(0) == "Baja")
        #expect(CaptureDetails.priorityTitle(1) == "Media")
        #expect(CaptureDetails.priorityTitle(2) == "Alta")
        #expect(CaptureDetails.durations.contains(30))
        var details = CaptureDetails(mode: .personal, now: date(6, 10), calendar: calendar)
        details.notes = "  llamar antes  \n"
        #expect(details.cleanNotes == "llamar antes")
    }

    /// Los avisos tienen que oírse: cerca del máximo (antes estaban a −9,9 dBFS) y por debajo de
    /// los 30 s que admite iOS para el sonido de una notificación.
    @Test(arguments: AlertSoundSet.allCases.filter { $0 != .system }, [true, false])
    func alertSoundsAreLoudAndShort(set: AlertSoundSet, isBreak: Bool) throws {
        let name = try #require(set.fileName(isBreak: isBreak))
        let data = try Data(contentsOf: root.appending(path: "App/Sounds/\(name)"))
        #expect(String(decoding: data[0..<4], as: UTF8.self) == "RIFF")
        let channels = data.readUInt16(at: 22)
        let rate = data.readUInt32(at: 24)
        let bits = data.readUInt16(at: 34)
        #expect(channels == 1 && rate == 44_100 && bits == 16)
        let samples = stride(from: 44, to: data.count - 1, by: 2).map { Int16(bitPattern: data.readUInt16(at: $0)) }
        let peak = samples.map { abs(Int($0)) }.max() ?? 0
        let decibels = 20 * log10(Double(peak) / 32_768)
        #expect(decibels > -3, "pico \(decibels) dBFS")
        #expect(Double(samples.count) / Double(rate) < 30)
    }

    /// El icono es el PNG de 1024 × 1024 sin transparencia que pide el catálogo, y la distribución
    /// usa el mismo archivo.
    @Test func appIconIsTheDistributedOne() throws {
        let icon = try Data(contentsOf: root.appending(path: "App/Assets.xcassets/AppIcon.appiconset/icon.png"))
        #expect(icon.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        #expect(icon.readUInt32BE(at: 16) == 1024)
        #expect(icon.readUInt32BE(at: 20) == 1024)
        #expect(icon[25] == 2, "RGB sin canal alfa")
        let distributed = try Data(contentsOf: root.appending(path: "distribution/icon.png"))
        #expect(distributed == icon)
    }
}

private extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }

    func readUInt32(at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(self[startIndex + offset + $1]) << (8 * $1) }
    }

    func readUInt32BE(at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(self[startIndex + offset + $1]) }
    }
}
