import AppKit
import SwiftUI

/// Owns the desktop panel: builds it, installs its glass background and the
/// SwiftUI content, restores the saved position and writes it back when the
/// user drags the panel somewhere else.
@MainActor
final class PanelController: NSObject {
    /// Placeholder size for this phase; Phase 4 grows the height with the
    /// project list.
    static let panelSize = CGSize(width: 280, height: 320)

    /// Debounce for the frame writes, so a drag is one write and not one per
    /// mouse-moved event.
    private static let frameSaveDelay = Duration.milliseconds(500)

    private static let cornerRadius: CGFloat = 14

    /// Ink `#15171C` from SPEC §9, translucent so the blur still reads.
    private static let inkTint = CGColor(red: 21 / 255, green: 23 / 255, blue: 28 / 255, alpha: 0.72)

    private let store: AppStateStore
    private var state: AppState
    private let panel: DesktopPanel
    private let backdrop: NSVisualEffectView
    private var frameSaveTask: Task<Void, Never>?

    var isVisible: Bool { panel.isVisible }

    init(store: AppStateStore = AppStateStore()) {
        self.store = store
        self.state = store.load()

        let frame = WindowPlacement.resolvedFrame(
            saved: state.windowFrame,
            size: Self.panelSize,
            screens: Self.screenRects()
        )

        // `.nonactivatingPanel` has to be in the style mask here and must never
        // be mutated afterwards, or key input silently stops working.
        panel = DesktopPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        backdrop = NSVisualEffectView(frame: CGRect(origin: .zero, size: frame.size))
        super.init()

        configurePanel()
        installContent()
        // The first-launch placement is state too: persist it so the panel does
        // not wander if the display arrangement changes before the first drag.
        persistFrame()
        observeNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Visibility

    func show() {
        // `orderFrontRegardless` shows the panel without activating Chronos.
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    // MARK: - Panel construction

    private func configurePanel() {
        // +1 keeps the panel above Finder's desktop-icon layer, which would
        // otherwise swallow clicks, while staying below every app window.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        // Only the header drags the panel; see DragHandleView.
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        // SPEC §9: Chronos is dark by default. Without this the `.hudWindow`
        // material follows the system appearance and turns into light glass,
        // which the Paper-on-Ink palette is not readable on.
        panel.appearance = NSAppearance(named: .darkAqua)
    }

    private func installContent() {
        backdrop.material = .hudWindow
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = Self.cornerRadius
        backdrop.layer?.cornerCurve = .continuous
        backdrop.layer?.masksToBounds = true
        backdrop.autoresizingMask = [.width, .height]

        // The material alone follows the wallpaper's brightness; SPEC §9 wants
        // Ink dark glass, so tint it and keep the blur showing through.
        let tint = NSView(frame: backdrop.bounds)
        tint.wantsLayer = true
        tint.layer?.backgroundColor = Self.inkTint
        tint.autoresizingMask = [.width, .height]
        backdrop.addSubview(tint)

        let hostingView = FirstMouseHostingView(rootView: PanelPlaceholderView())
        hostingView.frame = backdrop.bounds
        hostingView.autoresizingMask = [.width, .height]
        backdrop.addSubview(hostingView)

        panel.contentView = backdrop
    }

    // MARK: - Notifications

    private func observeNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidMove),
            name: NSWindow.didMoveNotification,
            object: panel
        )
        // The behind-window blur can go stale after sleep or a Space switch;
        // re-poking it costs nothing and keeps the glass from turning flat.
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(refreshBackdrop),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(refreshBackdrop),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    @objc private func panelDidMove(_ notification: Notification) {
        scheduleFrameSave()
    }

    @objc private func refreshBackdrop(_ notification: Notification) {
        guard isVisible else { return }
        backdrop.state = .active
        panel.orderFrontRegardless()
    }

    // MARK: - Frame persistence

    private func scheduleFrameSave() {
        frameSaveTask?.cancel()
        frameSaveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.frameSaveDelay)
            guard !Task.isCancelled else { return }
            self?.persistFrame()
        }
    }

    private func persistFrame() {
        let frame = panel.frame
        guard state.windowFrame != frame else { return }
        state.windowFrame = frame
        do {
            try store.save(state)
        } catch {
            NSLog("Chronos: could not save the window position: \(error.localizedDescription)")
        }
    }

    /// Screen rectangles the panel may live in, main screen first so it is the
    /// one used for the first-launch placement.
    private static func screenRects() -> [CGRect] {
        let screens = NSScreen.screens
        guard let main = NSScreen.main else { return screens.map(\.visibleFrame) }
        return [main.visibleFrame] + screens.filter { $0 !== main }.map(\.visibleFrame)
    }
}
