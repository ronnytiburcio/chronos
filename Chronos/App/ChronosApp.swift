import AppKit

/// Entry point. Chronos is a background agent (`LSUIElement`), so it boots
/// AppKit directly and never shows a Dock icon or a main window.
@main
enum ChronosApp {
    @MainActor private static let delegate = AppDelegate()

    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
