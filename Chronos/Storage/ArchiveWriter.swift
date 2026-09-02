import Foundation

/// Writes the human-readable archive (SPEC §8): the two CSVs everything else
/// can read, plus an optional markdown note per day.
///
/// The CSVs are append-only — one rollover adds its rows to the end and never
/// rewrites what is already there — so the header is written exactly once, when
/// the file is created. The markdown note is a whole file per day and is
/// overwritten, which is what makes a second manual reset on the same day
/// rewrite the note with that reset's rows.
///
/// Everything is written through a `FileHandle` seek-to-end rather than by
/// reading, editing, and rewriting the file: a year of rollovers must not get
/// slower, and a crash mid-append can cost at most the last line.
struct ArchiveWriter: Sendable {
    /// The archive folder, created on first write.
    let folder: URL
    /// Carries the time zone the day boundaries and session timestamps are
    /// expressed in, so the CSV agrees with what the panel showed.
    let calendar: Calendar
    /// SPEC §8's "markdown daily notes" setting.
    let writesMarkdownNotes: Bool

    init(folder: URL, calendar: Calendar, writesMarkdownNotes: Bool = true) {
        self.folder = folder
        self.calendar = calendar
        self.writesMarkdownNotes = writesMarkdownNotes
    }

    var summaryFile: URL { folder.appendingPathComponent("daily-summary.csv", isDirectory: false) }
    var sessionsFile: URL { folder.appendingPathComponent("sessions.csv", isDirectory: false) }
    var dailyNotesDirectory: URL { folder.appendingPathComponent("daily", isDirectory: true) }

    func markdownFile(for dateString: String) -> URL {
        dailyNotesDirectory.appendingPathComponent("\(dateString).md", isDirectory: false)
    }

    // MARK: - Writing

    func write(day: ArchivedDay) throws {
        // Everything that fails for a permissions reason fails here, before a
        // single row is appended, so a retry into the fallback folder never
        // files half a day twice.
        try prepare()
        try append(summaryRows(for: day), to: summaryFile)
        try append(sessionRows(for: day), to: sessionsFile)
        guard writesMarkdownNotes else { return }
        try writeMarkdown(for: day)
    }

    /// Creates the folder and the CSV files (with their headers) and checks
    /// they can be written to.
    private func prepare() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        try ensureHeader(Self.summaryHeader, at: summaryFile)
        try ensureHeader(Self.sessionsHeader, at: sessionsFile)
        if writesMarkdownNotes {
            try manager.createDirectory(at: dailyNotesDirectory, withIntermediateDirectories: true)
        }
        for url in [summaryFile, sessionsFile] where !manager.isWritableFile(atPath: url.path) {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: url.path])
        }
    }

    /// Writes the header when the file is missing — or present but empty, as
    /// a placeholder left by a sync client or a curious user would be.
    private func ensureHeader(_ header: String, at url: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: url.path) {
            let size = (try manager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            guard size == 0 else { return }
        }
        try Data(header.utf8).write(to: url, options: .atomic)
    }

    private static let summaryHeader = "date,project,seconds,hours\n"
    private static let sessionsHeader = "date,project,start,end,seconds\n"

    private func summaryRows(for day: ArchivedDay) -> String {
        day.totals.reduce(into: "") { rows, total in
            let seconds = Int(total.seconds)
            rows += CSV.row([
                day.dateString,
                total.name,
                String(seconds),
                // Hours to two decimals, for the spreadsheet that does not
                // want to divide by 3600 itself.
                String(format: "%.2f", Double(seconds) / 3600),
            ])
        }
    }

    private func sessionRows(for day: ArchivedDay) -> String {
        // One formatter for the whole day: building an `ISO8601DateFormatter`
        // is not cheap, and a day can hold a lot of sessions.
        let formatter = timestampFormatter()
        return day.sessions.reduce(into: "") { rows, session in
            // The timestamps print whole seconds, so the seconds column is
            // the difference of those same whole seconds: the three columns
            // always reconcile.
            let startSecond = floor(session.start.timeIntervalSince1970)
            let endSecond = floor(session.end.timeIntervalSince1970)
            rows += CSV.row([
                day.dateString,
                session.projectName,
                formatter.string(from: session.start),
                formatter.string(from: session.end),
                String(Int(max(0, endSecond - startSecond))),
            ])
        }
    }

    private func writeMarkdown(for day: ArchivedDay) throws {
        var text = "# \(AppInfo.name) — \(day.dateString)\n"
        text += "**Total:** \(TimeFormatting.hoursMinutes(day.totalSeconds))\n\n"
        text += "| Project | Time |\n|---|---|\n"
        for total in day.totals {
            text += "| \(total.name) | \(TimeFormatting.hoursMinutes(total.seconds)) |\n"
        }

        // Whole file, replaced: a second reset on the same day rewrites the
        // note rather than stacking two tables in it.
        try Data(text.utf8).write(to: markdownFile(for: day.dateString), options: .atomic)
    }

    // MARK: - Appending

    private func append(_ text: String, to url: URL) throws {
        guard !text.isEmpty else { return }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    // MARK: - Timestamps

    /// ISO-8601 with the local UTC offset (`2026-09-02T09:15:00-04:00`), so a
    /// row read months later still says what time of day it was.
    private func timestampFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = calendar.timeZone
        return formatter
    }
}
