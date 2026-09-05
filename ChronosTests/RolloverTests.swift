import XCTest
@testable import Chronos

/// The daily rollover (SPEC §7) and what it leaves behind (SPEC §8).
///
/// Every test drives a fake clock over temp files, so a week of tracking runs
/// in a millisecond and nothing touches the real archive folder — the engine's
/// ``ArchiveLocation`` is injected, both the folder and its fallback.
@MainActor
final class RolloverTests: XCTestCase {
    private var directory: URL!
    private var fakeNow: FakeClock!

    /// 2025-09-02 04:00 America/New_York: a tracking-day start, well clear of
    /// either daylight-saving change.
    private let dayStart = Date(timeIntervalSince1970: 1_756_800_000)
    private static let day: TimeInterval = 24 * 3600

    override func setUp() async throws {
        try await super.setUp()
        try makeDirectory()
        fakeNow = FakeClock(dayStart.addingTimeInterval(5 * 3600)) // 09:00
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        fakeNow = nil
        try await super.tearDown()
    }

    // MARK: - The boundary

    func testRolloverClosesTheOpenSessionAtTheBoundaryAndZeroesTheDay() throws {
        try seedState(lastRollover: dayStart)
        let engine = makeEngine()
        let project = try XCTUnwrap(engine.addProject(named: "Client Work"))
        engine.start(projectID: project.id)
        let boundary = dayStart.addingTimeInterval(Self.day)
        advance(to: boundary.addingTimeInterval(3600))

        engine.performRolloversIfNeeded(now: fakeNow.current)

        XCTAssertNil(engine.openSession)
        XCTAssertEqual(engine.sessions.last?.end, boundary)
        XCTAssertEqual(engine.lastRollover, boundary)
        XCTAssertEqual(engine.dayTotal(asOf: fakeNow.current), 0)
        // 09:00 to 04:00 is nineteen hours, and the archive says so.
        XCTAssertEqual(
            try read(summaryFile),
            """
            date,project,seconds,hours
            2025-09-02,Client Work,68400,19.00

            """
        )
        XCTAssertTrue(try read(sessionsFileCSV).contains("2025-09-03T04:00:00-04:00,68400"))
    }

    func testADayWithSessionsWritesTheThreeArchiveFiles() throws {
        let files = try archivedDay { engine, boundary in
            engine.performRolloversIfNeeded(now: boundary)
        }

        XCTAssertEqual(
            files.summary,
            """
            date,project,seconds,hours
            2025-09-02,Client Work,6730,1.87
            2025-09-02,Side Project,2880,0.80

            """
        )
        XCTAssertEqual(
            files.sessions,
            """
            date,project,start,end,seconds
            2025-09-02,Client Work,2025-09-02T09:00:00-04:00,2025-09-02T10:52:10-04:00,6730
            2025-09-02,Side Project,2025-09-02T11:00:00-04:00,2025-09-02T11:48:00-04:00,2880

            """
        )
        XCTAssertEqual(
            files.markdown,
            """
            # Chronos — 2025-09-02
            **Total:** 2h 40m

            | Project | Time |
            |---|---|
            | Client Work | 1h 52m |
            | Side Project | 0h 48m |

            """
        )
    }

