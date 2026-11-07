import AppKit
import PomodoroCore
import SwiftUI

/// Renders the real views with fixed sample data into PNGs for the README,
/// in light and dark appearance. Drawing happens offscreen, so no screen
/// recording permission is needed and the output is reproducible.
@MainActor
enum ScreenshotRenderer {
    static func render(to directory: URL) {
        // Must run before anything touches NSApplication.shared.
        ActiveApplication.shared.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for (name, dark) in [("light", false), ("dark", true)] {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            write(popover(PopoverView(), controller: focusing()), appearance, directory, "timer-\(name)")
            write(popover(PopoverView(), controller: onBreak()), appearance, directory, "break-\(name)")
            write(popover(StatsView(range: .week) {}, controller: focusing()), appearance, directory, "stats-week-\(name)")
            write(popover(StatsView(range: .today) {}, controller: focusing()), appearance, directory, "stats-today-\(name)")
            write(popover(PopoverView(screen: .settings), controller: settingsShown()), appearance, directory, "settings-\(name)")
            write(menuBar(dark: dark), appearance, directory, "menubar-\(name)")
        }
    }

    // MARK: Scenes

    private static let calendar = Calendar.current
    /// Friday afternoon, so the week chart has a realistic shape.
    private static let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 14, minute: 40))!
    private static let durations = PomodoroCore.Settings().durations()

    /// Second focus block of the day, 10 of 25 minutes in.
    private static func focusing() -> TimerController {
        var settings = PomodoroCore.Settings()
        settings.focusModeEnabled = true
        var engine = TimerEngine()
        let start = now - 2400
        engine.start(at: start, durations: durations)
        _ = engine.tick(at: start + 1500, durations: durations, autoStartFocus: true)
        _ = engine.tick(at: start + 1800, durations: durations, autoStartFocus: true)
        return controller(engine: engine, settings: settings)
    }

    /// Two minutes into a short break, with parked thoughts to review.
    private static func onBreak() -> TimerController {
        var engine = TimerEngine()
        engine.start(at: now - 1620, durations: durations)
        _ = engine.tick(at: now - 120, durations: durations, autoStartFocus: false)
        return controller(engine: engine, settings: PomodoroCore.Settings())
    }

    private static func settingsShown() -> TimerController {
        var settings = PomodoroCore.Settings()
        settings.focusModeEnabled = true
        return controller(engine: TimerEngine(), settings: settings, missingFocusShortcuts: [])
    }

    private static func controller(engine: TimerEngine, settings: PomodoroCore.Settings,
                                   missingFocusShortcuts: [String]? = nil) -> TimerController {
        TimerController(
            engine: engine, settings: settings, history: sampleHistory(),
            parkedThoughts: ["Reply to Anna about Thursday", "Look up SwiftUI Charts hover API"],
            nextStep: "Write the stats section of the README",
            now: now, breakTip: "Take a short walk.", missingFocusShortcuts: missingFocusShortcuts
        )
    }

    /// A week of plausible history: (full, partial minutes) per day, oldest first.
    private static func sampleHistory() -> [BlockRecord] {
        let days: [(full: Int, partial: [Double])] = [
            (5, [12]), (6, []), (3, [8, 15]), (0, []), (4, [10]), (7, [20]), (3, [10]),
        ]
        var records: [BlockRecord] = []
        for (offset, day) in days.enumerated() {
            let date = calendar.date(byAdding: .day, value: offset - (days.count - 1), to: now)!
            var time = calendar.date(bySettingHour: 9, minute: 5, second: 0, of: date)!
            func add(_ phase: Phase, _ planned: Double, _ actual: Double, _ outcome: Outcome) {
                records.append(BlockRecord(phase: phase, startedAt: time, endedAt: time + actual * 60,
                                           planned: planned * 60, actual: actual * 60, outcome: outcome))
                time += actual * 60 + 60
            }
            for index in 0..<day.full {
                add(.focus, 25, 25, .completed)
                // Every so often a break gets skipped.
                add(.shortBreak, 5, index == 2 ? 1 : 5, index == 2 ? .skipped : .completed)
                if index == 0, let partial = day.partial.first { add(.focus, 25, partial, .skipped) }
            }
            for partial in day.partial.dropFirst() { add(.focus, 25, partial, .reset) }
        }
        return records.filter { $0.startedAt <= now }
    }

    // MARK: Drawing

    /// The popover's content on a window-like card with a soft shadow.
    private static func popover(_ content: some View, controller: TimerController) -> some View {
        content
            .environmentObject(controller)
            .padding(16)
            .frame(width: 320)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            .padding(28)
    }

    /// The menu bar item in its three states, on a strip like the menu bar.
    private static func menuBar(dark: Bool) -> some View {
        let focus = focusing()
        let breakController = onBreak()
        let ink = dark ? Color.white : Color.black
        func item(_ controller: TimerController) -> some View {
            MenuBarLabel(controller: controller)
                .foregroundStyle(ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
        }
        return HStack(spacing: 0) {
            item(focus)
            item(breakController)
            item(controller(engine: TimerEngine(), settings: PomodoroCore.Settings()))
        }
        .font(.system(size: 13))
        .padding(.horizontal, 6)
        .frame(height: 24)
        .background(dark ? Color(white: 0.16) : Color(white: 0.93), in: RoundedRectangle(cornerRadius: 6))
        .padding(10)
    }

    private static func write(_ view: some View, _ appearance: NSAppearance, _ directory: URL, _ name: String) {
        let hosting = NSHostingView(rootView: view.environment(\.controlActiveState, .key))
        hosting.appearance = appearance
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

        // Controls draw in their inactive gray unless the window is key, so
        // order a key window in far off the visible screen area.
        let window = KeyWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        // Let Charts and AppKit-backed controls finish their first layout pass.
        RunLoop.main.run(until: Date() + 0.3)

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: directory.appendingPathComponent("\(name).png"))
    }
}

/// AppKit controls draw in inactive gray unless the app is active, which a
/// process launched from a terminal can't reliably become.
private final class ActiveApplication: NSApplication {
    override var isActive: Bool { true }
}

private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}
