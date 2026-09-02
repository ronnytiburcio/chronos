import Foundation

/// Which way ``TimerEngine/moveProject(_:direction:)`` shifts a project in the
/// panel list.
enum MoveDirection: Sendable {
    case up
    case down
}

/// The running state of Chronos: the project list, the session history, and
/// the one session that may be open (SPEC §6).
///
/// **Persistence is write-through.** Every mutation lands on disk before the
/// method returns — the project list through ``ProjectStore``, sessions as
/// append-only records in ``SessionLog``, and the rest of the state through
/// ``AppStateStore``. Nothing is batched or flushed later, so a crash costs at
/// most the current second.
///
/// **Totals come from timestamps, never counters.** `now` is re-read from the
/// clock on every tick rather than accumulated, so sleeping the Mac for three
/// hours mid-session adds exactly three hours and nothing drifts.
///
/// This is also the single owner of ``AppState``: the window frame lives here
/// alongside `lastRollover` and `settings` so there is exactly one writer of
/// `state.json` and a frame save can never clobber the rollover bookkeeping.
@MainActor
@Observable
final class TimerEngine {
    /// Every project, archived ones included, ordered by `sortOrder`.
    private(set) var projects: [Project]
    /// Every session ever recorded, in the order they were opened.
    private(set) var sessions: [Session]
    /// The instant the UI should render times against. Updated once a second
    /// while a session is open, and on every mutation.
    private(set) var now: Date
    /// The persisted state (`state.json`). Observed, so `settings`,
    /// `lastRollover`, and `windowFrame` derived from it update the UI.
    private(set) var state: AppState
    /// The last thing that went wrong and the user might want to know about —
    /// an archive that had to be written somewhere else, a file that could not
    /// be saved. Shown in the menu bar menu until dismissed. `nil` when all is
    /// well, which is the normal case.
    private(set) var lastWarning: String?

    @ObservationIgnored private let clock: Clock
    @ObservationIgnored private let projectStore: ProjectStore
    @ObservationIgnored private let sessionLog: SessionLog
    @ObservationIgnored private let stateStore: AppStateStore
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let archiveLocation: ArchiveLocation
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private let tickTarget = TickTarget()

    /// A ticking UI does not need to be perfectly punctual; the slack lets the
    /// system coalesce the timer and keeps it cheap.
    private static let tickTolerance: TimeInterval = 0.1

    init(
        clock: Clock = .system,
        projectStore: ProjectStore = ProjectStore(),
        sessionLog: SessionLog = SessionLog(),
        stateStore: AppStateStore = AppStateStore(),
        calendar: Calendar = .current,
        archiveLocation: ArchiveLocation = .standard
    ) {
        self.clock = clock
        self.projectStore = projectStore
        self.sessionLog = sessionLog
        self.stateStore = stateStore
        self.calendar = calendar
        self.archiveLocation = archiveLocation

        let loadedState = stateStore.load()
        let loadedSessions: [Session]
        do {
            loadedSessions = try sessionLog.loadSessions()
        } catch {
            NSLog("Chronos: could not read the session log: \(error.localizedDescription)")
            loadedSessions = []
        }
        // A first launch has no rollover on record; the tracking day it lands
        // in becomes the starting point.
        let instant = clock.now()
        let resolvedRollover = loadedState.lastRollover ?? TrackingDay.start(
            containing: instant,
            rollover: loadedState.settings.rollover,
            calendar: calendar
        )

        var resolvedState = loadedState
        resolvedState.lastRollover = resolvedRollover
        state = resolvedState
        now = instant
        projects = Self.sorted(projectStore.load())
        sessions = loadedSessions
        tickTarget.engine = self

        // Write the resolved boundary down, so relaunching later in the day
        // cannot silently move it.
        if loadedState.lastRollover == nil {
            persistState()
        }

        // SPEC §6: a session that was still open across a rollover belongs to
        // a day that has already turned over. Close it at the boundary and file
        // it under the day it started, on its own: the catch-up below only
        // covers days from the boundary onwards, and the rest of that earlier
        // day was archived when its rollover ran.
        if let open = openSession, open.start < resolvedRollover {
            NSLog("Chronos: session \(open.id) started before the last rollover; closing it at \(resolvedRollover)")
            close(open, at: resolvedRollover)
            let staleDayStart = TrackingDay.start(
                containing: open.start,
                rollover: loadedState.settings.rollover,
                calendar: calendar
            )
            let stale = archivedDay(from: staleDayStart, to: resolvedRollover) { $0.id == open.id }
            if !stale.isEmpty {
                writeArchive(stale)
            }
        }

        // Every rollover missed while Chronos was closed (SPEC §7), oldest
        // first, before anything is on screen.
        performRolloversIfNeeded(now: instant)

        // An open session in the log means the app died (or was quit) while a
        // timer ran: resume it, still counting from its original start.
        if openSession != nil {
            startTicking()
        }
    }

