import Foundation

public enum Preset: String, CaseIterable, Sendable {
    case classic, deep, custom

    var minutes: (focus: Int, shortBreak: Int, longBreak: Int)? {
        switch self {
        case .classic: (25, 5, 20)
        case .deep: (50, 10, 30)
        case .custom: nil
        }
    }
}

public struct Settings: Codable, Equatable, Sendable {
    public var focusMinutes = 25
    public var shortBreakMinutes = 5
    public var longBreakMinutes = 20
    public var roundsBeforeLongBreak = 4
    public var autoStartFocus = false
    public var soundEnabled = true
    public var iconOnly = false
    public var hotkeyEnabled = true

    public init() {}

    /// Derived from the durations so it can never disagree with them.
    public var preset: Preset {
        Preset.allCases.first { preset in
            guard let m = preset.minutes else { return false }
            return m == (focusMinutes, shortBreakMinutes, longBreakMinutes)
        } ?? .custom
    }

    public mutating func apply(_ preset: Preset) {
        guard let m = preset.minutes else { return }
        focusMinutes = m.focus
        shortBreakMinutes = m.shortBreak
        longBreakMinutes = m.longBreak
    }

    /// - Parameter unit: seconds per "minute"; tests and fast mode pass 1.
    public func durations(unit: TimeInterval = 60) -> Durations {
        Durations(
            focus: TimeInterval(focusMinutes) * unit,
            shortBreak: TimeInterval(shortBreakMinutes) * unit,
            longBreak: TimeInterval(longBreakMinutes) * unit,
            roundsBeforeLongBreak: roundsBeforeLongBreak
        )
    }
}
