import Foundation

/// Small mutable state that survives relaunches: where the user parked the
/// panel, when the last rollover ran, and the settings.
///
/// Every key decodes with a default when it is missing, so a `state.json`
/// written by an older build keeps loading.
struct AppState: Codable, Equatable, Sendable {
    var windowFrame: CGRect?
    /// The start of the tracking day currently on screen. Totals shown in the
    /// panel are the sessions that started at or after it (SPEC §7); Phase 5
    /// advances it when a rollover runs.
    var lastRollover: Date?
    var settings: Settings

    init(windowFrame: CGRect? = nil, lastRollover: Date? = nil, settings: Settings = Settings()) {
        self.windowFrame = windowFrame
        self.lastRollover = lastRollover
        self.settings = settings
    }

    // `CGRect`'s synthesized Codable writes nested arrays; the state file is
    // meant to be readable by people, so the frame is stored with named keys.
    private enum CodingKeys: String, CodingKey {
        case windowFrame
        case lastRollover
        case settings
    }

    private struct FrameRecord: Codable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double

        init(_ rect: CGRect) {
            x = rect.origin.x
            y = rect.origin.y
            width = rect.size.width
            height = rect.size.height
        }

        var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        windowFrame = try container.decodeIfPresent(FrameRecord.self, forKey: .windowFrame)?.rect
        lastRollover = try container.decodeIfPresent(Date.self, forKey: .lastRollover)
        settings = try container.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(windowFrame.map(FrameRecord.init), forKey: .windowFrame)
        try container.encodeIfPresent(lastRollover, forKey: .lastRollover)
        try container.encode(settings, forKey: .settings)
    }
}

/// Reads and writes ``AppState`` as JSON via ``JSONFile``.
/// A missing or corrupt file is not an error: it yields a default ``AppState``.
struct AppStateStore: Sendable {
    let fileURL: URL

    init(fileURL: URL = AppPaths.stateFile) {
        self.fileURL = fileURL
    }

    func load() -> AppState {
        (try? JSONFile.read(AppState.self, from: fileURL)) ?? AppState()
    }

    func save(_ state: AppState) throws {
        try JSONFile.write(state, to: fileURL)
    }
}
