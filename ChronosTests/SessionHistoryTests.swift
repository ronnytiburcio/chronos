import XCTest
@testable import Chronos

/// The shared history loader behind the export and the review window: the live
/// `sessions.jsonl` plus every rotated `sessions-YYYY.jsonl` beside it.
///
/// Every file lives in a temp directory, so the real Application Support folder
/// is never touched.
final class SessionHistoryTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SessionHistoryTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        super.tearDown()
    }

    func testRotatedYearsComeFirstOldestToNewestThenTheLiveLog() throws {
        let project = UUID()
        try append(project, at: at(2023, 5, 1), in: url("sessions-2023.jsonl"))
        try append(project, at: at(2024, 5, 1), in: url("sessions-2024.jsonl"))
        try append(project, at: at(2025, 5, 1), in: liveURL)

        let starts = try history().load().map(\.start)

        XCTAssertEqual(starts, [at(2023, 5, 1), at(2024, 5, 1), at(2025, 5, 1)])
    }

    /// A log copied by hand into place is the realistic way this happens; the
    /// session must not be counted twice.
    func testASessionIdSeenTwiceIsLoadedOnce() throws {
        let project = UUID()
        let id = UUID()
        try append(project, at: at(2024, 5, 1), id: id, in: url("sessions-2024.jsonl"))
        try append(project, at: at(2024, 5, 1), id: id, in: liveURL)

        XCTAssertEqual(try history().load().count, 1)
    }

    func testAMissingLiveLogIsAnEmptyHistoryRatherThanAnError() throws {
        XCTAssertEqual(try history().load(), [])
    }

    /// Only `sessions-<year>.jsonl` counts. A stray file in Application Support
    /// must not be parsed as a session log.
    func testUnrelatedFilesInTheFolderAreIgnored() throws {
        try Data("not a log".utf8).write(to: url("sessions-notes.jsonl"))
        try Data("{}".utf8).write(to: url("projects.json"))
        try append(UUID(), at: at(2025, 5, 1), in: liveURL)

        XCTAssertEqual(history().rotatedLogURLs(), [])
        XCTAssertEqual(try history().load().count, 1)
    }

    // MARK: - Fixtures

    private var liveURL: URL { url("sessions.jsonl") }

    private func url(_ name: String) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    private func history() -> SessionHistory {
        SessionHistory(sessionsFileURL: liveURL)
    }

    private func append(_ projectID: UUID, at start: Date, id: UUID = UUID(), in url: URL) throws {
        let log = SessionLog(fileURL: url)
        try log.append(.open(id: id, projectID: projectID, start: start))
        try log.append(.close(id: id, end: start.addingTimeInterval(3600)))
    }

    private func at(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9))!
    }
}
