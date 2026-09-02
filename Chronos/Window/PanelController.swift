import AppKit
import SwiftUI

/// Owns the desktop panel: builds it, installs its glass background and the
/// SwiftUI content, restores the saved position and reports it back (debounced)
/// when the user drags the panel somewhere else.
///
/// Persistence is not this object's business: it receives the saved frame and
/// hands frame changes to `onFrameChange`, so there is exactly one owner of the
/// app state (`TimerEngine`).
@MainActor
final class PanelController: NSObject {
    /// Debounce for frame-change reports, so a drag is one write and not one
    /// per mouse-moved event.
    private static let frameSaveDelay = Duration.milliseconds(500)

    private static let cornerRadius: CGFloat = 14

    /// How much Ink sits between the blur and the content. Phase 7 tunes this
    /// against SPEC §9's "~92% opacity" with real wallpapers.
    private static let inkTintAlpha = 0.72

    private let panel: DesktopPanel
    private let backdrop: NSVisualEffectView
    private let engine: TimerEngine
    private let actions: PanelActions
    private let onFrameChange: (CGRect) -> Void
    private var lastReportedFrame: CGRect?
    private var frameSaveTask: Task<Void, Never>?

    var isVisible: Bool { panel.isVisible }

    /// - Parameters:
    ///   - engine: the running state the panel content reads from.
    ///   - savedFrame: the frame from the last run, if any. Only its origin is
    ///     honoured, and only if enough of it is still on a connected screen.
    ///   - actions: what the panel content cannot do for itself.
    ///   - onFrameChange: called (debounced) with the panel's frame whenever it
    ///     differs from the last one reported or restored.
    init(
        engine: TimerEngine,
        savedFrame: CGRect?,
        actions: PanelActions,
        onFrameChange: @escaping (CGRect) -> Void
    ) {
        self.engine = engine
        self.actions = actions
        self.onFrameChange = onFrameChange
        self.lastReportedFrame = savedFrame

        // The height is a pure function of the row count, so the panel opens at
        // the right size instead of laying out once and then jumping.
        let size = CGSize(
            width: PanelLayout.width,
            height: PanelLayout.height(rowCount: engine.visibleProjects.count)
        )
        let frame = WindowPlacement.resolvedFrame(
            saved: savedFrame,
            size: size,
            screens: NSScreen.screens.map(\.frame),
            placementArea: (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
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
        observeNotifications()
        // The first-launch placement is state too; report it so the panel does
        // not wander if the display arrangement changes before the first drag.
        scheduleFrameSave()
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

    /// Reports a pending frame change immediately. Call before the app quits so
    /// a drag in the last half second is not lost.
    func flushPendingFrameSave() {
        frameSaveTask?.cancel()
        frameSaveTask = nil
        reportFrameIfChanged()
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
    }

    /// Builds the dark-glass backdrop and puts the SwiftUI content on top.
    ///
    /// "Dark glass" is two settings that only work together, so they live in
    /// one place: the `.darkAqua` appearance stops `.hudWindow` from following
    /// the system appearance (light glass on a light desktop), and the Ink tint
    /// darkens the blur to SPEC §9's panel color while letting it show through.
    private func installContent() {
        panel.appearance = NSAppearance(named: .darkAqua)

        backdrop.material = .hudWindow
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = Self.cornerRadius
        backdrop.layer?.cornerCurve = .continuous
        backdrop.layer?.masksToBounds = true
        backdrop.autoresizingMask = [.width, .height]

        let tint = NSView(frame: backdrop.bounds)
        tint.wantsLayer = true
        tint.layer?.backgroundColor = Palette.ink.cgColor(alpha: Self.inkTintAlpha)
        tint.autoresizingMask = [.width, .height]
        backdrop.addSubview(tint)

        let content = PanelView(engine: engine, actions: actions) { [weak self] height in
            self?.setHeight(height)
        }
        let hostingView = FirstMouseHostingView(rootView: content)
        hostingView.frame = backdrop.bounds
        hostingView.autoresizingMask = [.width, .height]
        backdrop.addSubview(hostingView)

        panel.contentView = backdrop
    }

    // MARK: - Height

    /// Grows or shrinks the panel with the project list, keeping the *top*
    /// edge where the user put it. Cocoa's origin is bottom-left, so the origin
    /// moves by the height delta.
    ///
    /// Never animated: the panel sits at desktop level behind other windows,
    /// where a sliding edge would read as a glitch rather than a transition.
    private func setHeight(_ height: CGFloat) {
        var frame = panel.frame
        guard abs(frame.height - height) > 0.5 else { return }
        let top = frame.maxY
        frame.size.height = height
        frame.origin.y = top - height
        panel.setFrame(frame, display: true, animate: false)
        // A resize is a frame change like any other; persist it so the panel
        // comes back where (and as tall as) it was.
        scheduleFrameSave()
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
        // re-poking its state costs nothing and keeps the glass from going flat.
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
        backdrop.state = .active
    }

    // MARK: - Frame reporting

    private func scheduleFrameSave() {
        frameSaveTask?.cancel()
        frameSaveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.frameSaveDelay)
            guard !Task.isCancelled else { return }
            self?.reportFrameIfChanged()
        }
    }

    private func reportFrameIfChanged() {
        let frame = panel.frame
        guard lastReportedFrame != frame else { return }
        lastReportedFrame = frame
        onFrameChange(frame)
    }
}
