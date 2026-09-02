import AppKit
import Observation

/// Owns the menu bar status item (SPEC §10): a bolt that fills while a timer
/// runs, optionally with the running project's elapsed time beside it, and a
/// menu that can stop, switch, show or hide the panel, and quit.
///
/// It talks to the panel and the settings window through closures so it can be
/// created *before* either exists: the menu carries Quit, the only way out of a
/// Dock-less agent.
///
/// The button refreshes off ``TimerEngine``'s observation rather than a timer
/// of its own — the engine already ticks once a second while a session is open,
/// and stops ticking when nothing is running.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let engine: TimerEngine
    private let isPanelVisible: () -> Bool
    private let togglePanel: () -> Void
    private let openSettings: () -> Void

    init(
        engine: TimerEngine,
        isPanelVisible: @escaping () -> Bool,
        togglePanel: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) {
        self.engine = engine
        self.isPanelVisible = isPanelVisible
        self.togglePanel = togglePanel
        self.openSettings = openSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        observeEngine()
    }

    // MARK: - Button

    /// Re-arms itself on every change, because `withObservationTracking` fires
    /// once per registration. `onChange` runs *before* the value is applied and
    /// off the main actor, so the work hops back to it.
    private func observeEngine() {
        withObservationTracking {
            _ = engine.openSession
            _ = engine.now
            _ = engine.projects
            _ = engine.settings.showElapsedInMenuBar
        } onChange: { [weak self] in
            // Re-arming also refreshes, so the button is redrawn exactly once
            // per change.
            Task { @MainActor [weak self] in self?.observeEngine() }
        }
        refreshButton()
    }

    private func refreshButton() {
        guard let button = statusItem.button else { return }
        let running = engine.runningProject

        // SPEC §10: filled and red while a timer runs, an outline (template,
        // so it follows the menu bar's own color) when idle.
        if running != nil {
            let configuration = NSImage.SymbolConfiguration(paletteColors: [Palette.scarlet.nsColor])
            let image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Chronos: running")?
                .withSymbolConfiguration(configuration)
            image?.isTemplate = false
            button.image = image
        } else {
            let image = NSImage(systemSymbolName: "bolt", accessibilityDescription: "Chronos: not running")
            image?.isTemplate = true
            button.image = image
        }

        if let running, engine.settings.showElapsedInMenuBar {
            let elapsed = engine.total(for: running.id, asOf: engine.now)
            button.title = " " + TimeFormatting.hoursMinutesCompact(elapsed)
            button.imagePosition = .imageLeading
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    // MARK: - Menu

    /// Rebuilt on every open so the project list, the running project, and the
    /// panel's visibility are always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // A failed archive write is the one thing the panel has no room to
        // say, so it surfaces here (SPEC §8's graceful-fallback note).
        if let warning = engine.lastWarning {
            let item = disabledItem(title: "⚠️ " + Self.truncated(warning))
            item.toolTip = warning
            menu.addItem(item)

            let dismiss = NSMenuItem(title: "Dismiss warning", action: #selector(dismissWarning), keyEquivalent: "")
            dismiss.target = self
            menu.addItem(dismiss)
            menu.addItem(.separator())
        }

        if let running = engine.runningProject {
            menu.addItem(disabledItem(title: "Running: \(running.name)"))
            let stop = NSMenuItem(title: "Stop", action: #selector(stopTiming), keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)
        } else {
            menu.addItem(disabledItem(title: "Not running"))
        }

        let projects = engine.visibleProjects
        if !projects.isEmpty {
            menu.addItem(.separator())
            for project in projects {
                let item = NSMenuItem(
                    title: project.name,
                    action: #selector(startProject(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = project.id
                item.state = engine.runningProject?.id == project.id ? .on : .off
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let toggle = NSMenuItem(
            title: isPanelVisible() ? "Hide Panel" : "Show Panel",
            action: #selector(togglePanelAction),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettingsAction),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Chronos",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        menu.addItem(quit)
    }

    private func disabledItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// A warning naming two folder paths would push the menu off the screen;
    /// the whole text stays available as the item's tooltip.
    private static let warningLimit = 60

    private static func truncated(_ text: String) -> String {
        guard text.count > warningLimit else { return text }
        return text.prefix(warningLimit - 1).trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: - Actions

    @objc private func stopTiming() {
        engine.stop()
    }

    @objc private func startProject(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        engine.toggle(projectID: id)
    }

    @objc private func dismissWarning() {
        engine.clearWarning()
    }

    @objc private func togglePanelAction() {
        togglePanel()
    }

    @objc private func openSettingsAction() {
        openSettings()
    }
}
