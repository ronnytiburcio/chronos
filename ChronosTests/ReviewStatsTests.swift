import XCTest
@testable import Chronos

/// Phase 9's review dashboard: the pure statistics behind it.
///
/// Everything here is built in memory against a calendar pinned to
/// America/New_York, so the tracking-day boundaries, the week's first day, and
/// the month lengths do not depend on the machine the tests run on.
final class ReviewStatsTests: XCTestCase {
    private var clientWork: Project!
    private var sideProject: Project!
    private var admin: Project!

    override func setUp() {
        super.setUp()
        clientWork = Project(name: "Client Work", sortOrder: 0)
        sideProject = Project(name: "Side Project", sortOrder: 1)
        admin = Project(name: "Admin", sortOrder: 2, isArchived: true)
    }

    override func tearDown() {
        clientWork = nil
        sideProject = nil
        admin = nil
        super.tearDown()
    }

    // MARK: - Headline totals

    /// Thursday 2025-09-04 12:00. Today is the 04th, this week began Sunday the
    /// 31st (the Gregorian calendar's `firstWeekday` is Sunday), this month
    /// began on the 1st.
    func testTodayWeekAndMonthTotalsAreEachTheirOwnPeriod() {
        let sessions = [
            // Today: 2h.
            closed(clientWork, from: at(2025, 9, 4, 9), to: at(2025, 9, 4, 11)),
            // Tuesday the 2nd, still this week: 1h.
            closed(clientWork, from: at(2025, 9, 2, 9), to: at(2025, 9, 2, 10)),
            // Saturday the 30th of August: last week, last month: 3h.
            closed(sideProject, from: at(2025, 8, 30, 9), to: at(2025, 8, 30, 12)),
        ]

        let totals = snapshot(sessions).totals

        XCTAssertEqual(seconds(totals, .day), 2 * 3600)
        XCTAssertEqual(seconds(totals, .week), 3 * 3600)
        XCTAssertEqual(seconds(totals, .month), 3 * 3600)
    }

    /// SPEC §7: 01:00 is before the 04:00 rollover, so it is still the previous
    /// tracking day — and here that also puts it in the previous week.
    func testASessionAfterMidnightBelongsToThePreviousTrackingDay() {
        // Sunday 2025-09-07 01:00 is Saturday the 6th's time, and Saturday is
        // the last day of the week that began Sunday the 31st.
        let sessions = [closed(clientWork, from: at(2025, 9, 7, 1), to: at(2025, 9, 7, 3))]

        let sunday = snapshot(sessions, now: at(2025, 9, 7, 12))
        XCTAssertEqual(seconds(sunday.totals, .day), 0, "the new tracking day started at 04:00")
        XCTAssertEqual(seconds(sunday.totals, .week), 0, "and the new week with it")

        // Read from inside that same 01:00 hour, it is today's — and yesterday
        // by the calendar.
        let overnight = snapshot(sessions, now: at(2025, 9, 7, 3))
        XCTAssertEqual(seconds(overnight.totals, .day), 2 * 3600)
        XCTAssertEqual(seconds(overnight.daily.last?.dateString ?? "", in: overnight), 2 * 3600)
        XCTAssertEqual(overnight.daily.last?.dateString, "2025-09-06")
    }

    func testYesterdayIsTheDayTileSPreviousPeriod() {
        let sessions = [
            closed(clientWork, from: at(2025, 9, 4, 9), to: at(2025, 9, 4, 10)),
            closed(clientWork, from: at(2025, 9, 3, 9), to: at(2025, 9, 3, 13)),
        ]

        let day = total(snapshot(sessions).totals, .day)
        XCTAssertEqual(day.seconds, 3600)
        XCTAssertEqual(day.previousSeconds, 4 * 3600)
        XCTAssertEqual(day.delta, -3 * 3600)
    }

    /// The week runs Sunday to Saturday here, so Saturday the 30th and Sunday
    /// the 31st are in different weeks even though they are a day apart.
    func testTheWeekBreaksOnTheCalendarSFirstWeekday() {
        let sessions = [
            // Sunday the 31st, 04:00 onwards: this week.
            closed(clientWork, from: at(2025, 8, 31, 9), to: at(2025, 8, 31, 10)),
            // Saturday the 30th: last week.
            closed(clientWork, from: at(2025, 8, 30, 9), to: at(2025, 8, 30, 12)),
        ]

        let week = total(snapshot(sessions).totals, .week)
        XCTAssertEqual(week.seconds, 3600)
        XCTAssertEqual(week.previousSeconds, 3 * 3600)
    }

