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

    /// Small mutable app state: window frame, last rollover, settings.
    static var stateFile: URL {
        appSupportDirectory.appendingPathComponent("state.json", isDirectory: false)
    }

    /// The project list, as a JSON array.
    static var projectsFile: URL {
        appSupportDirectory.appendingPathComponent("projects.json", isDirectory: false)
    }

    /// The append-only session log, one JSON object per line. Rotated yearly
    /// to `sessions-YYYY.jsonl` alongside it.
    static var sessionsFile: URL {
        appSupportDirectory.appendingPathComponent("sessions.jsonl", isDirectory: false)
    }

    /// Where a year's session log goes when the log rotates.
    ///
    /// The folder is a parameter rather than always Application Support so the
    /// archive lands beside whichever log is in use (a test's temp directory
    /// included) instead of in the real one.
    static func sessionsArchiveFile(year: Int, in directory: URL? = nil) -> URL {
        (directory ?? appSupportDirectory)
            .appendingPathComponent("sessions-\(year).jsonl", isDirectory: false)
    }

    /// The human-readable archive folder (SPEC §8): the user's chosen path, or
    /// `~/Documents/Chronos`. A stored path may be `~`-relative, so it is
    /// expanded here rather than at the point it was typed.
    static func archiveDirectory(forSettingsPath path: String?) -> URL {
        if let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        let manager = FileManager.default
        let documents = manager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? manager.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
        return documents.appendingPathComponent(AppInfo.name, isDirectory: true)
    }

    /// Where the archive goes when the chosen folder cannot be written to —
    /// most likely because the user declined the one-time Documents prompt.
    /// Application Support is always writable by us, so the day's totals are
    /// never lost to a permission dialog.
    static var fallbackArchiveDirectory: URL {
        appSupportDirectory.appendingPathComponent("Archive", isDirectory: true)
    }
}

/// Where the archive is written, and where it goes when that fails.
///
/// Injected into ``TimerEngine`` as a value so tests can point both at a temp
/// directory and never touch `~/Documents` or the real Application Support
/// folder.
struct ArchiveLocation: Sendable {
    /// The folder the settings ask for.
    var folder: @Sendable (Settings) -> URL
    /// The folder to retry into when the first one refuses the write.
    var fallbackFolder: @Sendable () -> URL

    static let standard = ArchiveLocation(
        folder: { AppPaths.archiveDirectory(forSettingsPath: $0.archiveFolderPath) },
        fallbackFolder: { AppPaths.fallbackArchiveDirectory }
    )
}
