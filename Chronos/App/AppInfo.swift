import Foundation

/// Static facts about the running build, read from the bundle so they are
/// never hard-coded in two places.
enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static let name = "Chronos"
}
