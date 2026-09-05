import Foundation

/// The pure arithmetic behind the session editor: turning a time-of-day the
/// user picked into an instant inside the tracking day, and saying why an edit
/// is not valid yet.
///
/// Like ``TrackingDay`` this takes an explicit `Calendar` (which carries the
/// time zone) and reads no clock and no disk, so every rule here is testable
/// without an engine.
enum SessionEditing {
    /// The instant inside `[dayStart, dayEnd)` that the user means by picking
    /// `hour:minute` while looking at `reference`.
    ///
    /// A `.hourAndMinute` `DatePicker` keeps the calendar day of whatever
    /// `Date` it was handed and only swaps the time, which is wrong on a
    /// tracking day that straddles midnight: for a 01:30 session on an
    /// 04:00-rollover day, "23:00" means *last* evening, not tonight. So the
    /// candidate is built on `reference`'s calendar day and then snapped by a
    /// day in whichever direction lands it inside the tracking day. If neither
    /// does — the time simply does not occur in this tracking day — the result
    /// is `nil` and the caller leaves the draft alone.
    ///
    /// On a fall-back day a time that occurs twice resolves the way
    /// `Calendar.date(bySettingHour:...)` resolves it, which is the first
    /// occurrence on `reference`'s day.
    static func instant(
        hour: Int,
        minute: Int,
        reference: Date,
        dayStart: Date,
        dayEnd: Date,
        calendar: Calendar
    ) -> Date? {
        guard var candidate = calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: reference
        ) else { return nil }

        if candidate < dayStart {
            guard let shifted = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
            candidate = shifted
        } else if candidate >= dayEnd {
            guard let shifted = calendar.date(byAdding: .day, value: -1, to: candidate) else { return nil }
            candidate = shifted
        }

        guard candidate >= dayStart, candidate < dayEnd else { return nil }
        return candidate
    }

    /// Why this draft cannot be saved yet, or `nil` when it can.
    ///
    /// This is the *only* copy of the rule set: ``TimerEngine/editSession(_:projectID:start:end:)``
    /// calls it too, after its own `unknownSession`/`notToday`/`unknownProject`
    /// checks, so the row can grey out Save before the engine ever refuses it
    /// and the two cannot drift apart. The order is fixed — `startBeforeDay`,
    /// `startInFuture`, `cannotReopen`, `endBeforeStart`, `endInFuture` — and
    /// a zero-length session is allowed.
    ///
    /// `isOpen` is the *stored* session's state, not the draft's: clearing an
    /// end is only legal on a session that is still running.
    static func validationError(
        start: Date,
        end: Date?,
        isOpen: Bool,
        dayStart: Date,
        now: Date
    ) -> SessionEditError? {
        guard start >= dayStart else { return .startBeforeDay }
        guard start <= now else { return .startInFuture }
        guard let end else {
            return isOpen ? nil : .cannotReopen
        }
        guard end >= start else { return .endBeforeStart }
        guard end <= now else { return .endInFuture }
        return nil
    }

    /// The other sessions whose span overlaps the draft's, sorted by start.
    ///
    /// Chronos does not forbid overlap (SPEC's 2026-09-05 decision: a session
    /// moved to the wrong project, then corrected, can legitimately sit on top
    /// of another one, and the day total is allowed to count that time twice)
    /// — this only powers the row's informational caption. An open end (the
    /// draft's or another session's) is measured to `now`, matching how a
    /// running session is measured everywhere else. Touching endpoints — one
    /// session ending exactly when another starts — are not an overlap, so the
    /// comparison is strict on both sides and a zero-length draft can never
    /// "overlap" its own neighbours.
    static func overlaps(
        start: Date,
        end: Date?,
        now: Date,
        excluding id: UUID,
        among sessions: [Session]
    ) -> [Session] {
        let draftEnd = end ?? now
        return sessions
            .filter { $0.id != id }
            .filter { other in
                let otherEnd = other.end ?? now
                return other.start < draftEnd && start < otherEnd
            }
            .sorted { $0.start < $1.start }
    }
}