    // MARK: - Derived state

    var settings: Settings { state.settings }

    /// The calendar (and therefore the time zone) the engine does its
    /// tracking-day math in. The header formats the date with it so the label
    /// and the totals can never disagree about which day it is.
    var trackingCalendar: Calendar { calendar }

    /// Start of the tracking day on screen. Today's totals are the sessions
    /// that started at or after it. Phase 5 advances it.
    var lastRollover: Date {
        // Always set in init; the fallback only guards against a future
        // code path that clears it.
        state.lastRollover ?? TrackingDay.start(containing: now, rollover: settings.rollover, calendar: calendar)
    }

    /// The one session that may be running. The engine's invariant is that
    /// there is never more than one.
    var openSession: Session? {
        sessions.last { $0.isOpen }
    }

    /// What the panel shows: archived projects keep their history but drop out
    /// of the list.
    var visibleProjects: [Project] {
        projects.filter { !$0.isArchived }
    }

    var runningProject: Project? {
        guard let projectID = openSession?.projectID else { return nil }
        return projects.first { $0.id == projectID }
    }

    /// The window frame from the last run, if one was saved.
    var windowFrame: CGRect? { state.windowFrame }

    // MARK: - Totals

    /// Seconds spent on one project so far today.
    func total(for projectID: UUID, asOf now: Date) -> TimeInterval {
        Self.total(of: sessions, projectID: projectID, since: lastRollover, asOf: now)
    }

    /// Seconds spent across every project so far today.
    func dayTotal(asOf now: Date) -> TimeInterval {
        Self.total(of: sessions, projectID: nil, since: lastRollover, asOf: now)
    }

    /// The totals math, kept pure so it can be tested without an engine, a
    /// clock, or a disk.
    ///
    /// - Parameters:
    ///   - projectID: the project to total, or `nil` for every project.
    ///   - since: sessions that started before this are a previous tracking
    ///     day's business and are excluded.
    ///   - now: the instant an open session is measured to.
    nonisolated static func total(
        of sessions: [Session],
        projectID: UUID?,
        since: Date,
        asOf now: Date
    ) -> TimeInterval {
        sessions.reduce(0) { running, session in
            guard session.start >= since else { return running }
            guard projectID == nil || session.projectID == projectID else { return running }
            return running + session.duration(asOf: now)
        }
    }

    // MARK: - Timing

    /// Starts timing `projectID`, closing whatever was running first.
    /// Starting the project that is already running does nothing.
    func start(projectID: UUID) {
        guard projects.contains(where: { $0.id == projectID }) else {
            NSLog("Chronos: refusing to start unknown project \(projectID)")
            return
        }
        guard openSession?.projectID != projectID else { return }

        // A clock that jumped backwards past the rollover must not start a
        // session that today's totals would then ignore.
        let instant = max(clock.now(), lastRollover)
        if let open = openSession {
            close(open, at: instant)
        }

        guard beginSession(projectID: projectID, at: instant) else { return }
        now = instant
        startTicking()
    }

