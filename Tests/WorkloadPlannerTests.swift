import Foundation
import Testing

@Suite("WorkloadPlanner")
struct WorkloadPlannerTests {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var planner: WorkloadPlanner { WorkloadPlanner(calendar: calendar) }

    /// Lunes 2 de noviembre de 2026.
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func item(minutes: Int, deadline: Date, priority: Int = 1, availability: Availability = .work) -> WorkItem {
        WorkItem(id: UUID(), deadline: deadline, minutes: minutes, priority: priority, availability: availability, capGroup: "work")
    }

    @Test func spreadsWorkBeforeDeadlineInsideWorkingHours() {
        let task = item(minutes: 360, deadline: date(6, 18))
        let result = planner.plan([task], busy: [], from: date(2, 8))

        #expect(result.shortfalls.isEmpty)
        #expect(result.blocks.reduce(0) { $0 + $1.minutes } == 360)
        for block in result.blocks {
            #expect(block.end <= date(6, 18))
            #expect(block.minutes <= 90)
            let hour = calendar.component(.hour, from: block.start)
            #expect(hour >= 9 && hour < 18)
        }
        // Repartido: ningún día se lleva todo.
        let days = Set(result.blocks.map { calendar.startOfDay(for: $0.start) })
        #expect(days.count >= 3)
    }

    @Test func skipsWeekendsForWork() {
        // Viernes 6 por la tarde hasta el lunes 9 a mediodía.
        let task = item(minutes: 120, deadline: date(9, 12))
        let result = planner.plan([task], busy: [], from: date(6, 17))
        for block in result.blocks {
            let weekday = calendar.component(.weekday, from: block.start)
            #expect(weekday != 1 && weekday != 7)
        }
    }

    @Test func reportsShortfallWhenDeadlineIsImpossible() {
        let task = item(minutes: 600, deadline: date(2, 18))
        let result = planner.plan([task], busy: [], from: date(2, 9))
        #expect(result.shortfalls[task.id] == 600 - 360)
    }

    @Test func avoidsBusyTimeAndKeepsBreaks() {
        let meeting = DateInterval(start: date(2, 10), end: date(2, 11))
        let task = item(minutes: 120, deadline: date(2, 18))
        let result = planner.plan([task], busy: [meeting], from: date(2, 9))
        for block in result.blocks {
            let padded = DateInterval(start: meeting.start.addingTimeInterval(-15 * 60), end: meeting.end.addingTimeInterval(15 * 60))
            #expect(!(block.start < padded.end && block.end > padded.start))
        }
        #expect(result.shortfalls.isEmpty)
    }

    @Test func earliestDeadlineGoesFirst() {
        let later = item(minutes: 90, deadline: date(4, 18))
        let sooner = item(minutes: 90, deadline: date(2, 18))
        let result = planner.plan([later, sooner], busy: [], from: date(2, 9))
        let first = result.blocks.first
        #expect(first?.itemID == sooner.id)
    }

    @Test func respectsDailyCap() {
        var tight = Availability.work
        tight.dailyCapMinutes = 120
        let task = item(minutes: 300, deadline: date(4, 18), availability: tight)
        let result = planner.plan([task], busy: [], from: date(2, 9))
        let perDay = Dictionary(grouping: result.blocks) { calendar.startOfDay(for: $0.start) }
            .mapValues { $0.reduce(0) { $0 + $1.minutes } }
        #expect(perDay.values.allSatisfy { $0 <= 120 })
    }

    @Test func demandingWorkGoesToPeakHours() {
        var planner = self.planner
        planner.energyByHour = (0..<24).map { (15..<18).contains($0) ? 1.0 : 0.3 }
        var task = item(minutes: 120, deadline: date(2, 18))
        task.difficulty = 5
        let result = planner.plan([task], busy: [], from: date(2, 9))
        #expect(result.shortfalls.isEmpty)
        for block in result.blocks {
            #expect(calendar.component(.hour, from: block.start) >= 15)
        }
    }

    @Test func lightWorkLeavesPeakHoursFree() {
        var planner = self.planner
        planner.energyByHour = (0..<24).map { (9..<12).contains($0) ? 1.0 : 0.3 }
        var task = item(minutes: 60, deadline: date(2, 18))
        task.difficulty = 1
        let result = planner.plan([task], busy: [], from: date(2, 9))
        #expect(result.blocks.count == 1)
        #expect(calendar.component(.hour, from: result.blocks[0].start) >= 12)
    }

    @Test func chosenOrderWinsOverDeadline() {
        var soonerDeadline = item(minutes: 90, deadline: date(2, 18))
        soonerDeadline.rank = 1
        var prioritized = item(minutes: 90, deadline: date(4, 18))
        prioritized.rank = 0
        let result = planner.plan([soonerDeadline, prioritized], busy: [], from: date(2, 9))
        #expect(result.blocks.first?.itemID == prioritized.id)
        #expect(result.shortfalls.isEmpty)
    }

    @Test func dayWithOwnHoursUsesThem() {
        // Los viernes (6 de noviembre) solo hasta las 15:00.
        var rules = Availability.work
        rules.dayHours = [6: .init(startMinute: 8 * 60, endMinute: 15 * 60)]
        let task = item(minutes: 600, deadline: date(6, 23), availability: rules)
        let result = planner.plan([task], busy: [], from: date(6, 7))

        #expect(result.blocks.allSatisfy { $0.start >= date(6, 8) && $0.end <= date(6, 15) })
        #expect(result.shortfalls[task.id] == 600 - 360)
    }

    @Test func subtractSplitsIntervals() {
        let free = WorkloadPlanner.subtract(
            [DateInterval(start: date(2, 10), end: date(2, 11))],
            from: DateInterval(start: date(2, 9), end: date(2, 12))
        )
        #expect(free == [DateInterval(start: date(2, 9), end: date(2, 10)), DateInterval(start: date(2, 11), end: date(2, 12))])
    }
}
