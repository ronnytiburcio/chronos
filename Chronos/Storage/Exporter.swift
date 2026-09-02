import Foundation

/// The date range an export covers (SPEC §8's "week / month / custom").
///
/// A range is resolved to a pair of inclusive `yyyy-MM-dd` **tracking days**,
/// not instants: the archive is keyed by tracking day, so "this week" means
/// seven of those days rather than 168 hours measured from the current second.
enum ExportRange: Equatable, Sendable {
    case thisWeek
    case thisMonth
    /// Two days the user picked. Only the calendar day of each date matters,
    /// and the pair is put in order if it arrives reversed.
    case custom(from: Date, to: Date)

    /// Inclusive `yyyy-MM-dd` bounds, both ends comparable as plain strings.
    ///
    /// The week and the month are anchored on the tracking day `now` falls in,
    /// so at 02:00 with an 04:00 rollover the export still belongs to
    /// yesterday's week. The week starts on the calendar's own `firstWeekday`.
    func bounds(asOf now: Date, rollover: RolloverTime, calendar: Calendar) -> (from: String, to: String) {
        switch self {
        case .thisWeek:
            return span(of: .weekOfYear, asOf: now, rollover: rollover, calendar: calendar)
        case .thisMonth:
            return span(of: .month, asOf: now, rollover: rollover, calendar: calendar)
        case let .custom(from, to):
            let first = TrackingDay.dateString(for: from, calendar: calendar)
            let second = TrackingDay.dateString(for: to, calendar: calendar)
            return first <= second ? (first, second) : (second, first)
        }
    }

    /// The calendar unit containing today's tracking day, as day strings.
    private func span(
        of component: Calendar.Component,
        asOf now: Date,
        rollover: RolloverTime,
        calendar: Calendar
    ) -> (from: String, to: String) {
        let today = TrackingDay.start(containing: now, rollover: rollover, calendar: calendar)
        guard let interval = calendar.dateInterval(of: component, for: today),
              // `interval.end` is the first instant of the *next* unit, so the
              // last day of this one is a day back from it.
              let last = calendar.date(byAdding: .day, value: -1, to: interval.end)
        else {
            let single = TrackingDay.dateString(for: today, calendar: calendar)
            NSLog("Chronos: could not resolve the \(component) containing \(today); exporting that day alone")
            return (single, single)
        }
        return (
            TrackingDay.dateString(for: interval.start, calendar: calendar),
            TrackingDay.dateString(for: last, calendar: calendar)
        )
    }
}

/// Builds the CSV behind Settings' Export button (SPEC §8).
///
/// It reads the session history straight off disk rather than from the engine,
/// because a yearly rotation moves finished sessions out of memory: the current
/// `sessions.jsonl` plus every `sessions-YYYY.jsonl` beside it is the whole
/// story. The output has the same shape as `daily-summary.csv`
/// (`date,project,seconds,hours`), so an export and the archive concatenate.
struct Exporter: Sendable {
    /// The live log. Rotated logs in the same folder are read too.
    let sessionsFileURL: URL
    /// Carries the time zone the tracking days are measured in.
    let calendar: Calendar
    let rollover: RolloverTime
    /// Names come from the current list, archived projects included; a session
    /// whose project has been deleted outright is skipped.
    let projects: [Project]

    init(
        sessionsFileURL: URL = AppPaths.sessionsFile,
        calendar: Calendar,
        rollover: RolloverTime,
        projects: [Project]
    ) {
        self.sessionsFileURL = sessionsFileURL
        self.calendar = calendar
        self.rollover = rollover
        self.projects = projects
    }

    static let header = "date,project,seconds,hours\n"

    /// One row per (tracking day, project) with time on it, ordered by date and
    /// then by the panel's project order. A session still open is measured to
    /// `now`, exactly as the panel shows it.
    func csv(for range: ExportRange, asOf now: Date) throws -> String {
        let (from, to) = range.bounds(asOf: now, rollover: rollover, calendar: calendar)
        return try csv(from: from, to: to, asOf: now)
    }

    /// The same thing for bounds that have already been resolved, so a caller
    /// naming the file after the range cannot resolve it twice and disagree.
    func csv(from: String, to: String, asOf now: Date) throws -> String {
        let sessions = try loadHistory()
        let order = Dictionary(uniqueKeysWithValues: projects.enumerated().map { ($0.element.id, $0.offset) })

        // Keyed by day and project so a day's rows can be emitted in project
        // order; the day strings sort lexicographically, which for `yyyy-MM-dd`
        // is chronological.
        var totals: [String: [UUID: TimeInterval]] = [:]
        for session in sessions {
            guard order[session.projectID] != nil else {
                NSLog("Chronos: session \(session.id) names a project that no longer exists; leaving it out of the export")
                continue
            }
            let dayStart = TrackingDay.start(containing: session.start, rollover: rollover, calendar: calendar)
            let day = TrackingDay.dateString(for: dayStart, calendar: calendar)
            guard day >= from, day <= to else { continue }
            totals[day, default: [:]][session.projectID, default: 0] += session.duration(asOf: now)
        }

        var text = Self.header
        for day in totals.keys.sorted() {
            guard let byProject = totals[day] else { continue }
            for project in projects {
                let seconds = Int(byProject[project.id] ?? 0)
                guard seconds > 0 else { continue }
                text += CSV.row([
                    day,
                    project.name,
                    String(seconds),
                    TimeFormatting.decimalHours(Double(seconds)),
                ])
            }
        }
        return text
    }

    /// A suggested file name for the save panel: `chronos-<from>_<to>.csv`.
    static func fileName(from: String, to: String) -> String {
        "chronos-\(from)_\(to).csv"
    }

    // MARK: - History

    /// Every session Chronos still has on disk: the rotated years first, oldest
    /// to newest, then the live log. A session id seen twice (a log copied by
    /// hand, say) is counted once.
    private func loadHistory() throws -> [Session] {
        var sessions: [Session] = []
        var seen: Set<UUID> = []
        for url in rotatedLogURLs() + [sessionsFileURL] {
            let loaded = try SessionLog(fileURL: url).loadSessions()
            for session in loaded where seen.insert(session.id).inserted {
                sessions.append(session)
            }
        }
        return sessions
    }

    /// `sessions-YYYY.jsonl` beside the live log, oldest year first.
    private func rotatedLogURLs() -> [URL] {
        let folder = sessionsFileURL.deletingLastPathComponent()
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        } catch {
            NSLog("Chronos: could not list \(folder.path) for rotated session logs: \(error.localizedDescription)")
            return []
        }
        return names
            .compactMap { name -> (year: Int, url: URL)? in
                guard name.hasPrefix("sessions-"), name.hasSuffix(".jsonl") else { return nil }
                let year = name.dropFirst("sessions-".count).dropLast(".jsonl".count)
                guard let value = Int(year) else { return nil }
                return (value, folder.appendingPathComponent(name, isDirectory: false))
            }
            .sorted { $0.year < $1.year }
            .map(\.url)
    }
}
