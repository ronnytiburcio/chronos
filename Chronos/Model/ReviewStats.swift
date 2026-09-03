import Foundation

/// The stretch of time the review window's breakdown, chart, and insights
/// cover. The three headline totals are always all three.
enum ReviewPeriod: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month

    var id: String { rawValue }

    /// The tile heading and the segmented control's label.
    var title: String {
        switch self {
        case .day: "Today"
        case .week: "This week"
        case .month: "This month"
        }
    }

    /// The segmented control is narrow; the tiles are not.
    var shortTitle: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        }
    }

    /// What the delta caption compares against.
    var previousTitle: String {
        switch self {
        case .day: "yesterday"
        case .week: "last week"
        case .month: "last month"
        }
    }

    /// How many tracking days the daily chart shows for this period.
    var dailySeriesLength: Int {
        switch self {
        case .day, .week: 7
        case .month: 30
        }
    }
}

/// One headline number: the period, what it holds now, and what the period
/// before it held.
struct PeriodTotal: Identifiable, Equatable, Sendable {
    let period: ReviewPeriod
    let seconds: TimeInterval
    /// The immediately preceding *full* period — yesterday's tracking day, last
    /// calendar week, last calendar month.
    let previousSeconds: TimeInterval

    var id: ReviewPeriod.ID { period.id }

    /// Positive when this period is ahead of the last one. Note the current
    /// period is still running, so early in a week the delta is normally
    /// negative and that is not a bug.
    var delta: TimeInterval { seconds - previousSeconds }
}

/// One project's slice of the selected period.
struct ProjectShare: Identifiable, Equatable, Sendable {
    let project: Project
    let seconds: TimeInterval
    /// Share of the period's total, 0...1. Zero when the period is empty.
    let fraction: Double

    var id: Project.ID { project.id }
}

/// One bar of the daily chart: a whole tracking day, zero included.
struct DayTotal: Identifiable, Equatable, Sendable {
    /// The instant the tracking day began (the rollover), which is what the
    /// chart plots against.
    let dayStart: Date
    /// `yyyy-MM-dd` of that tracking day.
    let dateString: String
    let seconds: TimeInterval
    /// The last day of the series is the tracking day in progress.
    let isToday: Bool

    var id: String { dateString }
}

/// Everything the review window draws, resolved once per refresh.
struct ReviewSnapshot: Equatable, Sendable {
    /// Which period ``breakdown``, ``daily``, and ``insights`` describe.
    let period: ReviewPeriod
    /// Today, this week, this month — in that order, always all three.
    let totals: [PeriodTotal]
    /// The selected period by project, biggest first, projects with no time
    /// left out. Archived projects appear when they have time.
    let breakdown: [ProjectShare]
    /// The last 7 (day, week) or 30 (month) tracking days, oldest first.
    let daily: [DayTotal]
    /// Short lines of the "here is what that means" kind.
    let insights: [String]
    /// The calendar the days were measured in. The chart bins and labels its
    /// bars with it, so the axis can never fall a day out of step with the
    /// tracking days behind it.
    let calendar: Calendar
    /// Whether any session anywhere in the history has time on it — however
    /// long ago. Old history still counts as history.
    let hasHistory: Bool

    /// True only when nothing has ever been tracked, which is the one case that
    /// gets an empty state instead of zeroes.
    var isEmpty: Bool { !hasHistory }

    /// A snapshot with no data, for a view that has not refreshed yet.
    static func empty(period: ReviewPeriod = .week, calendar: Calendar = .current) -> ReviewSnapshot {
        ReviewSnapshot(period: period, totals: [], breakdown: [], daily: [], insights: [], calendar: calendar, hasHistory: false)
    }
}

