import AppKit

/// Owns the menu bar status item. Phase 1 ships only the icon and Quit;
/// later phases add the current project, quick-start list, and settings.
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bolt", accessibilityDescription: "Chronos")
            button.image?.isTemplate = true
        }
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let quit = NSMenuItem(title: "Quit Chronos", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }
}
