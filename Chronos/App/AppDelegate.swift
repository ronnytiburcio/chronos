import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var panel: PanelController?
    /// Built at launch rather than at init so the unit tests, which use this
    /// app as their host, never touch the real Application Support folder.
    private var engine: TimerEngine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The unit tests use this app as their host; they must not put a panel
        // on screen or touch the real state file.
        guard !Self.isRunningUnitTests else { return }

        // Menu bar first: it carries Quit, the only exit from a Dock-less agent.
        menuBar = MenuBarController(
            isPanelVisible: { [weak self] in self?.panel?.isVisible ?? false },
            togglePanel: { [weak self] in self?.panel?.toggle() }
        )

        // The engine is the single owner of `AppState`, the window frame
        // included, so a frame save can never clobber the rollover
        // bookkeeping or the settings sitting in the same file.
        let engine = TimerEngine()
        self.engine = engine

        let panel = PanelController(engine: engine, savedFrame: engine.windowFrame) { frame in
            engine.updateWindowFrame(frame)
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

    private static var isRunningUnitTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
    }
}
