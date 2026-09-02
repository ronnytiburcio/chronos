import Foundation

/// The little bit of RFC-4180 that Chronos actually needs.
///
/// Project names are user-typed, so `Admin, "Finance"` has to survive the trip
/// into a spreadsheet intact: a field containing a comma, a double quote, or a
/// newline is wrapped in quotes and its own quotes are doubled.
enum CSV {
    static func field(_ value: String) -> String {
        // Scalars, not characters: a CRLF is a *single* Swift `Character`, so
        // a grapheme-level search for "\n" walks straight past it.
        guard value.unicodeScalars.contains(where: {
            $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r"
        }) else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// One line, escaped and newline-terminated.
    static func row(_ fields: [String]) -> String {
        fields.map(field).joined(separator: ",") + "\n"
    }
}