    /// Opens a session, log first. Returns `false` when the log refused the
    /// record: a session the log never got is a session that would vanish on
    /// relaunch anyway, so it is not put in memory either.
    @discardableResult
    private func beginSession(projectID: UUID, at start: Date) -> Bool {
        let session = Session(projectID: projectID, start: start)
        do {
            try sessionLog.append(.open(id: session.id, projectID: projectID, start: start))
        } catch {
            warn("Could not record the start of a session: \(error.localizedDescription)")
            return false
        }
        sessions.append(session)
        return true
    }

    /// Closes the open session, if there is one.
    func stop() {
        guard let open = openSession else { return }
        let instant = clock.now()
        close(open, at: instant)
        now = instant
        stopTicking()
    }

    /// Panel behaviour (SPEC §5): clicking the running row stops it, clicking
    /// any other row switches to it.
    func toggle(projectID: UUID) {
        if openSession?.projectID == projectID {
            stop()
        } else {
            start(projectID: projectID)
        }
    }

    private func close(_ session: Session, at date: Date) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        // A backwards clock jump must not create a negative session.
        let end = max(date, session.start)
        do {
            try sessionLog.append(.close(id: session.id, end: end))
        } catch {
            warn("Could not record the end of a session: \(error.localizedDescription)")
        }
        sessions[index].end = end
    }

    // MARK: - Rollover

    /// Runs every rollover that is due, oldest first (SPEC §7).
    ///
    /// One call handles all four prompts — launch, the scheduled timer, waking
    /// from sleep, and the system clock changing — because they ask the same
    /// question: has the tracking day on screen ended? A Mac that was asleep
    /// for three days answers it three times, in order, so each day lands in
    /// the archive under its own date. Running this when nothing is due does
    /// nothing at all.
    func performRolloversIfNeeded(now instant: Date) {
        // Each rollover advances `lastRollover` to a strictly later boundary,
        // so the loop always terminates.
        while true {
            let boundary = nextRolloverBoundary
            guard boundary <= instant else { break }
            performRollover(at: boundary)
        }
        if instant > now {
            now = instant
        }
    }

    /// Manual reset (SPEC §5's ⟳): the rollover routine with *now* as the
    /// boundary, so the day is archived under the date it started and the
    /// panel starts counting again from zero.
    func resetDay() {
        // A clock that jumped backwards must not produce a boundary before the
        // day it is ending.
        let instant = max(clock.now(), lastRollover)
        // Any day that already ended is filed first, under its own date; the
        // reset only ever closes out the day that is actually on screen.
        performRolloversIfNeeded(now: instant)
        performRollover(at: instant)
        now = instant
    }

    /// When the tracking day on screen ends. The scheduler arms its timer for
    /// this, and the catch-up loop runs while it is in the past.
    var nextRolloverBoundary: Date {
        TrackingDay.next(after: lastRollover, rollover: settings.rollover, calendar: calendar)
    }

    /// Closes out the tracking day `[lastRollover, boundary)`.
    private func performRollover(at boundary: Date) {
        let dayStart = lastRollover

        // 1. Whatever was running stops at the boundary, not at "now": the
        //    time after it belongs to the next day.
        var interrupted: UUID?
        if let open = openSession {
            close(open, at: boundary)
            interrupted = open.projectID
        }

        let day = archivedDay(from: dayStart, to: boundary)

        // 2. An empty day writes nothing but still turns over.
        if !day.isEmpty {
            writeArchive(day)
        }

        // 3. Rotate the log before anything reopens, so the close record lands
        //    in the year that is ending and the restart in the year beginning.
        rotateSessionLogIfYearChanged(from: dayStart, to: boundary)

        // 4. SPEC §7's optional restart, from the boundary rather than now, so
        //    no time goes missing between the two days.
        if settings.restartRunningProjectAfterRollover, let projectID = interrupted {
            beginSession(projectID: projectID, at: boundary)
        }

        // 5. The new day is what the panel shows: totals are the sessions that
        //    started at or after this.
        state.lastRollover = boundary
        persistState()

        if openSession == nil {
            stopTicking()
        } else {
            startTicking()
        }
    }

    /// Everything the archive needs about the day, resolved while the sessions
    /// are still in hand: totals in the panel's project order, sessions in the
    /// order they were opened.
    ///
    /// Called after the open session has been closed at the boundary, so every
    /// session it sees has an end; measuring to the boundary anyway keeps it
    /// honest if one somehow does not.
    private func archivedDay(
        from dayStart: Date,
        to boundary: Date,
        including isIncluded: (Session) -> Bool = { _ in true }
    ) -> ArchivedDay {
        let daySessions = sessions.filter { $0.start >= dayStart && $0.start < boundary && isIncluded($0) }
        let names = Dictionary(projects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        // Archived projects are included when they have time on them: the
        // archive records what happened, not what the panel shows.
        let totals: [ProjectTotal] = projects.compactMap { project in
            let seconds = daySessions.reduce(0.0) { running, session in
                session.projectID == project.id ? running + session.duration(asOf: boundary) : running
            }
            return seconds > 0 ? ProjectTotal(name: project.name, seconds: seconds) : nil
        }

        let archived: [ArchivedSession] = daySessions.compactMap { session in
            guard let name = names[session.projectID] else {
                NSLog("Chronos: session \(session.id) names a project that no longer exists; leaving it out of the archive")
                return nil
            }
            return ArchivedSession(
                projectName: name,
                start: session.start,
                end: min(session.end ?? boundary, boundary)
            )
        }

        return ArchivedDay(
            dateString: TrackingDay.dateString(
                // A manual reset boundary is not a day start, so the date the
                // rows carry comes from the day the reset ended.
                for: TrackingDay.start(containing: dayStart, rollover: settings.rollover, calendar: calendar),
                calendar: calendar
            ),
            dayStart: dayStart,
            dayEnd: boundary,
            totals: totals,
            sessions: archived
        )
    }

    /// Writes the archive, falling back to Application Support when the chosen
    /// folder refuses (most likely the one-time Documents prompt was declined).
    /// A failure never stops the rollover: the sessions are still in the log,
    /// and a day that cannot be filed is better than a day that never ends.
    private func writeArchive(_ day: ArchivedDay) {
        let folder = archiveLocation.folder(settings)
        do {
            try writer(at: folder).write(day: day)
            return
        } catch {
            NSLog("Chronos: could not write the archive to \(folder.path): \(error.localizedDescription)")
        }

        let fallback = archiveLocation.fallbackFolder()
        do {
            try writer(at: fallback).write(day: day)
            warn("Archive written to \(fallback.path) because \(folder.path) was not writable")
        } catch {
            warn("Could not write the archive for \(day.dateString) to \(folder.path) or \(fallback.path)")
        }
    }

    private func writer(at folder: URL) -> ArchiveWriter {
        ArchiveWriter(
            folder: folder,
            calendar: calendar,
            writesMarkdownNotes: settings.writeMarkdownDailyNotes
        )
    }

    /// Moves `sessions.jsonl` aside as `sessions-YYYY.jsonl` when a rollover
    /// crosses into a new year, and drops the sessions it took with it from
    /// memory. Refusing to overwrite an existing archive is the log's own rule;
    /// here that just means the rotation is skipped and the day still turns.
    private func rotateSessionLogIfYearChanged(from previous: Date, to boundary: Date) {
        let closingYear = calendar.component(.year, from: previous)
        guard calendar.component(.year, from: boundary) != closingYear else { return }

        let archiveURL = AppPaths.sessionsArchiveFile(
            year: closingYear,
            in: sessionLog.fileURL.deletingLastPathComponent()
        )
        do {
            try sessionLog.rotate(to: archiveURL)
            // Every record written before the rotation now lives in the
            // archive, the session just closed *at* the boundary included, so
            // memory is left holding exactly what a relaunch would load.
            sessions.removeAll { session in
                guard let end = session.end else { return false }
                return end <= boundary
            }
        } catch {
            warn("Could not rotate the session log into \(archiveURL.lastPathComponent): \(error.localizedDescription)")
        }
    }

    // MARK: - Warnings

    /// Clears the warning shown in the menu bar menu.
    func clearWarning() {
        lastWarning = nil
    }

    /// Records something the user should know about. It goes to the log as
    /// well, because the menu only ever shows the most recent one.
    private func warn(_ text: String) {
        NSLog("Chronos: \(text)")
        lastWarning = text
    }

    // MARK: - Projects

    /// Appends a project to the end of the list. A blank name is ignored.
    @discardableResult
    func addProject(named name: String) -> Project? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let project = Project(name: trimmed, sortOrder: projects.count)
        projects.append(project)
        renumber()
        persistProjects()
        return project
    }

    /// Renames a project. A blank name is ignored.
    func renameProject(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].name = trimmed
        persistProjects()
    }

    /// Sets a project's `#RRGGBB` color, or clears it back to the palette
    /// default with `nil`.
    func setColor(_ colorHex: String?, for id: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].colorHex = colorHex
        persistProjects()
    }

    /// Swaps a project with its neighbour in the list.
    ///
    /// The neighbour is the next project with the same archived state, so
    /// reordering the visible list is not blocked by an archived project
    /// sitting between two visible ones.
    func moveProject(_ id: UUID, direction: MoveDirection) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        let isArchived = projects[index].isArchived
        let step = direction == .up ? -1 : 1

        var neighbour = index + step
        while projects.indices.contains(neighbour), projects[neighbour].isArchived != isArchived {
            neighbour += step
        }
        guard projects.indices.contains(neighbour) else { return }

        projects.swapAt(index, neighbour)
        renumber()
        persistProjects()
    }

    /// Hides a project from the panel, keeping its history. If it was running,
    /// its session is closed first.
    func archiveProject(_ id: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == id }), !projects[index].isArchived
        else { return }
        if openSession?.projectID == id {
            stop()
        }
        projects[index].isArchived = true
        persistProjects()
    }

    func unarchiveProject(_ id: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == id }), projects[index].isArchived
        else { return }
        projects[index].isArchived = false
        persistProjects()
    }

    // MARK: - Window frame

    /// Records where the user parked the panel. Called by the panel controller
    /// so `state.json` keeps a single writer.
    func updateWindowFrame(_ frame: CGRect) {
        guard state.windowFrame != frame else { return }
        state.windowFrame = frame
        persistState()
    }

    // MARK: - Ticking

    /// Runs a one-second timer, but only while something is being timed: an
    /// idle Chronos wakes the CPU for nothing.
    private func startTicking() {
        guard ticker == nil else { return }
        // Target/selector through a proxy that holds the engine weakly: a
        // block-based timer would capture `self` and keep the engine alive for
        // as long as it ticks. `.common` keeps the clock moving while the user
        // drags the panel or has a menu open.
        let timer = Timer(
            timeInterval: 1,
            target: tickTarget,
            selector: #selector(TickTarget.fire(_:)),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = Self.tickTolerance
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    fileprivate func tick() {
        // Re-read the clock rather than adding a second, so time spent asleep
        // is counted exactly once.
        now = clock.now()
        if openSession == nil {
            stopTicking()
        }
    }

    // MARK: - Persistence

    private func persistProjects() {
        do {
            try projectStore.save(projects)
        } catch {
            warn("Could not save the project list: \(error.localizedDescription)")
        }
    }

    private func persistState() {
        do {
            try stateStore.save(state)
        } catch {
            warn("Could not save app state: \(error.localizedDescription)")
        }
    }

    // MARK: - Ordering

    /// Rewrites `sortOrder` to match the array, keeping it contiguous from 0.
    private func renumber() {
        for index in projects.indices {
            projects[index].sortOrder = index
        }
    }

    /// Ordering as loaded from disk: `sortOrder` first, name as a stable
    /// tie-break so a hand-edited `projects.json` still lists predictably.
    private static func sorted(_ projects: [Project]) -> [Project] {
        projects.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

/// The ticker's timer target. It holds the engine weakly so the timer never
/// keeps an engine alive, and invalidates itself once the engine is gone.
@MainActor
private final class TickTarget: NSObject {
    weak var engine: TimerEngine?

    @objc func fire(_ timer: Timer) {
        guard let engine else {
            timer.invalidate()
            return
        }
        engine.tick()
    }
}
