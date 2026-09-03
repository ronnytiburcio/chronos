import Foundation

/// Every session Chronos still has on disk, in one list.
///
/// A yearly rotation moves finished sessions out of `sessions.jsonl` and out of
/// ``TimerEngine``'s memory, so anything that looks further back than the
/// current tracking day has to read the rotated logs too. This is that reader,
/// shared by ``Exporter`` (SPEC §8's export) and the review window.
///
/// It is deliberately a value with no state of its own: loading is a fresh read
/// every time, because the log is appended to by the engine while the reader is
/// alive.
struct SessionHistory: Sendable {
    /// The live log. Rotated logs in the same folder are read too.
    let sessionsFileURL: URL

    init(sessionsFileURL: URL = AppPaths.sessionsFile) {
        self.sessionsFileURL = sessionsFileURL
    }

    /// The rotated years first, oldest to newest, then the live log. A session
    /// id seen twice (a log copied by hand, say) is counted once.
    func load() throws -> [Session] {
        var sessions: [Session] = []
        var seen: Set<UUID> = []
        for url in rotatedLogURLs() + [sessionsFileURL] {
            let loaded = try SessionLog(fileURL: url).loadSessions()
            for session in loaded where seen.insert(session.id).inserted {
                sessions.append(session)
            }
        }
        return sessions
    }

    /// `sessions-YYYY.jsonl` beside the live log, oldest year first.
    ///
    /// A folder that cannot be listed is not an error: the live log alone is
    /// still a usable history, and refusing to show anything would be worse.
    func rotatedLogURLs() -> [URL] {
        let folder = sessionsFileURL.deletingLastPathComponent()
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        } catch {
            NSLog("Chronos: could not list \(folder.path) for rotated session logs: \(error.localizedDescription)")
            return []
        }
        return names
            .compactMap { name -> (year: Int, url: URL)? in
                guard name.hasPrefix("sessions-"), name.hasSuffix(".jsonl") else { return nil }
                let year = name.dropFirst("sessions-".count).dropLast(".jsonl".count)
                guard let value = Int(year) else { return nil }
                return (value, folder.appendingPathComponent(name, isDirectory: false))
            }
            .sorted { $0.year < $1.year }
            .map(\.url)
    }
}
