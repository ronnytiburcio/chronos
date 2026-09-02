import Foundation

/// Every on-disk location Chronos uses, derived from `FileManager` so no
/// absolute path is ever hard-coded.
enum AppPaths {
    /// `~/Library/Application Support/Chronos`, created once on first access.
    static let appSupportDirectory: URL = {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? manager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
        let directory = base.appendingPathComponent(AppInfo.name, isDirectory: true)
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            NSLog("Chronos: could not create \(directory.path): \(error.localizedDescription)")
        }
        return directory
    }()

    /// Small mutable app state (window frame today; rollover bookkeeping later).
    static var stateFile: URL {
        appSupportDirectory.appendingPathComponent("state.json", isDirectory: false)
    }
}
