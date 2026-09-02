import SwiftUI

extension PaletteColor {
    /// Parses `#RRGGBB` (the `#` is optional), case-insensitive.
    ///
    /// Returns `nil` for anything else, so a hand-edited or truncated
    /// `projects.json` falls back to the palette default rather than painting a
    /// row an undefined color.
    init?(hexString: String) {
        var text = hexString.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6,
              text.allSatisfy(\.isHexDigit),
              let value = UInt32(text, radix: 16)
        else { return nil }
        self.init(hex: value)
    }
}

extension Palette {
    /// The color for a stored `#RRGGBB` string, or `nil` when it is absent or
    /// malformed. Call sites decide what the fallback should be.
    static func color(fromHex hex: String?) -> Color? {
        hex.flatMap(PaletteColor.init(hexString:))?.color
    }
}

extension Project {
    /// The project's color as palette components: the stored hex when it
    /// parses, Scarlet (SPEC §9's active-state color) otherwise.
    var paletteColor: PaletteColor {
        colorHex.flatMap(PaletteColor.init(hexString:)) ?? Palette.scarlet
    }

    /// The project's color, ready for SwiftUI.
    var displayColor: Color { paletteColor.color }
}

/// One entry in a row's "Change color" menu.
struct ProjectColorOption: Identifiable, Sendable {
    let name: String
    /// `#RRGGBB`, or `nil` for the palette default.
    let hex: String?

    var id: String { hex ?? "default" }
    var color: Color { Palette.color(fromHex: hex) ?? .chronosScarlet }
}

/// The fixed set of row colors (SPEC §5, "optional per-project color").
///
/// Scarlet and Gold come from the SPEC §9 palette; the rest are picked to stay
/// legible against Ink at the 18% tint the active row uses.
enum ProjectColorOptions {
    static let all: [ProjectColorOption] = [
        ProjectColorOption(name: "Default", hex: nil),
        ProjectColorOption(name: "Scarlet", hex: "#D7262F"),
        ProjectColorOption(name: "Gold", hex: "#F2B233"),
        ProjectColorOption(name: "Sky", hex: "#4FA3E3"),
        ProjectColorOption(name: "Mint", hex: "#3FBF8F"),
        ProjectColorOption(name: "Violet", hex: "#9B6DFF"),
        ProjectColorOption(name: "Coral", hex: "#FF7A59"),
    ]
}
