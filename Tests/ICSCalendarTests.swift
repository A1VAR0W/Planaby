import Foundation
import Testing

@Suite("ICSCalendar")
struct ICSCalendarTests {
    private var utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func calendar(_ events: String) -> String {
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n\(events)\r\nEND:VCALENDAR\r\n"
    }

    @Test func readsSimpleEventWithFoldingEscapesAndAlarm() {
        let text = calendar(#"""
        BEGIN:VEVENT
        UID:1
        SUMMARY:Revisión\, sprint
          semanal
        DTSTART:20261103T090000Z
        DTEND:20261103T100000Z
        BEGIN:VALARM
        TRIGGER:-PT15M
        DESCRIPTION:Recordatorio
        END:VALARM
        END:VEVENT
        """#)
        let result = ICSCalendar.occurrences(in: text, from: date(2026, 11, 1), to: date(2026, 11, 8))
        #expect(result.count == 1)
        #expect(result.first?.title == "Revisión, sprint semanal")
        #expect(result.first?.start == date(2026, 11, 3, 9))
        #expect(result.first?.end == date(2026, 11, 3, 10))
        #expect(result.first?.isBusy == true)
    }

    @Test func understandsOutlookWindowsTimeZones() {
        let text = calendar("""
        BEGIN:VEVENT
        UID:2
        SUMMARY:Daily
        DTSTART;TZID=Romance Standard Time:20261103T090000
        DTEND;TZID=Romance Standard Time:20261103T091500
        END:VEVENT
        """)
        let result = ICSCalendar.occurrences(in: text, from: date(2026, 11, 1), to: date(2026, 11, 8))
        // Madrid en noviembre es UTC+1.
        #expect(result.first?.start == date(2026, 11, 3, 8))
        #expect(result.first?.end == date(2026, 11, 3, 8, 15))
    }

    @Test func weeklySeriesWithExceptionAndMovedMeeting() {
        let text = calendar("""
        BEGIN:VEVENT
        UID:serie
        SUMMARY:Seguimiento
        DTSTART:20261102T100000Z
        DTEND:20261102T103000Z
        RRULE:FREQ=WEEKLY;BYDAY=MO,WE
        EXDATE:20261104T100000Z
        END:VEVENT
        BEGIN:VEVENT
        UID:serie
        RECURRENCE-ID:20261109T100000Z
        SUMMARY:Seguimiento (movida)
        DTSTART:20261109T150000Z
        DTEND:20261109T153000Z
        END:VEVENT
        """)
        let result = ICSCalendar.occurrences(in: text, from: date(2026, 11, 2), to: date(2026, 11, 16))
        #expect(result.map(\.start) == [date(2026, 11, 2, 10), date(2026, 11, 9, 15), date(2026, 11, 11, 10)])
        #expect(result[1].title == "Seguimiento (movida)")
    }

    @Test func monthlySecondTuesdayWithCount() {
        let text = calendar("""
        BEGIN:VEVENT
        UID:mes
        SUMMARY:Comité
        DTSTART:20261110T120000Z
        DTEND:20261110T130000Z
        RRULE:FREQ=MONTHLY;BYDAY=2TU;COUNT=3
        END:VEVENT
        """)
        let result = ICSCalendar.occurrences(in: text, from: date(2026, 11, 1), to: date(2027, 3, 1))
        #expect(result.map(\.start) == [date(2026, 11, 10, 12), date(2026, 12, 8, 12), date(2027, 1, 12, 12)])
    }

    @Test func dailyWithIntervalAndUntil() {
        let text = calendar("""
        BEGIN:VEVENT
        UID:dia
        SUMMARY:Correo
        DTSTART:20261102T080000Z
        DURATION:PT20M
        RRULE:FREQ=DAILY;INTERVAL=2;UNTIL=20261108T080000Z
        END:VEVENT
        """)
        let result = ICSCalendar.occurrences(in: text, from: date(2026, 11, 1), to: date(2026, 12, 1))
        #expect(result.count == 4)
        #expect(result.last?.start == date(2026, 11, 8, 8))
        #expect(result.last?.end == date(2026, 11, 8, 8, 20))
    }

    @Test func oldSeriesJumpsStraightToTheWindow() {
        let text = calendar("""
        BEGIN:VEVENT
        UID:vieja
        SUMMARY:Reunión semanal
        DTSTART:20200106T090000Z
        DTEND:20200106T100000Z
        RRULE:FREQ=WEEKLY
        END:VEVENT
        """)
        let result = ICSCalendar.occurrences(in: text, from: date(2026, 11, 2), to: date(2026, 11, 9))
        #expect(result.map(\.start) == [date(2026, 11, 2, 9)])
    }

    @Test func freeAllDayAndCancelledEvents() {
        let text = calendar("""
        BEGIN:VEVENT
        UID:fiesta
        SUMMARY:Festivo
        DTSTART;VALUE=DATE:20261105
        DTEND;VALUE=DATE:20261106
        X-MICROSOFT-CDO-BUSYSTATUS:FREE
        END:VEVENT
        BEGIN:VEVENT
        UID:cancelada
        SUMMARY:Cancelada
        STATUS:CANCELLED
        DTSTART:20261105T100000Z
        DTEND:20261105T110000Z
        END:VEVENT
        """)
        let result = ICSCalendar.occurrences(in: text, from: date(2026, 11, 1), to: date(2026, 11, 8))
        #expect(result.count == 1)
        #expect(result.first?.isAllDay == true)
        #expect(result.first?.isBusy == false)
    }
}
