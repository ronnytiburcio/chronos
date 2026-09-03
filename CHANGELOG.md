# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-09-02

### Added

- **Desktop panel.** A borderless, non-activating `NSPanel` at desktop-icon
  window level: visible on the desktop behind every app window, on all Spaces,
  draggable by its header, with its position remembered across launches.
  Clicking it never steals focus from the app you are working in.
- **One-click timers.** A fixed project list; click a row to start it, click
  again to stop, click another to switch. Only one project runs at a time.
  Rows show today's total in `H:MM:SS`, ticking live. Add, rename, recolor,
  reorder, and archive projects from the panel or from Settings.
- **Daily rollover and archive.** At the configurable rollover time (default
  04:00) Chronos closes the running session, appends the day to
  `daily-summary.csv` and `sessions.csv`, writes a `daily/YYYY-MM-DD.md` note,
  and zeroes the panel. Days missed while the Mac was asleep or the app was
  quit are caught up in order on next launch. The footer's reset button runs
  the same routine on demand.
- **Settings window.** Rollover time, archive folder, launch at login, restart
  the running project after rollover, markdown daily notes, elapsed time in the
  menu bar, and full project management.
- **Export.** A CSV summary for this week, this month, or a custom date range,
  saved wherever you choose.
- **Review window.** A dark dashboard over the whole history: today, this week
  and this month with their deltas against the previous period, the selected
  period split by project, a bar chart of the last 7 or 30 tracking days, and
  insight lines for the busiest day, the average across tracked days, the
  current streak, and the longest session. Opens from the panel's chart button
  or the menu bar's `Review…`.
- **Menu bar item.** A bolt that fills and turns red while a timer runs, with
  optional elapsed time, quick-start for any project, show/hide panel,
  Settings, and Quit.
- **Launch at login** via `SMAppService`, on by default and approvable in
  System Settings.