    /// A month is whatever length the calendar says: March compares against a
    /// 28-day February without any arithmetic about it.
    func testThePreviousMonthIsWhateverLengthTheCalendarSays() {
        let sessions = [
            // The whole of February, one hour on the 1st and one on the last
            // day, which only exists if the range really is February.
            closed(clientWork, from: at(2025, 2, 1, 9), to: at(2025, 2, 1, 10)),
            closed(clientWork, from: at(2025, 2, 28, 9), to: at(2025, 2, 28, 10)),
            // January, which must not be counted.
            closed(clientWork, from: at(2025, 1, 31, 9), to: at(2025, 1, 31, 15)),
            // March, the month under review.
            closed(clientWork, from: at(2025, 3, 5, 9), to: at(2025, 3, 5, 12)),
        ]

        let month = total(snapshot(sessions, now: at(2025, 3, 10, 12)).totals, .month)
        XCTAssertEqual(month.seconds, 3 * 3600)
        XCTAssertEqual(month.previousSeconds, 2 * 3600)
    }

    /// An open session is measured to `now`, exactly as the panel shows it.
    func testAnOpenSessionIsMeasuredToNow() {
        let sessions = [running(clientWork, from: at(2025, 9, 4, 9))]

        let totals = snapshot(sessions, now: at(2025, 9, 4, 11, 30)).totals
        XCTAssertEqual(seconds(totals, .day), 2.5 * 3600)
    }

    /// A session that runs past the end of the period it started in keeps only
    /// the part inside it — the same clipping the archive does.
    func testTimeIsClippedToThePeriodTheSessionStartedIn() {
        // Wednesday 23:00 to Thursday 06:00, across the 04:00 rollover.
        let sessions = [closed(clientWork, from: at(2025, 9, 3, 23), to: at(2025, 9, 4, 6))]

        let result = snapshot(sessions)
        // Five hours on Wednesday (23:00 to 04:00), nothing on Thursday: the
        // session is filed by its start.
        XCTAssertEqual(total(result.totals, .day).seconds, 0)
        XCTAssertEqual(total(result.totals, .day).previousSeconds, 5 * 3600)
        XCTAssertEqual(result.daily.last?.seconds, 0)
        XCTAssertEqual(result.daily.dropLast().last?.seconds, 5 * 3600)
    }

    // MARK: - Breakdown

    func testBreakdownIsBiggestFirstWithFractionsThatSumToOne() {
        let sessions = [
            closed(clientWork, from: at(2025, 9, 2, 9), to: at(2025, 9, 2, 10)),
            closed(sideProject, from: at(2025, 9, 3, 9), to: at(2025, 9, 3, 12)),
            closed(admin, from: at(2025, 9, 4, 9), to: at(2025, 9, 4, 11)),
        ]

        let breakdown = snapshot(sessions, period: .week).breakdown

        XCTAssertEqual(breakdown.map(\.project.name), ["Side Project", "Admin", "Client Work"])
        XCTAssertEqual(breakdown.map { Int($0.seconds) }, [3 * 3600, 2 * 3600, 3600])
        XCTAssertEqual(breakdown.reduce(0) { $0 + $1.fraction }, 1, accuracy: 0.0001)
        XCTAssertEqual(breakdown[0].fraction, 0.5, accuracy: 0.0001)
    }

    /// The archive records what happened, not what the panel shows, and so
    /// does the review.
    func testAnArchivedProjectAppearsWhenItHasTime() {
        let sessions = [closed(admin, from: at(2025, 9, 4, 9), to: at(2025, 9, 4, 10))]

        XCTAssertEqual(snapshot(sessions).breakdown.map(\.project.name), ["Admin"])
    }

    func testAProjectWithNoTimeInThePeriodIsLeftOut() {
        let sessions = [closed(clientWork, from: at(2025, 9, 4, 9), to: at(2025, 9, 4, 10))]

        XCTAssertEqual(snapshot(sessions).breakdown.count, 1)
    }

    func testASessionNamingADeletedProjectIsSkipped() {
        let ghost = Project(name: "Gone", sortOrder: 9)
        let sessions = [
            closed(clientWork, from: at(2025, 9, 4, 9), to: at(2025, 9, 4, 10)),
            closed(ghost, from: at(2025, 9, 4, 10), to: at(2025, 9, 4, 12)),
        ]

        let breakdown = snapshot(sessions).breakdown
        XCTAssertEqual(breakdown.map(\.project.name), ["Client Work"])
        // The deleted project's time is still in the period's total, which is
        // what the tile says; only the named rows drop it.
        XCTAssertEqual(seconds(snapshot(sessions).totals, .day), 3 * 3600)
    }

