import AppKit
import PomodoroCore
import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var controller: TimerController

    var body: some View {
        let engine = controller.engine
        HStack(spacing: 3) {
            Image(systemName: icon(for: engine))
            // Minutes only: a ticking seconds display invites clock-watching.
            if !controller.settings.iconOnly, engine.status != .idle {
                Text("\(Int((controller.remaining / 60).rounded(.up)))m")
                    .monospacedDigit()
            }
        }
    }

    private func icon(for engine: TimerEngine) -> String {
        if engine.isPaused { return "pause.circle" }
        if engine.phase.isBreak { return "cup.and.saucer.fill" }
        return engine.isRunning ? "timer" : "timer.circle"
    }
}

struct PopoverView: View {
    @EnvironmentObject private var controller: TimerController
    @State private var showingSettings = false

    var body: some View {
        Group {
            if showingSettings {
                SettingsView { showingSettings = false }
            } else {
                TimerView { showingSettings = true }
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

private struct TimerView: View {
    @EnvironmentObject private var controller: TimerController
    @State private var draftThought = ""
    let openSettings: () -> Void

    private var engine: TimerEngine { controller.engine }
    private var isFocusing: Bool { engine.phase == .focus && engine.isRunning }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Text(Self.format(controller.remaining))
                .font(.system(size: 48, weight: .light, design: .rounded).monospacedDigit())
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
                .help(engine.phase.isBreak ? "Skip break" : "Skip to break")
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
        HStack {
            Label("Today: \(controller.todayCount)", systemImage: "checkmark.seal")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: openSettings) { Image(systemName: "gearshape") }
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
            HStack {
                Button(action: done) { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Text("Settings").font(.headline)
            }

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

            Divider()

            Toggle("Start focus automatically after breaks", isOn: $controller.settings.autoStartFocus)
            Toggle("Play chime", isOn: $controller.settings.soundEnabled)
            Toggle("Icon only in menu bar", isOn: $controller.settings.iconOnly)
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
