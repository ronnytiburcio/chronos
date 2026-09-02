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
}
