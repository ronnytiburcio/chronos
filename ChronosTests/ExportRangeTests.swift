import XCTest
@testable import Chronos

/// SPEC §8's "week / month / custom" ranges, resolved to inclusive
/// `yyyy-MM-dd` tracking days.
final class ExportRangeTests: XCTestCase {
    // MARK: - This week

    func testThisWeekIsTheSundayToSaturdayAroundToday() {
        // Tuesday 2025-09-02, 09:00.
        let bounds = ExportRange.thisWeek.bounds(
            asOf: at(2025, 9, 2, 9),
            rollover: .default,
            calendar: sundayFirst
        )

        XCTAssertEqual(bounds.from, "2025-08-31")
        XCTAssertEqual(bounds.to, "2025-09-06")
    }

    func testThisWeekFollowsTheCalendarsFirstWeekday() {
        let bounds = ExportRange.thisWeek.bounds(
            asOf: at(2025, 9, 2, 9),
            rollover: .default,
            calendar: mondayFirst
        )

        XCTAssertEqual(bounds.from, "2025-09-01")
        XCTAssertEqual(bounds.to, "2025-09-07")
    }

    /// Before the rollover the tracking day is still yesterday's, so an export
    /// run at 02:00 on Sunday covers the week that is ending, not the one that
    /// has just begun on the wall calendar.
    func testBeforeTheRolloverTheWeekIsStillTheOneThatIsEnding() {
        let bounds = ExportRange.thisWeek.bounds(
            asOf: at(2025, 9, 7, 2), // Sunday 02:00
            rollover: .default,      // 04:00
            calendar: sundayFirst
        )

        XCTAssertEqual(bounds.from, "2025-08-31")
        XCTAssertEqual(bounds.to, "2025-09-06")

        // Past the rollover the same Sunday starts the next week.
        let after = ExportRange.thisWeek.bounds(
            asOf: at(2025, 9, 7, 9),
            rollover: .default,
            calendar: sundayFirst
        )
        XCTAssertEqual(after.from, "2025-09-07")
        XCTAssertEqual(after.to, "2025-09-13")
    }

    // MARK: - This month

    func testThisMonthIsTheFirstToTheLastDay() {
        let bounds = ExportRange.thisMonth.bounds(
            asOf: at(2025, 9, 17, 14),
            rollover: .default,
            calendar: sundayFirst
        )

        XCTAssertEqual(bounds.from, "2025-09-01")
        XCTAssertEqual(bounds.to, "2025-09-30")
    }

    func testThisMonthKnowsHowLongFebruaryIs() {
        let leap = ExportRange.thisMonth.bounds(
            asOf: at(2024, 2, 10, 9),
            rollover: .default,
            calendar: sundayFirst
        )
        XCTAssertEqual(leap.from, "2024-02-01")
        XCTAssertEqual(leap.to, "2024-02-29")

        let common = ExportRange.thisMonth.bounds(
            asOf: at(2025, 2, 10, 9),
            rollover: .default,
            calendar: sundayFirst
        )
        XCTAssertEqual(common.to, "2025-02-28")
    }

    /// 01:00 on the first of the month still belongs to the month that is
    /// ending.
    func testBeforeTheRolloverTheMonthIsStillTheOneThatIsEnding() {
        let bounds = ExportRange.thisMonth.bounds(
            asOf: at(2025, 10, 1, 1),
            rollover: .default,
            calendar: sundayFirst
        )

        XCTAssertEqual(bounds.from, "2025-09-01")
        XCTAssertEqual(bounds.to, "2025-09-30")
    }

    // MARK: - Custom

    /// A date picker hands back midnight, which is *before* the 04:00 rollover.
    /// A custom range means the days the user pointed at, so it uses the
    /// calendar day rather than the tracking day that instant falls in.
    func testCustomUsesTheCalendarDayOfEachPickedDate() {
        let bounds = ExportRange.custom(
            from: at(2025, 9, 2, 0),
            to: at(2025, 9, 5, 0)
        ).bounds(asOf: at(2025, 9, 6, 9), rollover: .default, calendar: sundayFirst)

        XCTAssertEqual(bounds.from, "2025-09-02")
        XCTAssertEqual(bounds.to, "2025-09-05")
    }

    func testCustomPutsAReversedPairInOrder() {
        let bounds = ExportRange.custom(
            from: at(2025, 9, 5, 0),
            to: at(2025, 9, 2, 0)
        ).bounds(asOf: at(2025, 9, 6, 9), rollover: .default, calendar: sundayFirst)

        XCTAssertEqual(bounds.from, "2025-09-02")
        XCTAssertEqual(bounds.to, "2025-09-05")
    }

    func testASingleDayIsAValidRange() {
        let bounds = ExportRange.custom(
            from: at(2025, 9, 2, 9),
            to: at(2025, 9, 2, 22)
        ).bounds(asOf: at(2025, 9, 6, 9), rollover: .default, calendar: sundayFirst)

        XCTAssertEqual(bounds.from, "2025-09-02")
        XCTAssertEqual(bounds.to, "2025-09-02")
    }

    // MARK: - Fixtures

    private var sundayFirst: Calendar { calendar(firstWeekday: 1) }
    private var mondayFirst: Calendar { calendar(firstWeekday: 2) }

    private func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        sundayFirst.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
