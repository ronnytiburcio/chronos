import Foundation

/// The wall-clock time of day at which one tracking day becomes the next
/// (SPEC §7). Default 04:00, so late-night work stays attached to the day it
/// belongs to.
struct RolloverTime: Codable, Equatable, Sendable {
    var hour: Int
    var minute: Int

    init(hour: Int = 4, minute: Int = 0) {
        self.hour = hour
        self.minute = minute
    }

    /// 04:00, per SPEC §7.
    static let `default` = RolloverTime()
}

/// Pure tracking-day arithmetic: given an instant and a rollover time, which
/// tracking day is it, when does the next one begin, and what does that day
/// call itself.
///
/// Everything here takes an explicit `Calendar` (which carries the time zone)
/// so the math is deterministic and testable; nothing reads `Calendar.current`
/// on its own.
///
/// Daylight saving is handled by `Calendar.nextDate`'s
/// `.nextTimePreservingSmallerComponents` policy: on a spring-forward day a
/// rollover of 02:30 does not exist and resolves to 03:30, and on a fall-back
/// day a repeated rollover resolves to its first occurrence. Either way each
/// calendar day gets exactly one rollover, and consecutive day starts sit 23,
/// 24, or 25 hours apart.
enum TrackingDay {
    /// The most recent rollover instant at or before `date` — the start of the
    /// tracking day that `date` falls in.
    static func start(containing date: Date, rollover: RolloverTime, calendar: Calendar) -> Date {
        // `nextDate` only ever matches *strictly* before the anchor when
        // searching backwards, so the anchor is nudged a second past `date`:
        // an instant that is itself a rollover is the start of its own day.
        // If that finds a rollover in the sub-second gap *after* `date`, it
        // is the next day's; step back once more.
        let anchor = date.addingTimeInterval(1)
        var match = previousRollover(before: anchor, rollover: rollover, calendar: calendar)
        if let found = match, found > date {
            match = previousRollover(before: found, rollover: rollover, calendar: calendar)
        }
        guard let match else {
            // Unreachable with a Gregorian calendar and a valid rollover time;
            // treating `date` as its own day start keeps callers total.
            NSLog("Chronos: no rollover found at or before \(date); using it as the day start")
            return date
        }
        return match
    }

    /// The next rollover instant strictly after `date`.
    static func next(after date: Date, rollover: RolloverTime, calendar: Calendar) -> Date {
        guard let match = calendar.nextDate(
            after: date,
            matching: components(for: rollover),
            matchingPolicy: .nextTimePreservingSmallerComponents,
            direction: .forward
        ) else {
            NSLog("Chronos: no rollover found after \(date); falling back to +24h")
            return date.addingTimeInterval(24 * 60 * 60)
        }
        return match
    }

    /// `yyyy-MM-dd` of the tracking day that begins at `dayStart`, in the
    /// calendar's time zone. This is the date that goes into archive filenames
    /// and CSV rows, so it is built from calendar components rather than a
    /// `DateFormatter` (no locale, no calendar-of-the-formatter surprises).
    static func dateString(for dayStart: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: dayStart)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func previousRollover(before date: Date, rollover: RolloverTime, calendar: Calendar) -> Date? {
        calendar.nextDate(
            after: date,
            matching: components(for: rollover),
            matchingPolicy: .nextTimePreservingSmallerComponents,
            direction: .backward
        )
    }

    private static func components(for rollover: RolloverTime) -> DateComponents {
        DateComponents(hour: rollover.hour, minute: rollover.minute)
    }
}
