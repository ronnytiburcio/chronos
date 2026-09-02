import AppKit

/// The desktop-level panel Chronos lives in.
///
/// Two overrides carry the whole "never steal focus" contract:
/// - `canBecomeKey` is `true` so the inline text fields can take keystrokes.
///   Combined with `.nonactivatingPanel` in the style mask, the panel becomes
///   key *without* Chronos becoming the active application.
/// - `canBecomeMain` is `false` so Chronos never owns the main window and the
///   frontmost app keeps its menu bar.
///
/// The style mask must contain `.nonactivatingPanel` at init and must never be
/// mutated afterwards: AppKit only syncs the "prevents activation" tag when the
/// window is created, and toggling it later breaks key input silently.
final class DesktopPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
