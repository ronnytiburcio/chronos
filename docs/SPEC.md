# Chronos — Desktop Time Tracker

> A floating, clickable panel that lives on the macOS desktop. One click starts the clock on a project, one click stops it. At the end of every day, Chronos tallies the totals, archives them to a file, and resets for tomorrow.

Open source (MIT). Built because nothing on GitHub does this simple loop: fixed project list → click on/off → auto-tally, archive, and reset every day.

---

## 1. Goals

- **One-click tracking.** A fixed list of projects. Click one to start timing it; click again to stop. Only one project can be running at a time — starting another stops the current one.
- **Always visible, never in the way.** Sits on the desktop *behind* app windows (like a widget), not floating over them. Visible when the desktop is visible.
- **Automatic end-of-day.** At the daily rollover, close any running timer, write the day's totals to a log, and reset the display to zero.
- **Reviewable history.** Every day's results land in a plain file that can be opened, charted, or fed into another tool later.
- **Local and private.** No accounts, no cloud, no telemetry. Everything on disk.

## 2. Non-goals (v1)

- Invoicing, billing rates, or client management.
- Cloud sync, mobile app, team features.
- Automatic activity detection (what app/site is open).
- Manual editing of sessions from *previous* days (today's can be corrected in the session editor).

## 3. Platform & stack

- **macOS 14+ (Sonoma or later).** Apple Silicon and Intel.
- **Native Swift: SwiftUI for the UI, AppKit for the window.** This is a deliberate choice: a panel that sits at desktop level *and* accepts clicks requires an `NSPanel`/`NSWindow` with a custom window level. Electron/Tauri "desktop" windows on macOS are non-interactive, so they don't work here. Native Apple widgets (WidgetKit) are also read-only — which is why the existing desktop widgets can't be clicked.
- **No external dependencies.** Foundation, SwiftUI, AppKit only.
- Distributed as a single `.app` via GitHub Releases (see §11). Runs as a background agent (`LSUIElement = YES`) — no Dock icon, small menu bar icon for quit/settings.

## 4. Window behavior

| Behavior | Spec |
|---|---|
| Chrome | Borderless, transparent background, rounded corners (~14pt), subtle shadow. |
| Window level | Desktop-icon level: `NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))`. Above the wallpaper, below every app window. Must still receive mouse events. |
| Focus | Never steals focus. Clicking a button should not bring Chronos "to the front" or activate it as an app. |
| Spaces | Visible on all Spaces (`collectionBehavior: [.canJoinAllSpaces, .stationary]`). Ignores Mission Control / Exposé rearrangement. |
| Dragging | Draggable by the header area only. Position is saved and restored across launches. |
| Size | ~280pt wide. Height grows with the project list (min ~200pt, max ~600pt, then scrolls). |
| Launch | Option to launch at login (SMAppService). Default on. |

## 5. UI layout

```
┌──────────────────────────────────┐
│  ⚡ CHRONOS            Tue Sep 2 │   ← header: logo mark, name, date (drag handle)
│  Today  3h 42m                   │   ← live day total
├──────────────────────────────────┤
│  ● Client Work          1:52:10  │   ← ACTIVE row: highlighted, clock ticking
│  ○ Side Project         0:48:00  │
│  ○ Admin / Finance      1:02:15  │
│  ○ Learning             0:00:00  │
├──────────────────────────────────┤
│  + Add project        ⟳  ⚙       │   ← footer: add, manual reset, settings
└──────────────────────────────────┘
```

### Project row
- Whole row is the click target (large hit area, no tiny buttons).
- Left indicator: filled/pulsing dot when active, hollow when idle. Optional per-project color.
- Right: today's accumulated time for this project, `H:MM:SS`, updating every second when active.
- Active row gets a tinted background and a bolt glyph next to the name.
- Right-click (or long-press) → context menu: Rename, Change color, Move up/down, Archive.

### Header
- Original lightning-bolt mark (see §9), app name, today's date.
- Day total in large tabular numerals.
- Dragging the header moves the window.

### Footer
- **Add project** — inline text field, Enter to save.
- **Reset** (⟳) — manually trigger the end-of-day rollover now (archives, then zeroes). Confirm first.
- **Settings** (⚙) — opens a small standard window (see §8).

### States
- **Idle:** all rows hollow, no ticking.
- **Running:** exactly one row active. Menu bar icon shows a filled bolt + optional elapsed time.
- **Empty:** no projects → friendly prompt to add the first one.

## 6. Timer engine

- Everything is a **session**: `{ id, projectId, start: Date, end: Date? }`.
- Starting a project: if another session is open, close it (`end = now`), then open a new one.
- Stopping: close the open session.
- Today's total per project = sum of sessions where `start` falls in the current tracking day (see §7), including the open one (computed live).
- **Crash safety:** the open session is written to disk immediately on start. On launch, if an open session exists, resume it (clock keeps counting from the original start). If the open session's start is before the last rollover, close it at the rollover time and archive it to that day.
- **Sleep/wake:** on wake, recompute totals from timestamps (never from an in-memory counter) so time stays correct.
- Idle detection (auto-pause after N minutes of no input): **v2**.

## 7. Daily rollover

- **Rollover time** is configurable; default **04:00**. (Late-night work stays attached to the day it belongs to.)
- A "tracking day" runs from rollover to rollover.
- At rollover:
  1. Close any open session at the rollover timestamp.
  2. Write the day's summary + sessions to the archive (§8).
  3. Reset the displayed totals to zero.
  4. If the same project was running, optionally restart it in the new day (setting, default **off**).
- If the Mac is asleep or Chronos isn't running at rollover, perform the rollover on next launch/wake for each missed day, in order.
- Manual reset (⟳) runs the same routine immediately.

## 8. Storage & archive

### App data (source of truth)
`~/Library/Application Support/Chronos/`
- `projects.json` — `[{ id, name, color, sortOrder, archived }]`
- `sessions.jsonl` — all sessions, append-only (`open`/`close`/`adjust`/`delete` records, rotate yearly)
- `state.json` — window position, open session id, last rollover date, settings

### Human-readable archive (for review later)
Default `~/Documents/Chronos/` (changeable in Settings):

- `daily-summary.csv` — one row per project per day, appended at every rollover:
  ```
  date,project,seconds,hours
  2026-09-02,Client Work,6730,1.87
  2026-09-02,Side Project,2880,0.80
  ```
- `sessions.csv` — one row per session: `date,project,start,end,seconds`
- `daily/2026-09-02.md` — optional markdown note per day (setting, default on):
  ```
  # Chronos — 2026-09-02
  **Total:** 3h 42m

  | Project | Time |
  |---|---|
  | Client Work | 1h 52m |
  | Side Project | 0h 48m |
  ```
- **Export** button in Settings: build a summary for any date range (week / month / custom) as CSV.

CSV first, because it drops straight into Numbers/Sheets/Python and can feed a dashboard later.

### Settings window
- Rollover time
- Archive folder location
- Launch at login
- Restart running project after rollover (on/off)
- Write markdown daily notes (on/off)
- Show elapsed time in menu bar (on/off)
- Manage projects (reorder, rename, color, archive/unarchive)
- Export date range

### Session editor
A small dedicated window, opened from a project row's `•••` menu ("Edit today's sessions…") or the menu bar's "Edit Sessions…" item, for fixing a timer that ran too long or was started on the wrong project.

- **Today only.** It lists sessions whose start is at or after the last rollover. Everything older has already been written into the append-only archive CSVs, so correcting it would mean rewriting a day that has been filed — out of scope until that becomes its own storage change (v2, see §14).
- Each row shows the project, a start time picker, and either an end time picker or "Running" with a "Stop at…" button that stops the timer as of the picked time.
- A row can be reassigned to a different project, corrected, or deleted (with a confirmation).
- Overlapping sessions are allowed and shown: the row surfaces an informational caption naming what it overlaps, but never blocks Save. An hour that lands in two overlapping sessions is counted in both totals.
- A time picker only shows hours and minutes, so a value near midnight is snapped onto whichever side of the 04:00 (default) rollover boundary it actually belongs to — a session that started at 01:30 and a "23:00" pick means the previous evening, not 22 hours in the future.

## 9. Visual design

**Concept:** speed and lightning — a god of time who moves fast.

- **Logo mark:** an original stylized lightning bolt, designed from scratch for Chronos. Keep it simple and geometric so it reads at 16pt (menu bar) and 28pt (header). Ship as an SF-Symbol-style vector asset in the asset catalog, plus the app icon. Do not reproduce any existing character emblem or licensed artwork.
- **Palette:**
  - Scarlet `#D7262F` — active state, bolt mark, accents
  - Gold `#F2B233` — day total, highlights
  - Ink `#15171C` — panel background (dark glass, ~92% opacity, `NSVisualEffectView` .hudWindow material acceptable)
  - Paper `#F4F5F7` — primary text
  - Muted `#8C93A1` — secondary text, idle rows
- **Type:** SF Pro for labels; SF Mono (tabular numerals) for all times.
- **Motion:** active dot pulses gently; the bolt in the header does a quick flicker when a timer starts. Respect Reduce Motion.
- **Appearance:** dark by default. Light variant optional (v2).

## 10. Menu bar item

- Bolt icon. Filled/red when a timer is running, outline when idle.
- Optional text: `1:52` (elapsed on the active project).
- Menu: current project + Stop, quick-start list of projects, Show/Hide panel, Settings…, Quit.

## 11. Open source & distribution

Chronos is a public GitHub repository. Build it as a project other people can clone, build, and run — not as a personal tool.

### Repo
- **License:** MIT (`LICENSE` in root).
- **Repo layout:**
  ```
  Chronos/
  ├── Chronos.xcodeproj
  ├── Chronos/            # source
  ├── Assets/             # logo mark, app icon source, screenshots
  ├── README.md
  ├── LICENSE
  ├── CONTRIBUTING.md
  ├── CHANGELOG.md
  └── .github/
      ├── workflows/build.yml
      └── ISSUE_TEMPLATE/ (bug, feature)
  ```
- **No personal data in the repo.** No hard-coded project names, usernames, or absolute paths. All paths derive from `FileManager` standard directories. Ship with an empty project list (the app shows the "add your first project" state on first launch).
- `.gitignore` for Xcode: `xcuserdata/`, `DerivedData/`, `*.xcuserstate`, `.DS_Store`.

### README must include
1. One-paragraph pitch + a screenshot/GIF of the panel on a desktop.
2. Why it exists (the gap: no simple desktop-widget tracker with daily auto-archive).
3. Features list (short).
4. **Install:** download the `.dmg` from Releases → drag to Applications → first launch. If the build is unsigned, document the right-click → Open (or `xattr -d com.apple.quarantine`) step honestly.
5. **Build from source:** Xcode version, `xcodebuild` one-liner.
6. Where data lives (§8 paths) and the CSV/markdown formats, so people can pipe the output into their own tools.
7. Settings overview.
8. Roadmap (v2 list) and how to contribute.
9. Credits / license.

### Releases
- Semantic versioning, starting at `v0.1.0`. Tag pushes trigger the workflow.
- GitHub Actions workflow: builds a **universal binary** (arm64 + x86_64), packages a `.dmg`, attaches it to the GitHub Release.
- Signing/notarization with a Developer ID is **optional** — make the workflow support it via repository secrets, but succeed without them. Unsigned builds are fine for v0.x; document the Gatekeeper workaround.
- `CHANGELOG.md` updated per release (Keep a Changelog format).
- Stretch: a Homebrew cask (`brew install --cask chronos`) once there's a stable release.

### Contributing
- `CONTRIBUTING.md`: how to build, code style (SwiftFormat defaults), PR expectations, that features should stay within the "simple daily tracker" scope.
- Issue templates for bugs and feature requests.
- Keep the app free of analytics, telemetry, and network calls — state this in the README as a promise.

## 12. Build plan (suggested order for Claude Code)

1. **Scaffold** — SwiftUI app, `LSUIElement`, menu bar item with Quit. Confirm it launches with no Dock icon.
2. **The window** — borderless, transparent `NSPanel` at desktop-icon level, all Spaces, receives clicks, draggable, position persisted. *This is the hard part; prove it before building UI.*
3. **Data layer** — `Project`, `Session`, JSON persistence, `TimerEngine` with start/stop/resume + live totals computed from timestamps.
4. **Panel UI** — header, project rows, footer. Wire clicks to the engine. Live ticking.
5. **Rollover** — scheduled rollover, missed-rollover catch-up, manual reset, archive writers (CSV + markdown).
6. **Settings window** — all §8 settings, project management, export.
7. **Polish** — logo mark, app icon, animations, launch at login.
8. **Ship** — README with screenshots, LICENSE, CONTRIBUTING, CHANGELOG, GitHub Actions release workflow, tag `v0.1.0`.

## 13. Acceptance criteria

- [ ] Panel is visible on the desktop, behind app windows, on every Space, and survives Mission Control.
- [ ] Clicking a project row starts it; clicking again stops it; clicking a different row switches. Never two running at once.
- [ ] Clicking the panel does not activate Chronos or steal focus from the current app.
- [ ] Quit Chronos mid-session, relaunch → the same project is still running with the correct elapsed time.
- [ ] Sleep the Mac for 10 minutes mid-session → elapsed time is correct on wake.
- [ ] At the rollover time, totals reset to zero and `daily-summary.csv`, `sessions.csv`, and `daily/YYYY-MM-DD.md` are written correctly.
- [ ] Chronos is closed overnight → on next launch, the missed day is archived before the new day starts.
- [ ] Manual reset produces the same output as an automatic rollover.
- [ ] Window position, project list, and settings persist across launches.
- [ ] No network access of any kind.
- [ ] A stranger can clone the repo, open it in Xcode, and build it with no extra setup.
- [ ] Pushing a version tag produces a downloadable `.dmg` on GitHub Releases.
- [ ] Repo contains no personal names, paths, or data.

## 14. Later (v2 ideas)

- Idle detection with "keep / discard" prompt.
- Edit or delete sessions from earlier days (re-archiving).
- Add a session that was never tracked (needs its own `add` record: an `open`+`close` pair would trip replay's force-close rule).
- Weekly/monthly review view inside the app, styled like the Financial Snapshot dashboard.
- Global keyboard shortcut to toggle the last-used project.
- Notes tagged to a session.
