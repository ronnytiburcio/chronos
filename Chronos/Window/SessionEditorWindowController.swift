import AppKit
import Observation
import SwiftUI

/// Which project the session editor is filtered to.
///
/// Owned by the window controller rather than by the view, so opening the
/// editor a second time from a different project's row re-filters the window
/// that is already on screen instead of leaving it showing the old project.
@MainActor
@Observable
final class SessionEditorState {
    /// `nil` means "all projects" — what the menu bar item opens with.
    var projectFilter: UUID?

    init(projectFilter: UUID? = nil) {
        self.projectFilter = projectFilter
    }
}

/// Owns the session editor window: an ordinary titled window, created on first
/// open and reused afterwards, in the same shape as ``SettingsWindowController``.
///
/// This, ``SettingsWindowController`` and ``ReviewWindowController`` are the
/// three places in Chronos that call `NSApp.activate`. Everything else goes out
/// of its way *not* to steal focus (the desktop panel never activates the app
/// at all), but a window the user has just asked for has to come forward and
/// take the keyboard — Chronos is an `LSUIElement` agent, so without the
/// activate it would open behind whatever is frontmost and ignore every
/// keystroke.
@MainActor
final class SessionEditorWindowController {
    /// Wide enough for a project picker, two time pickers and the buttons on
    /// one line; tall enough for a few sessions before the form scrolls.
    static let contentSize = NSSize(width: 520, height: 420)

    private let engine: TimerEngine
    private let state = SessionEditorState()
    private var window: NSWindow?

    init(engine: TimerEngine) {
        self.engine = engine
    }

    /// Shows the window filtered to `projectID` (`nil` for every project),
    /// building it the first time and centring it then only: a window the user
    /// has moved stays where they put it.
    func show(projectID: UUID?) {
        state.projectFilter = projectID
        let window = self.window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(
            rootView: SessionEditorView(engine: engine, state: state)
        )
        controller.preferredContentSize = Self.contentSize

        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = "\(AppInfo.name) Sessions"
        window.setContentSize(Self.contentSize)
        window.contentMinSize = Self.contentSize
        // The agent has no Dock icon to restore from, so closing must not
        // deallocate the window out from under a later "Edit today's
        // sessions…".
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
