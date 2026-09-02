import AppKit

/// Makes the daily rollover happen on time (SPEC §7).
///
/// The engine knows *how* to roll over and how to catch up on days it missed;
/// this object only decides *when* to ask it. There are three prompts:
///
/// - a one-shot timer armed for the next boundary, re-armed after every run;
/// - waking from sleep, because a sleeping Mac's timers do not fire;
/// - the system clock changing (a time-zone move, an NTP correction, or the
///   user setting the date by hand), which can move the boundary underneath
///   an already-armed timer.
///
/// All three run the same catch-up, and running it when nothing is due is
/// free, so there is no need to work out which of them was right.
@MainActor
final class RolloverScheduler {
    private let engine: TimerEngine
    private let clock: Clock
    private var timer: Timer?
    private let target = SchedulerTarget()
    private let observers = ObserverTokens()

    /// A rollover a few seconds late is invisible; the slack lets the system
    /// coalesce the timer instead of waking the CPU precisely at 04:00.
    private static let tolerance: TimeInterval = 5

    init(engine: TimerEngine, clock: Clock = .system) {
        self.engine = engine
        self.clock = clock
        target.scheduler = self

        observe(NSWorkspace.shared.notificationCenter, name: NSWorkspace.didWakeNotification)
        observe(NotificationCenter.default, name: NSNotification.Name.NSSystemClockDidChange)
        arm()
    }

    /// Runs every rollover that is due and re-arms for the next boundary.
    func catchUp() {
        engine.performRolloversIfNeeded(now: clock.now())
        arm()
    }

    /// Points the timer at the next boundary after the day currently on
    /// screen. Called again after every run, so one missed fire cannot leave
    /// the app without a schedule.
    private func arm() {
        timer?.invalidate()
        let fireDate = engine.nextRolloverBoundary
        // Target/selector through a proxy that holds this object weakly, and
        // `.common` so a menu or a drag cannot delay the rollover.
        let timer = Timer(
            fireAt: fireDate,
            interval: 0,
            target: target,
            selector: #selector(SchedulerTarget.fire(_:)),
            userInfo: nil,
            repeats: false
        )
        timer.tolerance = Self.tolerance
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// The observer block is `@Sendable`; a main-actor class is `Sendable`, so
    /// `self` can cross into it, and `.main` guarantees the block runs on the
    /// main thread. Only `Void` comes back out of `assumeIsolated`.
    private func observe(_ center: NotificationCenter, name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.catchUp() }
        }
        observers.add(token, to: center)
    }
}

/// The timer's target. Holds the scheduler weakly so a pending timer never
/// keeps it alive, and a fire after it is gone is simply ignored.
@MainActor
private final class SchedulerTarget: NSObject {
    weak var scheduler: RolloverScheduler?

    @objc func fire(_ timer: Timer) {
        scheduler?.catchUp()
    }
}

/// Removes the scheduler's notification observers when it goes away.
///
/// The tokens live in this box rather than in the scheduler because a
/// main-actor class's `deinit` is not isolated and cannot touch non-`Sendable`
/// stored values; the box has no isolation to violate.
private final class ObserverTokens {
    private var entries: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    func add(_ token: NSObjectProtocol, to center: NotificationCenter) {
        entries.append((center, token))
    }

    deinit {
        for entry in entries {
            entry.center.removeObserver(entry.token)
        }
    }
}
