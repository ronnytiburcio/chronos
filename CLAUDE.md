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
Chronos/Window    DesktopPanel (NSPanel subclass), PanelController, drag handle
Chronos/Model     Project, Session, Settings, TrackingDay
Chronos/Engine    TimerEngine, RolloverEngine, Clock (injectable now())
Chronos/Storage   AppDataStore (projects.json, sessions.jsonl, state.json), ArchiveWriter, Exporter
Chronos/UI        SwiftUI views + BoltShape
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
- Window level is `CGWindowLevelForKey(.desktopIconWindow) + 1` so Finder's desktop-icon layer cannot swallow clicks.
- `NSHostingView` subclass overrides `acceptsFirstMouse` so the first click acts without activating the app.
- Ad-hoc code signing (`CODE_SIGN_IDENTITY=-`) is required even for local runs: `SMAppService` login-item registration fails on unsigned binaries.
- Writing to `~/Documents` triggers a one-time TCC prompt; `NSDocumentsFolderUsageDescription` is set in `project.yml`.
