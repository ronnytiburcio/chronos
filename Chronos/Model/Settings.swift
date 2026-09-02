import Foundation

/// Everything the user can change (SPEC §8, "Settings window"). Stored inside
/// `state.json`.
///
/// Decoding fills in a default for every missing key, so a `state.json` written
/// by an older build keeps loading and simply picks up the new defaults.
struct Settings: Codable, Equatable, Sendable {
    /// When one tracking day becomes the next. Default 04:00.
    var rollover: RolloverTime
    /// Where the human-readable archive is written. `nil` means the default,
    /// `~/Documents/Chronos`, which is resolved through `FileManager` at the
    /// moment of writing — an absolute path is never stored, so the setting
    /// survives a different Mac or a renamed home folder.
    var archiveFolderPath: String?
    var launchAtLogin: Bool
    /// Whether the project that was running at rollover restarts in the new
    /// day. Default off, per SPEC §7.
    var restartRunningProjectAfterRollover: Bool
    var writeMarkdownDailyNotes: Bool
    var showElapsedInMenuBar: Bool

    init(
        rollover: RolloverTime = .default,
        archiveFolderPath: String? = nil,
        launchAtLogin: Bool = true,
        restartRunningProjectAfterRollover: Bool = false,
        writeMarkdownDailyNotes: Bool = true,
        showElapsedInMenuBar: Bool = true
    ) {
        self.rollover = rollover
        self.archiveFolderPath = archiveFolderPath
        self.launchAtLogin = launchAtLogin
        self.restartRunningProjectAfterRollover = restartRunningProjectAfterRollover
        self.writeMarkdownDailyNotes = writeMarkdownDailyNotes
        self.showElapsedInMenuBar = showElapsedInMenuBar
    }

    private enum CodingKeys: String, CodingKey {
        case rollover
        case archiveFolderPath
        case launchAtLogin
        case restartRunningProjectAfterRollover
        case writeMarkdownDailyNotes
        case showElapsedInMenuBar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings()
        rollover = try container.decodeIfPresent(RolloverTime.self, forKey: .rollover)
            ?? defaults.rollover
        archiveFolderPath = try container.decodeIfPresent(String.self, forKey: .archiveFolderPath)
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin)
            ?? defaults.launchAtLogin
        restartRunningProjectAfterRollover = try container.decodeIfPresent(
            Bool.self,
            forKey: .restartRunningProjectAfterRollover
        ) ?? defaults.restartRunningProjectAfterRollover
        writeMarkdownDailyNotes = try container.decodeIfPresent(
            Bool.self,
            forKey: .writeMarkdownDailyNotes
        ) ?? defaults.writeMarkdownDailyNotes
        showElapsedInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showElapsedInMenuBar)
            ?? defaults.showElapsedInMenuBar
    }
}
