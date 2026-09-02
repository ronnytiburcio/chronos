import SwiftUI

/// Chronos's mark (SPEC §9): an original two-kink lightning bolt, drawn as a
/// plain polygon so there is no artwork file to license and the same geometry
/// serves the 14pt header mark, the 18pt menu bar template, and the 1024px app
/// icon.
///
/// The outline is six vertices in a unit box (`0...1` on both axes, y growing
/// *downwards* like SwiftUI and SVG). Scaling to a rect is the only thing
/// ``path(in:)`` does, so the shape is resolution-independent by construction.
///
/// ```
///            (0.72, 0.00)          apex
///           /        \
///          /          \            upper limb (the heavier one)
///  (0.14,0.56)         (0.60,0.44)–(0.86,0.44)
///        \                        /
///     (0.44,0.56)                /  lower limb
///           \                   /
///            (0.28, 1.00)          bottom tip
/// ```
///
/// - Important: ``points`` is duplicated in `Scripts/render-icons.swift`, which
///   renders the app icon and the menu bar template images from the same list.
///   **The two must stay identical** — `BoltShapeTests` pins this list against a
///   fixture so a change here fails the build until the script is updated and
///   the icons are re-rendered (`swift Scripts/render-icons.swift`).
struct BoltShape: Shape {
    /// The bolt outline in a unit box, clockwise from the apex, y down.
    static let points: [CGPoint] = [
        CGPoint(x: 0.72, y: 0.00),   // apex
        CGPoint(x: 0.14, y: 0.56),   // left kink, outer
        CGPoint(x: 0.44, y: 0.56),   // left kink, inner
        CGPoint(x: 0.28, y: 1.00),   // bottom tip
        CGPoint(x: 0.86, y: 0.44),   // right kink, outer
        CGPoint(x: 0.60, y: 0.44)    // right kink, inner
    ]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width > 0, rect.height > 0 else { return path }

        let scaled = Self.points.map { point in
            CGPoint(
                x: rect.minX + point.x * rect.width,
                y: rect.minY + point.y * rect.height
            )
        }

        path.move(to: scaled[0])
        for point in scaled.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
}
