import AppKit
import SwiftUI

extension View {
    /// Runs `action` when Escape is pressed, but only while `isActive`.
    ///
    /// SwiftUI's own escape hatches do not work here: neither `onExitCommand`
    /// nor `onKeyPress(.escape)` fires while an AppKit-backed `TextField` is
    /// editing, because the field editor consumes the key first (verified live
    /// in the panel). A local event monitor sees it before that happens.
    func onEscape(while isActive: Bool, perform action: @escaping () -> Void) -> some View {
        modifier(EscapeKeyModifier(isActive: isActive, action: action))
    }
}

@MainActor
private struct EscapeKeyModifier: ViewModifier {
    let isActive: Bool
    let action: () -> Void

    /// `NSEvent`'s opaque monitor token. Held so it can be removed again: a
    /// monitor that outlives its field would swallow Escape for the whole app.
    @State private var monitor: MonitorBox = MonitorBox()

    private static let escapeKeyCode: UInt16 = 53

    func body(content: Content) -> some View {
        content
            .onAppear { sync() }
            .onChange(of: isActive) { _, _ in sync() }
            .onDisappear { monitor.remove() }
    }

    private func sync() {
        // The action is refreshed every update: the modifier is a value that
        // SwiftUI rebuilds, while the box (and its monitor) lives on.
        monitor.action = action
        if isActive {
            monitor.install(keyCode: Self.escapeKeyCode)
        } else {
            monitor.remove()
        }
    }
}

/// Reference box for the monitor token, so the modifier's `@State` survives the
/// struct being recreated on every update.
@MainActor
private final class MonitorBox {
    /// What to run when the key arrives. Stored here rather than captured by
    /// the monitor: the monitor's closure is `@Sendable` and the view's action
    /// is not, but a main-actor class is `Sendable` and can carry it across.
    var action: (() -> Void)?

    private var token: Any?

    /// Watches for one key and swallows it, so AppKit does not beep at a key
    /// the field editor would otherwise reject.
    ///
    /// The monitor's closure is not main-actor isolated, but AppKit only ever
    /// calls it on the main thread. Only `Void` crosses back out of
    /// `assumeIsolated`: handing it the `NSEvent` would need `NSEvent` to be
    /// `Sendable`, which it is not.
    func install(keyCode: UInt16) {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == keyCode else { return event }
            MainActor.assumeIsolated { self?.action?() }
            return nil
        }
    }

    func remove() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}
