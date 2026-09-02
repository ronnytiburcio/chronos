# Chronos — project notes for Claude Code

Native macOS desktop time tracker: a clickable panel at desktop-icon window level (behind app windows), one-click project timers, automatic daily rollover that archives to CSV/markdown. Open source, MIT. Full spec: `docs/SPEC.md`. Build plan with locked decisions: `~/.claude/plans/take-a-look-at-linked-wirth.md`.

## Stack
- Swift 6 language mode, strict concurrency. SwiftUI views hosted in AppKit windows. No third-party dependencies.
- Deployment target macOS 14. Local machine runs macOS 27 beta / Xcode 27 beta; CI runs `macos-26` (Xcode 26.6). Keep APIs <= macOS 14 and avoid Xcode-27-only project features.
- App entry is pure AppKit (`Chronos/App/ChronosApp.swift` -> `AppDelegate`), not a SwiftUI `App` scene, because the app is an `LSUIElement` agent with an `NSPanel` at desktop level.

## Project definition
- `project.yml` (xcodegen) is the source of truth. `Chronos.xcodeproj` is generated and committed so cloners just open it.
- After adding/removing source files or editing `project.yml`: `xcodegen generate` then commit the regenerated xcodeproj.
- `Info.plist` is generated into `Chronos/Resources/Info.plist` by xcodegen from the `info:` block; edit `project.yml`, not the plist.

## Commands
```bash
xcodegen generate
xcodebuild -project Chronos.xcodeproj -scheme Chronos -destination 'platform=macOS' build
xcodebuild -project Chronos.xcodeproj -scheme Chronos -destination 'platform=macOS' test
open Chronos.xcodeproj
```
Run the built app: `open "$(xcodebuild -project Chronos.xcodeproj -scheme Chronos -showBuildSettings | awk '/ BUILT_PRODUCTS_DIR/{print $3}')/Chronos.app"` (or Cmd-R in Xcode). Quit via the menu bar bolt -> Quit.

## Layout
```
Chronos/App       entry, AppDelegate, MenuBarController
Chronos/Window    DesktopPanel (NSPanel subclass), PanelController, FirstMouseHostingView, DragHandleView, PanelKeyWindow, WindowPlacement
Chronos/Model     Project, Session, Settings, TrackingDay
Chronos/Engine    TimerEngine, RolloverEngine, Clock (injectable now())
Chronos/Storage   AppPaths, JSONFile, AppStateStore (state.json), ProjectStore (projects.json), SessionLog (sessions.jsonl), ArchiveWriter, Exporter
Chronos/UI        Palette, ProjectColor, TimeFormatting, PanelLayout, EscapeKeyMonitor,
                  PanelView (root) -> HeaderView / ProjectRowView (+ RowMenu) / FooterView, + BoltShape
Chronos/Resources Assets.xcassets, generated Info.plist
ChronosTests      XCTest
Scripts           render-icons.swift, make-dmg.sh
```

## Conventions
- Everything UI/model is `@MainActor`; model objects are `@Observable`.
- Totals are always computed from session timestamps, never from counters.
- "Today" = sessions with `start >= state.lastRollover`. Tracking day runs rollover-to-rollover (default 04:00).
- Storage: `sessions.jsonl` append-only (open/close records), `projects.json` + `state.json` written atomically (temp + rename).
- Archive CSV rows only for projects with > 0 seconds; empty days write nothing but still advance `lastRollover`.
- No network code, ever. No personal names/paths in the repo; all paths from `FileManager`.
- Build in vertical slices; each phase ends runnable. Verify gate = `/phase-review` (+ `/code-review` for phases 2, 3, 5).

