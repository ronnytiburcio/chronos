import XCTest
@testable import Chronos

/// The pure half of the session editor: resolving a picked time of day into an
/// instant inside the tracking day, and the one copy of the edit rules.
///
/// Everything runs against `Calendar.newYork` from `TestSupport`, so midnight,
/// the 04:00 rollover, and both daylight-saving transitions do not depend on
/// the machine the tests run on.
final class SessionEditingTests: XCTestCase {
    // MARK: - instant

    /// Thursday's tracking day: 2025-09-04 04:00 → 2025-09-05 04:00.
    func testDaytimeTimeStaysOnTheSessionsOwnDay() {
        let resolved = SessionEditing.instant(
            hour: 14,
            minute: 30,
            reference: at(2025, 9, 4, 9),
            dayStart: at(2025, 9, 4, 4),
            dayEnd: at(2025, 9, 5, 4),
            calendar: Calendar.newYork
        )

        XCTAssertEqual(resolved, at(2025, 9, 4, 14, 30))
    }

    /// The case the helper exists for: a session that started at 01:30 sits on
    /// the *next* calendar day, so a picker handed 23:00 would put it 22 hours
    /// in the future. It belongs to the previous evening instead.
    func testLateEveningTimeOnAnAfterMidnightSessionMapsToThePreviousEvening() {
        let resolved = SessionEditing.instant(
            hour: 23,
            minute: 0,
            reference: at(2025, 9, 5, 1, 30),
            dayStart: at(2025, 9, 4, 4),
            dayEnd: at(2025, 9, 5, 4),
            calendar: Calendar.newYork
        )

        XCTAssertEqual(resolved, at(2025, 9, 4, 23))
    }

    /// The mirror image: an early-morning time picked while looking at an
    /// evening session means tomorrow morning, before the rollover.
    func testEarlyMorningTimeOnAnEveningSessionMapsToTheNextCalendarDay() {
        let resolved = SessionEditing.instant(
            hour: 2,
            minute: 15,
            reference: at(2025, 9, 4, 23),
            dayStart: at(2025, 9, 4, 4),
            dayEnd: at(2025, 9, 5, 4),
            calendar: Calendar.newYork
        )

        XCTAssertEqual(resolved, at(2025, 9, 5, 2, 15))
    }

    /// A time that does not occur inside the window at all — here a day the
    /// caller has cut short — resolves to nothing rather than to an instant
    /// outside it, so the row leaves the draft alone.
    func testTimeOutsideTheWindowResolvesToNothing() {
        let resolved = SessionEditing.instant(
            hour: 20,
            minute: 0,
            reference: at(2025, 9, 4, 9),
            dayStart: at(2025, 9, 4, 4),
            dayEnd: at(2025, 9, 4, 12),
            calendar: Calendar.newYork
        )

        XCTAssertNil(resolved)
    }

    /// Fall back, 2026-11-01: the clocks go back at 02:00, so 01:30 happens
    /// twice and the tracking day that began on Oct 31 at 04:00 is 25 hours
    /// long. Both 01:30s are inside it, so nothing is snapped by a day; the
    /// time resolves on the reference's own calendar day, at the first
    /// occurrence — which is what `Calendar` itself picks.
    func testFallBackDayResolvesARepeatedTimeOnTheReferencesDay() {
        let dayStart = at(2026, 10, 31, 4)
        let dayEnd = at(2026, 11, 1, 4)
        // Sanity: the day really is 25 hours long.
        XCTAssertEqual(dayEnd.timeIntervalSince(dayStart), 25 * 3600)

        let firstOccurrence = at(2026, 11, 1, 1, 30)
        let secondOccurrence = firstOccurrence.addingTimeInterval(3600)

        for reference in [firstOccurrence, secondOccurrence] {
            let resolved = SessionEditing.instant(
                hour: 1,
                minute: 30,
                reference: reference,
                dayStart: dayStart,
                dayEnd: dayEnd,
                calendar: Calendar.newYork
            )
            XCTAssertEqual(resolved, firstOccurrence)
        }
    }

