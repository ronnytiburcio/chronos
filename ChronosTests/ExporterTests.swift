import XCTest
@testable import Chronos

/// SPEC §8's Export button: a CSV for any date range, built from the session
/// history on disk.
///
/// The calendar is pinned to America/New_York so the tracking-day boundaries do
/// not depend on the machine's time zone, and every file lives in a temp
/// directory.
final class ExporterTests: XCTestCase {
    private var directory: URL!
    private var fakeNow: FakeClock!
    private var clientWork: Project!
    private var sideProject: Project!

    /// Tuesday 2025-09-04 12:00, three hours into an open session.
    private var now: Date { fakeNow.current }

    override func setUp() {
        super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ExporterTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fakeNow = FakeClock(at(2025, 9, 4, 12))
        clientWork = Project(name: "Client Work", sortOrder: 0)
        sideProject = Project(name: "Side Project", sortOrder: 1)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        fakeNow = nil
        clientWork = nil
        sideProject = nil
        super.tearDown()
    }

    // MARK: - The whole history

    func testExportsEveryTrackingDayInRangeAcrossBothLogs() throws {
        try seedHistory()

        let csv = try exporter().csv(from: "2025-08-01", to: "2025-12-31", asOf: now)

        // The 01:00 session on 2025-09-03 is before the 04:00 rollover, so it
        // belongs to the 2025-09-02 tracking day and adds to that day's row.
        XCTAssertEqual(
            csv,
            """
            date,project,seconds,hours
            2025-08-30,Client Work,5400,1.50
            2025-09-02,Client Work,7200,2.00
            2025-09-02,Side Project,1800,0.50
            2025-09-03,Side Project,7200,2.00
            2025-09-04,Client Work,10800,3.00

            """
        )
    }

    /// The rotated log is a separate file; without reading it the oldest day
    /// would simply be missing.
    func testTheRotatedLogIsReadTooAndTheLiveLogIsNotEnough() throws {
        try seedHistory()

        let onlyLiveLog = try SessionLog(fileURL: sessionsURL).loadSessions()
        XCTAssertFalse(onlyLiveLog.contains { $0.start == at(2025, 8, 30, 9) })
        XCTAssertTrue(try exporter().csv(from: "2025-08-30", to: "2025-08-30", asOf: now)
            .contains("2025-08-30,Client Work,5400,1.50"))
    }

    // MARK: - Range filtering

    func testBoundsAreInclusiveAtBothEnds() throws {
        try seedHistory()

        let csv = try exporter().csv(from: "2025-09-02", to: "2025-09-03", asOf: now)

        XCTAssertEqual(
            csv,
            """
            date,project,seconds,hours
            2025-09-02,Client Work,7200,2.00
            2025-09-02,Side Project,1800,0.50
            2025-09-03,Side Project,7200,2.00

            """
        )
    }

    func testARangeWithNothingInItIsJustTheHeader() throws {
        try seedHistory()

        XCTAssertEqual(
            try exporter().csv(from: "2025-10-01", to: "2025-10-31", asOf: now),
            "date,project,seconds,hours\n"
        )
    }

    // MARK: - Open sessions

    func testAnOpenSessionIsMeasuredToNowAndGrowsWithTheClock() throws {
        try seedHistory()
        XCTAssertTrue(try exporter().csv(from: "2025-09-04", to: "2025-09-04", asOf: now)
            .contains("2025-09-04,Client Work,10800,3.00"))

        fakeNow.advance(by: 1800)

        XCTAssertTrue(try exporter().csv(from: "2025-09-04", to: "2025-09-04", asOf: now)
            .contains("2025-09-04,Client Work,12600,3.50"))
    }

    // MARK: - Names

    /// Archived projects keep their history (SPEC §5), so an export still names
    /// them; only a project deleted outright drops out.
    func testAnArchivedProjectIsStillExportedButADeletedOneIsSkipped() throws {
        try seedHistory()
        var archived = sideProject!
        archived.isArchived = true

        let withArchived = try Exporter(
            sessionsFileURL: sessionsURL,
            calendar: Self.newYorkCalendar,
            rollover: .default,
            projects: [clientWork, archived]
        ).csv(from: "2025-09-03", to: "2025-09-03", asOf: now)
        XCTAssertTrue(withArchived.contains("2025-09-03,Side Project,7200,2.00"))

        let withoutSideProject = try Exporter(
            sessionsFileURL: sessionsURL,
            calendar: Self.newYorkCalendar,
            rollover: .default,
            projects: [clientWork]
        ).csv(from: "2025-09-03", to: "2025-09-03", asOf: now)
        XCTAssertEqual(withoutSideProject, "date,project,seconds,hours\n")
    }

