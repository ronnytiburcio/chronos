import Foundation

/// One project's share of an archived tracking day.
struct ProjectTotal: Equatable, Sendable {
    /// The project's display name at the moment the day was archived; the
    /// archive is a historical record, so a later rename does not rewrite it.
    let name: String
    let seconds: TimeInterval
}

/// One finished session, as it goes into `sessions.csv`.
struct ArchivedSession: Equatable, Sendable {
    let projectName: String
    let start: Date
    let end: Date
}

/// A finished tracking day, ready for ``ArchiveWriter`` (SPEC §8).
///
/// This is a snapshot, not a view onto the engine: names, totals, and session
/// times are all resolved before it is built, so writing it cannot depend on
/// anything that has moved on since the rollover ran.
struct ArchivedDay: Equatable, Sendable {
    /// `yyyy-MM-dd` of the tracking day, in the tracking calendar's time zone.
    /// This is the `date` column in both CSVs and the markdown file's name.
    let dateString: String
    /// The window the rows cover: `[dayStart, dayEnd)`. `dayEnd` is the
    /// rollover boundary — the manual-reset time when the user reset early.
    let dayStart: Date
    let dayEnd: Date
    /// Projects with time on them, in the panel's project order.
    let totals: [ProjectTotal]
    /// Every session of the day, in the order they were opened.
    let sessions: [ArchivedSession]

    var totalSeconds: TimeInterval { totals.reduce(0) { $0 + $1.seconds } }

    /// A day with no time on it writes nothing at all (the rollover still
    /// advances, so an idle day leaves no empty rows behind).
    var isEmpty: Bool { totalSeconds <= 0 }
}
