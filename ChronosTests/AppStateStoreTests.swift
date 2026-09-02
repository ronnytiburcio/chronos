import XCTest
@testable import Chronos

final class AppStateStoreTests: XCTestCase {
    private var directory: URL!
    private var store: AppStateStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AppStateStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        store = nil
        try super.tearDownWithError()
    }

    func testMissingFileLoadsDefaultState() {
        XCTAssertEqual(store.load(), AppState())
    }

    func testRoundTrip() throws {
        let state = AppState(windowFrame: CGRect(x: 12, y: 34, width: 280, height: 320))

        try store.save(state)

        XCTAssertEqual(store.load(), state)
    }

    func testSaveOverwritesPreviousState() throws {
        try store.save(AppState(windowFrame: CGRect(x: 1, y: 2, width: 3, height: 4)))
        let newer = AppState(windowFrame: CGRect(x: 100, y: 200, width: 280, height: 320))

        try store.save(newer)

        XCTAssertEqual(store.load(), newer)
    }

    func testCorruptFileFallsBackToDefaultState() throws {
        try Data("{ not json at all".utf8).write(to: store.fileURL)

        XCTAssertEqual(store.load(), AppState())
    }

    func testSaveLeavesNoTemporaryFilesBehind() throws {
        try store.save(AppState(windowFrame: CGRect(x: 1, y: 2, width: 3, height: 4)))
        try store.save(AppState(windowFrame: CGRect(x: 5, y: 6, width: 7, height: 8)))

        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(contents, ["state.json"])
    }

    func testSaveCreatesMissingDirectory() throws {
        let nested = directory
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("state.json")
        let nestedStore = AppStateStore(fileURL: nested)
        let state = AppState(windowFrame: CGRect(x: 9, y: 9, width: 280, height: 320))

        try nestedStore.save(state)

        XCTAssertEqual(nestedStore.load(), state)
    }

    func testSavedJSONContainsWindowFrameKey() throws {
        try store.save(AppState(windowFrame: CGRect(x: 12, y: 34, width: 280, height: 320)))

        let json = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertTrue(json.contains("windowFrame"), json)
        XCTAssertTrue(json.contains("\"width\" : 280"), "frame should use named keys: \(json)")
    }

    // MARK: - Rollover bookkeeping and settings

    func testDefaultStateHasNoRolloverAndDefaultSettings() {
        let state = AppState()

        XCTAssertNil(state.lastRollover)
        XCTAssertEqual(state.settings.rollover, RolloverTime(hour: 4, minute: 0))
        XCTAssertFalse(state.settings.restartRunningProjectAfterRollover)
        XCTAssertTrue(state.settings.launchAtLogin)
        XCTAssertTrue(state.settings.writeMarkdownDailyNotes)
        XCTAssertTrue(state.settings.showElapsedInMenuBar)
        XCTAssertNil(state.settings.archiveFolderPath)
    }

    func testFullStateRoundTrip() throws {
        var settings = Settings()
        settings.rollover = RolloverTime(hour: 6, minute: 30)
        settings.archiveFolderPath = "Chronos/Archive"
        settings.launchAtLogin = false
        settings.restartRunningProjectAfterRollover = true
        settings.writeMarkdownDailyNotes = false
        settings.showElapsedInMenuBar = false
        let state = AppState(
            windowFrame: CGRect(x: 12, y: 34, width: 280, height: 420),
            lastRollover: Date(timeIntervalSince1970: 1_756_800_000),
            settings: settings
        )

        try store.save(state)

        XCTAssertEqual(store.load(), state)
    }

    /// A `state.json` from Phase 2 has only a window frame; it must keep
    /// loading, with defaults filled in for everything added since.
    func testStateFileWithOnlyAWindowFrameStillLoads() throws {
        let legacy = """
        { "windowFrame" : { "height" : 320, "width" : 280, "x" : 12, "y" : 34 } }
        """
        try Data(legacy.utf8).write(to: store.fileURL)

        let state = store.load()

        XCTAssertEqual(state.windowFrame, CGRect(x: 12, y: 34, width: 280, height: 320))
        XCTAssertNil(state.lastRollover)
        XCTAssertEqual(state.settings, Settings())
    }

    /// A partially written settings block picks up defaults for the rest
    /// rather than failing the whole file.
    func testPartialSettingsBlockFillsInDefaults() throws {
        let partial = """
        { "settings" : { "showElapsedInMenuBar" : false } }
        """
        try Data(partial.utf8).write(to: store.fileURL)

        let settings = store.load().settings

        XCTAssertFalse(settings.showElapsedInMenuBar)
        XCTAssertEqual(settings.rollover, RolloverTime(hour: 4, minute: 0))
        XCTAssertTrue(settings.launchAtLogin)
    }

    func testLastRolloverIsWrittenAsAnISO8601String() throws {
        try store.save(AppState(lastRollover: Date(timeIntervalSince1970: 1_756_800_000)))

        let json = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertTrue(json.contains("\"lastRollover\" : \"2025-09-02T08:00:00Z\""), json)
    }
}
