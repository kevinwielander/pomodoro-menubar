import AppKit
import PomodoroCore
import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var controller: TimerController

    var body: some View {
        let engine = controller.engine
        let display = controller.settings.menuBarDisplay
        HStack(spacing: 3) {
            if engine.status == .idle {
                Image(systemName: "timer")
            } else if display != .time {
                Image(nsImage: MenuBarIcon.ring(
                    progress: controller.progress, phase: engine.phase, paused: engine.isPaused))
            } else if engine.isPaused {
                Image(systemName: "pause.circle")
            }
            // Minutes only: a ticking seconds display invites clock-watching.
            if engine.status != .idle, display != .ring {
                Text("\(Int((controller.remaining / 60).rounded(.up)))m")
                    .monospacedDigit()
            }
        }
    }
}

enum Screen {
    case timer, stats, settings
}

struct PopoverView: View {
    @EnvironmentObject private var controller: TimerController
    @State private var screen = Screen.timer

    var body: some View {
        Group {
            switch screen {
            case .timer: TimerView(screen: $screen)
            case .stats: StatsView { screen = .timer }
            case .settings: SettingsView { screen = .timer }
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

/// Formats a duration as "1h 05m" or "25m".
func formatDuration(_ interval: TimeInterval) -> String {
    let minutes = Int((interval / 60).rounded())
    return minutes >= 60 ? String(format: "%dh %02dm", minutes / 60, minutes % 60) : "\(minutes)m"
}

struct BackHeader: View {
    let title: String
    let back: () -> Void

    var body: some View {
        HStack {
            Button(action: back) { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
            Text(title).font(.headline)
            Spacer()
        }
    }
}

private struct TimerView: View {
    @EnvironmentObject private var controller: TimerController
    @State private var draftThought = ""
    @Binding var screen: Screen

    private var engine: TimerEngine { controller.engine }
    private var isFocusing: Bool { engine.phase == .focus && engine.isRunning }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            VStack(spacing: 6) {
                Text(Self.format(controller.remaining))
                    .font(.system(size: 48, weight: .light, design: .rounded).monospacedDigit())
                ProgressView(value: controller.progress)
                    .tint(engine.phase.isBreak ? .green : .accentColor)
            }
            .frame(maxWidth: .infinity)
            controls
            if engine.phase.isBreak {
                Label(controller.breakTip, systemImage: "figure.walk")
                    .foregroundStyle(.secondary)
            }
            nextStep
            Divider()
            parkingLot
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack {
            Text(title).font(.headline)
            if controller.settings.focusModeEnabled, isFocusing {
                Image(systemName: "moon.fill")
                    .foregroundStyle(.secondary)
                    .help("Focus mode is on")
            }
            Spacer()
            if engine.phase == .focus {
                Text("Round \(engine.completedRounds + 1) of \(controller.settings.roundsBeforeLongBreak)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var title: String {
        switch engine.phase {
        case .focus: engine.status == .idle ? "Ready to focus" : "Focus"
        case .shortBreak: "Short break"
        case .longBreak: "Long break"
        }
    }

    private var controls: some View {
        HStack {
            Button(engine.isRunning ? "Pause" : engine.isPaused ? "Resume" : "Start") {
                controller.toggle()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            if engine.canExtend {
                Button("+5 min") { controller.extend() }
                    .help("Extend this focus block once")
            }
            Spacer()
            Button { controller.skip() } label: { Image(systemName: "forward.end") }
                .help(engine.phase.isBreak ? "Skip break" : "Skip to break (logged as a partial block)")
            Button { controller.reset() } label: { Image(systemName: "arrow.counterclockwise") }
                .help("Reset")
        }
    }

    @ViewBuilder
    private var nextStep: some View {
        if engine.phase == .focus, engine.status != .idle {
            if !controller.nextStep.isEmpty {
                HStack(alignment: .top) {
                    Label(controller.nextStep, systemImage: "arrow.right.circle")
                    Spacer()
                    Button { controller.nextStep = "" } label: { Image(systemName: "checkmark") }
                        .buttonStyle(.borderless)
                        .help("Done")
                }
            }
        } else {
            // Writing down the next step makes it easier to pick work back up.
            TextField("Next step when you're back…", text: $controller.nextStep)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var parkingLot: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Park a distracting thought…", text: $draftThought)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    controller.park(draftThought)
                    draftThought = ""
                }
            if isFocusing {
                if !controller.parkedThoughts.isEmpty {
                    Text("\(controller.parkedThoughts.count) parked. Review them at your break.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(Array(controller.parkedThoughts.enumerated()), id: \.offset) { index, thought in
                    HStack(alignment: .top) {
                        Text("• \(thought)")
                        Spacer()
                        Button { controller.unpark(at: index) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless)
                            .help("Remove")
                    }
                }
            }
        }
    }

    private var footer: some View {
        let stats = controller.stats
        let today = stats.summary(in: stats.interval(days: 1, endingAt: controller.now))
        return HStack {
            Button { screen = .stats } label: {
                Label("Today: \(today.completedFocus) · \(formatDuration(today.focusTime))",
                      systemImage: "chart.bar.fill")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.secondary)
            .help("Stats")
            Spacer()
            Button { screen = .settings } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Settings")
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
        }
    }

    static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var controller: TimerController
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BackHeader(title: "Settings", back: done)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    durations
                    Divider()
                    focusMode
                    Divider()
                    general
                }
                .padding(.trailing, 8)
            }
            .frame(maxHeight: 480)
        }
    }

    private var durations: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Preset", selection: preset) {
                Text("25 / 5").tag(Preset.classic)
                Text("50 / 10").tag(Preset.deep)
                Text("Custom").tag(Preset.custom)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Stepper("Focus: \(controller.settings.focusMinutes) min",
                    value: $controller.settings.focusMinutes, in: 5...120, step: 5)
            Stepper("Short break: \(controller.settings.shortBreakMinutes) min",
                    value: $controller.settings.shortBreakMinutes, in: 1...30)
            Stepper("Long break: \(controller.settings.longBreakMinutes) min",
                    value: $controller.settings.longBreakMinutes, in: 5...60, step: 5)
            Stepper("Long break every \(controller.settings.roundsBeforeLongBreak) rounds",
                    value: $controller.settings.roundsBeforeLongBreak, in: 2...8)
            Text("Duration changes apply from the next block.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var focusMode: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Turn on Focus during focus blocks", isOn: $controller.settings.focusModeEnabled)
            if controller.settings.focusModeEnabled {
                if let missing = controller.missingFocusShortcuts, !missing.isEmpty {
                    FocusSetupInstructions(missing: missing) { controller.checkFocusShortcuts() }
                } else if controller.missingFocusShortcuts == nil {
                    Text("Checking shortcuts…").font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("Shortcuts ready", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = controller.focusModeError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Menu bar", selection: $controller.settings.menuBarDisplay) {
                Text("Ring + time").tag(MenuBarDisplay.ringAndTime)
                Text("Ring").tag(MenuBarDisplay.ring)
                Text("Time").tag(MenuBarDisplay.time)
            }
            Toggle("Start focus automatically after breaks", isOn: $controller.settings.autoStartFocus)
            Toggle("Play chime", isOn: $controller.settings.soundEnabled)
            Toggle("Shortcut ⌥⌘P to start/pause", isOn: $controller.settings.hotkeyEnabled)
            Toggle("Launch at login", isOn: Binding(
                get: { controller.launchAtLogin },
                set: { controller.setLaunchAtLogin($0) }
            ))
            if let error = controller.loginItemError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var preset: Binding<Preset> {
        Binding(
            get: { controller.settings.preset },
            set: { controller.settings.apply($0) }
        )
    }
}

private struct FocusSetupInstructions: View {
    let missing: [String]
    let checkAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("One-time setup: create these shortcuts in the Shortcuts app.")
            if missing.contains(FocusModeShortcuts.onName) {
                Text("• **\(FocusModeShortcuts.onName)**: add the action *Set Focus*, choose Do Not Disturb, *Turn On* until *Turned Off*.")
            }
            if missing.contains(FocusModeShortcuts.offName) {
                Text("• **\(FocusModeShortcuts.offName)**: add the action *Set Focus*, choose Do Not Disturb, *Turn Off*.")
            }
            HStack {
                Button("Open Shortcuts") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
                }
                Button("Check again", action: checkAgain)
            }
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }
}
