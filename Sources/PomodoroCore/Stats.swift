import Foundation

public enum Outcome: String, Codable, Sendable {
    case completed, skipped, reset
}

/// One block as it actually happened. `actual` excludes paused time, so a
/// focus block skipped after 10 of 25 minutes records 10 minutes.
public struct BlockRecord: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var phase: Phase
    public var startedAt: Date
    public var endedAt: Date
    public var planned: TimeInterval
    public var actual: TimeInterval
    public var outcome: Outcome

    public init(phase: Phase, startedAt: Date, endedAt: Date, planned: TimeInterval, actual: TimeInterval, outcome: Outcome) {
        self.phase = phase
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.planned = planned
        self.actual = actual
        self.outcome = outcome
    }
}

public struct StatsSummary: Equatable, Sendable {
    /// All focused time, full and partial blocks alike.
    public var focusTime: TimeInterval = 0
    public var completedFocus = 0
    public var partialFocus = 0
    public var partialFocusTime: TimeInterval = 0
    public var breaksTaken = 0
    public var breaksSkipped = 0
}

public struct DayTotal: Equatable, Identifiable, Sendable {
    public var day: Date
    public var completedTime: TimeInterval = 0
    public var partialTime: TimeInterval = 0
    public var completedCount = 0
    public var partialCount = 0

    public var id: Date { day }
}

/// Aggregates the block history. Blocks belong to the day they started.
public struct Stats: Sendable {
    public var records: [BlockRecord]
    public var calendar: Calendar

    public init(records: [BlockRecord], calendar: Calendar = .current) {
        self.records = records
        self.calendar = calendar
    }

    /// The `days` calendar days ending with the day containing `now`.
    public func interval(days: Int, endingAt now: Date) -> DateInterval {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let start = calendar.date(byAdding: .day, value: -days, to: end)!
        return DateInterval(start: start, end: end)
    }

    public func records(in interval: DateInterval) -> [BlockRecord] {
        records.filter { $0.startedAt >= interval.start && $0.startedAt < interval.end }
    }

    public func summary(in interval: DateInterval) -> StatsSummary {
        var summary = StatsSummary()
        for record in records(in: interval) {
            switch (record.phase, record.outcome) {
            case (.focus, .completed):
                summary.completedFocus += 1
                summary.focusTime += record.actual
            case (.focus, _):
                summary.partialFocus += 1
                summary.partialFocusTime += record.actual
                summary.focusTime += record.actual
            case (_, .completed):
                summary.breaksTaken += 1
            case (_, _):
                summary.breaksSkipped += 1
            }
        }
        return summary
    }

    public func dailyTotals(days: Int, endingAt now: Date) -> [DayTotal] {
        let range = interval(days: days, endingAt: now)
        var totals = (0..<days).map { offset in
            DayTotal(day: calendar.date(byAdding: .day, value: offset, to: range.start)!)
        }
        for record in records(in: range) where record.phase == .focus {
            let day = calendar.startOfDay(for: record.startedAt)
            guard let index = totals.firstIndex(where: { $0.day == day }) else { continue }
            if record.outcome == .completed {
                totals[index].completedTime += record.actual
                totals[index].completedCount += 1
            } else {
                totals[index].partialTime += record.actual
                totals[index].partialCount += 1
            }
        }
        return totals
    }

    /// Consecutive days with at least one completed focus block. Today counts
    /// once it has one, but an empty today does not break the streak yet.
    public func streak(at now: Date) -> Int {
        let activeDays = Set(records.lazy
            .filter { $0.phase == .focus && $0.outcome == .completed }
            .map { calendar.startOfDay(for: $0.startedAt) })
        var day = calendar.startOfDay(for: now)
        if !activeDays.contains(day) {
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        var streak = 0
        while activeDays.contains(day) {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    public static func csv(_ records: [BlockRecord]) -> String {
        let formatter = ISO8601DateFormatter()
        let minutes = { (t: TimeInterval) in String(format: "%.2f", t / 60) }
        let rows = records.map { r in
            [r.phase.rawValue, r.outcome.rawValue, formatter.string(from: r.startedAt),
             formatter.string(from: r.endedAt), minutes(r.planned), minutes(r.actual)].joined(separator: ",")
        }
        return (["phase,outcome,started_at,ended_at,planned_min,actual_min"] + rows).joined(separator: "\n") + "\n"
    }
}
