import XCTest
@testable import PomodoroCore

final class TimerEngineTests: XCTestCase {
    let durations = Durations(focus: 1500, shortBreak: 300, longBreak: 1200, roundsBeforeLongBreak: 4)
    let t0 = Date(timeIntervalSinceReferenceDate: 0)

    func testIdleShowsFullFocusDuration() {
        let engine = TimerEngine()
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertEqual(engine.remaining(at: t0, durations: durations), 1500)
        XCTAssertEqual(engine.progress(at: t0, durations: durations), 0)
    }

    func testRunningCountsDownFromEndDate() {
        var engine = TimerEngine()
        engine.start(at: t0, durations: durations)
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.remaining(at: t0 + 100, durations: durations), 1400)
    }

    func testProgress() {
        var engine = TimerEngine()
        engine.start(at: t0, durations: durations)
        XCTAssertEqual(engine.progress(at: t0 + 750, durations: durations), 0.5, accuracy: 0.0001)
        engine.extend(at: t0 + 750)
        // 750 of 1800 elapsed after the extension.
        XCTAssertEqual(engine.progress(at: t0 + 750, durations: durations), 750.0 / 1800, accuracy: 0.0001)
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

    func testFocusCompletionStartsShortBreakAndRecordsFullBlock() throws {
        var engine = TimerEngine()
        engine.start(at: t0, durations: durations)
        let event = try XCTUnwrap(engine.tick(at: t0 + 1500, durations: durations, autoStartFocus: false))
        guard case .focusCompleted(let record, let next) = event else { return XCTFail("\(event)") }
        XCTAssertEqual(next, .shortBreak)
        XCTAssertEqual(record.phase, .focus)
        XCTAssertEqual(record.outcome, .completed)
        XCTAssertEqual(record.actual, 1500)
        XCTAssertEqual(record.startedAt, t0)
        XCTAssertEqual(engine.phase, .shortBreak)
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.completedRounds, 1)
    }

    func testCompletedRecordEndsAtScheduledEndAfterSleep() throws {
        var engine = TimerEngine()
        engine.start(at: t0, durations: durations)
        let wake = t0 + 5000
        let event = try XCTUnwrap(engine.tick(at: wake, durations: durations, autoStartFocus: false))
        XCTAssertEqual(event.record.endedAt, t0 + 1500)
        // The break starts from wake-up, not from the missed end.
        XCTAssertEqual(engine.remaining(at: wake, durations: durations), 300)
    }

    func testBreakCompletionWaitsForUserByDefault() {
        var engine = TimerEngine()
        engine.start(at: t0, durations: durations)
        _ = engine.tick(at: t0 + 1500, durations: durations, autoStartFocus: false)
        let event = engine.tick(at: t0 + 1800, durations: durations, autoStartFocus: false)
        guard case .breakCompleted(let record, let focusStarted) = event else { return XCTFail("\(String(describing: event))") }
        XCTAssertFalse(focusStarted)
        XCTAssertEqual(record.phase, .shortBreak)
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertEqual(engine.status, .idle)
    }

    func testBreakCompletionCanAutoStartFocus() {
        var engine = TimerEngine()
        engine.start(at: t0, durations: durations)
        _ = engine.tick(at: t0 + 1500, durations: durations, autoStartFocus: true)
        let event = engine.tick(at: t0 + 1800, durations: durations, autoStartFocus: true)
        guard case .breakCompleted(_, let focusStarted) = event else { return XCTFail() }
        XCTAssertTrue(focusStarted)
        XCTAssertTrue(engine.isRunning)
    }

    func testLongBreakAfterConfiguredRounds() {
        var engine = TimerEngine()
        var now = t0
        for round in 1...4 {
            engine.start(at: now, durations: durations)
            now += 1500
            guard case .focusCompleted(_, let next) = engine.tick(at: now, durations: durations, autoStartFocus: false)
            else { return XCTFail() }
            XCTAssertEqual(next, round == 4 ? .longBreak : .shortBreak)
            now += engine.remaining(at: now, durations: durations)
            _ = engine.tick(at: now, durations: durations, autoStartFocus: false)
        }
        XCTAssertEqual(engine.completedRounds, 0)
        XCTAssertEqual(engine.phase, .focus)
    }

    func testExtendAddsFiveMinutesEachTime() {
        var engine = TimerEngine()
        XCTAssertFalse(engine.canExtend)
        engine.start(at: t0, durations: durations)
        engine.extend(at: t0)
        XCTAssertEqual(engine.remaining(at: t0, durations: durations), 1800)
        XCTAssertTrue(engine.canExtend)
        engine.extend(at: t0)
        XCTAssertEqual(engine.remaining(at: t0, durations: durations), 2100)
    }

    func testExtendedBlockRecordsExtendedLength() throws {
        var engine = TimerEngine()
        engine.start(at: t0, durations: durations)
        engine.extend(at: t0)
        let event = try XCTUnwrap(engine.tick(at: t0 + 1800, durations: durations, autoStartFocus: false))
        XCTAssertEqual(event.record.planned, 1800)
        XCTAssertEqual(event.record.actual, 1800)
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


    func testSkipFocusRecordsOnlyTimeSpent() throws {
        var engine = TimerEngine()
        engine.start(at: t0, durations: durations)
        let record = try XCTUnwrap(engine.skip(at: t0 + 600, durations: durations))
        XCTAssertEqual(record.outcome, .skipped)
        XCTAssertEqual(record.planned, 1500)
        XCTAssertEqual(record.actual, 600)
        XCTAssertEqual(engine.phase, .shortBreak)
        XCTAssertEqual(engine.completedRounds, 0)
        XCTAssertTrue(engine.isRunning)
    }

    func testSkipExcludesPausedTime() throws {
        var engine = TimerEngine()
        engine.start(at: t0, durations: durations)
        engine.pause(at: t0 + 300)
        engine.start(at: t0 + 3000, durations: durations)
        let record = try XCTUnwrap(engine.skip(at: t0 + 3100, durations: durations))
        XCTAssertEqual(record.actual, 400)
    }

    func testSkipFromIdleRecordsNothing() {
        var engine = TimerEngine()
        XCTAssertNil(engine.skip(at: t0, durations: durations))
        XCTAssertEqual(engine.phase, .shortBreak)
    }

    func testSkipBreakStartsFocus() {
        var engine = TimerEngine()
        engine.start(at: t0, durations: durations)
        _ = engine.tick(at: t0 + 1500, durations: durations, autoStartFocus: false)
        let record = engine.skip(at: t0 + 1510, durations: durations)
        XCTAssertEqual(record?.phase, .shortBreak)
        XCTAssertEqual(record?.outcome, .skipped)
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertEqual(engine.remaining(at: t0 + 1510, durations: durations), 1500)
    }

    func testResetRecordsBlockInProgress() {
        var engine = TimerEngine()
        engine.start(at: t0, durations: durations)
        let record = engine.reset(at: t0 + 200, durations: durations)
        XCTAssertEqual(record?.outcome, .reset)
        XCTAssertEqual(record?.actual, 200)
        XCTAssertEqual(engine, TimerEngine())
    }

    func testImmediateResetRecordsNothing() {
        var engine = TimerEngine()
        engine.start(at: t0, durations: durations)
        XCTAssertNil(engine.reset(at: t0 + 0.5, durations: durations))
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

    func testDecodingKeepsSavedValuesWhenKeysAreMissing() throws {
        let json = #"{"focusMinutes": 40, "iconOnly": true}"#
        let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.focusMinutes, 40)
        XCTAssertEqual(settings.shortBreakMinutes, 5)
        XCTAssertEqual(settings.menuBarDisplay, .ringAndTime)
        XCTAssertFalse(settings.focusModeEnabled)
    }
}
