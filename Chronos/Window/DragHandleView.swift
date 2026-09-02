import AppKit
import SwiftUI

/// Invisible SwiftUI overlay that makes the region it covers drag the window.
///
/// The panel sets `isMovableByWindowBackground = false`, so only the areas
/// covered by this view move the window; every other part of the panel stays a
/// normal click target.
struct DragHandleView: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleNSView {
        DragHandleNSView()
    }

    func updateNSView(_ nsView: DragHandleNSView, context: Context) {}
}

/// The `NSView` behind ``DragHandleView``.
final class DragHandleNSView: NSView {
    /// Dragging must work on the first click even though Chronos is never the
    /// active application.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
