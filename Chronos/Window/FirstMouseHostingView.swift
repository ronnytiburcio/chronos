import AppKit
import SwiftUI

/// `NSHostingView` that acts on the very first click it receives.
///
/// By default AppKit swallows the click that would activate an inactive window
/// and only delivers the *second* one. Chronos never activates, so without this
/// override every button in the panel would need two clicks.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported; Chronos builds its views in code")
    }
}