/// Pure statistics over the session history (Phase 9's review dashboard).
///
/// Everything here is tracking-day based (SPEC §7): a session belongs to the
/// day, week, or month its **start** falls in, and its time is clipped to that
/// period's end — the same rule ``ArchiveWriter`` files a day under, so the
/// review and the CSVs can never disagree. An open session is measured to
/// `now`.
///
/// The calendar is always injected (it carries the time zone and the week's
/// `firstWeekday`); nothing here reads `Calendar.current` or the system clock,
/// which is what makes the whole thing testable without a disk or an engine.
enum ReviewStats {
    /// Builds everything the review window shows.
    ///
    /// - Parameters:
    ///   - sessions: the whole history, live log plus rotated years.
    ///   - projects: the current list, archived ones included. A session naming
    ///     a project that no longer exists is skipped.
    ///   - period: which period drives the breakdown, the chart, and the
    ///     insights. The three headline totals do not depend on it.
    ///   - now: the instant open sessions are measured to.
    static func snapshot(
        sessions: [Session],
        projects: [Project],
        period: ReviewPeriod,
        now: Date,
        rollover: RolloverTime,
        calendar: Calendar
    ) -> ReviewSnapshot {
        let today = TrackingDay.start(containing: now, rollover: rollover, calendar: calendar)

        let totals = ReviewPeriod.allCases.map { each -> PeriodTotal in
            let current = range(for: each, containing: today, rollover: rollover, calendar: calendar)
            let earlier = previousRange(for: each, containing: today, rollover: rollover, calendar: calendar)
            return PeriodTotal(
                period: each,
                seconds: seconds(of: sessions, in: current, asOf: now),
                previousSeconds: seconds(of: sessions, in: earlier, asOf: now)
            )
        }

        let selected = range(for: period, containing: today, rollover: rollover, calendar: calendar)
        let breakdown = breakdown(of: sessions, projects: projects, in: selected, asOf: now)
        let daily = dailySeries(
            of: sessions,
            length: period.dailySeriesLength,
            endingAt: today,
            rollover: rollover,
            calendar: calendar,
            asOf: now
        )
        let insights = insights(
            sessions: sessions,
            projects: projects,
            daily: daily,
            selected: selected,
            period: period,
            rollover: rollover,
            calendar: calendar,
            asOf: now
        )

        return ReviewSnapshot(
            period: period,
            totals: totals,
            breakdown: breakdown,
            daily: daily,
            insights: insights,
            calendar: calendar,
            hasHistory: sessions.contains { $0.duration(asOf: now) > 0 }
        )
    }

    // MARK: - Periods

    /// The half-open instant range a period covers, anchored on the tracking
    /// day `today` rather than on a calendar midnight: at 02:00 with an 04:00
    /// rollover "this week" is still the week yesterday belongs to.
    ///
    /// Week and month bounds are the calendar's own (its `firstWeekday`
    /// included), converted from midnights to the rollovers of the same
    /// calendar days so the range is a whole number of tracking days.
    static func range(
        for period: ReviewPeriod,
        containing today: Date,
        rollover: RolloverTime,
        calendar: Calendar
    ) -> Range<Date> {
        switch period {
        case .day:
            return today..<TrackingDay.next(after: today, rollover: rollover, calendar: calendar)
        case .week:
            return trackingRange(of: .weekOfYear, containing: today, rollover: rollover, calendar: calendar)
        case .month:
            return trackingRange(of: .month, containing: today, rollover: rollover, calendar: calendar)
        }
    }

    /// The full period immediately before ``range(for:containing:rollover:calendar:)``.
    static func previousRange(
        for period: ReviewPeriod,
        containing today: Date,
        rollover: RolloverTime,
        calendar: Calendar
    ) -> Range<Date> {
        switch period {
        case .day:
            let yesterday = TrackingDay.start(
                containing: today.addingTimeInterval(-1),
                rollover: rollover,
                calendar: calendar
            )
            return yesterday..<today
        case .week, .month:
            let current = range(for: period, containing: today, rollover: rollover, calendar: calendar)
            // One second back from the start of this period lands in the last
            // day of the previous one, whatever length it had — which is what
            // makes a 28-day February work without arithmetic about it.
            let inPrevious = TrackingDay.start(
                containing: current.lowerBound.addingTimeInterval(-1),
                rollover: rollover,
                calendar: calendar
            )
            let unit: Calendar.Component = period == .week ? .weekOfYear : .month
            let previous = trackingRange(of: unit, containing: inPrevious, rollover: rollover, calendar: calendar)
            // Whatever the calendar said, the previous period ends where this
            // one begins.
            return previous.lowerBound..<current.lowerBound
        }
    }

