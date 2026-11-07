import AppKit
import PomodoroCore
import ServiceManagement

/// Owns the engine and connects it to the clock, persistence, notifications
/// and the global hotkey.
@MainActor
final class TimerController: ObservableObject {
    @Published private(set) var engine: TimerEngine {
        didSet { save(engine, forKey: Keys.engine) }
    }
    @Published var settings: Settings {
        didSet {
            save(settings, forKey: Keys.settings)
            updateHotKey()
        }
    }
    @Published var parkedThoughts: [String] {
        didSet { defaults.set(parkedThoughts, forKey: Keys.parked) }
    }
    @Published var nextStep: String {
        didSet { defaults.set(nextStep, forKey: Keys.nextStep) }
    }
    @Published private(set) var now = Date()
    @Published private(set) var todayCount: Int
    @Published private(set) var breakTip = BreakTips.random()
    @Published private(set) var loginItemError: String?

    /// Set POMODOROBAR_FAST=1 to treat minutes as seconds when trying things out.
    private let unit: TimeInterval = ProcessInfo.processInfo.environment["POMODOROBAR_FAST"] == nil ? 60 : 1
    private let defaults = UserDefaults.standard
    private let notifier = Notifier()
    private var todayKey: String
    private var ticker: Timer?
    private var hotKey: GlobalHotKey?
    private var wakeObserver: NSObjectProtocol?

    var durations: Durations { settings.durations(unit: unit) }
    var remaining: TimeInterval { engine.remaining(at: now, durations: durations) }

    init() {
        engine = Self.load(TimerEngine.self, forKey: Keys.engine) ?? TimerEngine()
        settings = Self.load(Settings.self, forKey: Keys.settings) ?? Settings()
        parkedThoughts = defaults.stringArray(forKey: Keys.parked) ?? []
        nextStep = defaults.string(forKey: Keys.nextStep) ?? ""
        todayKey = defaults.string(forKey: Keys.todayKey) ?? ""
        todayCount = defaults.integer(forKey: Keys.todayCount)

        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Keep ticking while a menu is being tracked.
        RunLoop.main.add(ticker!, forMode: .common)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        updateHotKey()
        tick()
    }

    // MARK: Actions

    func toggle() {
        notifier.requestAuthorizationIfNeeded()
        engine.toggle(at: Date(), durations: durations)
        tick()
    }

    func skip() {
        engine.skip(at: Date(), durations: durations)
        if engine.phase.isBreak { breakTip = BreakTips.random() }
        tick()
    }

    func reset() {
        engine.reset()
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

    // MARK: Clock

    private func tick() {
        now = Date()
        rollOverDayIfNeeded()
        guard let event = engine.tick(at: now, durations: durations, autoStartFocus: settings.autoStartFocus) else { return }
        handle(event)
    }

    private func handle(_ event: TimerEvent) {
        switch event {
        case .focusCompleted(let next):
            todayCount += 1
            defaults.set(todayCount, forKey: Keys.todayCount)
            breakTip = BreakTips.random()
            let minutes = Int(durations.duration(of: next) / unit)
            let kind = next == .longBreak ? "long break" : "break"
            notifier.post(title: "Focus block done", body: "\(minutes) min \(kind). \(breakTip)")
        case .breakCompleted(let focusStarted):
            let body = focusStarted
                ? "Next focus block started."
                : "Start the next focus block when you're ready."
            notifier.post(title: "Break's over", body: nextStep.isEmpty ? body : "\(body) Next: \(nextStep)")
        }
        if settings.soundEnabled {
            NSSound(named: "Glass")?.play()
        }
    }

    private func rollOverDayIfNeeded() {
        let key = Self.dayFormatter.string(from: now)
        guard key != todayKey else { return }
        todayKey = key
        todayCount = 0
        defaults.set(key, forKey: Keys.todayKey)
        defaults.set(0, forKey: Keys.todayCount)
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
        static let todayKey = "todayKey"
        static let todayCount = "todayCount"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

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
