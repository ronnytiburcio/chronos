import XCTest
@testable import Chronos

final class TimeFormattingTests: XCTestCase {
    func testFormatsHoursMinutesAndSeconds() {
        XCTAssertEqual(TimeFormatting.hms(0), "0:00:00")
        XCTAssertEqual(TimeFormatting.hms(5), "0:00:05")
        XCTAssertEqual(TimeFormatting.hms(65), "0:01:05")
        XCTAssertEqual(TimeFormatting.hms(3725), "1:02:05")
    }

    func testTruncatesRatherThanRounds() {
        XCTAssertEqual(TimeFormatting.hms(0.99), "0:00:00")
        XCTAssertEqual(TimeFormatting.hms(59.9), "0:00:59")
    }

    func testHoursDoNotWrapAtADay() {
        XCTAssertEqual(TimeFormatting.hms(25 * 3600 + 61), "25:01:01")
    }

    func testNonsenseInputsReadAsZero() {
        XCTAssertEqual(TimeFormatting.hms(-10), "0:00:00")
        XCTAssertEqual(TimeFormatting.hms(.nan), "0:00:00")
        XCTAssertEqual(TimeFormatting.hms(.infinity), "0:00:00")
    }

    // MARK: - Day total

    func testFormatsTheDayTotalAsHoursAndMinutes() {
        XCTAssertEqual(TimeFormatting.hoursMinutes(3 * 3600 + 42 * 60), "3h 42m")
        XCTAssertEqual(TimeFormatting.hoursMinutes(0), "0h 0m")
        XCTAssertEqual(TimeFormatting.hoursMinutes(60), "0h 1m")
        XCTAssertEqual(TimeFormatting.hoursMinutes(3600), "1h 0m")
    }

    func testDayTotalDropsSecondsRatherThanRounding() {
        XCTAssertEqual(TimeFormatting.hoursMinutes(119), "0h 1m")
        XCTAssertEqual(TimeFormatting.hoursMinutes(3599), "0h 59m")
    }

    func testDayTotalHoursDoNotWrap() {
        XCTAssertEqual(TimeFormatting.hoursMinutes(30 * 3600 + 60), "30h 1m")
    }

    func testDayTotalNonsenseInputsReadAsZero() {
        XCTAssertEqual(TimeFormatting.hoursMinutes(-10), "0h 0m")
        XCTAssertEqual(TimeFormatting.hoursMinutes(.nan), "0h 0m")
        XCTAssertEqual(TimeFormatting.hoursMinutes(.infinity), "0h 0m")
    }

    // MARK: - Menu bar

    func testFormatsTheMenuBarElapsedTime() {
        XCTAssertEqual(TimeFormatting.hoursMinutesCompact(3600 + 52 * 60), "1:52")
        XCTAssertEqual(TimeFormatting.hoursMinutesCompact(7 * 60), "0:07")
        XCTAssertEqual(TimeFormatting.hoursMinutesCompact(12 * 3600 + 5 * 60), "12:05")
        XCTAssertEqual(TimeFormatting.hoursMinutesCompact(0), "0:00")
    }

    func testMenuBarElapsedTimeDropsSeconds() {
        XCTAssertEqual(TimeFormatting.hoursMinutesCompact(59), "0:00")
        XCTAssertEqual(TimeFormatting.hoursMinutesCompact(3600 + 52 * 60 + 59), "1:52")
    }

    func testMenuBarNonsenseInputsReadAsZero() {
        XCTAssertEqual(TimeFormatting.hoursMinutesCompact(-10), "0:00")
        XCTAssertEqual(TimeFormatting.hoursMinutesCompact(.nan), "0:00")
        XCTAssertEqual(TimeFormatting.hoursMinutesCompact(.infinity), "0:00")
    }
}