    // MARK: - Daily series

    func testTheDailySeriesIsSevenDaysForDayAndWeekAndThirtyForMonth() {
        for period in [ReviewPeriod.day, .week] {
            XCTAssertEqual(snapshot([], period: period).daily.count, 7, "\(period)")
        }
        XCTAssertEqual(snapshot([], period: .month).daily.count, 30)
    }

    func testTheDailySeriesIsOldestFirstEndsTodayAndZeroFillsTheGaps() {
        let sessions = [
            closed(clientWork, from: at(2025, 9, 4, 9), to: at(2025, 9, 4, 10)),
            closed(clientWork, from: at(2025, 9, 1, 9), to: at(2025, 9, 1, 11)),
        ]

        let daily = snapshot(sessions, period: .week).daily

        XCTAssertEqual(
            daily.map(\.dateString),
            [
                "2025-08-29", "2025-08-30", "2025-08-31",
                "2025-09-01", "2025-09-02", "2025-09-03", "2025-09-04",
            ]
        )
        XCTAssertEqual(daily.map { Int($0.seconds) }, [0, 0, 0, 2 * 3600, 0, 0, 3600])
        XCTAssertEqual(daily.filter(\.isToday).map(\.dateString), ["2025-09-04"])
        // Every day starts at the rollover, not at midnight.
        XCTAssertEqual(daily.first?.dayStart, at(2025, 8, 29, 4))
    }

    // MARK: - Insights

    func testEveryInsightAppearsWhenThereIsSomethingToSay() {
        let sessions = [
            // Monday the 1st: the busiest day, 4h 12m.
            closed(clientWork, from: at(2025, 9, 1, 9), to: at(2025, 9, 1, 13, 12)),
            // Tuesday, Wednesday, Thursday: with Monday that is a four-day
            // streak ending today.
            closed(sideProject, from: at(2025, 9, 2, 9), to: at(2025, 9, 2, 10)),
            closed(clientWork, from: at(2025, 9, 3, 9), to: at(2025, 9, 3, 10, 30)),
            closed(clientWork, from: at(2025, 9, 4, 9), to: at(2025, 9, 4, 10)),
        ]

        let insights = snapshot(sessions, period: .week).insights

        XCTAssertEqual(
            insights,
            [
                "Busiest day (last 7 days): Mon Sep 1, 4h 12m",
                // (4h12m + 1h + 1h30m + 1h) / 4 active days.
                "Average on tracked days (last 7 days): 1h 55m",
                "4-day streak",
                // The longest single session in the week, not the busiest day.
                "Longest session (this week): Client Work, 4h 12m",
            ]
        )
    }

    /// The chart shows a week, but a streak is as long as it really is.
    func testAStreakLongerThanTheChartWindowIsCountedInFull() {
        // Ten consecutive tracked days ending today (the 4th): Aug 26 to Sep 4.
        var sessions: [Session] = []
        for offset in 0..<10 {
            let day = at(2025, 9, 4, 9).addingTimeInterval(-Double(offset) * 24 * 3600)
            sessions.append(closed(clientWork, from: day, to: day.addingTimeInterval(1800)))
        }

        XCTAssertTrue(snapshot(sessions, period: .week).insights.contains("10-day streak"))
        XCTAssertEqual(snapshot(sessions, period: .week).daily.count, 7, "the chart window is unchanged")
    }