    func testRowsFollowTheProjectListOrderNotTheSessionOrder() throws {
        try seedHistory()

        // Side Project first in the list, so it comes first in the day's rows
        // even though Client Work's session was opened earlier.
        let csv = try Exporter(
            sessionsFileURL: sessionsURL,
            calendar: Self.newYorkCalendar,
            rollover: .default,
            projects: [sideProject, clientWork]
        ).csv(from: "2025-09-02", to: "2025-09-02", asOf: now)

        XCTAssertEqual(
            csv,
            """
            date,project,seconds,hours
            2025-09-02,Side Project,1800,0.50
            2025-09-02,Client Work,7200,2.00

            """
        )
    }

    func testACommaInAProjectNameIsQuoted() throws {
        let admin = Project(name: "Admin, Finance", sortOrder: 0)
        try append(admin.id, from: at(2025, 9, 2, 9), to: at(2025, 9, 2, 10))

        let csv = try Exporter(
            sessionsFileURL: sessionsURL,
            calendar: Self.newYorkCalendar,
            rollover: .default,
            projects: [admin]
        ).csv(from: "2025-09-02", to: "2025-09-02", asOf: now)

        XCTAssertEqual(
            csv,
            """
            date,project,seconds,hours
            2025-09-02,"Admin, Finance",3600,1.00

            """
        )
    }

    // MARK: - Rollover time

    /// A different rollover moves the boundary, and with it which day the
    /// after-midnight session belongs to.
    func testTheRolloverTimeDecidesWhichDayASessionLandsOn() throws {
        try seedHistory()

        let csv = try Exporter(
            sessionsFileURL: sessionsURL,
            calendar: Self.newYorkCalendar,
            rollover: RolloverTime(hour: 0, minute: 0),
            projects: [clientWork, sideProject]
        ).csv(from: "2025-09-02", to: "2025-09-03", asOf: now)

        // At midnight rollover the 01:00 session is its own day's business.
        XCTAssertEqual(
            csv,
            """
            date,project,seconds,hours
            2025-09-02,Client Work,3600,1.00
            2025-09-02,Side Project,1800,0.50
            2025-09-03,Client Work,3600,1.00
            2025-09-03,Side Project,7200,2.00

            """
        )
    }

    // MARK: - Missing files

    func testNoLogAtAllExportsAnEmptyFileRatherThanThrowing() throws {
        XCTAssertEqual(
            try exporter().csv(from: "2025-01-01", to: "2025-12-31", asOf: now),
            "date,project,seconds,hours\n"
        )
    }

    // MARK: - Fixtures

    private var sessionsURL: URL { directory.appendingPathComponent("sessions.jsonl") }
    private var rotatedURL: URL { directory.appendingPathComponent("sessions-2025.jsonl") }

    private static let newYorkCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private func exporter() -> Exporter {
        Exporter(
            sessionsFileURL: sessionsURL,
            calendar: Self.newYorkCalendar,
            rollover: .default,
            projects: [clientWork, sideProject]
        )
    }

    /// Two projects over three tracking days, with the oldest day sitting in a
    /// rotated log and the newest session still open.
    private func seedHistory() throws {
        try append(clientWork.id, from: at(2025, 8, 30, 9), to: at(2025, 8, 30, 10, 30), in: rotatedURL)

        try append(clientWork.id, from: at(2025, 9, 2, 9), to: at(2025, 9, 2, 10))
        try append(sideProject.id, from: at(2025, 9, 2, 11), to: at(2025, 9, 2, 11, 30))
        // Wednesday 01:00, before the 04:00 rollover: Tuesday's time.
        try append(clientWork.id, from: at(2025, 9, 3, 1), to: at(2025, 9, 3, 2))
        try append(sideProject.id, from: at(2025, 9, 3, 10), to: at(2025, 9, 3, 12))
        try append(clientWork.id, from: at(2025, 9, 4, 9), to: nil)
    }

    private func append(_ projectID: UUID, from start: Date, to end: Date?, in url: URL? = nil) throws {
        let log = SessionLog(fileURL: url ?? sessionsURL)
        let id = UUID()
        try log.append(.open(id: id, projectID: projectID, start: start))
        if let end {
            try log.append(.close(id: id, end: end))
        }
    }

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Self.newYorkCalendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        )!
    }
}
