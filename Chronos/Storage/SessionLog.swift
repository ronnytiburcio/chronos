import Foundation

/// One line of `sessions.jsonl`.
///
/// A session is written twice: an `open` record the instant it starts (so a
/// crash can never lose a running timer, SPEC §6) and a `close` record when it
/// ends. An `adjust` record corrects a session after the fact (a moved start
/// or end, or a reassigned project — the latest one wins) and a `delete`
/// record removes one outright; both are themselves just new lines. Nothing is
/// ever rewritten in place, which is what makes the file append-only and cheap
/// to trust.
enum SessionRecord: Codable, Equatable, Sendable {
    case open(id: UUID, projectID: UUID, start: Date)
    case close(id: UUID, end: Date)
    /// A correction to an existing session. `projectID` is omitted when the
    /// project did not change; `end` is omitted for a still-running session
    /// (only its start moved).
    case adjust(id: UUID, projectID: UUID?, start: Date, end: Date?)
    /// Terminal: nothing recorded after this for `id` applies.
    case delete(id: UUID)

    /// The session this record refers to.
    var sessionID: UUID {
        switch self {
        case let .open(id, _, _): id
        case let .close(id, _): id
        case let .adjust(id, _, _, _): id
        case let .delete(id): id
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, id, projectID, start, end
    }

    private enum Kind: String, Codable {
        case open, close, adjust, delete
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        switch try container.decode(Kind.self, forKey: .type) {
        case .open:
            self = .open(
                id: id,
                projectID: try container.decode(UUID.self, forKey: .projectID),
                start: try container.decode(Date.self, forKey: .start)
            )
        case .close:
            self = .close(id: id, end: try container.decode(Date.self, forKey: .end))
        case .adjust:
            self = .adjust(
                id: id,
                projectID: try container.decodeIfPresent(UUID.self, forKey: .projectID),
                start: try container.decode(Date.self, forKey: .start),
                end: try container.decodeIfPresent(Date.self, forKey: .end)
            )
        case .delete:
            self = .delete(id: id)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .open(id, projectID, start):
            try container.encode(Kind.open, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(projectID, forKey: .projectID)
            try container.encode(start, forKey: .start)
        case let .close(id, end):
            try container.encode(Kind.close, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(end, forKey: .end)
        case let .adjust(id, projectID, start, end):
            try container.encode(Kind.adjust, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(projectID, forKey: .projectID)
            try container.encode(start, forKey: .start)
            try container.encodeIfPresent(end, forKey: .end)
        case let .delete(id):
            try container.encode(Kind.delete, forKey: .type)
            try container.encode(id, forKey: .id)
        }
    }
}

enum SessionLogError: Error, Equatable {
    /// `rotate(to:)` refuses to overwrite an existing archive; a year's log is
    /// never worth clobbering silently.
    case archiveDestinationExists(URL)
}

/// The append-only session store (`sessions.jsonl`).
///
/// Appending is a seek-to-end plus a write, which is atomic enough for single
/// short lines and far cheaper than rewriting the whole history on every
/// click. `fsync` is deliberately not called: losing the last line to a power
/// cut costs one session, and paying a disk flush per click is not worth it.
///
/// Replay is forgiving by design. A truncated last line, a `close` with no
/// `open`, a duplicate `open`, an unreadable `"type"` (an old build's file
/// read by a newer one, or vice versa) — each is logged and skipped rather
/// than throwing, because a single bad line must never lock the user out of
/// their own history. Replay also enforces the engine's one-open-session
/// invariant: if an `open` arrives while another session is still open (a
/// `close` record that never made it to disk), the earlier session is closed
/// at the new one's start, so a lost line can never turn into two ticking
/// timers. An `adjust` never reopens a closed session (an omitted `end` on a
/// closed session is a no-op, not a reopen), and a `delete` is terminal: the
/// row is dropped from the result rather than rewritten, any `close` or
/// `adjust` recorded for that id afterwards is ignored, and a still-open
/// deleted session stops counting as the tracked open session so a later
/// `open` never force-closes it.
struct SessionLog: Sendable {
    let fileURL: URL

    init(fileURL: URL = AppPaths.sessionsFile) {
        self.fileURL = fileURL
    }

    // MARK: - Writing

    func append(_ record: SessionRecord) throws {
        var line = try Self.encoder.encode(record)
        line.append(0x0A) // "\n"

        let manager = FileManager.default
        try manager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !manager.fileExists(atPath: fileURL.path) {
            try Data().write(to: fileURL, options: .atomic)
        }

        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    // MARK: - Reading

    /// Replays the log into sessions, in the order they were opened — an
    /// `adjust` can move a session's `start` earlier or later than a
    /// neighbour's without moving it in this array, which is fine: nothing
    /// downstream (totals, export, the archive, `ReviewStats`) depends on
    /// array order, only on the timestamps themselves.
    func loadSessions() throws -> [Session] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard var text = String(data: data, encoding: .utf8) else {
            NSLog("Chronos: \(fileURL.lastPathComponent) is not valid UTF-8; ignoring it")
            return []
        }
        // A byte-order mark from an outside editor is not part of the first record.
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }

        var sessions: [Session] = []
        var indexByID: [UUID: Int] = [:]
        var openIndex: Int?
        // Terminal ids: a `delete` clears the row from `openIndex` bookkeeping
        // (without rewriting the row itself) and is recorded here so the row
        // is dropped from the result and a later `close`/`adjust` for the same
        // id is a deliberate no-op rather than a resurrection.
        var deleted: Set<UUID> = []

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let record = decode(line) else { continue }
            switch record {
            case let .open(id, projectID, start):
                guard indexByID[id] == nil else {
                    NSLog("Chronos: duplicate open record for session \(id); skipping")
                    continue
                }
                if let previous = openIndex, sessions[previous].isOpen {
                    NSLog("Chronos: session \(sessions[previous].id) was never closed; closing it at \(start)")
                    sessions[previous].end = max(start, sessions[previous].start)
                }
                indexByID[id] = sessions.count
                openIndex = sessions.count
                sessions.append(Session(id: id, projectID: projectID, start: start))
            case let .close(id, end):
                guard let index = indexByID[id] else {
                    NSLog("Chronos: close record for unknown session \(id); skipping")
                    continue
                }
                guard sessions[index].isOpen else {
                    NSLog("Chronos: session \(id) is already closed; skipping extra close")
                    continue
                }
                sessions[index].end = end
            case let .adjust(id, projectID, start, end):
                guard let index = indexByID[id] else {
                    NSLog("Chronos: adjust record for unknown session \(id); skipping")
                    continue
                }
                guard !deleted.contains(id) else {
                    NSLog("Chronos: adjust record for deleted session \(id); skipping")
                    continue
                }
                sessions[index].start = start
                if let projectID {
                    sessions[index].projectID = projectID
                }
                if let end {
                    sessions[index].end = end
                } else if !sessions[index].isOpen {
                    // An adjust never reopens a closed session — a reordered or
                    // hand-edited log must never resurrect a second ticking
                    // timer — so an omitted `end` here is a no-op, not a revert
                    // to running.
                    NSLog("Chronos: adjust for closed session \(id) omits end; leaving it closed")
                }
            case let .delete(id):
                guard let index = indexByID[id] else {
                    NSLog("Chronos: delete record for unknown session \(id); skipping")
                    continue
                }
                guard !deleted.contains(id) else { continue }
                // The row itself is left untouched — it is dropped from the
                // result below, not rewritten — but a still-open session must
                // stop being the tracked "open" one, or a following `open`
                // would force-close this ghost instead of ignoring it.
                if openIndex == index {
                    openIndex = nil
                }
                deleted.insert(id)
            }
        }
        return deleted.isEmpty ? sessions : sessions.filter { !deleted.contains($0.id) }
    }

    private func decode(_ line: Substring) -> SessionRecord? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            return try Self.decoder.decode(SessionRecord.self, from: Data(trimmed.utf8))
        } catch {
            NSLog("Chronos: skipping unreadable line in \(fileURL.lastPathComponent): \(error)")
            return nil
        }
    }

    // MARK: - Rotation

    /// Moves the current log aside, leaving no file behind so the next append
    /// starts a fresh one. Used for the yearly `sessions-YYYY.jsonl` rotation.
    func rotate(to archiveURL: URL) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path) else { return }
        guard !manager.fileExists(atPath: archiveURL.path) else {
            throw SessionLogError.archiveDestinationExists(archiveURL)
        }
        try manager.createDirectory(
            at: archiveURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try manager.moveItem(at: fileURL, to: archiveURL)
    }

    // MARK: - Coding

    /// One line per record: no pretty printing, ISO-8601 dates, stable key
    /// order so the file diffs cleanly.
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = JSONDates.encodingStrategy
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = JSONDates.decodingStrategy
        return decoder
    }()
}
