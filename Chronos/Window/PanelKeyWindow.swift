import AppKit

/// Gives the desktop panel keyboard focus without activating Chronos.
///
/// The panel is a `.nonactivatingPanel` with `becomesKeyOnlyIfNeeded = true`,
/// so clicking it does not take key status unless the clicked view needs
/// typing. The inline fields (add project, rename) appear *after* such a click,
/// so they have to ask: `makeKey()` on a non-activating panel makes it the key
/// window while the frontmost application stays frontmost, which
/// `NSApp.activate` would not.
///
/// Verified live: with another app frontmost, this leaves that app frontmost
/// and the panel reports `isKeyWindow == true`.
///
/// It finds the panel through `NSApp.windows` rather than taking a reference,
/// so a SwiftUI view deep in the hierarchy does not have to be handed one.
@MainActor
enum PanelKeyWindow {
    /// Makes the panel key and returns once the change has settled.
    ///
    /// The trailing `Task.yield()` matters: `makeKey()` leaves the panel itself
    /// as first responder, so a `@FocusState` set in the same pass is undone.
    /// Callers `await` this and then claim focus, which sticks.
    static func makeKey() async {
        if let panel = NSApp.windows.first(where: { $0 is DesktopPanel }), !panel.isKeyWindow {
            panel.makeKey()
        }
        await Task.yield()
    }
}
