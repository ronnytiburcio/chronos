import XCTest
@testable import Chronos

@MainActor
final class TimerEngineTests: XCTestCase {
    private var directory: URL!
    /// Drives ``Clock`` so a whole day of tracking runs in a millisecond.
    private var fakeNow: FakeClock!

    private let dayStart = Date(timeIntervalSince1970: 1_756_800_000)

    // `async` overrides so they inherit this class's `@MainActor` isolation;
    // the throwing non-async hooks are nonisolated and cannot touch the
    // properties the tests share.
    override func setUp() async throws {
        try await super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("TimerEngineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fakeNow = FakeClock(dayStart.addingTimeInterval(8 * 3600))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        fakeNow = nil
        try await super.tearDown()
    }

    // MARK: - Starting and stopping

    func testStartOpensASessionAndPersistsItImmediately() throws {
        let engine = makeEngine()
        let project = try XCTUnwrap(engine.addProject(named: "Client Work"))

        engine.start(projectID: project.id)

        assertAtMostOneOpenSession(engine)
        XCTAssertEqual(engine.openSession?.projectID, project.id)
        XCTAssertEqual(engine.openSession?.start, fakeNow.current)
        XCTAssertEqual(engine.runningProject, engine.projects.first)
        // On disk before the method returned, not at quit time.
        let persisted = try SessionLog(fileURL: sessionsURL).loadSessions()
        XCTAssertEqual(persisted.count, 1)
        XCTAssertTrue(persisted[0].isOpen)
    }

    func testStartingAnotherProjectClosesTheFirstAtNow() throws {
        let engine = makeEngine()
        let first = try XCTUnwrap(engine.addProject(named: "First"))
        let second = try XCTUnwrap(engine.addProject(named: "Second"))
        engine.start(projectID: first.id)
        let switchedAt = fakeNow.advance(by: 600)

        engine.start(projectID: second.id)

        assertAtMostOneOpenSession(engine)
        XCTAssertEqual(engine.sessions.count, 2)
        XCTAssertEqual(engine.sessions[0].end, switchedAt)
        XCTAssertEqual(engine.sessions[1].start, switchedAt)
        XCTAssertEqual(engine.openSession?.projectID, second.id)
    }

    func testStartingTheRunningProjectAgainIsANoOp() throws {
        let engine = makeEngine()
        let project = try XCTUnwrap(engine.addProject(named: "Client Work"))
        engine.start(projectID: project.id)
        let originalStart = try XCTUnwrap(engine.openSession?.start)
        fakeNow.advance(by: 300)

        engine.start(projectID: project.id)

        assertAtMostOneOpenSession(engine)
        XCTAssertEqual(engine.sessions.count, 1)
        XCTAssertEqual(engine.openSession?.start, originalStart)
    }

    func testStartingAnUnknownProjectDoesNotDisturbTheRunningOne() throws {
        let engine = makeEngine()
        let project = try XCTUnwrap(engine.addProject(named: "Client Work"))
        engine.start(projectID: project.id)

        engine.start(projectID: UUID())

        assertAtMostOneOpenSession(engine)
        XCTAssertEqual(engine.openSession?.projectID, project.id)
    }

    func testStopClosesTheOpenSession() throws {
        let engine = makeEngine()
        let project = try XCTUnwrap(engine.addProject(named: "Client Work"))
        engine.start(projectID: project.id)
        let stoppedAt = fakeNow.advance(by: 125)

        engine.stop()

        assertAtMostOneOpenSession(engine)
        XCTAssertNil(engine.openSession)
        XCTAssertNil(engine.runningProject)
        XCTAssertEqual(engine.sessions.first?.end, stoppedAt)
    }

    func testStopWithNothingRunningIsANoOp() {
        let engine = makeEngine()

        engine.stop()

        XCTAssertTrue(engine.sessions.isEmpty)
    }

    // MARK: - Toggle

    func testToggleOnTheRunningProjectStops() throws {
        let engine = makeEngine()
        let project = try XCTUnwrap(engine.addProject(named: "Client Work"))
        engine.toggle(projectID: project.id)
        XCTAssertNotNil(engine.openSession)
        fakeNow.advance(by: 60)

        engine.toggle(projectID: project.id)

        assertAtMostOneOpenSession(engine)
        XCTAssertNil(engine.openSession)
    }

    func testToggleOnAnotherProjectSwitches() throws {
        let engine = makeEngine()
        let first = try XCTUnwrap(engine.addProject(named: "First"))
        let second = try XCTUnwrap(engine.addProject(named: "Second"))
        engine.toggle(projectID: first.id)
        fakeNow.advance(by: 60)

        engine.toggle(projectID: second.id)

        assertAtMostOneOpenSession(engine)
        XCTAssertEqual(engine.openSession?.projectID, second.id)
    }

    func testNeverTwoOpenSessionsAcrossALongSequence() throws {
        let engine = makeEngine()
        let projects = try (0..<3).map { try XCTUnwrap(engine.addProject(named: "Project \($0)")) }

        for step in 0..<12 {
            engine.toggle(projectID: projects[step % projects.count].id)
            fakeNow.advance(by: 30)
            assertAtMostOneOpenSession(engine)
        }
    }

    // MARK: - Totals

    func testTotalsAreComputedFromTimestamps() throws {
        let engine = makeEngine()
        let first = try XCTUnwrap(engine.addProject(named: "First"))
        let second = try XCTUnwrap(engine.addProject(named: "Second"))

        engine.start(projectID: first.id)
        fakeNow.advance(by: 600)
        engine.start(projectID: second.id)
        fakeNow.advance(by: 300)
        engine.stop()
        // Reopened at the same instant `stop()` closed the previous session.
        engine.start(projectID: first.id)
        let asOf = fakeNow.advance(by: 100).addingTimeInterval(50)

        // The open session counts live, without any ticking: 600 closed plus
        // 150 still running.
        XCTAssertEqual(engine.total(for: first.id, asOf: asOf), 750)
        XCTAssertEqual(engine.total(for: second.id, asOf: asOf), 300)
        XCTAssertEqual(engine.dayTotal(asOf: asOf), 1050)
    }

    func testTotalsExcludeSessionsFromBeforeTheLastRollover() throws {
        let project = Project(name: "Client Work", sortOrder: 0)
        try ProjectStore(fileURL: projectsURL).save([project])
        let log = SessionLog(fileURL: sessionsURL)
        // Yesterday: an hour, well before the rollover on record.
        let yesterday = UUID()
        try log.append(.open(id: yesterday, projectID: project.id, start: dayStart.addingTimeInterval(-20 * 3600)))
        try log.append(.close(id: yesterday, end: dayStart.addingTimeInterval(-19 * 3600)))
        try AppStateStore(fileURL: stateURL).save(AppState(lastRollover: dayStart))

        let engine = makeEngine()
        engine.start(projectID: project.id)
        let now = fakeNow.advance(by: 120)

        XCTAssertEqual(engine.lastRollover, dayStart)
        XCTAssertEqual(engine.sessions.count, 2, "yesterday's session is still loaded")
        XCTAssertEqual(engine.total(for: project.id, asOf: now), 120, "but it is not part of today")
        XCTAssertEqual(engine.dayTotal(asOf: now), 120)
    }

    func testPureTotalHelperIgnoresOtherProjectsAndEarlierSessions() {
        let wanted = UUID()
        let other = UUID()
        let sessions = [
            Session(projectID: wanted, start: dayStart.addingTimeInterval(-60), end: dayStart),
            Session(projectID: wanted, start: dayStart, end: dayStart.addingTimeInterval(100)),
            Session(projectID: other, start: dayStart, end: dayStart.addingTimeInterval(30)),
            Session(projectID: wanted, start: dayStart.addingTimeInterval(200))
        ]

        let forProject = TimerEngine.total(
            of: sessions,
            projectID: wanted,
            since: dayStart,
            asOf: dayStart.addingTimeInterval(250)
        )
        let forEverything = TimerEngine.total(
            of: sessions,
            projectID: nil,
            since: dayStart,
            asOf: dayStart.addingTimeInterval(250)
        )

        XCTAssertEqual(forProject, 150)
        XCTAssertEqual(forEverything, 180)
    }

    func testStartAfterABackwardClockJumpIsClampedToTheRollover() throws {
        let project = Project(name: "Client Work", sortOrder: 0)
        try ProjectStore(fileURL: projectsURL).save([project])
        try AppStateStore(fileURL: stateURL).save(AppState(lastRollover: dayStart))
        let engine = makeEngine()
        // The clock is corrected to ten minutes before the boundary on record.
        fakeNow.advance(by: -(8 * 3600) - 600)

        engine.start(projectID: project.id)

        XCTAssertEqual(engine.openSession?.start, dayStart, "the session is pinned to today")
        XCTAssertEqual(engine.total(for: project.id, asOf: dayStart.addingTimeInterval(60)), 60)
    }

    func testFirstLaunchRecordsTheTrackingDayItStartedIn() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!

        let engine = makeEngine(calendar: calendar)

        let expected = TrackingDay.start(
            containing: fakeNow.current,
            rollover: .default,
            calendar: calendar
        )
        XCTAssertEqual(engine.lastRollover, expected)
        XCTAssertEqual(AppStateStore(fileURL: stateURL).load().lastRollover, expected, "written down, not recomputed")
    }