    /// Only history counts as history: the empty state is for a first launch,
    /// not for a quiet month.
    func testOldHistoryIsStillHistory() {
        let sessions = [closed(clientWork, from: at(2025, 3, 1, 9), to: at(2025, 3, 1, 10))]

        let result = snapshot(sessions)

        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.breakdown.isEmpty)
    }

    func testNoDataMeansNoInsightsAtAll() {
        XCTAssertEqual(snapshot([]).insights, [])
    }

    /// A streak should not look broken at 09:00 just because nothing has been
    /// started yet today.
    func testTheStreakSurvivesAnUntouchedToday() {
        let sessions = [
            closed(clientWork, from: at(2025, 9, 2, 9), to: at(2025, 9, 2, 10)),
            closed(clientWork, from: at(2025, 9, 3, 9), to: at(2025, 9, 3, 10)),
        ]

        XCTAssertTrue(snapshot(sessions).insights.contains("2-day streak"))
    }

    func testAGapEndsTheStreak() {
        let sessions = [
            // Monday and Tuesday, then nothing on Wednesday.
            closed(clientWork, from: at(2025, 9, 1, 9), to: at(2025, 9, 1, 10)),
            closed(clientWork, from: at(2025, 9, 2, 9), to: at(2025, 9, 2, 10)),
            closed(clientWork, from: at(2025, 9, 4, 9), to: at(2025, 9, 4, 10)),
        ]

        XCTAssertTrue(snapshot(sessions).insights.contains("1-day streak"))
    }

    func testNoStreakLineWhenNeitherTodayNorYesterdayWasTracked() {
        let sessions = [closed(clientWork, from: at(2025, 9, 1, 9), to: at(2025, 9, 1, 10))]

        let insights = snapshot(sessions).insights
        XCTAssertFalse(insights.contains { $0.hasSuffix("streak") }, "\(insights)")
        XCTAssertTrue(insights.contains("Busiest day (last 7 days): Mon Sep 1, 1h 0m"))
    }

    /// The longest session is drawn from the *selected* period, so switching to
    /// Day narrows it.
    func testTheLongestSessionFollowsTheSelectedPeriod() {
        let sessions = [
            closed(clientWork, from: at(2025, 9, 1, 9), to: at(2025, 9, 1, 15)),
            closed(sideProject, from: at(2025, 9, 4, 9), to: at(2025, 9, 4, 11)),
        ]

        XCTAssertTrue(snapshot(sessions, period: .week).insights.contains("Longest session (this week): Client Work, 6h 0m"))
        XCTAssertTrue(snapshot(sessions, period: .day).insights.contains("Longest session (today): Side Project, 2h 0m"))
    }

    // MARK: - Empty

    func testAnEmptyHistoryIsAnEmptySnapshot() {
        let result = snapshot([])

        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(result.breakdown.isEmpty)
        XCTAssertTrue(result.insights.isEmpty)
        XCTAssertEqual(result.totals.map(\.period), [.day, .week, .month])
        XCTAssertEqual(result.totals.map { Int($0.seconds) }, [0, 0, 0])
        XCTAssertEqual(result.daily.count, 7)
    }

    func testASnapshotWithAnySecondsIsNotEmpty() {
        let sessions = [closed(clientWork, from: at(2025, 9, 4, 9), to: at(2025, 9, 4, 10))]

        XCTAssertFalse(snapshot(sessions).isEmpty)
    }

    /// Time older than the chart's window still counts against the tiles, and
    /// keeps the window out of its empty state.
    func testDataOutsideTheChartWindowStillCounts() {
        let sessions = [closed(clientWork, from: at(2025, 8, 1, 9), to: at(2025, 8, 1, 10))]

        let result = snapshot(sessions)
        XCTAssertFalse(result.isEmpty, "August is in the month tile's previous period")
        XCTAssertTrue(result.daily.allSatisfy { $0.seconds == 0 })
    }

    // MARK: - Fixtures

    /// Thursday 2025-09-04 12:00, the default vantage point for these tests.
    private func snapshot(
        _ sessions: [Session],
        projects: [Project]? = nil,
        period: ReviewPeriod = .day,
        now: Date? = nil
    ) -> ReviewSnapshot {
        ReviewStats.snapshot(
            sessions: sessions,
            projects: projects ?? [clientWork, sideProject, admin],
            period: period,
            now: now ?? at(2025, 9, 4, 12),
            rollover: .default,
            calendar: Calendar.newYork
        )
    }

    private func total(_ totals: [PeriodTotal], _ period: ReviewPeriod) -> PeriodTotal {
        totals.first { $0.period == period } ?? PeriodTotal(period: period, seconds: -1, previousSeconds: -1)
    }

    private func seconds(_ totals: [PeriodTotal], _ period: ReviewPeriod) -> TimeInterval {
        total(totals, period).seconds
    }

    private func seconds(_ dateString: String, in snapshot: ReviewSnapshot) -> TimeInterval {
        snapshot.daily.first { $0.dateString == dateString }?.seconds ?? -1
    }

    private func closed(_ project: Project, from start: Date, to end: Date) -> Session {
        Session(projectID: project.id, start: start, end: end)
    }

    private func running(_ project: Project, from start: Date) -> Session {
        Session(projectID: project.id, start: start)
    }
}
