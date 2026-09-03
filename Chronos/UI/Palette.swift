import AppKit
import SwiftUI

/// One color from the SPEC §9 palette, stored as plain sRGB components so the
/// values are `Sendable` and can be turned into whichever color type a call
/// site needs.
struct PaletteColor: Sendable, Equatable {
    let red: Double
    let green: Double
    let blue: Double

    init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    var color: Color { Color(red: red, green: green, blue: blue) }

    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

    func cgColor(alpha: Double = 1) -> CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

/// The Chronos palette (SPEC §9). Single source of truth for every color in
/// the app; the `AccentColor` asset mirrors `scarlet` for system controls.
enum Palette {
    /// Active state, bolt mark, accents.
    static let scarlet = PaletteColor(hex: 0xD7262F)
    /// Day total, highlights.
    static let gold = PaletteColor(hex: 0xF2B233)
    /// Panel background (dark glass).
    static let ink = PaletteColor(hex: 0x15171C)
    /// Primary text.
    static let paper = PaletteColor(hex: 0xF4F5F7)
    /// Secondary text, idle rows.
    static let muted = PaletteColor(hex: 0x8C93A1)
    /// A period ahead of the one before it, in the review window. Also one of
    /// the row colors in ``ProjectColorOptions``.
    static let mint = PaletteColor(hex: 0x3FBF8F)
    /// A period behind the one before it, in the review window. Also one of
    /// the row colors in ``ProjectColorOptions``.
    static let coral = PaletteColor(hex: 0xFF7A59)
}

extension Color {
    static var chronosScarlet: Color { Palette.scarlet.color }
    static var chronosGold: Color { Palette.gold.color }
    static var chronosInk: Color { Palette.ink.color }
    static var chronosPaper: Color { Palette.paper.color }
    static var chronosMuted: Color { Palette.muted.color }
    static var chronosMint: Color { Palette.mint.color }
    static var chronosCoral: Color { Palette.coral.color }
}
