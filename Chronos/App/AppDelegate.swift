import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var panel: PanelController?
    /// Built at launch rather than at init so the unit tests, which use this
    /// app as their host, never touch the real Application Support folder.
    private var engine: TimerEngine?
    private var rollover: RolloverScheduler?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The unit tests use this app as their host; they must not put a panel
        // on screen or touch the real state file.
        guard !Self.isRunningUnitTests else { return }

        // The engine is the single owner of `AppState`, the window frame
        // included, so a frame save can never clobber the rollover
        // bookkeeping or the settings sitting in the same file. It is built
        // first because both the menu bar and the panel read from it.
        let engine = TimerEngine()
        self.engine = engine

        // Catching up on missed days happens inside the engine's init, before
        // anything is on screen; the scheduler takes it from there and fires
        // the next one on time.
        rollover = RolloverScheduler(engine: engine)

        // Menu bar second: it carries Quit, the only exit from a Dock-less
        // agent, so it must exist even if building the panel goes wrong.
        menuBar = MenuBarController(
            engine: engine,
            isPanelVisible: { [weak self] in self?.panel?.isVisible ?? false },
            togglePanel: { [weak self] in self?.panel?.toggle() },
            openSettings: { Self.openSettings() }
        )

        let actions = PanelActions(
            onReset: { engine.resetDay() },
            onOpenSettings: { Self.openSettings() }
        )
        let panel = PanelController(
            engine: engine,
            savedFrame: engine.windowFrame,
            actions: actions
        ) { frame in
            engine.updateWindowFrame(frame)
        }
        panel.show()
        self.panel = panel
    }

    /// The settings window lands in Phase 6.
    private static func openSettings() {
        NSLog("Chronos: settings window arrives in Phase 6")
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
