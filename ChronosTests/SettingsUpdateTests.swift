import XCTest
@testable import Chronos

/// ``TimerEngine/updateSettings(_:)``: the settings window's one way in, and
/// still the single writer of `state.json`.
@MainActor
final class SettingsUpdateTests: XCTestCase {
    private var directory: URL!
    private var fakeNow: FakeClock!

    /// 2025-09-02 09:00 America/New_York.
    private let instant = Date(timeIntervalSince1970: 1_756_800_000 + 5 * 3600)

    override func setUp() async throws {
        try await super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SettingsUpdateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fakeNow = FakeClock(instant)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        fakeNow = nil
        try await super.tearDown()
    }

    func testUpdatingSettingsWritesThemThroughToDisk() throws {
        let engine = makeEngine()

        let updated = engine.updateSettings {
            $0.rollover = RolloverTime(hour: 6, minute: 30)
            $0.writeMarkdownDailyNotes = false
            $0.archiveFolderPath = "~/Documents/Timesheets"
        }

        XCTAssertEqual(updated.rollover, RolloverTime(hour: 6, minute: 30))
        XCTAssertEqual(engine.settings, updated)

        // A fresh store reading the same file sees exactly what the engine says.
        let onDisk = AppStateStore(fileURL: stateURL).load()
        XCTAssertEqual(onDisk.settings, updated)
        XCTAssertEqual(onDisk.settings.archiveFolderPath, "~/Documents/Timesheets")
        XCTAssertFalse(onDisk.settings.writeMarkdownDailyNotes)
    }

    func testASettingsChangeSurvivesARelaunch() throws {
        let engine = makeEngine()
        engine.updateSettings { $0.showElapsedInMenuBar = false }

        let relaunched = makeEngine()

        XCTAssertFalse(relaunched.settings.showElapsedInMenuBar)
    }

    /// The engine owns the whole of `AppState`, so a frame save cannot land on
    /// a copy that predates the settings change (or the other way round).
    func testAFrameSaveAfterwardsKeepsTheSettings() throws {
        let engine = makeEngine()
        engine.updateSettings { $0.restartRunningProjectAfterRollover = true }

        engine.updateWindowFrame(CGRect(x: 40, y: 60, width: 280, height: 320))

        let onDisk = AppStateStore(fileURL: stateURL).load()
        XCTAssertTrue(onDisk.settings.restartRunningProjectAfterRollover)
        XCTAssertEqual(onDisk.windowFrame, CGRect(x: 40, y: 60, width: 280, height: 320))
        // And the rollover bookkeeping in the same file is untouched.
        XCTAssertEqual(onDisk.lastRollover, engine.lastRollover)
    }

    func testASettingsChangeKeepsAnAlreadySavedFrame() throws {
        let engine = makeEngine()
        engine.updateWindowFrame(CGRect(x: 12, y: 34, width: 280, height: 240))

        engine.updateSettings { $0.launchAtLogin = false }

        let onDisk = AppStateStore(fileURL: stateURL).load()
        XCTAssertEqual(onDisk.windowFrame, CGRect(x: 12, y: 34, width: 280, height: 240))
        XCTAssertFalse(onDisk.settings.launchAtLogin)
    }

    /// Changing nothing writes nothing: the returned value is still the current
    /// settings, so callers comparing the rollover time see no change either.
    func testANoOpChangeLeavesTheSettingsAlone() throws {
        let engine = makeEngine()
        let before = engine.settings

        let returned = engine.updateSettings { _ in }

        XCTAssertEqual(returned, before)
        XCTAssertEqual(engine.settings, before)
    }

    /// The rollover time is what the scheduler arms on, so the engine's idea of
    /// the next boundary moves the instant the setting does — which is exactly
    /// why the settings window has to call `RolloverScheduler.rearm()`: an
    /// already-armed timer would still be pointing at the old date.
    func testChangingTheRolloverTimeMovesTheNextBoundary() throws {
        let engine = makeEngine()
        // 2025-09-03 04:00, the boundary of the day the engine opened in.
        let before = engine.nextRolloverBoundary

        engine.updateSettings { $0.rollover = RolloverTime(hour: 2, minute: 0) }

        XCTAssertEqual(engine.nextRolloverBoundary, before.addingTimeInterval(-2 * 3600))
    }

    // MARK: - Fixtures

    private var stateURL: URL { directory.appendingPathComponent("state.json") }

    private static let newYorkCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private func makeEngine() -> TimerEngine {
        let archive = directory.appendingPathComponent("Archive", isDirectory: true)
        return TimerEngine(
            clock: fakeNow.clock,
            projectStore: ProjectStore(fileURL: directory.appendingPathComponent("projects.json")),
            sessionLog: SessionLog(fileURL: directory.appendingPathComponent("sessions.jsonl")),
            stateStore: AppStateStore(fileURL: stateURL),
            calendar: Self.newYorkCalendar,
            archiveLocation: ArchiveLocation(folder: { _ in archive }, fallbackFolder: { archive })
        )
    }
}
