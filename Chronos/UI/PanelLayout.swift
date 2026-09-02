import CoreGraphics

/// The panel's fixed geometry, kept as pure arithmetic so the window can be
/// sized before the SwiftUI view has ever laid out (SPEC §4: ~280pt wide,
/// height grows with the project list between ~200 and ~600pt, then scrolls).
///
/// Every constant here is also applied to the matching view, so
/// ``height(rowCount:)`` and what the panel actually draws cannot drift:
/// ``HeaderView`` is pinned to ``headerHeight``, ``FooterView`` to
/// ``footerHeight``, and each ``ProjectRowView`` to ``rowHeight``.
enum PanelLayout {
    static let width: CGFloat = 280

    static let headerHeight: CGFloat = 66
    static let footerHeight: CGFloat = 40
    static let rowHeight: CGFloat = 32
    /// Breathing room above and below the row list (each side).
    static let listVerticalPadding: CGFloat = 8
    /// The prompt shown instead of the list when there are no projects.
    static let emptyStateHeight: CGFloat = 60
    static let dividerHeight: CGFloat = 1

    /// Horizontal inset shared by the header, the rows, and the footer.
    static let horizontalPadding: CGFloat = 14
    /// How far a row's tinted background extends past its content on each
    /// side; the row is inset by this much less than `horizontalPadding` so
    /// the text still lines up with the header and footer.
    static let rowInset: CGFloat = 6

    static let minHeight: CGFloat = 200
    static let maxHeight: CGFloat = 600

    /// The panel height that fits `rowCount` project rows, clamped to
    /// [``minHeight``, ``maxHeight``]. Past the maximum the list scrolls
    /// instead of growing.
    static func height(rowCount: Int) -> CGFloat {
        let rows = max(0, rowCount)
        let listHeight = rows == 0
            ? emptyStateHeight
            : CGFloat(rows) * rowHeight + listVerticalPadding * 2
        let content = headerHeight + dividerHeight + listHeight + dividerHeight + footerHeight
        return min(max(content, minHeight), maxHeight)
    }
}
