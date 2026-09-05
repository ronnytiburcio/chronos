import Foundation

/// One stretch of time spent on a project (SPEC §6). A session with no `end`
/// is *open*: it is still running, and its duration is computed live against
/// the current time rather than stored.
///
/// Sessions are the only source of truth for totals. Nothing in Chronos keeps
/// a running counter, so sleep, wake, and clock changes cannot drift.
struct Session: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var projectID: UUID
    var start: Date
    var end: Date?

    init(id: UUID = UUID(), projectID: UUID, start: Date, end: Date? = nil) {
        self.id = id
        self.projectID = projectID
        self.start = start
        self.end = end
    }

    var isOpen: Bool { end == nil }

    /// Seconds elapsed, measured to `end` when the session is closed and to
    /// `now` while it is still running.
    ///
    /// Never negative: a backwards clock jump (or a stray record whose `end`
    /// precedes its `start`) reads as zero rather than subtracting time from
    /// the day's total.
    func duration(asOf now: Date) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }
}
