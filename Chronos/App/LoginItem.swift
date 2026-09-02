import Foundation
import ServiceManagement

/// The "Launch at login" setting (SPEC §4), as thin a wrapper over
/// ``SMAppService/mainApp`` as it can be.
///
/// macOS, not `state.json`, is the source of truth for whether the app is
/// actually registered: the user can turn it off in System Settings without
/// Chronos ever hearing about it. `Settings.launchAtLogin` records the user's
/// *intent* so first launch knows what to ask for; ``isEnabled`` says what is
/// really the case.
///
/// Registration needs at least an ad-hoc code signature — an unsigned build
/// gets an error from `register()`, which is why the project signs with
/// `CODE_SIGN_IDENTITY=-` even for local runs.
@MainActor
enum LoginItem {
    private static var service: SMAppService { .mainApp }

    static var status: SMAppService.Status { service.status }

    /// Registered and running at login.
    static var isEnabled: Bool { status == .enabled }

    /// Registered, but waiting for the user to allow it in System Settings ›
    /// General › Login Items. The toggle reads as on; the app will not actually
    /// launch until it is approved, so the UI says so.
    static var requiresApproval: Bool { status == .requiresApproval }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }

    /// First launch registers the login item once, because the setting defaults
    /// to on (SPEC §4). Only when macOS has never heard of it: a user who
    /// turned it off in System Settings is left alone, and a failure (an
    /// unsigned build, most likely) is logged and forgotten rather than nagged
    /// about at every launch.
    static func registerOnFirstLaunchIfWanted(_ wanted: Bool) {
        guard wanted, status == .notRegistered else { return }
        do {
            try setEnabled(true)
        } catch {
            NSLog("Chronos: could not register the login item: \(error.localizedDescription)")
        }
    }
}
