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

    @ObservationIgnored private let clock: Clock
    @ObservationIgnored private let projectStore: ProjectStore
    @ObservationIgnored private let sessionLog: SessionLog
    @ObservationIgnored private let stateStore: AppStateStore
    @ObservationIgnored private let calendar: Calendar
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
        calendar: Calendar = .current
    ) {
        self.clock = clock
        self.projectStore = projectStore
        self.sessionLog = sessionLog
        self.stateStore = stateStore
        self.calendar = calendar

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

        // An open session in the log means the app died (or was quit) while a
        // timer ran: resume it, still counting from its original start.
        if openSession != nil {
            startTicking()
        }
    }

    // MARK: - Derived state

    var settings: Settings { state.settings }

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

        let instant = clock.now()
        if let open = openSession {
            close(open, at: instant)
        }

        let session = Session(projectID: projectID, start: instant)
        do {
            // On disk before it is in memory: a session the log never got is a
            // session that would vanish on relaunch anyway.
            try sessionLog.append(.open(id: session.id, projectID: projectID, start: instant))
        } catch {
            NSLog("Chronos: could not record the start of a session: \(error.localizedDescription)")
            return
        }
        sessions.append(session)
        now = instant
        startTicking()
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
            NSLog("Chronos: could not record the end of a session: \(error.localizedDescription)")
        }
        sessions[index].end = end
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
            NSLog("Chronos: could not save the project list: \(error.localizedDescription)")
        }
    }

    private func persistState() {
        do {
            try stateStore.save(state)
        } catch {
            NSLog("Chronos: could not save app state: \(error.localizedDescription)")
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
