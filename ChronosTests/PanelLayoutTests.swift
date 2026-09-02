import XCTest
@testable import Chronos

final class PanelLayoutTests: XCTestCase {
    /// The height that fits `count` rows before any clamping.
    private func unclampedHeight(rowCount: Int) -> CGFloat {
        PanelLayout.headerHeight
            + PanelLayout.dividerHeight * 2
            + CGFloat(rowCount) * PanelLayout.rowHeight
            + PanelLayout.listVerticalPadding * 2
            + PanelLayout.footerHeight
    }

    func testEmptyListStillMeetsTheMinimumHeight() {
        XCTAssertEqual(PanelLayout.height(rowCount: 0), PanelLayout.minHeight)
    }

    func testShortListsAreClampedToTheMinimum() {
        // A one-row panel would be shorter than the SPEC §4 minimum.
        XCTAssertLessThan(unclampedHeight(rowCount: 1), PanelLayout.minHeight)
        XCTAssertEqual(PanelLayout.height(rowCount: 1), PanelLayout.minHeight)
    }

    func testHeightGrowsOneRowAtATimeOncePastTheMinimum() {
        // Find the first count whose natural height clears the minimum; from
        // there every extra project adds exactly one row.
        guard let first = (0...20).first(where: { unclampedHeight(rowCount: $0) >= PanelLayout.minHeight })
        else { return XCTFail("no row count clears the minimum height") }

        XCTAssertEqual(PanelLayout.height(rowCount: first), unclampedHeight(rowCount: first))
        XCTAssertEqual(
            PanelLayout.height(rowCount: first + 1) - PanelLayout.height(rowCount: first),
            PanelLayout.rowHeight
        )
        XCTAssertEqual(
            PanelLayout.height(rowCount: first + 3) - PanelLayout.height(rowCount: first),
            PanelLayout.rowHeight * 3
        )
    }

    func testFourRowsFitWithoutClamping() {
        // The SPEC §5 mockup: four projects, one panel, no scrolling.
        let height = PanelLayout.height(rowCount: 4)
        XCTAssertEqual(height, unclampedHeight(rowCount: 4))
        XCTAssertGreaterThan(height, PanelLayout.minHeight)
        XCTAssertLessThan(height, PanelLayout.maxHeight)
    }

    func testLongListsStopAtTheMaximumAndScroll() {
        XCTAssertEqual(PanelLayout.height(rowCount: 100), PanelLayout.maxHeight)
        XCTAssertGreaterThan(unclampedHeight(rowCount: 100), PanelLayout.maxHeight)
    }

    func testHeightNeverDecreasesAsProjectsAreAdded() {
        for count in 0..<40 {
            XCTAssertLessThanOrEqual(
                PanelLayout.height(rowCount: count),
                PanelLayout.height(rowCount: count + 1)
            )
        }
    }

    func testNegativeRowCountsAreTreatedAsEmpty() {
        XCTAssertEqual(PanelLayout.height(rowCount: -3), PanelLayout.height(rowCount: 0))
    }

    func testPanelIsTheSpecWidth() {
        XCTAssertEqual(PanelLayout.width, 280)
    }
}
