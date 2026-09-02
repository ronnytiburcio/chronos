import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: PanelController?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = PanelController()
        panel.show()
        self.panel = panel
        menuBar = MenuBarController(panelController: panel)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