    /// Spring forward, 2026-03-08: the clocks jump 02:00 EST → 03:00 EDT, so
    /// 02:30 never happens. The tracking day containing the gap is the one that
    /// began Mar 7 at 04:00 EST and ends Mar 8 at 04:00 EDT — 23 hours long.
    ///
    /// Pinning Foundation's actual behaviour rather than an assumed one:
    /// `Calendar.date(bySettingHour:minute:second:of:)` resolves the missing
    /// 02:30 to **03:00 EDT**, the first instant after the gap — *not* to 03:30
    /// the way `Calendar.date(from:)` does with the same components. That is
    /// inside the window, so nothing is snapped by a day and the draft lands on
    /// a real instant on the short day.
    func testSpringForwardGapTimeResolvesToTheHourAfter() {
        let dayStart = at(2026, 3, 7, 4)
        let dayEnd = at(2026, 3, 8, 4)
        // Sanity: the day really is 23 hours long.
        XCTAssertEqual(dayEnd.timeIntervalSince(dayStart), 23 * 3600)

        let resolved = SessionEditing.instant(
            hour: 2,
            minute: 30,
            reference: at(2026, 3, 8, 1),
            dayStart: dayStart,
            dayEnd: dayEnd,
            calendar: Calendar.newYork
        )

        XCTAssertEqual(resolved, at(2026, 3, 8, 3))
        XCTAssertNotNil(resolved)
        XCTAssertTrue(resolved! >= dayStart && resolved! < dayEnd)
    }

    // MARK: - validationError

    func testAValidDraftHasNoError() {
        XCTAssertNil(SessionEditing.validationError(
            start: at(2025, 9, 4, 9),
            end: at(2025, 9, 4, 10),
            isOpen: false,
            dayStart: at(2025, 9, 4, 4),
            now: at(2025, 9, 4, 12)
        ))
    }

    /// A session that is still running may keep its missing end.
    func testAnOpenDraftOnAnOpenSessionHasNoError() {
        XCTAssertNil(SessionEditing.validationError(
            start: at(2025, 9, 4, 9),
            end: nil,
            isOpen: true,
            dayStart: at(2025, 9, 4, 4),
            now: at(2025, 9, 4, 12)
        ))
    }

    /// Clearing the end of a session that has already finished would reopen it.
    func testClearingTheEndOfAClosedSessionIsRejected() {
        XCTAssertEqual(
            SessionEditing.validationError(
                start: at(2025, 9, 4, 9),
                end: nil,
                isOpen: false,
                dayStart: at(2025, 9, 4, 4),
                now: at(2025, 9, 4, 12)
            ),
            .cannotReopen
        )
    }

    func testAZeroLengthDraftIsAllowed() {
        XCTAssertNil(SessionEditing.validationError(
            start: at(2025, 9, 4, 9),
            end: at(2025, 9, 4, 9),
            isOpen: false,
            dayStart: at(2025, 9, 4, 4),
            now: at(2025, 9, 4, 12)
        ))
    }

    func testAStartBeforeTheDayBeganIsRejected() {
        XCTAssertEqual(
            SessionEditing.validationError(
                start: at(2025, 9, 4, 3),
                end: at(2025, 9, 4, 10),
                isOpen: false,
                dayStart: at(2025, 9, 4, 4),
                now: at(2025, 9, 4, 12)
            ),
            .startBeforeDay
        )
    }

    func testAStartInTheFutureIsRejected() {
        XCTAssertEqual(
            SessionEditing.validationError(
                start: at(2025, 9, 4, 13),
                end: nil,
                isOpen: true,
                dayStart: at(2025, 9, 4, 4),
                now: at(2025, 9, 4, 12)
            ),
            .startInFuture
        )
    }

    func testAnEndBeforeTheStartIsRejected() {
        XCTAssertEqual(
            SessionEditing.validationError(
                start: at(2025, 9, 4, 10),
                end: at(2025, 9, 4, 9),
                isOpen: false,
                dayStart: at(2025, 9, 4, 4),
                now: at(2025, 9, 4, 12)
            ),
            .endBeforeStart
        )
    }

    func testAnEndInTheFutureIsRejected() {
        XCTAssertEqual(
            SessionEditing.validationError(
                start: at(2025, 9, 4, 10),
                end: at(2025, 9, 4, 13),
                isOpen: false,
                dayStart: at(2025, 9, 4, 4),
                now: at(2025, 9, 4, 12)
            ),
            .endInFuture
        )
    }