## Gotchas
- `DesktopPanel` must be created with `.nonactivatingPanel` in the style mask at init and never mutated afterwards, or keyboard input silently breaks.
- Window level is `CGWindowLevelForKey(.desktopIconWindow) + 1` so Finder's desktop-icon layer cannot swallow clicks. Verified live: the panel reports `kCGWindowLayer == -2147483602`.
- `NSHostingView` subclass overrides `acceptsFirstMouse` so the first click acts without activating the app.
- The panel's content view is the `NSVisualEffectView`; the hosting view is its subview. Rounded corners live on the effect view's layer (`cornerRadius` + `masksToBounds`), which is also what gives the window a rounded shadow.
- `.hudWindow` follows the *system* appearance, so the panel pins `appearance = NSAppearance(named: .darkAqua)` and adds an Ink `#15171C` tint view between the material and the hosting view. Without both, the panel reads as light grey glass on a light wallpaper and SPEC §9's Paper text is unreadable.
- `WindowPlacement.resolvedFrame` honours the saved *origin* but always applies the caller's size, so a frame saved by an older build cannot resurrect a stale panel height.
- `AppState.windowFrame` is encoded with named keys (`x`, `y`, `width`, `height`) via a custom `Codable`; `CGRect`'s synthesized Codable would write nested arrays.
- `ChronosTests` uses the app as its test host. `AppDelegate` skips all setup when `XCTestConfigurationFilePath` is in the environment, so tests never show the panel or touch the real state file. Tests that touch storage still take an injected file URL and use a temp directory.
- **`TimerEngine` is the single owner of `AppState`** (window frame, `lastRollover`, `settings`) and the only writer of `state.json`. `AppDelegate` builds it at launch and hands its `windowFrame` to `PanelController`, whose frame-change closure calls `engine.updateWindowFrame(_:)`. One owner means a frame save can never clobber the rollover bookkeeping sitting in the same file — do not add a second writer.
- `TimerEngine` takes `Clock`, `ProjectStore`, `SessionLog`, `AppStateStore`, and a `Calendar` in its init so tests run against temp dirs and a fake clock. Every mutation is write-through: it persists before the method returns.
- The 1s ticker only runs while a session is open, and `tick()` re-reads `clock.now()` rather than accumulating, so sleep/wake stays correct. It is a target/selector `Timer` on `RunLoop.main` in `.common` mode whose target (`TickTarget`) holds the engine weakly; do not switch it to a block-based timer, which would capture the engine strongly (and `Timer` is not `Sendable` under Swift 6).
- `SessionLog` replay is forgiving: a corrupt line, a leading BOM, a `close` with no `open`, or a duplicate `open` is logged via `NSLog` and skipped, never thrown; an `open` while another session is still open closes the earlier one at the new start. `rotate(to:)` refuses to overwrite an existing archive.
- Dates in every JSON file go through `JSONDates` (ISO-8601 with fractional seconds; whole-second input still parses).
- `TimerEngine.start` clamps the session start to `lastRollover` so a backward clock jump cannot start a session outside today.
- Tests for `@MainActor` types override `setUp() async throws` / `tearDown() async throws`, not the `WithError` variants — only the async hooks inherit the class's actor isolation, otherwise every shared property is a concurrency warning.
- `WindowPlacement` validates a saved frame against full screen frames (the user may park the panel under the Dock) and uses the main screen's `visibleFrame` only for first-launch placement.
- All JSON goes through `JSONFile` (atomic `Data.write`, ISO-8601 dates, sorted keys). Colors come from `Palette` in `Chronos/UI/Palette.swift`.
- **Panel height is `PanelLayout.height(rowCount:)`, pure arithmetic, not measured layout.** `PanelController` sizes the window from it at launch, and `PanelView` reports a new height through `onDesiredHeightChange` when `engine.visibleProjects.count` changes. The view's constants (`headerHeight`, `footerHeight`, `rowHeight`) are applied with `.frame(height:)` on the matching views, so the arithmetic and the drawing cannot drift — change one and change the other. Resizing keeps the panel's **top** edge fixed (Cocoa origin is bottom-left, so `origin.y` moves by the delta) and never animates. Note the asymmetry across launches: `WindowPlacement` restores the saved *origin* and applies the new size, so a relaunch with a different project count keeps the bottom-left corner, not the top.
- **Buttons in the panel must be `.buttonStyle(.plain)` over a `.contentShape(Rectangle())`.** Bordered/prominent styles want focus before they act, which costs a click in a panel that never activates. Plain buttons fire on the first mouse-down (with `FirstMouseHostingView`'s `acceptsFirstMouse`).
- **Inline text fields need `await PanelKeyWindow.makeKey()` before setting focus.** The panel is `becomesKeyOnlyIfNeeded = true`, so a field that *appears* after a button press never gets key status on its own. `panel.makeKey()` works (verified live: the panel reports `isKeyWindow == true` while Chrome stays frontmost, and typed characters land in the field) — but the `@FocusState` must be set on the *next* run-loop turn, because `makeKey()` leaves the panel itself as first responder and a same-pass focus is thrown away.
- **Row menus are AppKit `NSMenu`s (`RowMenu.swift`), opened from the row's `•••` button and from right-click via `menu(for:)`.** SwiftUI's `.contextMenu` never appears in the live panel because Chronos is never the active app; an `NSMenu` popped from an `NSView` works regardless (the same way status-bar menus do).
- **Escape needs a local `NSEvent` monitor (`View.onEscape(while:perform:)`).** Neither `onExitCommand` nor `onKeyPress(.escape)` fires while a SwiftUI `TextField` is editing on macOS 14+; both were tried in the live panel and neither reached the view. The monitor stores its action on a `@MainActor` class so nothing non-`Sendable` is captured by the `@Sendable` monitor closure, and only `Void` crosses out of `MainActor.assumeIsolated` (`NSEvent` is not `Sendable`).
- `MenuBarController` refreshes off `withObservationTracking` on the engine (`now`, `openSession`, `projects`, `settings`), re-arming inside the `onChange` hop; there is no second timer. `onChange` fires before the value is applied and off the main actor, hence the `Task { @MainActor ... }`. Re-arming also refreshes, so refresh exactly once per change.
- Ad-hoc code signing (`CODE_SIGN_IDENTITY=-`) is required even for local runs: `SMAppService` login-item registration fails on unsigned binaries.
- Writing to `~/Documents` triggers a one-time TCC prompt; `NSDocumentsFolderUsageDescription` is set in `project.yml`.
- `CGWindowListCreateImage` is obsoleted (macOS 15+); to screenshot the panel over the wallpaper, use ScreenCaptureKit with an `SCContentFilter` that excludes windows with `windowLayer >= 0`.
