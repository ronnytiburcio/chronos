import AppKit

/// Owns the menu bar status item. Phase 2 ships the panel toggle and Quit;
/// later phases add the current project, quick-start list, and settings.
///
/// It talks to the panel through closures so it can be created *before* the
/// panel exists: the menu carries Quit, the only way out of a Dock-less agent.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let isPanelVisible: () -> Bool
    private let togglePanel: () -> Void
    private let toggleItem: NSMenuItem

    init(isPanelVisible: @escaping () -> Bool, togglePanel: @escaping () -> Void) {
        self.isPanelVisible = isPanelVisible
        self.togglePanel = togglePanel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        toggleItem = NSMenuItem(title: "Hide Panel", action: nil, keyEquivalent: "")
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bolt", accessibilityDescription: "Chronos")
            button.image?.isTemplate = true
        }
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        toggleItem.target = self
        toggleItem.action = #selector(togglePanelAction)
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Chronos",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        toggleItem.title = isPanelVisible() ? "Hide Panel" : "Show Panel"
    }

    @objc private func togglePanelAction() {
        togglePanel()
    }
}