    // MARK: - Resume

    func testAFreshEngineResumesAnOpenSession() throws {
        let first = makeEngine()
        let project = try XCTUnwrap(first.addProject(named: "Client Work"))
        first.start(projectID: project.id)
        let startedAt = try XCTUnwrap(first.openSession?.start)
        // The app dies here: no stop, no clean shutdown.
        fakeNow.advance(by: 3600)

        let resumed = makeEngine()

        assertAtMostOneOpenSession(resumed)
        XCTAssertEqual(resumed.openSession?.projectID, project.id)
        XCTAssertEqual(resumed.openSession?.start, startedAt, "the clock keeps counting from the original start")
        XCTAssertEqual(resumed.runningProject?.name, "Client Work")
        XCTAssertEqual(resumed.total(for: project.id, asOf: fakeNow.current), 3600)
    }

    func testAFreshEngineWithNoOpenSessionIsIdle() throws {
        let first = makeEngine()
        let project = try XCTUnwrap(first.addProject(named: "Client Work"))
        first.start(projectID: project.id)
        fakeNow.advance(by: 60)
        first.stop()

        let resumed = makeEngine()

        XCTAssertNil(resumed.openSession)
        XCTAssertNil(resumed.runningProject)
        XCTAssertEqual(resumed.total(for: project.id, asOf: fakeNow.current), 60)
    }

