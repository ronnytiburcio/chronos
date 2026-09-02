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
}
