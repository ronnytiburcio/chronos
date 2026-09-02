import CoreGraphics

/// Pure geometry for deciding where the panel opens.
///
/// Kept free of AppKit so it can be unit tested without a screen. The caller
/// passes the full frame of every screen (a saved position is kept as long as
/// enough of the panel is on *some* screen, Dock and menu bar included, since
/// the user may have parked it there on purpose) and the area to use for the
/// first-launch placement (the main screen's `visibleFrame`).
enum WindowPlacement {
    /// Gap between the panel and the placement area's edges on first launch.
    static let defaultMargin: CGFloat = 24

    /// How much of the panel has to stay on a screen for a saved frame to be
    /// considered usable. A display that went away, or a frame saved from a
    /// larger arrangement, falls back to the default placement instead of
    /// leaving the panel somewhere the user cannot reach it.
    static let minimumVisibleExtent: CGFloat = 40

    /// The frame the panel should open with.
    ///
    /// The saved *origin* is honoured but the caller's `size` always wins, so a
    /// frame written by an older build (or before the project list changed the
    /// panel's height) can never resurrect a stale size.
    static func resolvedFrame(
        saved: CGRect?,
        size: CGSize,
        screens: [CGRect],
        placementArea: CGRect?
    ) -> CGRect {
        if let saved {
            let candidate = CGRect(origin: saved.origin, size: size)
            if isSufficientlyVisible(candidate, on: screens) {
                return candidate
            }
        }
        return defaultFrame(size: size, on: placementArea)
    }

    /// True when `frame` overlaps at least one screen by
    /// ``minimumVisibleExtent`` in both directions (or by its full extent, for
    /// panels smaller than that).
    static func isSufficientlyVisible(_ frame: CGRect, on screens: [CGRect]) -> Bool {
        screens.contains { screen in
            let overlap = screen.intersection(frame)
            guard !overlap.isNull else { return false }
            return overlap.width >= min(minimumVisibleExtent, frame.width)
                && overlap.height >= min(minimumVisibleExtent, frame.height)
        }
    }

    /// Top-right of the given area, inset by ``defaultMargin``.
    /// Coordinates are Cocoa's (origin bottom-left).
    static func defaultFrame(size: CGSize, on area: CGRect?) -> CGRect {
        guard let area, !area.isEmpty else {
            return CGRect(origin: .zero, size: size)
        }
        let x = max(area.minX, area.maxX - defaultMargin - size.width)
        let y = max(area.minY, area.maxY - defaultMargin - size.height)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
