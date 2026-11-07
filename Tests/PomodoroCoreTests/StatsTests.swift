import XCTest
@testable import PomodoroCore

final class StatsTests: XCTestCase {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return calendar
    }()

    /// 2026-11-07 10:00 Vienna time.
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 10))! }

    func record(_ phase: Phase, _ outcome: Outcome, daysAgo: Int = 0, minutes: Double, planned: Double = 25) -> BlockRecord {
        let start = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        return BlockRecord(phase: phase, startedAt: start, endedAt: start + minutes * 60,
                           planned: planned * 60, actual: minutes * 60, outcome: outcome)
    }

    func testSummarySeparatesCompletedAndPartialFocus() {
        let stats = Stats(records: [
            record(.focus, .completed, minutes: 25),
            record(.focus, .skipped, minutes: 10),
            record(.focus, .reset, minutes: 3),
            record(.shortBreak, .completed, minutes: 5, planned: 5),
            record(.shortBreak, .skipped, minutes: 1, planned: 5),
            record(.focus, .completed, daysAgo: 1, minutes: 25),
        ], calendar: calendar)

        let today = stats.summary(in: stats.interval(days: 1, endingAt: now))
        XCTAssertEqual(today.completedFocus, 1)
        XCTAssertEqual(today.partialFocus, 2)
        XCTAssertEqual(today.partialFocusTime, 13 * 60)
        XCTAssertEqual(today.focusTime, 38 * 60)
        XCTAssertEqual(today.breaksTaken, 1)
        XCTAssertEqual(today.breaksSkipped, 1)

        let week = stats.summary(in: stats.interval(days: 7, endingAt: now))
        XCTAssertEqual(week.completedFocus, 2)
    }

    func testDailyTotalsCoverEveryDayOldestFirst() {
        let stats = Stats(records: [
            record(.focus, .completed, minutes: 25),
            record(.focus, .skipped, minutes: 10),
            record(.focus, .completed, daysAgo: 2, minutes: 50, planned: 50),
            record(.focus, .completed, daysAgo: 9, minutes: 25),
            record(.shortBreak, .completed, minutes: 5),
        ], calendar: calendar)

        let totals = stats.dailyTotals(days: 7, endingAt: now)
        XCTAssertEqual(totals.count, 7)
        XCTAssertEqual(totals.last?.day, calendar.startOfDay(for: now))
        XCTAssertEqual(totals.last?.completedTime, 25 * 60)
        XCTAssertEqual(totals.last?.partialTime, 10 * 60)
        XCTAssertEqual(totals[4].completedTime, 50 * 60)
        XCTAssertEqual(totals.map(\.completedCount).reduce(0, +), 2)
    }

    func testStreakCountsConsecutiveDaysWithCompletedFocus() {
        let records = [0, 1, 2, 4].map { record(.focus, .completed, daysAgo: $0, minutes: 25) }
        XCTAssertEqual(Stats(records: records, calendar: calendar).streak(at: now), 3)
    }

    func testStreakIsNotBrokenByEmptyToday() {
        let records = [1, 2].map { record(.focus, .completed, daysAgo: $0, minutes: 25) }
        XCTAssertEqual(Stats(records: records, calendar: calendar).streak(at: now), 2)
    }

    func testSkippedBlocksDoNotCountTowardStreak() {
        let records = [record(.focus, .skipped, minutes: 20), record(.focus, .completed, daysAgo: 1, minutes: 25)]
        XCTAssertEqual(Stats(records: records, calendar: calendar).streak(at: now), 1)
    }

    func testCSV() {
        let csv = Stats.csv([record(.focus, .skipped, minutes: 10)])
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.first, "phase,outcome,started_at,ended_at,planned_min,actual_min")
        XCTAssertTrue(lines[1].hasPrefix("focus,skipped,2026-11-07T09:00:00Z,"))
        XCTAssertTrue(lines[1].hasSuffix(",25.00,10.00"))
    }
}
