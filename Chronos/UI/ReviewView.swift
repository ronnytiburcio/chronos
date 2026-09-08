import Charts
import SwiftUI

/// The review window's content (Phase 9): three headline totals, the selected
/// period split by project, the same projects as average tracked days, a daily
/// bar chart under its own average, and a few insight lines.
///
/// Unlike the settings window this one wears the panel's clothes — Ink behind
/// Paper and Muted text, Gold for the numbers that matter, Scarlet for today —
/// because it is a glance-at-it dashboard rather than a form.
///
/// It draws a ``ReviewSnapshot`` and nothing else: no engine, no clock, no
/// disk. Its owner refreshes the snapshot on open, on a session change, and
/// once a minute, so the view never re-renders per second.
struct ReviewView: View {
    let snapshot: ReviewSnapshot
    @Binding var period: ReviewPeriod

    /// The window's content size; ``ReviewWindowController`` uses the same
    /// numbers, and the body scrolls inside it.
    static let contentSize = CGSize(width: 560, height: 720)

    private static let gutter: CGFloat = 20
    /// The fixed column the project bars are drawn in. Fixed rather than
    /// measured so no `GeometryReader` has to sit in the middle of the layout.
    private static let barWidth: CGFloat = 150
    private static let barHeight: CGFloat = 8
    private static let timeColumnWidth: CGFloat = 70
    /// One scope's column in the averages table. Wide enough for the heading
    /// "THIS MONTH" on one line, which at 72pt it was not. Three of them plus
    /// the colour dot and the four 10pt gaps leave 209pt for a project name in
    /// the window's 520pt of content — tighter than the 263pt the bars row
    /// above leaves, and still around thirty characters before it truncates.
    private static let averageColumnWidth: CGFloat = 88
    private static let chartHeight: CGFloat = 140

