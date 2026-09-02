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
}
