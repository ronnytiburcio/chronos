import Foundation

/// Reads and writes the project list as `projects.json` via ``JSONFile``
/// (atomic write, ISO-8601 dates, sorted keys).
///
/// A missing or unreadable file is not an error: it yields an empty list, the
/// same thing a first launch sees.
struct ProjectStore: Sendable {
    let fileURL: URL

    init(fileURL: URL = AppPaths.projectsFile) {
        self.fileURL = fileURL
    }

    func load() -> [Project] {
        (try? JSONFile.read([Project].self, from: fileURL)) ?? []
    }

    func save(_ projects: [Project]) throws {
        try JSONFile.write(projects, to: fileURL)
    }
}
