import Foundation

public enum Phase: String, Codable, Sendable {
    case focus, shortBreak, longBreak

    public var isBreak: Bool { self != .focus }
}

public struct Durations: Equatable, Sendable {
    public var focus: TimeInterval
    public var shortBreak: TimeInterval
    public var longBreak: TimeInterval
    public var roundsBeforeLongBreak: Int

    public init(focus: TimeInterval, shortBreak: TimeInterval, longBreak: TimeInterval, roundsBeforeLongBreak: Int) {
        self.focus = focus
        self.shortBreak = shortBreak
        self.longBreak = longBreak
        self.roundsBeforeLongBreak = max(1, roundsBeforeLongBreak)
    }

    public func duration(of phase: Phase) -> TimeInterval {
        switch phase {
        case .focus: focus
        case .shortBreak: shortBreak
        case .longBreak: longBreak
        }
    }
}

public enum Status: Codable, Equatable, Sendable {
    case idle
    /// Running blocks store their end date rather than a countdown, so the
    /// timer stays correct across sleep, App Nap and app restarts.
    case running(endDate: Date)
    case paused(remaining: TimeInterval)
}

public enum TimerEvent: Equatable, Sendable {
    case focusCompleted(BlockRecord, next: Phase)
    case breakCompleted(BlockRecord, focusStarted: Bool)

    public var record: BlockRecord {
        switch self {
        case .focusCompleted(let record, _), .breakCompleted(let record, _): record
        }
    }
}

/// Pure Pomodoro state machine. All time-dependent operations take `now`
/// explicitly so the engine can be tested without a clock.
public struct TimerEngine: Codable, Equatable, Sendable {
    public static let extensionLength: TimeInterval = 5 * 60

    public private(set) var phase: Phase = .focus
    public private(set) var status: Status = .idle
    /// Focus blocks completed since the last long break.
    public private(set) var completedRounds = 0
    /// Planned length of the current block including any extension; 0 when idle.
    public private(set) var blockLength: TimeInterval = 0
    public private(set) var blockStartedAt: Date?

    public init() {}

    public var isRunning: Bool {
        if case .running = status { true } else { false }
    }

    public var isPaused: Bool {
        if case .paused = status { true } else { false }
    }

    public var canExtend: Bool {
        phase == .focus && status != .idle
    }

    public func remaining(at now: Date, durations: Durations) -> TimeInterval {
        switch status {
        case .idle: durations.duration(of: phase)
        case .running(let endDate): max(0, endDate.timeIntervalSince(now))
        case .paused(let remaining): remaining
        }
    }

    /// Fraction of the current block that has elapsed, from 0 to 1.
    public func progress(at now: Date, durations: Durations) -> Double {
        guard status != .idle, blockLength > 0 else { return 0 }
        return min(1, max(0, 1 - remaining(at: now, durations: durations) / blockLength))
    }

    public mutating func start(at now: Date, durations: Durations) {
        switch status {
        case .idle:
            blockLength = durations.duration(of: phase)
            blockStartedAt = now
            status = .running(endDate: now + blockLength)
        case .paused(let remaining):
            status = .running(endDate: now + remaining)
        case .running:
            break
        }
    }

    public mutating func pause(at now: Date) {
        guard case .running(let endDate) = status else { return }
        status = .paused(remaining: max(0, endDate.timeIntervalSince(now)))
    }

    public mutating func toggle(at now: Date, durations: Durations) {
        if isRunning {
            pause(at: now)
        } else {
            start(at: now, durations: durations)
        }
    }

    /// Returns to the initial state. A block in progress is recorded as reset.
    @discardableResult
    public mutating func reset(at now: Date, durations: Durations) -> BlockRecord? {
        let record = record(.reset, at: now, durations: durations)
        self = TimerEngine()
        return record
    }

    public mutating func extend(at now: Date) {
        guard canExtend else { return }
        switch status {
        case .running(let endDate): status = .running(endDate: max(endDate, now) + Self.extensionLength)
        case .paused(let remaining): status = .paused(remaining: remaining + Self.extensionLength)
        case .idle: return
        }
        blockLength += Self.extensionLength
    }

    /// Skips the current block without counting it as completed; only the time
    /// actually spent is recorded. Skipping a break means the user wants to
    /// work, so focus starts immediately.
    @discardableResult
    public mutating func skip(at now: Date, durations: Durations) -> BlockRecord? {
        let record = record(.skipped, at: now, durations: durations)
        begin(phase == .focus ? .shortBreak : .focus, at: now, durations: durations, running: true)
        return record
    }

    /// Advances the machine if the running block has ended.
    public mutating func tick(at now: Date, durations: Durations, autoStartFocus: Bool) -> TimerEvent? {
        guard case .running(let endDate) = status, now >= endDate,
              let record = record(.completed, at: endDate, durations: durations)
        else { return nil }

        if phase == .focus {
            completedRounds += 1
            let next: Phase = completedRounds >= durations.roundsBeforeLongBreak ? .longBreak : .shortBreak
            if next == .longBreak { completedRounds = 0 }
            // Breaks always start on their own: systematic breaks are the point.
            begin(next, at: now, durations: durations, running: true)
            return .focusCompleted(record, next: next)
        } else {
            begin(.focus, at: now, durations: durations, running: autoStartFocus)
            return .breakCompleted(record, focusStarted: autoStartFocus)
        }
    }

    private mutating func begin(_ phase: Phase, at now: Date, durations: Durations, running: Bool) {
        self.phase = phase
        if running {
            blockLength = durations.duration(of: phase)
            blockStartedAt = now
            status = .running(endDate: now + blockLength)
        } else {
            blockLength = 0
            blockStartedAt = nil
            status = .idle
        }
    }

    private func record(_ outcome: Outcome, at now: Date, durations: Durations) -> BlockRecord? {
        guard status != .idle else { return nil }
        let actual = outcome == .completed ? blockLength : blockLength - remaining(at: now, durations: durations)
        // A block abandoned within a second never really started.
        guard outcome == .completed || actual >= 1 else { return nil }
        return BlockRecord(
            phase: phase, startedAt: blockStartedAt ?? now - actual, endedAt: now,
            planned: blockLength, actual: actual, outcome: outcome
        )
    }
}
