import XCTest
@testable import Chronos

final class SessionLogTests: XCTestCase {
    private var directory: URL!
    private var log: SessionLog!

    private let projectID = UUID()
    private let start = Date(timeIntervalSince1970: 1_756_800_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SessionLogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        log = SessionLog(fileURL: directory.appendingPathComponent("sessions.jsonl"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        log = nil
        try super.tearDownWithError()
    }

    // MARK: - Round trip

    func testMissingFileLoadsNoSessions() throws {
        XCTAssertEqual(try log.loadSessions(), [])
    }

    func testAppendAndReplayAnOpenSession() throws {
        let id = UUID()

        try log.append(.open(id: id, projectID: projectID, start: start))

        let sessions = try log.loadSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, id)
        XCTAssertEqual(sessions.first?.projectID, projectID)
        XCTAssertEqual(sessions.first?.start, start)
        XCTAssertTrue(sessions.first?.isOpen == true)
    }

    func testCloseRecordEndsTheSession() throws {
        let id = UUID()
        let end = start.addingTimeInterval(90)

        try log.append(.open(id: id, projectID: projectID, start: start))
        try log.append(.close(id: id, end: end))

        let sessions = try log.loadSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.end, end)
        XCTAssertEqual(sessions.first?.duration(asOf: end.addingTimeInterval(1000)), 90)
    }

    func testSessionsReplayInTheOrderTheyWereOpened() throws {
        let first = UUID()
        let second = UUID()

        try log.append(.open(id: first, projectID: projectID, start: start))
        try log.append(.close(id: first, end: start.addingTimeInterval(60)))
        try log.append(.open(id: second, projectID: projectID, start: start.addingTimeInterval(60)))

        XCTAssertEqual(try log.loadSessions().map(\.id), [first, second])
    }

    func testEachRecordIsOneLine() throws {
        let id = UUID()

        try log.append(.open(id: id, projectID: projectID, start: start))
        try log.append(.close(id: id, end: start.addingTimeInterval(5)))

        let text = try String(contentsOf: log.fileURL, encoding: .utf8)
        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(text.hasSuffix("\n"), "every record ends its own line")
        XCTAssertTrue(lines[0].contains("\"type\":\"open\""), String(lines[0]))
        XCTAssertTrue(lines[1].contains("\"type\":\"close\""), String(lines[1]))
        XCTAssertFalse(lines[1].contains("projectID"), "a close record carries only id and end")
    }

    // MARK: - Damage tolerance

    func testCloseWithoutOpenIsSkipped() throws {
        let orphan = UUID()
        let real = UUID()

        try log.append(.close(id: orphan, end: start))
        try log.append(.open(id: real, projectID: projectID, start: start))

        XCTAssertEqual(try log.loadSessions().map(\.id), [real])
    }

    func testCorruptLineIsSkippedAndTheRestSurvives() throws {
        let before = UUID()
        let after = UUID()
        try log.append(.open(id: before, projectID: projectID, start: start))
        try appendRaw("{ this is not json")
        try appendRaw("")
        try log.append(.open(id: after, projectID: projectID, start: start.addingTimeInterval(10)))

        XCTAssertEqual(try log.loadSessions().map(\.id), [before, after])
    }

    func testTruncatedFinalLineIsSkipped() throws {
        let id = UUID()
        try log.append(.open(id: id, projectID: projectID, start: start))
        try appendRaw("{\"type\":\"clo")

        XCTAssertEqual(try log.loadSessions().map(\.id), [id])
    }

    func testDuplicateOpenIsSkipped() throws {
        let id = UUID()

        try log.append(.open(id: id, projectID: projectID, start: start))
        try log.append(.open(id: id, projectID: projectID, start: start.addingTimeInterval(60)))

        let sessions = try log.loadSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.start, start, "the first open wins")
    }

    // MARK: - Rotation

    func testRotateMovesTheFileAndAFreshAppendStartsANewOne() throws {
        let rotated = UUID()
        let fresh = UUID()
        try log.append(.open(id: rotated, projectID: projectID, start: start))
        let archiveURL = directory.appendingPathComponent("sessions-2026.jsonl")

        try log.rotate(to: archiveURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: log.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        XCTAssertEqual(try log.loadSessions(), [])
        XCTAssertEqual(try SessionLog(fileURL: archiveURL).loadSessions().map(\.id), [rotated])

        try log.append(.open(id: fresh, projectID: projectID, start: start.addingTimeInterval(60)))
        XCTAssertEqual(try log.loadSessions().map(\.id), [fresh])
    }

    func testRotateRefusesToOverwriteAnExistingArchive() throws {
        try log.append(.open(id: UUID(), projectID: projectID, start: start))
        let archiveURL = directory.appendingPathComponent("sessions-2026.jsonl")
        try Data("existing".utf8).write(to: archiveURL)

        XCTAssertThrowsError(try log.rotate(to: archiveURL)) { error in
            XCTAssertEqual(error as? SessionLogError, .archiveDestinationExists(archiveURL))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: log.fileURL.path), "the log is left alone")
    }

    func testRotateWithNoLogIsANoOp() throws {
        let archiveURL = directory.appendingPathComponent("sessions-2026.jsonl")

        try log.rotate(to: archiveURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL.path))
    }

    // MARK: - Housekeeping

    func testAppendLeavesNoTemporaryFilesBehind() throws {
        let id = UUID()
        try log.append(.open(id: id, projectID: projectID, start: start))
        try log.append(.close(id: id, end: start.addingTimeInterval(1)))

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["sessions.jsonl"])
    }

    func testAppendCreatesMissingDirectories() throws {
        let nested = SessionLog(
            fileURL: directory
                .appendingPathComponent("nested", isDirectory: true)
                .appendingPathComponent("sessions.jsonl")
        )
        let id = UUID()

        try nested.append(.open(id: id, projectID: projectID, start: start))

        XCTAssertEqual(try nested.loadSessions().map(\.id), [id])
    }

    private func appendRaw(_ line: String) throws {
        let handle = try FileHandle(forWritingTo: log.fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((line + "\n").utf8))
    }
}
