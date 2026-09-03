import AppKit
import SwiftUI

/// Owns the review window (Phase 9): an ordinary titled window in the app's own
/// dark clothes, created on first open and reused afterwards.
///
/// This is the **second** place in Chronos that calls `NSApp.activate`, after
/// ``SettingsWindowController``, and for the same reason: Chronos is an
/// `LSUIElement` agent, so a window it puts on screen opens behind whatever is
/// frontmost and ignores the keyboard until the app is activated. The desktop
/// panel still never activates anything — that rule is about the panel, not
/// about windows the user explicitly asked for.
@MainActor
final class ReviewWindowController {
    private let engine: TimerEngine
    private var window: NSWindow?

    init(engine: TimerEngine) {
        self.engine = engine
    }

    /// Shows the window, building it the first time and centring it then only:
    /// a window the user has moved stays where they put it.
    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: ReviewScreen(engine: engine))
        controller.preferredContentSize = NSSize(
            width: ReviewView.contentSize.width,
            height: ReviewView.contentSize.height
        )

        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = "\(AppInfo.name) Review"
        window.setContentSize(NSSize(
            width: ReviewView.contentSize.width,
            height: ReviewView.contentSize.height
        ))
        window.contentMinSize = NSSize(
            width: ReviewView.contentSize.width,
            height: ReviewView.contentSize.height
        )
        // The dashboard is Ink-on-Paper whatever the system appearance is, so
        // the title bar has to be told as well as the content.
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Palette.ink.nsColor
        // The agent has no Dock icon to restore from, so closing must not
        // deallocate the window out from under a later Review… click.
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

/// The stateful shell around ``ReviewView``: it owns the selected period and
/// the snapshot, and decides when to recompute.
///
/// The snapshot is built from the history **on disk** (``SessionHistory``)
/// rather than from ``TimerEngine/sessions``, because a yearly rotation has
/// already trimmed memory back to the current year — a month view in January
/// would otherwise lose December.
///
/// Refresh policy, deliberately not per second: on open, whenever the engine
/// gains or closes a session, when the period changes, and once a minute while
/// the window is on screen so an open session's numbers keep moving. Reading
/// `engine.now` here would redraw the whole dashboard every tick for a display
/// that only shows whole minutes.
struct ReviewScreen: View {
    let engine: TimerEngine

    /// How often an open session's numbers are refreshed while the window is
    /// visible. The dashboard shows `Xh Ym`, so a minute is as fine as it gets.
    private static let refreshInterval = Duration.seconds(60)

    @State private var period: ReviewPeriod = .week
    @State private var snapshot: ReviewSnapshot = .empty()

    var body: some View {
        ReviewView(snapshot: snapshot, period: $period)
            .onAppear { refresh() }
            .onChange(of: period) { _, _ in refresh() }
            // Both together: the count catches a session starting or being
            // recorded, the id catches the running one being stopped.
            .onChange(of: engine.sessions.count) { _, _ in refresh() }
            .onChange(of: engine.openSession?.id) { _, _ in refresh() }
            .task {
                // Cancelled when the window closes, restarted when it reopens.
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.refreshInterval)
                    guard !Task.isCancelled else { break }
                    refresh()
                }
            }
    }

    /// Rebuilds the snapshot. The read is synchronous, like the export's: the
    /// log is a few hundred kilobytes at worst and this runs at most once a
    /// minute.
    private func refresh() {
        let sessions: [Session]
        do {
            sessions = try engine.sessionHistory.load()
        } catch {
            NSLog("Chronos: could not read the session history for the review window: \(error.localizedDescription)")
            // Memory is still a true view of the current year, which is most
            // of what the dashboard shows.
            sessions = engine.sessions
        }

        snapshot = ReviewStats.snapshot(
            sessions: sessions,
            projects: engine.projects,
            period: period,
            now: engine.clock.now(),
            rollover: engine.settings.rollover,
            calendar: engine.trackingCalendar
        )
    }
}
