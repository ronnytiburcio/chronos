import Foundation
import XCTest

extension Calendar {
    /// The calendar the date-sensitive tests are pinned to.
    ///
    /// Tracking days, rollovers, and both daylight-saving transitions have to
    /// behave the same wherever the suite runs, so nothing here may reach for
    /// `Calendar.current`: America/New_York and `en_US_POSIX`, always.
    static let newYork: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()
}

/// New York wall-clock time as a `Date`, which is what every DST case in this
/// suite is really about.
///
/// A free function, deliberately not an `XCTestCase` extension: a few test
/// classes still declare their own `at` against a different calendar, and a
/// member on the shared superclass would make those read as (illegal)
/// overrides rather than as plain shadowing.
func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    Calendar.newYork.date(
        from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    )!
}
