import XCTest
@testable import PomodoroCore

final class TimerEngineTests: XCTestCase {
    let durations = Durations(focus: 1500, shortBreak: 300, longBreak: 1200, roundsBeforeLongBreak: 4)
    let t0 = Date(timeIntervalSinceReferenceDate: 0)

    func testIdleShowsFullFocusDuration() {
        let engine = TimerEngine()
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertEqual(engine.remaining(at: t0, durations: durations), 1500)
    }

    func testRunningCountsDownFromEndDate() {
        var engine = TimerEngine()
        engine.start(at: t0, durations: durations)
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.remaining(at: t0 + 100, durations: durations), 1400)
    }

    func testPauseAndResumePreserveRemaining() {
        var engine = TimerEngine()
        engine.start(at: t0, durations: durations)
        engine.pause(at: t0 + 100)
        XCTAssertTrue(engine.isPaused)
        // Time passing while paused does not count.
        XCTAssertEqual(engine.remaining(at: t0 + 10_000, durations: durations), 1400)
        engine.start(at: t0 + 10_000, durations: durations)
        XCTAssertEqual(engine.remaining(at: t0 + 10_400, durations: durations), 1000)
    }

    func testTickBeforeEndDoesNothing() {
        var engine = TimerEngine()
        engine.start(at: t0, durations: durations)
        XCTAssertNil(engine.tick(at: t0 + 1499, durations: durations, autoStartFocus: false))
        XCTAssertEqual(engine.phase, .focus)
    }

    func testFocusCompletionStartsShortBreak() {
        var engine = TimerEngine()
        engine.start(at: t0, durations: durations)
        let event = engine.tick(at: t0 + 1500, durations: durations, autoStartFocus: false)
        XCTAssertEqual(event, .focusCompleted(next: .shortBreak))
        XCTAssertEqual(engine.phase, .shortBreak)
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.completedRounds, 1)
    }

    func testBreakStartsFromNowAfterSleepingThroughFocusEnd() {
        var engine = TimerEngine()
        engine.start(at: t0, durations: durations)
        let wake = t0 + 5000
        _ = engine.tick(at: wake, durations: durations, autoStartFocus: false)
        XCTAssertEqual(engine.remaining(at: wake, durations: durations), 300)
    }

    func testBreakCompletionWaitsForUserByDefault() {
        var engine = TimerEngine()
        engine.start(at: t0, durations: durations)
        _ = engine.tick(at: t0 + 1500, durations: durations, autoStartFocus: false)
        let event = engine.tick(at: t0 + 1800, durations: durations, autoStartFocus: false)
        XCTAssertEqual(event, .breakCompleted(focusStarted: false))
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertEqual(engine.status, .idle)
    }

    func testBreakCompletionCanAutoStartFocus() {
        var engine = TimerEngine()
        engine.start(at: t0, durations: durations)
        _ = engine.tick(at: t0 + 1500, durations: durations, autoStartFocus: true)
        let event = engine.tick(at: t0 + 1800, durations: durations, autoStartFocus: true)
        XCTAssertEqual(event, .breakCompleted(focusStarted: true))
        XCTAssertTrue(engine.isRunning)
    }

    func testLongBreakAfterConfiguredRounds() {
        var engine = TimerEngine()
        var now = t0
        for round in 1...4 {
            engine.start(at: now, durations: durations)
            now += 1500
            let event = engine.tick(at: now, durations: durations, autoStartFocus: false)
            XCTAssertEqual(event, .focusCompleted(next: round == 4 ? .longBreak : .shortBreak))
            now += engine.remaining(at: now, durations: durations)
            _ = engine.tick(at: now, durations: durations, autoStartFocus: false)
        }
        XCTAssertEqual(engine.completedRounds, 0)
        XCTAssertEqual(engine.phase, .focus)
    }

    func testExtendAddsFiveMinutesOnlyOnce() {
        var engine = TimerEngine()
        XCTAssertFalse(engine.canExtend)
        engine.start(at: t0, durations: durations)
        engine.extend(at: t0)
        XCTAssertEqual(engine.remaining(at: t0, durations: durations), 1800)
        XCTAssertFalse(engine.canExtend)
        engine.extend(at: t0)
        XCTAssertEqual(engine.remaining(at: t0, durations: durations), 1800)
    }

    func testExtendWhilePaused() {
        var engine = TimerEngine()
        engine.start(at: t0, durations: durations)
        engine.pause(at: t0 + 1000)
        engine.extend(at: t0 + 1000)
        XCTAssertEqual(engine.remaining(at: t0 + 1000, durations: durations), 800)
    }

    func testCannotExtendBreaks() {
        var engine = TimerEngine()
        engine.start(at: t0, durations: durations)
        _ = engine.tick(at: t0 + 1500, durations: durations, autoStartFocus: false)
        XCTAssertFalse(engine.canExtend)
    }

    func testExtensionResetsForNextFocusBlock() {
        var engine = TimerEngine()
        engine.start(at: t0, durations: durations)
        engine.extend(at: t0)
        _ = engine.tick(at: t0 + 1800, durations: durations, autoStartFocus: true)
        _ = engine.tick(at: t0 + 2100, durations: durations, autoStartFocus: true)
        XCTAssertTrue(engine.canExtend)
    }

    func testSkipFocusDoesNotCountRound() {
        var engine = TimerEngine()
        engine.start(at: t0, durations: durations)
        engine.skip(at: t0 + 10, durations: durations)
        XCTAssertEqual(engine.phase, .shortBreak)
        XCTAssertEqual(engine.completedRounds, 0)
        XCTAssertTrue(engine.isRunning)
    }

    func testSkipBreakStartsFocus() {
        var engine = TimerEngine()
        engine.start(at: t0, durations: durations)
        _ = engine.tick(at: t0 + 1500, durations: durations, autoStartFocus: false)
        engine.skip(at: t0 + 1510, durations: durations)
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertEqual(engine.remaining(at: t0 + 1510, durations: durations), 1500)
    }

    func testResetReturnsToInitialState() {
        var engine = TimerEngine()
        engine.start(at: t0, durations: durations)
        _ = engine.tick(at: t0 + 1500, durations: durations, autoStartFocus: false)
        engine.reset()
        XCTAssertEqual(engine, TimerEngine())
    }

    func testCodableRoundTrip() throws {
        var engine = TimerEngine()
        engine.start(at: t0, durations: durations)
        engine.extend(at: t0)
        let decoded = try JSONDecoder().decode(TimerEngine.self, from: JSONEncoder().encode(engine))
        XCTAssertEqual(decoded, engine)
    }
}

final class SettingsTests: XCTestCase {
    func testDefaultsAreClassicPreset() {
        XCTAssertEqual(Settings().preset, .classic)
    }

    func testPresetIsDerivedFromDurations() {
        var settings = Settings()
        settings.apply(.deep)
        XCTAssertEqual(settings.preset, .deep)
        XCTAssertEqual(settings.focusMinutes, 50)
        settings.focusMinutes = 45
        XCTAssertEqual(settings.preset, .custom)
    }

    func testDurationsUseUnit() {
        let durations = Settings().durations(unit: 1)
        XCTAssertEqual(durations.focus, 25)
        XCTAssertEqual(durations.longBreak, 20)
    }
}
