import Foundation

/// Small mutable state that survives relaunches. Phase 3 adds the rollover
/// bookkeeping; today it only remembers where the user parked the panel.
struct AppState: Codable, Equatable, Sendable {
    var windowFrame: CGRect?

    init(windowFrame: CGRect? = nil) {
        self.windowFrame = windowFrame
    }

    // `CGRect`'s synthesized Codable writes nested arrays; the state file is
    // meant to be readable by people, so the frame is stored with named keys.
    private enum CodingKeys: String, CodingKey {
        case windowFrame
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
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(windowFrame.map(FrameRecord.init), forKey: .windowFrame)
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
