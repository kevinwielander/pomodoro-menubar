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

public enum MenuBarDisplay: String, Codable, CaseIterable, Sendable {
    case ringAndTime, ring, time
}

public struct Settings: Codable, Equatable, Sendable {
    public var focusMinutes = 25
    public var shortBreakMinutes = 5
    public var longBreakMinutes = 20
    public var roundsBeforeLongBreak = 4
    public var autoStartFocus = false
    public var soundEnabled = true
    public var menuBarDisplay = MenuBarDisplay.ringAndTime
    public var hotkeyEnabled = true
    public var focusModeEnabled = false

    public init() {}

    /// Missing keys fall back to defaults, so adding a setting never wipes
    /// the user's saved ones.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? d.focusMinutes
        shortBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? d.shortBreakMinutes
        longBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? d.longBreakMinutes
        roundsBeforeLongBreak = try c.decodeIfPresent(Int.self, forKey: .roundsBeforeLongBreak) ?? d.roundsBeforeLongBreak
        autoStartFocus = try c.decodeIfPresent(Bool.self, forKey: .autoStartFocus) ?? d.autoStartFocus
        soundEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? d.soundEnabled
        menuBarDisplay = (try? c.decodeIfPresent(MenuBarDisplay.self, forKey: .menuBarDisplay)) ?? d.menuBarDisplay
        hotkeyEnabled = try c.decodeIfPresent(Bool.self, forKey: .hotkeyEnabled) ?? d.hotkeyEnabled
        focusModeEnabled = try c.decodeIfPresent(Bool.self, forKey: .focusModeEnabled) ?? d.focusModeEnabled
    }

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
