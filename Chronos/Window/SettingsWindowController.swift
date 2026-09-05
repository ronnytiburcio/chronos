import AppKit
import SwiftUI

/// Owns the settings window: an ordinary titled window, created on first open
/// and reused afterwards.
///
/// This, ``ReviewWindowController`` and ``SessionEditorWindowController`` are
/// the three places in Chronos that call `NSApp.activate`. Everything
/// else goes out of its way *not* to steal focus (the desktop panel never
/// activates the app at all), but a settings window the user has just asked for
/// has to come forward and take the keyboard — Chronos is an `LSUIElement`
/// agent, so without the activate it would open behind whatever is frontmost
/// and ignore every keystroke.
@MainActor
final class SettingsWindowController {
    /// SPEC §8's list is long enough to want the height, and the form's
    /// controls stop looking sensible much below the width.
    static let contentSize = NSSize(width: 480, height: 560)

    private let engine: TimerEngine
    private let onRolloverChanged: () -> Void
    private var window: NSWindow?

    init(engine: TimerEngine, onRolloverChanged: @escaping () -> Void) {
        self.engine = engine
        self.onRolloverChanged = onRolloverChanged
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
        let controller = NSHostingController(
            rootView: SettingsView(engine: engine, onRolloverChanged: onRolloverChanged)
        )
        controller.preferredContentSize = Self.contentSize

        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = "\(AppInfo.name) Settings"
        window.setContentSize(Self.contentSize)
        window.contentMinSize = Self.contentSize
        // The agent has no Dock icon to restore from, so closing must not
        // deallocate the window out from under a later Settings… click.
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