    /// The calendar unit containing `today`, as a range of rollovers.
    private static func trackingRange(
        of component: Calendar.Component,
        containing today: Date,
        rollover: RolloverTime,
        calendar: Calendar
    ) -> Range<Date> {
        guard let interval = calendar.dateInterval(of: component, for: today) else {
            NSLog("Chronos: could not resolve the \(component) containing \(today); reviewing that day alone")
            return today..<TrackingDay.next(after: today, rollover: rollover, calendar: calendar)
        }
        // `interval` is midnight-to-midnight; the tracking days that cover the
        // same calendar days start one rollover into each of them, so the unit
        // shifts wholesale and stays a whole number of tracking days.
        let start = trackingDayStart(ofCalendarDay: interval.start, rollover: rollover, calendar: calendar)
        let end = trackingDayStart(ofCalendarDay: interval.end, rollover: rollover, calendar: calendar)
        return start..<end
    }

    /// The rollover on the calendar day that `midnight` begins — the instant
    /// that calendar day's tracking day starts.
    private static func trackingDayStart(
        ofCalendarDay midnight: Date,
        rollover: RolloverTime,
        calendar: Calendar
    ) -> Date {
        // `next(after:)` is strict, so the anchor sits a second before midnight
        // and a 00:00 rollover still resolves to that same day.
        TrackingDay.next(after: midnight.addingTimeInterval(-1), rollover: rollover, calendar: calendar)
    }

    // MARK: - Totals

    /// Seconds inside `range` from the sessions that **start** in it, clipped
    /// to the range's end (and to `now`, which is earlier for a period still
    /// running).
    static func seconds(
        of sessions: [Session],
        in range: Range<Date>,
        projectID: UUID? = nil,
        asOf now: Date
    ) -> TimeInterval {
        let cap = min(range.upperBound, now)
        return sessions.reduce(0) { running, session in
            guard range.contains(session.start) else { return running }
            guard projectID == nil || session.projectID == projectID else { return running }
            return running + clippedDuration(of: session, cap: cap)
        }
    }

    /// A session's seconds measured to `cap` at the latest. Never negative, so
    /// a session that started after the cap (a clock jump) reads as zero.
    private static func clippedDuration(of session: Session, cap: Date) -> TimeInterval {
        let end = min(session.end ?? cap, cap)
        return max(0, end.timeIntervalSince(session.start))
    }

    // MARK: - Breakdown

