import Foundation

/// Reads and writes `Codable` values as JSON files.
///
/// Writes are atomic (`Data.write(options: .atomic)` stages the bytes in a
/// temp file and renames it into place), so a crash mid-write can never leave
/// a half-written file behind. Every JSON file Chronos owns goes through here
/// so the encoding settings stay identical (dates: see ``JSONDates``).
enum JSONFile {
    static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = JSONDates.decodingStrategy
        return try decoder.decode(type, from: data)
    }

    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = JSONDates.encodingStrategy
        let data = try encoder.encode(value)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
