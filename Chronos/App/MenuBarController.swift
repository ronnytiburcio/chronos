import AppKit

/// Owns the menu bar status item. Phase 2 ships the panel toggle and Quit;
/// later phases add the current project, quick-start list, and settings.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let panelController: PanelController
    private let toggleItem: NSMenuItem

    init(panelController: PanelController) {
        self.panelController = panelController
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
        toggleItem.action = #selector(togglePanel)
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
        toggleItem.title = panelController.isVisible ? "Hide Panel" : "Show Panel"
    }

    @objc private func togglePanel() {
        panelController.toggle()
    }
}
