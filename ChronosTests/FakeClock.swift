import Foundation
@testable import Chronos

/// A hand-driven clock. `Clock` reads it through a closure, so advancing time
/// here moves the engine's idea of "now" without any waiting.
final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ start: Date) {
        value = start
    }

    var current: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    var clock: Clock {
        Clock(now: { [self] in current })
    }

    @discardableResult
    func advance(by seconds: TimeInterval) -> Date {
        lock.lock()
        defer { lock.unlock() }
        value = value.addingTimeInterval(seconds)
        return value
    }
}
