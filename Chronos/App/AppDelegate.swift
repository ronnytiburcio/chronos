import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let stateStore = AppStateStore()
    private var state = AppState()
    private var menuBar: MenuBarController?
    private var panel: PanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The unit tests use this app as their host; they must not put a panel
        // on screen or touch the real state file.
        guard !Self.isRunningUnitTests else { return }

        // Menu bar first: it carries Quit, the only exit from a Dock-less agent.
        menuBar = MenuBarController(
            isPanelVisible: { [weak self] in self?.panel?.isVisible ?? false },
            togglePanel: { [weak self] in self?.panel?.toggle() }
        )

        state = stateStore.load()
        let panel = PanelController(savedFrame: state.windowFrame) { [weak self] frame in
            self?.saveWindowFrame(frame)
        }
        panel.show()
        self.panel = panel
    }

    func applicationWillTerminate(_ notification: Notification) {
        panel?.flushPendingFrameSave()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func saveWindowFrame(_ frame: CGRect) {
        state.windowFrame = frame
        do {
            try stateStore.save(state)
        } catch {
            NSLog("Chronos: could not save the window position: \(error.localizedDescription)")
        }
    }

    private static var isRunningUnitTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
    }
}
