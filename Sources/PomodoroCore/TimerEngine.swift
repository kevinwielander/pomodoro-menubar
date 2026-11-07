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
    case focusCompleted(next: Phase)
    case breakCompleted(focusStarted: Bool)
}

/// Pure Pomodoro state machine. All time-dependent operations take `now`
/// explicitly so the engine can be tested without a clock.
public struct TimerEngine: Codable, Equatable, Sendable {
    public static let extensionLength: TimeInterval = 5 * 60

    public private(set) var phase: Phase = .focus
    public private(set) var status: Status = .idle
    /// Focus blocks completed since the last long break.
    public private(set) var completedRounds = 0
    /// Each focus block may be extended once, so flow is allowed without
    /// drifting into self-regulated breaks.
    public private(set) var hasExtended = false

    public init() {}

    public var isRunning: Bool {
        if case .running = status { true } else { false }
    }

    public var isPaused: Bool {
        if case .paused = status { true } else { false }
    }

    public var canExtend: Bool {
        phase == .focus && !hasExtended && status != .idle
    }

    public func remaining(at now: Date, durations: Durations) -> TimeInterval {
        switch status {
        case .idle: durations.duration(of: phase)
        case .running(let endDate): max(0, endDate.timeIntervalSince(now))
        case .paused(let remaining): remaining
        }
    }

    public mutating func start(at now: Date, durations: Durations) {
        switch status {
        case .idle: status = .running(endDate: now + durations.duration(of: phase))
        case .paused(let remaining): status = .running(endDate: now + remaining)
        case .running: break
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

    public mutating func reset() {
        self = TimerEngine()
    }

    public mutating func extend(at now: Date) {
        guard canExtend else { return }
        switch status {
        case .running(let endDate): status = .running(endDate: max(endDate, now) + Self.extensionLength)
        case .paused(let remaining): status = .paused(remaining: remaining + Self.extensionLength)
        case .idle: return
        }
        hasExtended = true
    }

    /// Skips the current block without counting it as completed. Skipping a
    /// break means the user wants to work, so focus starts immediately.
    public mutating func skip(at now: Date, durations: Durations) {
        begin(phase == .focus ? .shortBreak : .focus, at: now, durations: durations, running: true)
    }

    /// Advances the machine if the running block has ended.
    public mutating func tick(at now: Date, durations: Durations, autoStartFocus: Bool) -> TimerEvent? {
        guard case .running(let endDate) = status, now >= endDate else { return nil }

        if phase == .focus {
            completedRounds += 1
            let next: Phase = completedRounds >= durations.roundsBeforeLongBreak ? .longBreak : .shortBreak
            if next == .longBreak { completedRounds = 0 }
            // Breaks always start on their own: systematic breaks are the point.
            begin(next, at: now, durations: durations, running: true)
            return .focusCompleted(next: next)
        } else {
            begin(.focus, at: now, durations: durations, running: autoStartFocus)
            return .breakCompleted(focusStarted: autoStartFocus)
        }
    }

    private mutating func begin(_ phase: Phase, at now: Date, durations: Durations, running: Bool) {
        self.phase = phase
        hasExtended = false
        status = running ? .running(endDate: now + durations.duration(of: phase)) : .idle
    }
}
