import Foundation

/// Durations as the panel shows them.
///
/// Deliberately not `DateComponentsFormatter`: these strings tick once a
/// second next to each other, so they must be fixed-shape and locale-stable
/// (`1:02:05`, never "1 hr, 2 min"). Render them in a monospaced-digit font so
/// the columns do not jitter.
enum TimeFormatting {
    /// `H:MM:SS`, counting hours past 24 rather than wrapping (SPEC §5).
    /// Seconds are truncated, so a timer reads `0:00:00` for its first second.
    static func hms(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00:00" }
        let total = Int(max(0, seconds))
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// `Xh Ym` — the day total in the panel header (SPEC §5). Seconds are
    /// dropped, not rounded, so the header never reads a minute ahead of the
    /// row times below it.
    static func hoursMinutes(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0h 0m" }
        let total = Int(max(0, seconds))
        return "\(total / 3600)h \((total % 3600) / 60)m"
    }

    /// `H:MM` — the elapsed time beside the menu bar bolt (SPEC §10).
    static func hoursMinutesCompact(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(max(0, seconds))
        return String(format: "%d:%02d", total / 3600, (total % 3600) / 60)
    }

    /// Decimal hours to two places — the `hours` column of both CSVs (SPEC
    /// §8), for the spreadsheet that does not want to divide by 3600 itself.
    ///
    /// Shared by ``ArchiveWriter`` and ``Exporter`` so a rollover row and an
    /// exported row for the same day can never round differently.
    static func decimalHours(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0.00" }
        return String(format: "%.2f", max(0, seconds) / 3600)
    }
}