    var body: some View {
        ZStack {
            Color.chronosInk.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // The title stays put in both states, so an empty window is
                // still recognisably the review window.
                titleRow
                    .padding(.horizontal, Self.gutter)
                    .padding(.top, Self.gutter)

                if snapshot.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            tiles
                            breakdownSection
                            averagesSection
                            chartSection
                            insightsSection
                        }
                        .padding(Self.gutter)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.automatic)
                }
            }
        }
        .frame(minWidth: Self.contentSize.width, minHeight: Self.contentSize.height)
        // The window is pinned to `.darkAqua`; this keeps a SwiftUI preview and
        // any offscreen render honest about it too.
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Title

    private var titleRow: some View {
        HStack(spacing: 8) {
            BoltShape()
                .fill(Color.chronosScarlet)
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)

            Text("REVIEW")
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Color.chronosPaper)

            Spacer(minLength: 12)

            // Nothing to slice up yet, so the control would only be a lie
            // about there being three different empty states.
            if !snapshot.isEmpty {
                Picker("Period", selection: $period) {
                    ForEach(ReviewPeriod.allCases) { choice in
                        Text(choice.shortTitle).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
            }
        }
        .frame(height: 22)
    }

    // MARK: - Tiles

    private var tiles: some View {
        HStack(spacing: 12) {
            ForEach(snapshot.totals) { total in
                tile(total)
            }
        }
    }

    private func tile(_ total: PeriodTotal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(total.period.title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.chronosMuted)

            Text(TimeFormatting.hoursMinutes(total.seconds))
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Color.chronosGold)

            Text(deltaText(total))
                .font(.system(size: 10))
                .foregroundStyle(deltaColor(total))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.chronosPaper.opacity(0.05))
        )
        .accessibilityElement(children: .combine)
    }

    /// A minute of slack either way reads as "same": nobody means "+1m ahead of
    /// last month".
    private func deltaText(_ total: PeriodTotal) -> String {
        guard abs(total.delta) >= 60 else { return "same as \(total.period.previousTitle)" }
        return "\(TimeFormatting.signedHoursMinutes(total.delta)) vs \(total.period.previousTitle)"
    }

    private func deltaColor(_ total: PeriodTotal) -> Color {
        guard abs(total.delta) >= 60 else { return .chronosMuted }
        return total.delta > 0 ? .chronosMint : .chronosCoral
    }

    // MARK: - By project

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("By project")

            if snapshot.breakdown.isEmpty {
                caption("Nothing tracked \(inThisPeriod).")
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(snapshot.breakdown.enumerated()), id: \.element.id) { index, share in
                        breakdownRow(share, isTop: index == 0)
                    }
                }
            }
        }
    }

    private func breakdownRow(_ share: ProjectShare, isTop: Bool) -> some View {
        HStack(spacing: 10) {
            projectLabel(share.project, isTop: isTop)

            bar(share)

            Text(TimeFormatting.hoursMinutes(share.seconds))
                .font(.system(size: 12, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(isTop ? Color.chronosPaper : Color.chronosMuted)
                .frame(width: Self.timeColumnWidth, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("\(share.project.name), \(TimeFormatting.hoursMinutes(share.seconds)), \(Int((share.fraction * 100).rounded())) percent")
        )
    }

    private func bar(_ share: ProjectShare) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.chronosPaper.opacity(0.08))
                .frame(width: Self.barWidth, height: Self.barHeight)

            Capsule()
                .fill(share.project.displayColor)
                // A sliver still has to be visible, or a 1% project looks like
                // an empty row.
                .frame(width: max(3, Self.barWidth * share.fraction), height: Self.barHeight)
        }
        .frame(width: Self.barWidth, alignment: .leading)
        .accessibilityHidden(true)
    }

    // MARK: - Averages

    /// The same projects as the bars above, but as average days rather than
    /// totals. Its three scopes are fixed, so unlike everything else in the
    /// window it does not move when the period control does.
    private var averagesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Average per tracked day")

            if snapshot.averages.isEmpty {
                caption("Nothing to average yet.")
            } else {
                VStack(spacing: 6) {
                    averageHeaderRow

                    ForEach(Array(snapshot.averages.enumerated()), id: \.element.id) { index, average in
                        averageRow(average, isTop: index == 0)
                    }
                }
            }
        }
    }

    /// The scope headings. Same widths and spacing as ``averageRow(_:isTop:)``,
    /// so each label sits over its own numbers.
    private var averageHeaderRow: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            averageColumnTitle("This week")
            averageColumnTitle("This month")
            averageColumnTitle("All time")
        }
        // The values below say their own scope out loud.
        .accessibilityHidden(true)
    }

    private func averageColumnTitle(_ text: String) -> some View {
        sectionTitle(text)
            // A heading that no longer fits should truncate, not wrap: a second
            // line would push this row's labels out of step with each other.
            .lineLimit(1)
            .frame(width: Self.averageColumnWidth, alignment: .trailing)
    }

    private func averageRow(_ average: ProjectAverage, isTop: Bool) -> some View {
        HStack(spacing: 10) {
            projectLabel(average.project, isTop: isTop)

            averageValue(average.week, isTop: isTop)
            averageValue(average.month, isTop: isTop)
            averageValue(average.allTime, isTop: isTop)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("\(average.project.name), \(spokenAverage(average.week)) this week, \(spokenAverage(average.month)) this month, \(spokenAverage(average.allTime)) all time")
        )
    }

    /// An untouched scope is a dash rather than `0h 0m`: three columns of
    /// zeroes read as noise, and the row is about the scopes with time in them.
    private func averageValue(_ seconds: TimeInterval, isTop: Bool) -> some View {
        Text(seconds > 0 ? TimeFormatting.hoursMinutes(seconds) : "—")
            .font(.system(size: 12, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(averageColor(seconds, isTop: isTop))
            .frame(width: Self.averageColumnWidth, alignment: .trailing)
    }

    private func averageColor(_ seconds: TimeInterval, isTop: Bool) -> Color {
        guard seconds > 0 else { return Color.chronosMuted.opacity(0.5) }
        return isTop ? .chronosPaper : .chronosMuted
    }

    /// VoiceOver should hear "none", not "em dash".
    private func spokenAverage(_ seconds: TimeInterval) -> String {
        seconds > 0 ? TimeFormatting.hoursMinutes(seconds) : "none"
    }

    // MARK: - Chart

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                sectionTitle(snapshot.period.dailySeriesLength == 7 ? "Last 7 days" : "Last 30 days")

                Spacer(minLength: 8)

                // The rule is drawn in the same gold, and the label says which
                // days it counts — an unqualified "avg" over a chart with empty
                // bars in it would read as the mean of every bar.
                if snapshot.dailyAverageSeconds > 0 {
                    Text("avg \(TimeFormatting.hoursMinutes(snapshot.dailyAverageSeconds))/tracked day")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.chronosGold.opacity(0.85))
                }
            }

            Chart {
                ForEach(snapshot.daily) { day in
                    BarMark(
                        x: .value("Day", day.dayStart, unit: .day),
                        y: .value("Hours", day.seconds / 3600)
                    )
                    .foregroundStyle(day.isToday ? Color.chronosScarlet : Color.chronosMuted.opacity(0.55))
                    .cornerRadius(2)
                }

                // A mean over the tracked days can never exceed the tallest
                // bar, so the rule is always inside `chartUpperBound`.
                if snapshot.dailyAverageSeconds > 0 {
                    RuleMark(y: .value("Average", snapshot.dailyAverageSeconds / 3600))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Color.chronosGold.opacity(0.85))
                }
            }
            .chartXAxis {
                // No grid lines: 30 vertical rules behind 30 bars is noise.
                AxisMarks(values: .stride(by: .day, count: xAxisStride)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(axisLabel(for: date))
                                .font(.system(size: 9))
                                .foregroundStyle(Color.chronosMuted)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color.chronosPaper.opacity(0.08))
                    AxisValueLabel {
                        if let hours = value.as(Double.self) {
                            Text("\(Int(hours))h")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.chronosMuted)
                        }
                    }
                }
            }
            .chartYScale(domain: 0...chartUpperBound)
            // The bars are binned by day, so the chart has to agree with the
            // engine about where a day starts.
            .environment(\.calendar, snapshot.calendar)
            .environment(\.timeZone, snapshot.calendar.timeZone)
            .frame(height: Self.chartHeight)
        }
    }

    /// Seven labels fit; thirty do not.
    private var xAxisStride: Int {
        snapshot.period.dailySeriesLength == 7 ? 1 : 5
    }

    /// A flat zero series would otherwise be drawn against an arbitrary scale.
    private var chartUpperBound: Double {
        let peak = snapshot.daily.map { $0.seconds / 3600 }.max() ?? 0
        return max(1, peak * 1.1)
    }

    private func axisLabel(for date: Date) -> String {
        ReviewDateLabel.string(
            for: date,
            format: snapshot.period.dailySeriesLength == 7 ? "EEE" : "M/d",
            calendar: snapshot.calendar
        )
    }

    // MARK: - Insights

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Insights")

            if snapshot.insights.isEmpty {
                caption("Track some time and this fills in.")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(snapshot.insights, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            BoltShape()
                                .fill(Color.chronosScarlet)
                                .frame(width: 8, height: 10)
                                .accessibilityHidden(true)

                            Text(line)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.chronosPaper.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            BoltShape()
                .fill(Color.chronosScarlet.opacity(0.5))
                .frame(width: 28, height: 34)
                .accessibilityHidden(true)

            Text("Nothing tracked yet.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.chronosPaper)

            Text("Start a project in the panel and this fills in.")
                .font(.system(size: 12))
                .foregroundStyle(Color.chronosMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Pieces

    /// The colour dot and name that open a row in both project tables.
    ///
    /// Deliberately a `@ViewBuilder` of two views rather than a nested `HStack`:
    /// the pair stays a pair of direct children of the caller's stack, so the
    /// 10pt gap after the name is the same gap as everywhere else in the row.
    @ViewBuilder
    private func projectLabel(_ project: Project, isTop: Bool) -> some View {
        Circle()
            .fill(project.displayColor)
            .frame(width: 7, height: 7)

        Text(project.name)
            .font(.system(size: 12, weight: isTop ? .semibold : .regular))
            .foregroundStyle(isTop ? Color.chronosPaper : Color.chronosPaper.opacity(0.85))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Color.chronosMuted)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Color.chronosMuted)
    }

    private var inThisPeriod: String {
        switch snapshot.period {
        case .day: "today"
        case .week: "this week"
        case .month: "this month"
        }
    }
}

/// The chart's axis labels (`Mon`, `9/2`).
///
/// One cached formatter per shape, on the main actor because `DateFormatter` is
/// not `Sendable` and every caller is a view body. The chart re-labels whenever
/// the snapshot changes, which is rare, but building a formatter inside a
/// `Chart` body would still be wasteful.
@MainActor
enum ReviewDateLabel {
    private static var formatters: [String: DateFormatter] = [:]

    static func string(for date: Date, format: String, calendar: Calendar) -> String {
        let formatter: DateFormatter
        if let cached = formatters[format] {
            formatter = cached
        } else {
            formatter = DateFormatter()
            formatter.dateFormat = format
            formatters[format] = formatter
        }
        if formatter.timeZone != calendar.timeZone { formatter.timeZone = calendar.timeZone }
        let locale = calendar.locale ?? .current
        if formatter.locale != locale { formatter.locale = locale }
        return formatter.string(from: date)
    }
}
