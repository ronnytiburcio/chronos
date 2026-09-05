import XCTest
@testable import Chronos

/// Tracking-day arithmetic, pinned to America/New_York so the daylight-saving
/// cases are real rather than theoretical.
final class TrackingDayTests: XCTestCase {
    private var calendar: Calendar!
    private let rollover = RolloverTime.default // 04:00

    override func setUp() {
        super.setUp()
        calendar = Calendar.newYork
    }

    override func tearDown() {
        calendar = nil
        super.tearDown()
    }

    // MARK: - The 04:00 boundary

    func testDefaultRolloverIsFourAM() {
        XCTAssertEqual(RolloverTime.default, RolloverTime(hour: 4, minute: 0))
    }

    func testJustBeforeRolloverBelongsToThePreviousDay() {
        let start = TrackingDay.start(
            containing: date("2026-09-02 03:59:00"),
            rollover: rollover,
            calendar: calendar
        )

        XCTAssertEqual(start, date("2026-09-01 04:00:00"))
        XCTAssertEqual(TrackingDay.dateString(for: start, calendar: calendar), "2026-09-01")
    }

    func testHalfASecondBeforeRolloverBelongsToThePreviousDay() {
        // The lookup nudges its anchor one second past the instant; a rollover
        // inside that sub-second gap is the *next* day's, not this one's.
        let start = TrackingDay.start(
            containing: date("2026-09-02 04:00:00").addingTimeInterval(-0.5),
            rollover: rollover,
            calendar: calendar
        )

        XCTAssertEqual(start, date("2026-09-01 04:00:00"))
    }

    func testRolloverInstantStartsTheNewDay() {
        let start = TrackingDay.start(
            containing: date("2026-09-02 04:00:00"),
            rollover: rollover,
            calendar: calendar
        )

        XCTAssertEqual(start, date("2026-09-02 04:00:00"))
        XCTAssertEqual(TrackingDay.dateString(for: start, calendar: calendar), "2026-09-02")
    }

    func testMiddayBelongsToItsOwnDay() {
        let start = TrackingDay.start(
            containing: date("2026-09-02 12:00:00"),
            rollover: rollover,
            calendar: calendar
        )

        XCTAssertEqual(start, date("2026-09-02 04:00:00"))
    }

    func testStartIsIdempotentAcrossEveryHourOfADay() {
        for hour in 0..<24 {
            let instant = date(String(format: "2026-09-02 %02d:15:00", hour))
            let start = TrackingDay.start(containing: instant, rollover: rollover, calendar: calendar)

            XCTAssertLessThanOrEqual(start, instant, "day start must not be in the future at \(instant)")
            XCTAssertEqual(
                TrackingDay.start(containing: start, rollover: rollover, calendar: calendar),
                start,
                "a day start is its own day start at \(instant)"
            )
        }
    }

    // MARK: - next(after:)

    func testNextIsStrictlyAfterTheGivenInstant() {
        let boundary = date("2026-09-02 04:00:00")

        let next = TrackingDay.next(after: boundary, rollover: rollover, calendar: calendar)

        XCTAssertGreaterThan(next, boundary)
        XCTAssertEqual(next, date("2026-09-03 04:00:00"))
    }

    func testNextFromMiddayIsTomorrowsRollover() {
        let next = TrackingDay.next(
            after: date("2026-09-02 12:00:00"),
            rollover: rollover,
            calendar: calendar
        )

        XCTAssertEqual(next, date("2026-09-03 04:00:00"))
    }

    // MARK: - Daylight saving

    /// 2026-03-08: clocks jump 02:00 EST -> 03:00 EDT, so the tracking day
    /// that starts on the 7th is 23 hours long.
    func testSpringForwardYieldsOneRolloverPerDay() {
        let starts = dayStarts(from: "2026-03-06 12:00:00", count: 5, rollover: rollover)

        assertOneRolloverPerCalendarDay(starts)
        XCTAssertEqual(starts[1], date("2026-03-07 04:00:00"))
        XCTAssertEqual(starts[2], date("2026-03-08 04:00:00"))
        XCTAssertEqual(starts[2].timeIntervalSince(starts[1]), 23 * 3600, "the short day is 23h")
    }

    /// 2026-11-01: clocks fall back 02:00 EDT -> 01:00 EST, so the tracking
    /// day that starts on 10-31 is 25 hours long.
    func testFallBackYieldsOneRolloverPerDay() {
        let starts = dayStarts(from: "2026-10-30 12:00:00", count: 5, rollover: rollover)

        assertOneRolloverPerCalendarDay(starts)
        XCTAssertEqual(starts[1], date("2026-10-31 04:00:00"))
        XCTAssertEqual(starts[2], date("2026-11-01 04:00:00"))
        XCTAssertEqual(starts[2].timeIntervalSince(starts[1]), 25 * 3600, "the long day is 25h")
    }

