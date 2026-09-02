import AppKit
import SwiftUI

/// The row actions as an AppKit `NSMenu`.
///
/// SwiftUI's `.contextMenu` never appeared in the live panel: Chronos is never
/// the active application and SwiftUI's menu path stays silent there. An
/// `NSMenu` popped up from an `NSView` works whether or not the app is active
/// (it is what status-bar menus do), so each row carries an always-visible
/// "•••" button that pops this menu, and the same view answers a right-click
/// through `menu(for:)`.
struct RowMenuAnchor: NSViewRepresentable {
    /// Builds the menu fresh each time it opens, so enabled states are current.
    let makeMenu: @MainActor () -> NSMenu
    /// Receives the anchor view so the row's button can pop the menu.
    var presenter: RowMenuPresenter?

    func makeNSView(context: Context) -> RowMenuAnchorView {
        let view = RowMenuAnchorView()
        view.makeMenu = makeMenu
        presenter?.anchor = view
        return view
    }

    func updateNSView(_ nsView: RowMenuAnchorView, context: Context) {
        nsView.makeMenu = makeMenu
        presenter?.anchor = nsView
    }

    /// The same anchor, wired to `presenter` so the row's button can use it.
    func presenting(_ presenter: RowMenuPresenter) -> RowMenuAnchor {
        var copy = self
        copy.presenter = presenter
        return copy
    }
}

/// Sits behind a row. Pops the row menu on request or on right-click.
final class RowMenuAnchorView: NSView {
    var makeMenu: @MainActor () -> NSMenu = { NSMenu() }

    override func menu(for event: NSEvent) -> NSMenu? {
        makeMenu()
    }

    /// Pops the menu at the mouse pointer.
    func popUpMenu() {
        let menu = makeMenu()
        let screenPoint = NSEvent.mouseLocation
        let windowPoint = window?.convertPoint(fromScreen: screenPoint) ?? screenPoint
        let point = convert(windowPoint, from: nil)
        menu.popUp(positioning: nil, at: point, in: self)
    }
}

/// Finds the row's anchor view from SwiftUI so the "•••" button can pop the
/// menu. Injected as a `@State` object and filled in by the anchor.
@MainActor
final class RowMenuPresenter {
    weak var anchor: RowMenuAnchorView?

    func present() {
        anchor?.popUpMenu()
    }
}

/// `NSMenuItem` driven by a closure instead of a target/selector pair.
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(
        _ title: String,
        enabled: Bool = true,
        state: NSControl.StateValue = .off,
        image: NSImage? = nil,
        handler: @escaping @MainActor () -> Void
    ) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        isEnabled = enabled
        self.state = state
        self.image = image
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported; Chronos builds its menus in code")
    }

    @objc private func fire() {
        handler()
    }
}
