import Foundation

/// Small mutable state that survives relaunches. Phase 3 adds the rollover
/// bookkeeping; today it only remembers where the user parked the panel.
struct AppState: Codable, Equatable {
    var windowFrame: CGRect?

    init(windowFrame: CGRect? = nil) {
        self.windowFrame = windowFrame
    }
}

/// Reads and writes ``AppState`` as JSON.
///
/// Writes go to a temp file in the destination directory first and are then
/// swapped in, so a crash mid-write can never leave a half-written state file.
/// A missing or corrupt file is not an error: it yields a default ``AppState``.
struct AppStateStore: Sendable {
    let fileURL: URL

    init(fileURL: URL = AppPaths.stateFile) {
        self.fileURL = fileURL
    }

    func load() -> AppState {
        guard let data = try? Data(contentsOf: fileURL) else { return AppState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(AppState.self, from: data)) ?? AppState()
    }

    func save(_ state: AppState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)

        let manager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)

        let temporaryURL = directory.appendingPathComponent(
            ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false
        )
        try data.write(to: temporaryURL, options: .atomic)
        do {
            if manager.fileExists(atPath: fileURL.path) {
                _ = try manager.replaceItemAt(fileURL, withItemAt: temporaryURL)
            } else {
                try manager.moveItem(at: temporaryURL, to: fileURL)
            }
        } catch {
            try? manager.removeItem(at: temporaryURL)
            throw error
        }
    }
}