    // MARK: - Projects

    func testAddProjectTrimsAndOrders() throws {
        let engine = makeEngine()

        let first = try XCTUnwrap(engine.addProject(named: "  First  "))
        let second = try XCTUnwrap(engine.addProject(named: "Second"))

        XCTAssertEqual(first.name, "First")
        XCTAssertEqual(engine.projects.map(\.sortOrder), [0, 1])
        XCTAssertEqual(engine.projects.map(\.id), [first.id, second.id])
    }

    func testAddProjectIgnoresBlankNames() {
        let engine = makeEngine()

        XCTAssertNil(engine.addProject(named: "   \n "))
        XCTAssertNil(engine.addProject(named: ""))
        XCTAssertTrue(engine.projects.isEmpty)
        XCTAssertTrue(ProjectStore(fileURL: projectsURL).load().isEmpty)
    }

    func testAddedProjectsSurviveAReload() throws {
        let engine = makeEngine()
        _ = engine.addProject(named: "First")
        _ = engine.addProject(named: "Second")

        XCTAssertEqual(makeEngine().projects.map(\.name), ["First", "Second"])
    }

    func testRenamePersists() throws {
        let engine = makeEngine()
        let project = try XCTUnwrap(engine.addProject(named: "Old"))

        engine.renameProject(project.id, to: "  New  ")

        XCTAssertEqual(engine.projects.first?.name, "New")
        XCTAssertEqual(makeEngine().projects.first?.name, "New")
    }

    func testRenameIgnoresBlankNames() throws {
        let engine = makeEngine()
        let project = try XCTUnwrap(engine.addProject(named: "Old"))

        engine.renameProject(project.id, to: "  ")

        XCTAssertEqual(engine.projects.first?.name, "Old")
    }

    func testSetColorPersists() throws {
        let engine = makeEngine()
        let project = try XCTUnwrap(engine.addProject(named: "Client Work"))

        engine.setColor("#D7262F", for: project.id)
        XCTAssertEqual(makeEngine().projects.first?.colorHex, "#D7262F")

        engine.setColor(nil, for: project.id)
        XCTAssertNil(makeEngine().projects.first?.colorHex)
    }

