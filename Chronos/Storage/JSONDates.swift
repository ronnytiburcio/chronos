import Foundation

/// ISO-8601 with fractional seconds for every JSON file Chronos writes, so a
/// `Date` survives a round trip through disk unchanged. Reading also accepts
/// whole-second timestamps, so hand-written or older files still load.
enum JSONDates {
    static var encodingStrategy: JSONEncoder.DateEncodingStrategy {
        .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(string(from: date))
        }
    }

    static var decodingStrategy: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = date(from: text) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "not an ISO-8601 date: \(text)"
                )
            }
            return date
        }
    }

    static func string(from date: Date) -> String {
        formatter(fractional: true).string(from: date)
    }

    static func date(from text: String) -> Date? {
        formatter(fractional: true).date(from: text) ?? formatter(fractional: false).date(from: text)
    }

    private static func formatter(fractional: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractional
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }
}