    func testSessionsCSVRowsFollowStartTimeAfterAnEditReordersThem() throws {
        try seedState(lastRollover: dayStart)
        let engine = makeEngine()
        let first = try XCTUnwrap(engine.addProject(named: "First"))
        let second = try XCTUnwrap(engine.addProject(named: "Second"))

        engine.start(projectID: first.id) // 09:00:00
        fakeNow.advance(by: 600)
        engine.stop()
        let firstSession = try XCTUnwrap(engine.sessions.first { $0.projectID == first.id })

        advance(to: dayStart.addingTimeInterval(7 * 3600)) // 11:00:00
        engine.start(projectID: second.id)
        fakeNow.advance(by: 600)
        engine.stop()
        let secondSession = try XCTUnwrap(engine.sessions.first { $0.projectID == second.id })

        // Edit "First"'s start to land after "Second"'s start: insertion order
        // (First, then Second) now disagrees with start-time order.
        try engine.editSession(
            firstSession.id,
            projectID: first.id,
            start: secondSession.start.addingTimeInterval(60),
            end: secondSession.start.addingTimeInterval(300)
        )

        let boundary = dayStart.addingTimeInterval(Self.day)
        advance(to: boundary)
        engine.performRolloversIfNeeded(now: fakeNow.current)

        let rows = try read(sessionsFileCSV)
            .split(separator: "\n")
            .dropFirst() // header
            .filter { !$0.isEmpty }
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows[0].contains("Second"), "the earlier-starting session (Second) comes first")
        XCTAssertTrue(rows[1].contains("First"), "the edited, later-starting session (First) comes second")
    }

    func testAnEmptyDayWritesNothingButStillTurnsOver() throws {
        try seedState(lastRollover: dayStart)
        let engine = makeEngine()
        let boundary = dayStart.addingTimeInterval(Self.day)
        advance(to: boundary.addingTimeInterval(60))

        engine.performRolloversIfNeeded(now: fakeNow.current)

        XCTAssertEqual(engine.lastRollover, boundary)
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveFolder.path))
    }

    // MARK: - Catch-up

    func testThreeMissedDaysCatchUpInOrderOnLaunch() throws {
        let project = try seedProject(named: "Client Work")
        for offset in 0..<3 {
            let start = dayStart.addingTimeInterval(Double(offset) * Self.day + 5 * 3600)
            try seedSession(project.id, from: start, to: start.addingTimeInterval(3600))
        }
        try seedState(lastRollover: dayStart)
        // Chronos was closed for three days; it opens on the fourth at 09:00.
        fakeNow = FakeClock(dayStart.addingTimeInterval(3 * Self.day + 5 * 3600))

        let engine = makeEngine()

        XCTAssertEqual(engine.lastRollover, dayStart.addingTimeInterval(3 * Self.day))
        XCTAssertEqual(engine.dayTotal(asOf: fakeNow.current), 0)
        XCTAssertEqual(
            try read(summaryFile),
            """
            date,project,seconds,hours
            2025-09-02,Client Work,3600,1.00
            2025-09-03,Client Work,3600,1.00
            2025-09-04,Client Work,3600,1.00

            """
        )
    }

    func testAnOpenSessionFromBeforeTheLastRolloverIsClosedAndFiledUnderItsOwnDay() throws {
        let project = try seedProject(named: "Client Work")
        // Hand-edited state, or a build that predates this rule: a session
        // still open from before the rollover on record (SPEC §6).
        try seedSession(project.id, from: dayStart.addingTimeInterval(-4 * 3600), to: nil)
        try seedState(lastRollover: dayStart)
        fakeNow = FakeClock(dayStart.addingTimeInterval(Self.day + 5 * 3600))

        let engine = makeEngine()

        XCTAssertNil(engine.openSession)
        XCTAssertEqual(engine.sessions.first?.end, dayStart)
        // The close reached the log, so a relaunch sees the same thing.
        XCTAssertEqual(try SessionLog(fileURL: sessionsURL).loadSessions().first?.end, dayStart)
        // It counts towards neither the day on screen nor the day the
        // catch-up archives: it ran before both, so it is filed on its own
        // under the day it started (SPEC §6: "archive it to that day").
        XCTAssertEqual(engine.lastRollover, dayStart.addingTimeInterval(Self.day))
        XCTAssertEqual(engine.dayTotal(asOf: fakeNow.current), 0)
        XCTAssertEqual(
            try read(summaryFile),
            """
            date,project,seconds,hours
            2025-09-01,Client Work,14400,4.00

            """
        )
        XCTAssertTrue(try read(sessionsFileCSV).contains("2025-09-01,Client Work,2025-09-02T00:00:00-04:00,2025-09-02T04:00:00-04:00,14400"))
    }

    func testResetWithTheClockBehindTheDayStartDoesNothing() throws {
        try seedState(lastRollover: dayStart)
        let engine = makeEngine()
        let project = try XCTUnwrap(engine.addProject(named: "Client Work"))
        engine.start(projectID: project.id)
        // The clock is corrected to before the day on screen even began.
        fakeNow.advance(by: -6 * 3600)

        engine.resetDay()

        XCTAssertNotNil(engine.openSession, "the running session is left alone")
        XCTAssertNil(engine.sessions.last?.end)
        XCTAssertEqual(engine.lastRollover, dayStart)
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveFolder.path))
    }

    func testAnEmptyExistingSummaryFileStillGetsItsHeader() throws {
        try FileManager.default.createDirectory(at: archiveFolder, withIntermediateDirectories: true)
        try Data().write(to: summaryFile)
        try seedState(lastRollover: dayStart)

        try runOneHourDay(named: "Client Work")

        XCTAssertTrue(try read(summaryFile).hasPrefix("date,project,seconds,hours\n"))
    }

    func testASessionEndingAfterTheBoundaryIsClampedInBothFiles() throws {
        let project = try seedProject(named: "Client Work")
        // A hand-edited log line that runs past the boundary.
        try seedSession(
            project.id,
            from: dayStart.addingTimeInterval(3600),
            to: dayStart.addingTimeInterval(Self.day + 3600)
        )
        try seedState(lastRollover: dayStart)
        fakeNow = FakeClock(dayStart.addingTimeInterval(Self.day + 5 * 3600))

        _ = makeEngine()

        XCTAssertEqual(
            try read(summaryFile),
            """
            date,project,seconds,hours
            2025-09-02,Client Work,82800,23.00

            """
        )
        XCTAssertTrue(try read(sessionsFileCSV).contains("2025-09-03T04:00:00-04:00,82800"))
    }

    func testManualResetFilesAnOverdueDayBeforeResettingTheCurrentOne() throws {
        // Restart on, so the project keeps running into the new day and the
        // reset has something to file for it.
        try seedState(settings: Settings(restartRunningProjectAfterRollover: true), lastRollover: dayStart)
        let engine = makeEngine()
        let project = try XCTUnwrap(engine.addProject(named: "Client Work"))
        engine.start(projectID: project.id)
        // The scheduled rollover never ran (say the Mac slept through it), and
        // the user presses reset at 06:00 the next day.
        let boundary = dayStart.addingTimeInterval(Self.day)
        advance(to: boundary.addingTimeInterval(2 * 3600))

        engine.resetDay()

        XCTAssertEqual(
            try read(summaryFile),
            """
            date,project,seconds,hours
            2025-09-02,Client Work,68400,19.00
            2025-09-03,Client Work,7200,2.00

            """
        )
        XCTAssertEqual(engine.lastRollover, fakeNow.current)
    }

    func testALogWhoseOpenSessionIsFollowedByAnotherStillArchivesTheDay() throws {
        // The replay closes an abandoned session at the next one's start, so
        // the day it lands in is archived like any other.
        let project = try seedProject(named: "Client Work")
        try seedSession(project.id, from: dayStart.addingTimeInterval(3600), to: nil)
        try seedSession(
            project.id,
            from: dayStart.addingTimeInterval(2 * 3600),
            to: dayStart.addingTimeInterval(3 * 3600)
        )
        try seedState(lastRollover: dayStart)
        fakeNow = FakeClock(dayStart.addingTimeInterval(Self.day + 5 * 3600))

        _ = makeEngine()

        XCTAssertEqual(
            try read(summaryFile),
            """
            date,project,seconds,hours
            2025-09-02,Client Work,7200,2.00

            """
        )
    }

    // MARK: - Manual reset

    func testManualResetProducesTheSameRowsAsAnAutomaticRollover() throws {
        let automatic = try archivedDay { engine, boundary in
            engine.performRolloversIfNeeded(now: boundary)
        }
        let manual = try archivedDay { engine, _ in
            engine.resetDay()
        }

        XCTAssertEqual(automatic, manual)
    }

    // MARK: - Restarting

    func testRestartSettingReopensTheSameProjectAtTheBoundary() throws {
        var settings = Settings()
        settings.restartRunningProjectAfterRollover = true
        try seedState(settings: settings, lastRollover: dayStart)
        let engine = makeEngine()
        let project = try XCTUnwrap(engine.addProject(named: "Client Work"))
        engine.start(projectID: project.id)
        let boundary = dayStart.addingTimeInterval(Self.day)
        advance(to: boundary.addingTimeInterval(1800))

        engine.performRolloversIfNeeded(now: fakeNow.current)

        XCTAssertEqual(engine.openSession?.projectID, project.id)
        XCTAssertEqual(engine.openSession?.start, boundary)
        XCTAssertEqual(engine.sessions.first?.end, boundary)
        XCTAssertEqual(engine.total(for: project.id, asOf: fakeNow.current), 1800)
        // And it is on disk: the new session survives a relaunch.
        XCTAssertEqual(makeEngine().openSession?.start, boundary)
    }

    func testWithoutTheRestartSettingNothingIsRunningAfterTheRollover() throws {
        try seedState(lastRollover: dayStart)
        let engine = makeEngine()
        let project = try XCTUnwrap(engine.addProject(named: "Client Work"))
        engine.start(projectID: project.id)
        advance(to: dayStart.addingTimeInterval(Self.day + 1800))

        engine.performRolloversIfNeeded(now: fakeNow.current)

        XCTAssertNil(engine.openSession)
        XCTAssertNil(engine.runningProject)
        XCTAssertNil(makeEngine().openSession)
    }

    // MARK: - Settings and escaping

    func testMarkdownNotesCanBeTurnedOff() throws {
        var settings = Settings()
        settings.writeMarkdownDailyNotes = false
        try seedState(settings: settings, lastRollover: dayStart)
        try runOneHourDay(named: "Client Work")

        XCTAssertTrue(FileManager.default.fileExists(atPath: summaryFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: markdownFile("2025-09-02").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dailyNotesFolder.path))
    }

    func testAProjectNameWithACommaAndQuotesIsEscapedInBothCSVs() throws {
        try seedState(lastRollover: dayStart)
        try runOneHourDay(named: "Admin, \"Finance\"")

        XCTAssertEqual(
            try read(summaryFile),
            #"""
            date,project,seconds,hours
            2025-09-02,"Admin, ""Finance""",3600,1.00

            """#
        )
        XCTAssertTrue(try read(sessionsFileCSV).contains("2025-09-02,\"Admin, \"\"Finance\"\"\",2025-09-02"))
        // The markdown note is not CSV and keeps the name as typed.
        XCTAssertTrue(try read(markdownFile("2025-09-02")).contains("| Admin, \"Finance\" | 1h 0m |"))
    }

    // MARK: - Yearly rotation

    /// 2026-12-31 04:00 America/New_York.
    private let newYearsEve = Date(timeIntervalSince1970: 1_798_707_600)

    func testCrossingTheYearRotatesTheLogAndLeavesTheRestartInTheNewOne() throws {
        var settings = Settings()
        settings.restartRunningProjectAfterRollover = true
        try seedState(settings: settings, lastRollover: newYearsEve)
        let project = try seedProject(named: "Client Work")
        fakeNow = FakeClock(newYearsEve.addingTimeInterval(5 * 3600))
        let engine = makeEngine()
        engine.start(projectID: project.id)
        let boundary = newYearsEve.addingTimeInterval(Self.day)
        advance(to: boundary)

        engine.performRolloversIfNeeded(now: fakeNow.current)

        let archived = directory.appendingPathComponent("sessions-2026.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archived.path))
        let closed = try SessionLog(fileURL: archived).loadSessions()
        XCTAssertEqual(closed.count, 1)
        XCTAssertEqual(closed.first?.end, boundary)
        // The fresh log holds only the restarted session, and so does memory.
        let fresh = try SessionLog(fileURL: sessionsURL).loadSessions()
        XCTAssertEqual(fresh.count, 1)
        XCTAssertEqual(fresh.first?.start, boundary)
        XCTAssertEqual(fresh.first?.isOpen, true)
        XCTAssertEqual(engine.sessions.map(\.id), fresh.map(\.id))
        XCTAssertNil(engine.lastWarning)
    }

    func testRotationRefusesToOverwriteAnExistingArchiveAndSaysSo() throws {
        try seedState(lastRollover: newYearsEve)
        let project = try seedProject(named: "Client Work")
        try seedSession(
            project.id,
            from: newYearsEve.addingTimeInterval(5 * 3600),
            to: newYearsEve.addingTimeInterval(6 * 3600)
        )
        let existing = directory.appendingPathComponent("sessions-2026.jsonl")
        try Data("last year".utf8).write(to: existing)
        fakeNow = FakeClock(newYearsEve.addingTimeInterval(Self.day + 3600))

        let engine = makeEngine()

        // Nothing is lost: the archive is untouched and the log still has the
        // year in it. The day still turned over, and the user is told.
        XCTAssertEqual(try read(existing), "last year")
        XCTAssertEqual(try SessionLog(fileURL: sessionsURL).loadSessions().count, 1)
        XCTAssertEqual(engine.lastRollover, newYearsEve.addingTimeInterval(Self.day))
        XCTAssertNotNil(engine.lastWarning)
        XCTAssertEqual(engine.lastWarning?.contains("sessions-2026.jsonl"), true)
    }

    // MARK: - Failure handling

    func testAnUnwritableArchiveFolderFallsBackAndWarns() throws {
        // A plain file where the folder should be: creating the directory
        // fails, which is the same shape as a denied Documents prompt.
        try Data("not a folder".utf8).write(to: URL(fileURLWithPath: archiveFolder.path))
        try seedState(lastRollover: dayStart)

        let engine = try runOneHourDay(named: "Client Work")

        XCTAssertEqual(
            try read(fallbackFolder.appendingPathComponent("daily-summary.csv")),
            """
            date,project,seconds,hours
            2025-09-02,Client Work,3600,1.00

            """
        )
        XCTAssertEqual(
            engine.lastWarning,
            "Archive written to \(fallbackFolder.path) because \(archiveFolder.path) was not writable"
        )
        engine.clearWarning()
        XCTAssertNil(engine.lastWarning)
    }

    // MARK: - Folder resolution

    func testArchiveFolderComesFromTheSettingWithTildeExpanded() {
        XCTAssertEqual(
            AppPaths.archiveDirectory(forSettingsPath: "~/Chronos Archive").path,
            NSHomeDirectory() + "/Chronos Archive"
        )
        XCTAssertEqual(AppPaths.archiveDirectory(forSettingsPath: nil).lastPathComponent, "Chronos")
        XCTAssertEqual(AppPaths.archiveDirectory(forSettingsPath: "   ").lastPathComponent, "Chronos")
        XCTAssertEqual(AppPaths.archiveDirectory(forSettingsPath: nil).deletingLastPathComponent().lastPathComponent, "Documents")
    }

    // MARK: - Scenarios

    /// What one rollover left in the archive.
    private struct ArchiveContents: Equatable {
        var summary: String
        var sessions: String
        var markdown: String
    }

    /// Runs one tracking day with two projects and one session each, ends it
    /// with `finish`, and reports what the archive says. Starts from a clean
    /// directory so it can be run twice in a row and the results compared.
    private func archivedDay(finishedBy finish: (TimerEngine, Date) -> Void) throws -> ArchiveContents {
        try? FileManager.default.removeItem(at: directory)
        try makeDirectory()
        fakeNow = FakeClock(dayStart.addingTimeInterval(5 * 3600))
        try seedState(lastRollover: dayStart)

        let engine = makeEngine()
        let clientWork = try XCTUnwrap(engine.addProject(named: "Client Work"))
        let sideProject = try XCTUnwrap(engine.addProject(named: "Side Project"))

        engine.start(projectID: clientWork.id) // 09:00:00
        fakeNow.advance(by: 6730)              // 1.87 hours
        engine.stop()
        advance(to: dayStart.addingTimeInterval(7 * 3600)) // 11:00:00
        engine.start(projectID: sideProject.id)
        fakeNow.advance(by: 2880)              // 0.80 hours
        engine.stop()

        let boundary = dayStart.addingTimeInterval(Self.day)
        advance(to: boundary)
        finish(engine, boundary)

        return ArchiveContents(
            summary: try read(summaryFile),
            sessions: try read(sessionsFileCSV),
            markdown: try read(markdownFile("2025-09-02"))
        )
    }

    /// One project, one hour, then the day turns over.
    @discardableResult
    private func runOneHourDay(named name: String) throws -> TimerEngine {
        let engine = makeEngine()
        let project = try XCTUnwrap(engine.addProject(named: name))
        engine.start(projectID: project.id)
        fakeNow.advance(by: 3600)
        engine.stop()
        advance(to: dayStart.addingTimeInterval(Self.day))
        engine.performRolloversIfNeeded(now: fakeNow.current)
        return engine
    }

    // MARK: - Fixtures

    private var projectsURL: URL { directory.appendingPathComponent("projects.json") }
    private var sessionsURL: URL { directory.appendingPathComponent("sessions.jsonl") }
    private var stateURL: URL { directory.appendingPathComponent("state.json") }
    private var archiveFolder: URL { directory.appendingPathComponent("Archive", isDirectory: true) }
    private var fallbackFolder: URL { directory.appendingPathComponent("Fallback", isDirectory: true) }
    private var summaryFile: URL { archiveFolder.appendingPathComponent("daily-summary.csv") }
    private var sessionsFileCSV: URL { archiveFolder.appendingPathComponent("sessions.csv") }
    private var dailyNotesFolder: URL { archiveFolder.appendingPathComponent("daily", isDirectory: true) }

    private func markdownFile(_ dateString: String) -> URL {
        dailyNotesFolder.appendingPathComponent("\(dateString).md")
    }

    /// Pinned so the tracking-day math does not depend on the machine's zone.
    private static let newYorkCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private func makeEngine() -> TimerEngine {
        // Captured as values: the closures are `@Sendable` and a test case is
        // not, but a `URL` crosses happily.
        let archive = archiveFolder
        let fallback = fallbackFolder
        return TimerEngine(
            clock: fakeNow.clock,
            projectStore: ProjectStore(fileURL: projectsURL),
            sessionLog: SessionLog(fileURL: sessionsURL),
            stateStore: AppStateStore(fileURL: stateURL),
            calendar: Self.newYorkCalendar,
            archiveLocation: ArchiveLocation(
                folder: { _ in archive },
                fallbackFolder: { fallback }
            )
        )
    }

    private func makeDirectory() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("RolloverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func seedState(settings: Settings = Settings(), lastRollover: Date) throws {
        try AppStateStore(fileURL: stateURL)
            .save(AppState(lastRollover: lastRollover, settings: settings))
    }

    private func seedProject(named name: String) throws -> Project {
        let project = Project(name: name, sortOrder: 0)
        try ProjectStore(fileURL: projectsURL).save([project])
        return project
    }

    private func seedSession(_ projectID: UUID, from start: Date, to end: Date?) throws {
        let log = SessionLog(fileURL: sessionsURL)
        let id = UUID()
        try log.append(.open(id: id, projectID: projectID, start: start))
        if let end {
            try log.append(.close(id: id, end: end))
        }
    }

    private func advance(to date: Date) {
        fakeNow.advance(by: date.timeIntervalSince(fakeNow.current))
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
