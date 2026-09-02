import SwiftUI
import XCTest
@testable import Chronos

final class BoltShapeTests: XCTestCase {
    /// The bolt outline as `Scripts/render-icons.swift` has it. The app icon and
    /// the menu bar template images are rendered from that copy, so if this
    /// fixture and ``BoltShape/points`` ever disagree the shipped artwork no
    /// longer matches the mark drawn in the header.
    ///
    /// Changing the bolt means changing three things together: `BoltShape`,
    /// the `boltPoints` list in the script, and this fixture — then re-running
    /// `swift Scripts/render-icons.swift` and committing the new PNGs.
    private static let renderScriptPoints: [CGPoint] = [
        CGPoint(x: 0.72, y: 0.00),
        CGPoint(x: 0.14, y: 0.56),
        CGPoint(x: 0.44, y: 0.56),
        CGPoint(x: 0.28, y: 1.00),
        CGPoint(x: 0.86, y: 0.44),
        CGPoint(x: 0.60, y: 0.44)
    ]

    func testPointsMatchTheRenderScript() {
        XCTAssertEqual(BoltShape.points, Self.renderScriptPoints)
    }

    func testPointsLieInTheUnitBox() {
        for point in BoltShape.points {
            XCTAssertTrue((0...1).contains(point.x), "x out of the unit box: \(point)")
            XCTAssertTrue((0...1).contains(point.y), "y out of the unit box: \(point)")
        }
    }

    func testPathIsNotEmpty() {
        let path = BoltShape().path(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertFalse(path.isEmpty)
        XCTAssertGreaterThan(path.boundingRect.width, 0)
        XCTAssertGreaterThan(path.boundingRect.height, 0)
    }

    func testPathStaysInsideTheRect() {
        for rect in [
            CGRect(x: 0, y: 0, width: 16, height: 16),
            CGRect(x: 0, y: 0, width: 1024, height: 1024),
            CGRect(x: 37, y: -12, width: 40, height: 90)      // offset origins too
        ] {
            let bounds = BoltShape().path(in: rect).boundingRect
            XCTAssertTrue(
                rect.insetBy(dx: -0.001, dy: -0.001).contains(bounds),
                "\(bounds) escapes \(rect)"
            )
        }
    }

    /// The mark has to fill its box vertically (it is drawn at 14pt in the
    /// header and 16pt in the menu bar) and stay narrower than it is tall.
    func testPathFillsItsBoxVerticallyAndIsNarrowerThanItIsTall() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let bounds = BoltShape().path(in: rect).boundingRect
        XCTAssertEqual(bounds.height, 100, accuracy: 0.001)
        XCTAssertLessThan(bounds.width, bounds.height)
    }

    func testEmptyRectDrawsNothing() {
        XCTAssertTrue(BoltShape().path(in: .zero).isEmpty)
    }
}
