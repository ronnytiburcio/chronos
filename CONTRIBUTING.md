# Contributing to Chronos

Thanks for looking. Chronos is small on purpose, and the goal is to keep it
that way — see [Scope](#scope) before opening a pull request for a new feature.

## Build and test

You need **Xcode 16 or newer** on **macOS 14 or newer**. There are no external
dependencies to fetch.

```bash
git clone <this repository>
cd Chronos
open Chronos.xcodeproj          # or build from the command line:

xcodebuild -project Chronos.xcodeproj -scheme Chronos -destination 'platform=macOS' build
xcodebuild -project Chronos.xcodeproj -scheme Chronos -destination 'platform=macOS' test
```

The app is an `LSUIElement` agent: running it shows a panel on the desktop and
a bolt in the menu bar, never a Dock icon. Quit from the menu bar bolt.

`Chronos.xcodeproj` is committed so a clone opens and builds with no extra
setup, but it is **generated**. `project.yml` is the source of truth.

## Code style

- **SwiftFormat defaults.** No custom rule set; run `swiftformat .` before
  sending a change if you have it installed.
- Swift 6 language mode with complete strict concurrency. Everything UI- or
  model-facing is `@MainActor`; model objects are `@Observable`.
- Totals are always computed from session timestamps, never from counters.
- No third-party dependencies, and no network code of any kind.
- No personal names, usernames, or absolute paths anywhere in the repository.
  All paths come from `FileManager` standard directories. CI fails the build
  if that changes.

### After adding or removing source files

`project.yml` (xcodegen) defines the project. If you add, remove, or move a
file, or edit `project.yml` itself:

```bash
xcodegen generate
```

Then commit the regenerated `Chronos.xcodeproj` alongside your change.
`Chronos/Resources/Info.plist` is generated the same way — edit the `info:`
block in `project.yml`, never the plist.

### After changing the bolt mark

The lightning bolt is one polygon written down in two places:
`BoltShape.points` (`Chronos/UI/BoltShape.swift`) and `boltPoints` in
`Scripts/render-icons.swift`. A test pins them together, so change both, then
regenerate every raster asset from the repository root:

```bash
swift Scripts/render-icons.swift
```

That script owns the app icon set, the menu bar template images, and the
artwork in `Assets/`. Do not hand-edit those files.

## Pull requests

- **One change per pull request**, with a description of what it does and why.
- **Tests are expected for engine and storage changes.** `TimerEngine`,
  rollover, `SessionLog`, `ArchiveWriter`, `Exporter`, and the tracking-day
  math are all covered by `ChronosTests`; a change in that layer should come
  with a test that fails without it. UI-only changes do not need one.
- Tests take injected file URLs and a fake clock, and write into a temp
  directory. Never let a test touch `~/Documents` or the real Application
  Support folder.
- **Keep `CLAUDE.md` current.** It is the project's living list of gotchas —
  the non-obvious facts about AppKit panels, focus, storage, and rollover that
  cost someone a day to discover. If your change invalidates one or teaches a
  new one, edit it in the same pull request.
- Update `CHANGELOG.md` under `## [Unreleased]` for anything user-visible.
- The build and the test suite must be green on `macos-26` in CI.

## Scope

Chronos is a **simple daily tracker**: a fixed project list, one click on, one
click off, an automatic archive at the end of the day. Features that fit that
sentence are welcome. Features that do not are not, however well built:

- No cloud sync, accounts, or team features.
- No network calls, analytics, or telemetry — ever. This is a promise made in
  the README, and a pull request that breaks it will be declined.
- No invoicing, billing rates, or client management.

Ideas already on the list live in the README's
[Roadmap](README.md#roadmap). If you want to build one of those, open an issue
first so we can agree on the shape of it before you spend the time.