    /// The start is checked before the end, and this is the only copy of that
    /// order — `TimerEngine.editSession` asks the same function, so the row and
    /// the engine can never name different problems.
    func testTheStartIsReportedBeforeTheEnd() {
        XCTAssertEqual(
            SessionEditing.validationError(
                start: at(2025, 9, 4, 3),
                end: at(2025, 9, 4, 2),
                isOpen: false,
                dayStart: at(2025, 9, 4, 4),
                now: at(2025, 9, 4, 12)
            ),
            .startBeforeDay
        )
    }

    // MARK: - overlaps

    func testNoOverlapReturnsNothing() {
        let other = Session(projectID: UUID(), start: at(2025, 9, 4, 9), end: at(2025, 9, 4, 10))
        let overlapping = SessionEditing.overlaps(
            start: at(2025, 9, 4, 11),
            end: at(2025, 9, 4, 12),
            now: at(2025, 9, 4, 13),
            excluding: UUID(),
            among: [other]
        )
        XCTAssertTrue(overlapping.isEmpty)
    }

    func testAPartialOverlapIsReported() {
        let other = Session(projectID: UUID(), start: at(2025, 9, 4, 9), end: at(2025, 9, 4, 10, 30))
        let overlapping = SessionEditing.overlaps(
            start: at(2025, 9, 4, 10),
            end: at(2025, 9, 4, 11),
            now: at(2025, 9, 4, 12),
            excluding: UUID(),
            among: [other]
        )
        XCTAssertEqual(overlapping, [other])
    }

    func testADraftThatContainsAnotherSessionReportsIt() {
        let other = Session(projectID: UUID(), start: at(2025, 9, 4, 9, 30), end: at(2025, 9, 4, 9, 45))
        let overlapping = SessionEditing.overlaps(
            start: at(2025, 9, 4, 9),
            end: at(2025, 9, 4, 10),
            now: at(2025, 9, 4, 12),
            excluding: UUID(),
            among: [other]
        )
        XCTAssertEqual(overlapping, [other])
    }

    /// One session ending exactly when the draft begins (or vice versa) is
    /// adjacency, not overlap.
    func testTouchingEndpointsAreNotAnOverlap() {
        let before = Session(projectID: UUID(), start: at(2025, 9, 4, 8), end: at(2025, 9, 4, 9))
        let after = Session(projectID: UUID(), start: at(2025, 9, 4, 10), end: at(2025, 9, 4, 11))
        let overlapping = SessionEditing.overlaps(
            start: at(2025, 9, 4, 9),
            end: at(2025, 9, 4, 10),
            now: at(2025, 9, 4, 12),
            excluding: UUID(),
            among: [before, after]
        )
        XCTAssertTrue(overlapping.isEmpty)
    }

    /// The session being edited is never reported against itself.
    func testTheExcludedIDIsIgnored() {
        let id = UUID()
        let session = Session(id: id, projectID: UUID(), start: at(2025, 9, 4, 9), end: at(2025, 9, 4, 10))
        let overlapping = SessionEditing.overlaps(
            start: at(2025, 9, 4, 9),
            end: at(2025, 9, 4, 10),
            now: at(2025, 9, 4, 12),
            excluding: id,
            among: [session]
        )
        XCTAssertTrue(overlapping.isEmpty)
    }

    /// An open draft is measured to `now`, exactly like an open session
    /// everywhere else in Chronos.
    func testAnOpenDraftIsMeasuredToNow() {
        let other = Session(projectID: UUID(), start: at(2025, 9, 4, 11), end: at(2025, 9, 4, 11, 30))
        let overlapping = SessionEditing.overlaps(
            start: at(2025, 9, 4, 9),
            end: nil,
            now: at(2025, 9, 4, 12),
            excluding: UUID(),
            among: [other]
        )
        XCTAssertEqual(overlapping, [other])
    }

    func testOverlapsAreSortedByStart() {
        let later = Session(projectID: UUID(), start: at(2025, 9, 4, 10), end: at(2025, 9, 4, 11))
        let earlier = Session(projectID: UUID(), start: at(2025, 9, 4, 9), end: at(2025, 9, 4, 9, 45))
        let overlapping = SessionEditing.overlaps(
            start: at(2025, 9, 4, 8),
            end: at(2025, 9, 4, 12),
            now: at(2025, 9, 4, 13),
            excluding: UUID(),
            among: [later, earlier]
        )
        XCTAssertEqual(overlapping, [earlier, later])
    }
}
