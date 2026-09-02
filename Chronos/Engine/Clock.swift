import Foundation

/// The current time, as a value that can be swapped out.
///
/// Every part of Chronos that needs "now" takes one of these instead of
/// calling `Date()`, so tests can advance time by hand and a whole day of
/// tracking can be exercised in a millisecond.
struct Clock: Sendable {
    var now: @Sendable () -> Date

    static let system = Clock(now: { Date() })
}