    func testMoveProjectReordersAndPersists() throws {
        let engine = makeEngine()
        let first = try XCTUnwrap(engine.addProject(named: "First"))
        let second = try XCTUnwrap(engine.addProject(named: "Second"))
        _ = engine.addProject(named: "Third")

        engine.moveProject(second.id, direction: .up)

        XCTAssertEqual(engine.projects.map(\.name), ["Second", "First", "Third"])
        XCTAssertEqual(engine.projects.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(makeEngine().projects.map(\.name), ["Second", "First", "Third"])

        engine.moveProject(first.id, direction: .down)
        XCTAssertEqual(engine.projects.map(\.name), ["Second", "Third", "First"])
    }

    func testMoveAtTheEdgesDoesNothing() throws {
        let engine = makeEngine()
        let first = try XCTUnwrap(engine.addProject(named: "First"))
        let second = try XCTUnwrap(engine.addProject(named: "Second"))

        engine.moveProject(first.id, direction: .up)
        engine.moveProject(second.id, direction: .down)

        XCTAssertEqual(engine.projects.map(\.name), ["First", "Second"])
    }

    func testMoveSkipsArchivedNeighbours() throws {
        let engine = makeEngine()
        let first = try XCTUnwrap(engine.addProject(named: "First"))
        let hidden = try XCTUnwrap(engine.addProject(named: "Hidden"))
        let third = try XCTUnwrap(engine.addProject(named: "Third"))
        engine.archiveProject(hidden.id)

        engine.moveProject(third.id, direction: .up)

        XCTAssertEqual(engine.visibleProjects.map(\.name), ["Third", "First"])
        XCTAssertEqual(engine.projects.map(\.id), [third.id, hidden.id, first.id])
    }

    func testArchiveHidesTheProjectAndPersists() throws {
        let engine = makeEngine()
        let project = try XCTUnwrap(engine.addProject(named: "Client Work"))

        engine.archiveProject(project.id)

        XCTAssertTrue(engine.visibleProjects.isEmpty)
        XCTAssertEqual(engine.projects.count, 1)
        XCTAssertTrue(makeEngine().projects.first?.isArchived == true)
    }

    func testArchivingTheRunningProjectStopsIt() throws {
        let engine = makeEngine()
        let project = try XCTUnwrap(engine.addProject(named: "Client Work"))
        engine.start(projectID: project.id)
        let stoppedAt = fakeNow.advance(by: 45)

        engine.archiveProject(project.id)

        XCTAssertNil(engine.openSession)
        XCTAssertEqual(engine.sessions.first?.end, stoppedAt)
    }

    func testUnarchiveBringsTheProjectBack() throws {
        let engine = makeEngine()
        let project = try XCTUnwrap(engine.addProject(named: "Client Work"))
        engine.archiveProject(project.id)

        engine.unarchiveProject(project.id)

        XCTAssertEqual(engine.visibleProjects.map(\.name), ["Client Work"])
        XCTAssertTrue(makeEngine().visibleProjects.count == 1)
    }

    // MARK: - App state

    func testWindowFrameRoundTripsWithoutTouchingTheRollover() throws {
        let engine = makeEngine()
        let recordedRollover = engine.lastRollover
        let frame = CGRect(x: 40, y: 50, width: 280, height: 420)

        engine.updateWindowFrame(frame)

        let reloaded = makeEngine()
        XCTAssertEqual(reloaded.windowFrame, frame)
        XCTAssertEqual(reloaded.lastRollover, recordedRollover)
        XCTAssertEqual(reloaded.settings, Settings())
    }

    func testSettingsAreLoadedFromState() throws {
        var settings = Settings()
        settings.rollover = RolloverTime(hour: 6, minute: 30)
        settings.showElapsedInMenuBar = false
        try AppStateStore(fileURL: stateURL).save(AppState(settings: settings))

        let engine = makeEngine()

        XCTAssertEqual(engine.settings, settings)
    }

    // MARK: - Helpers

    private var projectsURL: URL { directory.appendingPathComponent("projects.json") }
    private var sessionsURL: URL { directory.appendingPathComponent("sessions.jsonl") }
    private var stateURL: URL { directory.appendingPathComponent("state.json") }

    /// A new engine over the same temp files, which is also how "quit and
    /// relaunch" is simulated.
    /// Pinned so the tracking-day math does not depend on the machine's zone.
    private static let newYorkCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private func makeEngine(calendar: Calendar = TimerEngineTests.newYorkCalendar) -> TimerEngine {
        // The archive stays inside the temp directory: a test that crosses a
        // day boundary must never write into the real Documents folder.
        let archive = directory.appendingPathComponent("Archive", isDirectory: true)
        let fallback = directory.appendingPathComponent("Fallback", isDirectory: true)
        return TimerEngine(
            clock: fakeNow.clock,
            projectStore: ProjectStore(fileURL: projectsURL),
            sessionLog: SessionLog(fileURL: sessionsURL),
            stateStore: AppStateStore(fileURL: stateURL),
            calendar: calendar,
            archiveLocation: ArchiveLocation(folder: { _ in archive }, fallbackFolder: { fallback })
        )
    }

    /// The engine's central invariant (SPEC §6): only one project runs at a time.
    private func assertAtMostOneOpenSession(
        _ engine: TimerEngine,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertLessThanOrEqual(
            engine.sessions.filter(\.isOpen).count,
            1,
            "more than one session is open",
            file: file,
            line: line
        )
    }
}
