## What this changes

<!-- One or two sentences, plus the issue it closes if there is one. -->

## Checklist

- [ ] Builds and the test suite passes:
      `xcodebuild -project Chronos.xcodeproj -scheme Chronos -destination 'platform=macOS' test`
- [ ] Ran `xcodegen generate` and committed the regenerated `Chronos.xcodeproj`
      (only if source files or `project.yml` changed)
- [ ] Tests added or updated for engine/storage changes
- [ ] `CLAUDE.md` gotchas updated if this change invalidates or adds one
- [ ] `CHANGELOG.md` updated under `## [Unreleased]` if this is user-visible
- [ ] No network calls, analytics, or third-party dependencies added
- [ ] No personal names, usernames, or absolute paths added
- [ ] Stays inside the "simple daily tracker" scope (see CONTRIBUTING.md)
