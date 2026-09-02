import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var panel: PanelController?
    /// Built at launch rather than at init so the unit tests, which use this
    /// app as their host, never touch the real Application Support folder.
    private var engine: TimerEngine?
    private var rollover: RolloverScheduler?
    /// Built on the first Settings… and kept, so the window reopens where the
    /// user left it.
    private var settings: SettingsWindowController?

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

        // SPEC §4: launch at login defaults to on, so the first launch asks
        // macOS for it once. A user who later turns it off in System Settings
        // is left alone.
        LoginItem.registerOnFirstLaunchIfWanted(engine.settings.launchAtLogin)

        // Menu bar second: it carries Quit, the only exit from a Dock-less
        // agent, so it must exist even if building the panel goes wrong.
        menuBar = MenuBarController(
            engine: engine,
            isPanelVisible: { [weak self] in self?.panel?.isVisible ?? false },
            togglePanel: { [weak self] in self?.panel?.toggle() },
            openSettings: { [weak self] in self?.openSettings() }
        )

        let actions = PanelActions(
            onReset: { engine.resetDay() },
            onOpenSettings: { [weak self] in self?.openSettings() }
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

        // A development and screenshot hook: `CHRONOS_OPEN_SETTINGS=1 open -a
        // Chronos` puts the settings window on screen at launch, which is
        // otherwise a two-click journey through a menu bar item.
        if ProcessInfo.processInfo.environment["CHRONOS_OPEN_SETTINGS"] == "1" {
            openSettings()
        }
    }

    /// Opens the settings window, building it the first time (SPEC §8).
    ///
    /// The controller is kept so a second Settings… reuses the same window
    /// rather than stacking a new one on top.
    private func openSettings() {
        guard let engine else { return }
        let controller = settings ?? SettingsWindowController(engine: engine) { [weak self] in
            // The rollover time moved; an armed timer keeps its old fire date
            // until something re-aims it.
            self?.rollover?.rearm()
        }
        settings = controller
        controller.show()
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