    /// The period by project: biggest first, nothing with zero time, fractions
    /// of the period's own total.
    static func breakdown(
        of sessions: [Session],
        projects: [Project],
        in range: Range<Date>,
        asOf now: Date
    ) -> [ProjectShare] {
        let cap = min(range.upperBound, now)
        var byProject: [UUID: TimeInterval] = [:]
        for session in sessions where range.contains(session.start) {
            byProject[session.projectID, default: 0] += clippedDuration(of: session, cap: cap)
        }

        let total = byProject.values.reduce(0, +)
        guard total > 0 else { return [] }

        return projects
            .compactMap { project -> ProjectShare? in
                guard let seconds = byProject[project.id], seconds > 0 else { return nil }
                return ProjectShare(project: project, seconds: seconds, fraction: seconds / total)
            }
            // Ties keep the panel's project order, which is the order
            // `projects` arrives in.
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.seconds != rhs.element.seconds { return lhs.element.seconds > rhs.element.seconds }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    // MARK: - Daily series

    /// The last `length` tracking days ending with the one `today` starts,
    /// oldest first, days with nothing on them included as zeroes.
    static func dailySeries(
        of sessions: [Session],
        length: Int,
        endingAt today: Date,
        rollover: RolloverTime,
        calendar: Calendar,
        asOf now: Date
    ) -> [DayTotal] {
        guard length > 0 else { return [] }

        // Walk back one tracking day at a time rather than subtracting 24
        // hours, so a DST day is one day and not 23 or 25 hours of one.
        var starts: [Date] = [today]
        while starts.count < length, let earliest = starts.last {
            starts.append(
                TrackingDay.start(containing: earliest.addingTimeInterval(-1), rollover: rollover, calendar: calendar)
            )
        }

        return starts.reversed().map { start in
            let end = TrackingDay.next(after: start, rollover: rollover, calendar: calendar)
            return DayTotal(
                dayStart: start,
                dateString: TrackingDay.dateString(for: start, calendar: calendar),
                seconds: seconds(of: sessions, in: start..<end, asOf: now),
                isToday: start == today
            )
        }
    }

    // MARK: - Insights

    /// The short lines under the chart. Each one is omitted rather than
    /// hedged when there is nothing to say.
    ///
    /// Busiest day and average describe the days the chart shows and say so
    /// ("last 7 days"), so neither can name a day the chart does not. The
    /// longest session follows the selected period, like the breakdown does,
    /// and says which ("today", "this week"). The streak keeps counting back
    /// past the chart, because a 40-day streak that reads "7-day streak" is
    /// wrong, not merely windowed.
    static func insights(
        sessions: [Session],
        projects: [Project],
        daily: [DayTotal],
        selected: Range<Date>,
        period: ReviewPeriod,
        rollover: RolloverTime,
        calendar: Calendar,
        asOf now: Date
    ) -> [String] {
        var lines: [String] = []
        let active = daily.filter { $0.seconds > 0 }
        let window = "last \(daily.count) days"

        // `>=` so a tie goes to the more recent day; the series is oldest first.
        var busiest: DayTotal?
        for day in active where day.seconds >= (busiest?.seconds ?? 0) {
            busiest = day
        }
        if let busiest {
            let label = dayLabel(for: busiest.dayStart, calendar: calendar)
            lines.append("Busiest day (\(window)): \(label), \(TimeFormatting.hoursMinutes(busiest.seconds))")
        }

        if !active.isEmpty {
            let average = active.reduce(0) { $0 + $1.seconds } / Double(active.count)
            lines.append("Average on tracked days (\(window)): \(TimeFormatting.hoursMinutes(average))")
        }

        let streak = currentStreak(in: daily, continuingWith: sessions, rollover: rollover, calendar: calendar, asOf: now)
        if streak > 0 {
            lines.append("\(streak)-day streak")
        }

        if let longest = longestSession(sessions, projects: projects, in: selected, asOf: now) {
            let scope = period.title.lowercased()
            lines.append("Longest session (\(scope)): \(longest.name), \(TimeFormatting.hoursMinutes(longest.seconds))")
        }

        return lines
    }

    /// Consecutive tracked days ending today, or ending yesterday when today
    /// has not been started yet — a streak should not look broken at 09:00.
    ///
    /// Counts through the series first, then keeps walking back through the
    /// history a tracking day at a time when the streak reaches the series'
    /// first day, up to ``streakLimit`` days.
    static func currentStreak(
        in daily: [DayTotal],
        continuingWith sessions: [Session] = [],
        rollover: RolloverTime = .default,
        calendar: Calendar = .current,
        asOf now: Date = .distantFuture
    ) -> Int {
        var index = daily.count - 1
        // Today counts for nothing yet if it is empty, but it does not end the
        // streak either.
        if index >= 0, daily[index].seconds <= 0 { index -= 1 }

        var streak = 0
        while index >= 0, daily[index].seconds > 0 {
            streak += 1
            index -= 1
        }
        guard index < 0, let earliest = daily.first, streak > 0 else { return streak }

        // The whole series was tracked; the streak may be older than the chart.
        var dayEnd = earliest.dayStart
        while streak < streakLimit {
            let dayStart = TrackingDay.start(containing: dayEnd.addingTimeInterval(-1), rollover: rollover, calendar: calendar)
            guard seconds(of: sessions, in: dayStart..<dayEnd, asOf: now) > 0 else { break }
            streak += 1
            dayEnd = dayStart
        }
        return streak
    }

    /// A year is enough streak for anyone; it also bounds the walk back.
    static let streakLimit = 366

    /// The single longest session that started inside the period, with the name
    /// of its project. Clipped like every other number here.
    private static func longestSession(
        _ sessions: [Session],
        projects: [Project],
        in range: Range<Date>,
        asOf now: Date
    ) -> (name: String, seconds: TimeInterval)? {
        let cap = min(range.upperBound, now)
        let names = Dictionary(projects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        var best: (name: String, seconds: TimeInterval)?
        for session in sessions where range.contains(session.start) {
            guard let name = names[session.projectID] else { continue }
            let seconds = clippedDuration(of: session, cap: cap)
            guard seconds > 0, seconds > (best?.seconds ?? 0) else { continue }
            best = (name, seconds)
        }
        return best
    }

    /// `Tue Sep 1` for an insight line.
    ///
    /// Built per call rather than cached: snapshots are taken on open, on a
    /// session change, and once a minute, so a `DateFormatter` here costs
    /// nothing and a shared one would need isolation this type does not have.
    private static func dayLabel(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        // The same fixed shape the panel header uses, so an insight line and
        // the header cannot name the same day two different ways.
        formatter.dateFormat = TimeFormatting.dayLabelFormat
        return formatter.string(from: date)
    }
}
