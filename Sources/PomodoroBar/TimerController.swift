import AppKit
import PomodoroCore
import ServiceManagement

/// Owns the engine and connects it to the clock, persistence, notifications,
/// Focus mode and the global hotkey.
@MainActor
final class TimerController: ObservableObject {
    @Published private(set) var engine: TimerEngine {
        didSet {
            save(engine, forKey: Keys.engine)
            syncFocusMode()
        }
    }
    @Published var settings: Settings {
        didSet {
            save(settings, forKey: Keys.settings)
            updateHotKey()
            if settings.focusModeEnabled != oldValue.focusModeEnabled {
                checkFocusShortcuts()
            }
            syncFocusMode()
        }
    }
    @Published var parkedThoughts: [String] {
        didSet { defaults.set(parkedThoughts, forKey: Keys.parked) }
    }
    @Published var nextStep: String {
        didSet { defaults.set(nextStep, forKey: Keys.nextStep) }
    }
    @Published private(set) var history: [BlockRecord]
    @Published private(set) var now = Date()
    @Published private(set) var breakTip = BreakTips.random()
    @Published private(set) var loginItemError: String?
    /// nil until checked; empty when both shortcuts exist.
    @Published private(set) var missingFocusShortcuts: [String]?
    @Published private(set) var focusModeError: String?

    /// Set POMODOROBAR_FAST=1 to treat minutes as seconds when trying things out.
    private let unit: TimeInterval = ProcessInfo.processInfo.environment["POMODOROBAR_FAST"] == nil ? 60 : 1
    private let defaults = UserDefaults.standard
    private let historyStore = HistoryStore()
    private let notifier = Notifier()
    private var focusModeActive = false
    private var ticker: Timer?
    private var hotKey: GlobalHotKey?
    private var observers: [NSObjectProtocol] = []

    var durations: Durations { settings.durations(unit: unit) }
    var remaining: TimeInterval { engine.remaining(at: now, durations: durations) }
    var progress: Double { engine.progress(at: now, durations: durations) }
    var stats: Stats { Stats(records: history) }

    init() {
        engine = Self.load(TimerEngine.self, forKey: Keys.engine) ?? TimerEngine()
        settings = Self.load(Settings.self, forKey: Keys.settings) ?? Settings()
        parkedThoughts = defaults.stringArray(forKey: Keys.parked) ?? []
        nextStep = defaults.string(forKey: Keys.nextStep) ?? ""
        history = historyStore.load()

        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Keep ticking while a menu is being tracked.
        RunLoop.main.add(ticker!, forMode: .common)
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Don't leave Do Not Disturb on after quitting.
                if self?.focusModeActive == true { FocusModeShortcuts.disableSynchronously() }
            }
        })
        updateHotKey()
        if settings.focusModeEnabled { checkFocusShortcuts() }
        tick()
        syncFocusMode()
    }

    // MARK: Actions

    func toggle() {
        notifier.requestAuthorizationIfNeeded()
        engine.toggle(at: Date(), durations: durations)
        tick()
    }

    func skip() {
        record(engine.skip(at: Date(), durations: durations))
        if engine.phase.isBreak { breakTip = BreakTips.random() }
        tick()
    }

    func reset() {
        record(engine.reset(at: Date(), durations: durations))
        tick()
    }

    func extend() {
        engine.extend(at: Date())
        tick()
    }

    func park(_ thought: String) {
        let trimmed = thought.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        parkedThoughts.append(trimmed)
    }

    func unpark(at index: Int) {
        guard parkedThoughts.indices.contains(index) else { return }
        parkedThoughts.remove(at: index)
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "pomodoro-history.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? Stats.csv(history).write(to: url, atomically: true, encoding: .utf8)
    }

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = "Couldn't change login item: \(error.localizedDescription)"
        }
        objectWillChange.send()
    }

    // MARK: Focus mode

    func checkFocusShortcuts() {
        FocusModeShortcuts.missing { missing in
            Task { @MainActor [weak self] in self?.missingFocusShortcuts = missing }
        }
    }

    /// Focus mode is on exactly while a focus block is running.
    private func syncFocusMode() {
        let wanted = settings.focusModeEnabled && engine.phase == .focus && engine.isRunning
        guard wanted != focusModeActive else { return }
        focusModeActive = wanted
        FocusModeShortcuts.set(enabled: wanted) { success in
            Task { @MainActor [weak self] in
                let name = wanted ? FocusModeShortcuts.onName : FocusModeShortcuts.offName
                self?.focusModeError = success ? nil : "Couldn't run the shortcut “\(name)”."
            }
        }
    }

    // MARK: Clock

    private func tick() {
        now = Date()
        guard let event = engine.tick(at: now, durations: durations, autoStartFocus: settings.autoStartFocus) else { return }
        record(event.record)
        handle(event)
    }

    private func handle(_ event: TimerEvent) {
        switch event {
        case .focusCompleted(_, let next):
            breakTip = BreakTips.random()
            let minutes = Int(durations.duration(of: next) / unit)
            let kind = next == .longBreak ? "long break" : "break"
            notifier.post(title: "Focus block done", body: "\(minutes) min \(kind). \(breakTip)")
        case .breakCompleted(_, let focusStarted):
            let body = focusStarted
                ? "Next focus block started."
                : "Start the next focus block when you're ready."
            notifier.post(title: "Break's over", body: nextStep.isEmpty ? body : "\(body) Next: \(nextStep)")
        }
        if settings.soundEnabled {
            NSSound(named: "Glass")?.play()
        }
    }

    private func record(_ record: BlockRecord?) {
        guard let record else { return }
        history.append(record)
        historyStore.save(history)
    }

    private func updateHotKey() {
        if settings.hotkeyEnabled, hotKey == nil {
            hotKey = GlobalHotKey.startPause { [weak self] in self?.toggle() }
        } else if !settings.hotkeyEnabled {
            hotKey = nil
        }
    }

    // MARK: Persistence

    private enum Keys {
        static let engine = "engine"
        static let settings = "settings"
        static let parked = "parkedThoughts"
        static let nextStep = "nextStep"
    }

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

enum BreakTips {
    // Breaks away from screens restore more than phone breaks (see PLAN.md).
    static let all = [
        "Stand up and stretch.",
        "Look at something far away.",
        "Get a glass of water.",
        "Take a short walk.",
        "Step outside for some daylight.",
        "Leave your phone where it is.",
    ]

    static func random() -> String { all.randomElement()! }
}
