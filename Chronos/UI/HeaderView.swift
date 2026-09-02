import SwiftUI

/// The panel header (SPEC §5): bolt mark, wordmark, the tracking day's date,
/// and the live day total. The whole block is the window's drag handle.
struct HeaderView: View {
    /// Start of the tracking day on screen — what the date label names.
    let trackingDay: Date
    /// The calendar (and time zone) the engine does its day math in, so the
    /// label and the totals can never disagree about which day it is.
    let calendar: Calendar
    /// Seconds tracked across every project so far today.
    let dayTotal: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                // Phase 7 swaps this SF Symbol for the custom BoltShape and
                // gives it the start-of-timer flicker.
                Image(systemName: "bolt.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.chronosScarlet)

                Text("CHRONOS")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Color.chronosPaper)

                Spacer(minLength: 8)

                Text(TrackingDateLabel.string(for: trackingDay, calendar: calendar))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.chronosMuted)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Today")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.chronosMuted)

                Text(TimeFormatting.hoursMinutes(dayTotal))
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color.chronosGold)

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, PanelLayout.horizontalPadding)
        .frame(height: PanelLayout.headerHeight, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // Only the header moves the panel (SPEC §4).
        .overlay(DragHandleView())
    }
}

/// `Tue Sep 2` for the header.
///
/// The formatter is cached because the header re-renders every second while a
/// timer runs, and `DateFormatter` is expensive to build. It lives on the main
/// actor rather than being `nonisolated`, since `DateFormatter` is not
/// `Sendable` and every caller is a SwiftUI view body.
@MainActor
enum TrackingDateLabel {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d"
        return formatter
    }()

    static func string(for date: Date, calendar: Calendar) -> String {
        if formatter.timeZone != calendar.timeZone { formatter.timeZone = calendar.timeZone }
        let locale = calendar.locale ?? .current
        if formatter.locale != locale { formatter.locale = locale }
        return formatter.string(from: date)
    }
}
