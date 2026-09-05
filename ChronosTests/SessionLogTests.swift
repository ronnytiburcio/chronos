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

    // MARK: - Adjust and delete

    func testAdjustRoundTripsStartAndEnd() throws {
        let id = UUID()
        let newStart = start.addingTimeInterval(120)
        let newEnd = start.addingTimeInterval(900)
        try log.append(.open(id: id, projectID: projectID, start: start))
        try log.append(.close(id: id, end: start.addingTimeInterval(600)))

        try log.append(.adjust(id: id, projectID: nil, start: newStart, end: newEnd))

        let session = try XCTUnwrap(log.loadSessions().first)
        XCTAssertEqual(session.start, newStart)
        XCTAssertEqual(session.end, newEnd)
        XCTAssertEqual(session.projectID, projectID, "a nil projectID leaves it unchanged")
    }

    func testAdjustJSONOmitsEndWhenNilAndProjectIDWhenUnchanged() throws {
        let id = UUID()
        try log.append(.open(id: id, projectID: projectID, start: start))

        try log.append(.adjust(id: id, projectID: nil, start: start.addingTimeInterval(60), end: nil))

        let text = try String(contentsOf: log.fileURL, encoding: .utf8)
        let lines = text.split(separator: "\n")
        XCTAssertTrue(lines[1].contains("\"type\":\"adjust\""), String(lines[1]))
        XCTAssertFalse(lines[1].contains("\"end\""), String(lines[1]))
        XCTAssertFalse(lines[1].contains("projectID"), String(lines[1]))
    }

    func testAdjustJSONIncludesProjectIDWhenMoved() throws {
        let id = UUID()
        let newProject = UUID()
        try log.append(.open(id: id, projectID: projectID, start: start))

        try log.append(.adjust(id: id, projectID: newProject, start: start, end: nil))

        let text = try String(contentsOf: log.fileURL, encoding: .utf8)
        let lines = text.split(separator: "\n")
        XCTAssertTrue(lines[1].contains("\"projectID\":\"\(newProject.uuidString)\""), String(lines[1]))
    }

    func testAdjustWithProjectIDMovesTheSessionAndWithoutLeavesItAlone() throws {
        let id = UUID()
        let newProject = UUID()
        try log.append(.open(id: id, projectID: projectID, start: start))

        try log.append(.adjust(id: id, projectID: newProject, start: start, end: nil))
        XCTAssertEqual(try log.loadSessions().first?.projectID, newProject)

        try log.append(.adjust(id: id, projectID: nil, start: start.addingTimeInterval(30), end: nil))
        XCTAssertEqual(try log.loadSessions().first?.projectID, newProject, "no projectID leaves the last one in place")
    }

    func testAdjustWithEndClosesAnOpenSessionAndALaterStrayCloseIsSkipped() throws {
        let id = UUID()
        try log.append(.open(id: id, projectID: projectID, start: start))
        let closedAt = start.addingTimeInterval(1800)

        try log.append(.adjust(id: id, projectID: nil, start: start, end: closedAt))
        try log.append(.close(id: id, end: start.addingTimeInterval(9999)))

        let session = try XCTUnwrap(log.loadSessions().first)
        XCTAssertEqual(session.end, closedAt, "the stray close after the adjust closed it is ignored")
    }

    func testAdjustWithoutEndKeepsAnOpenSessionOpenAndDoesNotReopenAClosedOne() throws {
        let closedID = UUID()
        let openID = UUID()
        try log.append(.open(id: closedID, projectID: projectID, start: start))
        try log.append(.close(id: closedID, end: start.addingTimeInterval(600)))
        try log.append(.open(id: openID, projectID: projectID, start: start.addingTimeInterval(700)))

        try log.append(.adjust(id: openID, projectID: nil, start: start.addingTimeInterval(705), end: nil))
        try log.append(.adjust(id: closedID, projectID: nil, start: start.addingTimeInterval(20), end: nil))

        let sessions = try log.loadSessions()
        let open = try XCTUnwrap(sessions.first { $0.id == openID })
        let closed = try XCTUnwrap(sessions.first { $0.id == closedID })
        XCTAssertTrue(open.isOpen, "the running session stays open")
        XCTAssertEqual(closed.end, start.addingTimeInterval(600), "the closed session keeps its end rather than reopening")
    }

    func testLastAdjustWins() throws {
        let id = UUID()
        try log.append(.open(id: id, projectID: projectID, start: start))

        try log.append(.adjust(id: id, projectID: nil, start: start.addingTimeInterval(60), end: nil))
        try log.append(.adjust(id: id, projectID: nil, start: start.addingTimeInterval(120), end: nil))

        XCTAssertEqual(try log.loadSessions().first?.start, start.addingTimeInterval(120))
    }

    func testAdjustForAnUnknownIDIsSkipped() throws {
        let id = UUID()
        try log.append(.open(id: id, projectID: projectID, start: start))

        try log.append(.adjust(id: UUID(), projectID: nil, start: start.addingTimeInterval(60), end: nil))

        XCTAssertEqual(try log.loadSessions().first?.start, start)
    }

    func testDeleteRemovesTheSession() throws {
        let id = UUID()
        try log.append(.open(id: id, projectID: projectID, start: start))
        try log.append(.close(id: id, end: start.addingTimeInterval(60)))

        try log.append(.delete(id: id))

        XCTAssertEqual(try log.loadSessions(), [])
    }

    func testDeleteForAnUnknownIDIsSkipped() throws {
        try log.append(.delete(id: UUID()))

        XCTAssertEqual(try log.loadSessions(), [])
    }

    func testAFollowingOpenDoesNotForceCloseAGhostFromADeletedSession() throws {
        let deletedID = UUID()
        let nextID = UUID()
        try log.append(.open(id: deletedID, projectID: projectID, start: start))
        try log.append(.delete(id: deletedID))

        // If the deleted session still read as "open", this open would force
        // it to close (logging a warning) instead of being ignored outright.
        try log.append(.open(id: nextID, projectID: projectID, start: start.addingTimeInterval(300)))

        let sessions = try log.loadSessions()
        XCTAssertEqual(sessions.map(\.id), [nextID])
        XCTAssertTrue(sessions[0].isOpen)
    }

    func testAdjustOrCloseAfterDeleteIsIgnored() throws {
        let id = UUID()
        try log.append(.open(id: id, projectID: projectID, start: start))
        try log.append(.delete(id: id))

        try log.append(.close(id: id, end: start.addingTimeInterval(60)))
        try log.append(.adjust(id: id, projectID: nil, start: start.addingTimeInterval(120), end: nil))

        XCTAssertEqual(try log.loadSessions(), [])
    }

    func testAnUnknownTypeLineIsSkippedAndTheRestSurvives() throws {
        let before = UUID()
        let after = UUID()
        try log.append(.open(id: before, projectID: projectID, start: start))
        try appendRaw(#"{"type":"futureKind","id":"\#(UUID().uuidString)"}"#)
        try log.append(.open(id: after, projectID: projectID, start: start.addingTimeInterval(10)))

        XCTAssertEqual(try log.loadSessions().map(\.id), [before, after])
    }

    // MARK: - Rotation

    func testLeadingByteOrderMarkIsIgnored() throws {
        let id = UUID()
        try log.append(.open(id: id, projectID: projectID, start: start))
        let bytes = try Data(contentsOf: log.fileURL)
        try (Data([0xEF, 0xBB, 0xBF]) + bytes).write(to: log.fileURL)

        XCTAssertEqual(try log.loadSessions().map(\.id), [id])
    }

    func testASecondOpenClosesAnUnclosedSessionAtItsStart() throws {
        // A close record that never reached the disk must not replay as two
        // open sessions.
        let first = UUID()
        let second = UUID()
        try log.append(.open(id: first, projectID: projectID, start: start))
        try log.append(.open(id: second, projectID: projectID, start: start.addingTimeInterval(300)))

        let sessions = try log.loadSessions()
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].end, start.addingTimeInterval(300))
        XCTAssertTrue(sessions[1].isOpen)
        XCTAssertEqual(sessions.filter(\.isOpen).count, 1)
    }

    func testFractionalSecondsSurviveARoundTrip() throws {
        let id = UUID()
        let precise = start.addingTimeInterval(0.25)
        try log.append(.open(id: id, projectID: projectID, start: precise))
        try log.append(.close(id: id, end: precise.addingTimeInterval(1.5)))

        let session = try XCTUnwrap(log.loadSessions().first)
        XCTAssertEqual(session.start.timeIntervalSince1970, precise.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(session.end?.timeIntervalSince1970 ?? 0, precise.timeIntervalSince1970 + 1.5, accuracy: 0.001)
    }

    func testWholeSecondTimestampsStillLoad() throws {
        let id = UUID()
        let line = #"{"id":"\#(id.uuidString)","projectID":"\#(projectID.uuidString)","start":"2026-09-02T12:00:00Z","type":"open"}"#
        try Data((line + "\n").utf8).write(to: log.fileURL)

        XCTAssertEqual(try log.loadSessions().first?.start, Date(timeIntervalSince1970: 1_788_350_400))
    }

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
