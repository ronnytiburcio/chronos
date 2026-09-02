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
    /// Whether a session is open. Going from `false` to `true` flickers the
    /// bolt (SPEC §9, "the bolt in the header does a quick flicker when a timer
    /// starts").
    let isRunning: Bool

    /// The flicker, as opacities. First and last are opaque, so whichever phase
    /// the animator rests on the bolt ends up solid.
    private static let flickerPhases: [Double] = [1, 0.2, 1, 0.5, 1]
    /// ~350ms all told, across the four transitions above.
    private static let flickerStep: TimeInterval = 0.09

    private static let markSize: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bumped once per start; never bumped under Reduce Motion, which leaves
    /// the animator parked on the first (opaque) phase.
    @State private var flickerCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                bolt

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
        .onChange(of: isRunning) { _, running in
            guard running, !reduceMotion else { return }
            flickerCount += 1
        }
    }

    /// The Chronos mark: ``BoltShape`` filled Scarlet, sized to sit level with
    /// the wordmark. The bolt's unit box carries its own side margins, so a
    /// square frame draws a bolt narrower than it is tall.
    private var bolt: some View {
        BoltShape()
            .fill(Color.chronosScarlet)
            .frame(width: Self.markSize, height: Self.markSize)
            .phaseAnimator(Self.flickerPhases, trigger: flickerCount) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in
                .linear(duration: Self.flickerStep)
            }
            .accessibilityHidden(true)
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