    /// 02:30 does not exist on the spring-forward day. It must still produce
    /// exactly one rollover, resolved forward to 03:30.
    func testRolloverTimeThatDoesNotExistOnASpringForwardDay() {
        let missing = RolloverTime(hour: 2, minute: 30)

        let start = TrackingDay.start(
            containing: date("2026-03-08 12:00:00"),
            rollover: missing,
            calendar: calendar
        )

        XCTAssertEqual(start, date("2026-03-08 03:30:00"))
        assertOneRolloverPerCalendarDay(dayStarts(from: "2026-03-06 12:00:00", count: 5, rollover: missing))
    }

    /// 01:30 happens twice on the fall-back day; the first occurrence wins, so
    /// the day that *starts* on 11-01 is the 25-hour one.
    func testRolloverTimeThatRepeatsOnAFallBackDay() {
        let repeated = RolloverTime(hour: 1, minute: 30)

        let starts = dayStarts(from: "2026-10-30 12:00:00", count: 5, rollover: repeated)

        assertOneRolloverPerCalendarDay(starts)
        XCTAssertEqual(TrackingDay.dateString(for: starts[2], calendar: calendar), "2026-11-01")
        XCTAssertEqual(starts[3].timeIntervalSince(starts[2]), 25 * 3600)
    }

    // MARK: - dateString

    func testDateStringUsesTheTrackingDayNotTheCalendarDay() {
        // 01:00 on the 3rd is still the 2nd's tracking day.
        let start = TrackingDay.start(
            containing: date("2026-09-03 01:00:00"),
            rollover: rollover,
            calendar: calendar
        )

        XCTAssertEqual(TrackingDay.dateString(for: start, calendar: calendar), "2026-09-02")
    }

    func testDateStringPadsSingleDigitMonthsAndDays() {
        let start = TrackingDay.start(
            containing: date("2026-01-05 09:00:00"),
            rollover: rollover,
            calendar: calendar
        )

        XCTAssertEqual(TrackingDay.dateString(for: start, calendar: calendar), "2026-01-05")
    }

    func testDateStringAcrossTheMidnightToRolloverWindow() {
        let dayStart = date("2026-09-02 04:00:00")
        // Every instant from the rollover to just before the next one is the
        // same tracking day, midnight included.
        for offset in stride(from: 0.0, to: 24 * 3600, by: 3600) {
            let instant = dayStart.addingTimeInterval(offset)
            let start = TrackingDay.start(containing: instant, rollover: rollover, calendar: calendar)

            XCTAssertEqual(
                TrackingDay.dateString(for: start, calendar: calendar),
                "2026-09-02",
                "wrong tracking day for \(instant)"
            )
        }
    }

    // MARK: - Helpers

    /// Walks `count` consecutive tracking-day starts, beginning with the one
    /// containing `from`.
    private func dayStarts(from: String, count: Int, rollover: RolloverTime) -> [Date] {
        var starts = [TrackingDay.start(containing: date(from), rollover: rollover, calendar: calendar)]
        while starts.count < count {
            starts.append(TrackingDay.next(after: starts[starts.count - 1], rollover: rollover, calendar: calendar))
        }
        return starts
    }

    private func assertOneRolloverPerCalendarDay(
        _ starts: [Date],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let days = starts.map { TrackingDay.dateString(for: $0, calendar: calendar) }
        XCTAssertEqual(Set(days).count, starts.count, "expected one rollover per day, got \(days)", file: file, line: line)

        for (earlier, later) in zip(starts, starts.dropFirst()) {
            let gap = later.timeIntervalSince(earlier)
            XCTAssertGreaterThan(gap, 0, "rollovers must advance", file: file, line: line)
            XCTAssertGreaterThanOrEqual(gap, 23 * 3600, "gap \(gap / 3600)h is under 23h", file: file, line: line)
            XCTAssertLessThanOrEqual(gap, 25 * 3600, "gap \(gap / 3600)h is over 25h", file: file, line: line)
        }
    }

    private func date(_ string: String) -> Date {
        guard let date = Self.parser.date(from: string) else {
            XCTFail("unparseable test date: \(string)")
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }

    /// Parses wall-clock New York time, which is what the DST cases are about.
    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.newYork
        formatter.timeZone = Calendar.newYork.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
