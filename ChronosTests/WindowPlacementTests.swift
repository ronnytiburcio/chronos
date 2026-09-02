import XCTest
@testable import Chronos

final class WindowPlacementTests: XCTestCase {
    private let panelSize = CGSize(width: 280, height: 320)
    private let mainScreen = CGRect(x: 0, y: 0, width: 1440, height: 875)

    func testNoSavedFrameOpensTopRightWithMargin() {
        let frame = WindowPlacement.resolvedFrame(saved: nil, size: panelSize, screens: [mainScreen], placementArea: mainScreen)

        XCTAssertEqual(frame.size, panelSize)
        XCTAssertEqual(frame.maxX, mainScreen.maxX - WindowPlacement.defaultMargin)
        XCTAssertEqual(frame.maxY, mainScreen.maxY - WindowPlacement.defaultMargin)
    }

    func testNoScreensStillReturnsRequestedSize() {
        let frame = WindowPlacement.resolvedFrame(saved: nil, size: panelSize, screens: [], placementArea: nil)

        XCTAssertEqual(frame.size, panelSize)
    }

    func testSavedFrameOnScreenIsRestored() {
        let saved = CGRect(x: 120, y: 200, width: 280, height: 320)

        let frame = WindowPlacement.resolvedFrame(saved: saved, size: panelSize, screens: [mainScreen], placementArea: mainScreen)

        XCTAssertEqual(frame, saved)
    }

    func testSavedFrameKeepsOriginButTakesCurrentSize() {
        // A frame written by an older build must not resurrect its height.
        let saved = CGRect(x: 120, y: 200, width: 280, height: 600)

        let frame = WindowPlacement.resolvedFrame(saved: saved, size: panelSize, screens: [mainScreen], placementArea: mainScreen)

        XCTAssertEqual(frame.origin, saved.origin)
        XCTAssertEqual(frame.size, panelSize)
    }

    func testFullyOffScreenSavedFrameFallsBackToDefault() {
        let saved = CGRect(x: 5000, y: 4000, width: 280, height: 320)

        let frame = WindowPlacement.resolvedFrame(saved: saved, size: panelSize, screens: [mainScreen], placementArea: mainScreen)

        XCTAssertEqual(frame, WindowPlacement.defaultFrame(size: panelSize, on: mainScreen))
    }

    func testBarelyVisibleSavedFrameIsRejected() {
        // Only 39pt of the panel would remain on screen horizontally.
        let saved = CGRect(x: mainScreen.maxX - 39, y: 200, width: 280, height: 320)

        let frame = WindowPlacement.resolvedFrame(saved: saved, size: panelSize, screens: [mainScreen], placementArea: mainScreen)

        XCTAssertEqual(frame, WindowPlacement.defaultFrame(size: panelSize, on: mainScreen))
    }

    func testExactlyMinimumVisibleSavedFrameIsAccepted() {
        let saved = CGRect(
            x: mainScreen.maxX - WindowPlacement.minimumVisibleExtent,
            y: 200,
            width: 280,
            height: 320
        )

        let frame = WindowPlacement.resolvedFrame(saved: saved, size: panelSize, screens: [mainScreen], placementArea: mainScreen)

        XCTAssertEqual(frame.origin, saved.origin)
    }

    func testSavedFrameOnSecondScreenIsRestored() {
        let secondScreen = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let saved = CGRect(x: 1600, y: 400, width: 280, height: 320)

        let frame = WindowPlacement.resolvedFrame(
            saved: saved,
            size: panelSize,
            screens: [mainScreen, secondScreen],
            placementArea: mainScreen
        )

        XCTAssertEqual(frame, saved)
    }

    func testSavedFrameOnDisconnectedScreenFallsBackToMainScreen() {
        let saved = CGRect(x: 1600, y: 400, width: 280, height: 320)

        let frame = WindowPlacement.resolvedFrame(saved: saved, size: panelSize, screens: [mainScreen], placementArea: mainScreen)

        XCTAssertEqual(frame, WindowPlacement.defaultFrame(size: panelSize, on: mainScreen))
    }

    func testSavedFrameUnderTheDockIsKeptWhenScreensAreFullFrames() {
        // The user may park the panel partly under the Dock on purpose; the
        // guard checks against full screen frames, not the visible area.
        let visibleArea = CGRect(x: 0, y: 80, width: 1440, height: 770)
        let saved = CGRect(x: 120, y: 10, width: 280, height: 320)

        let frame = WindowPlacement.resolvedFrame(
            saved: saved,
            size: panelSize,
            screens: [mainScreen],
            placementArea: visibleArea
        )

        XCTAssertEqual(frame, saved)
    }

    func testDefaultFrameOnTinyScreenStaysInsideIt() {
        let tinyScreen = CGRect(x: 0, y: 0, width: 200, height: 200)

        let frame = WindowPlacement.defaultFrame(size: panelSize, on: tinyScreen)

        XCTAssertEqual(frame.minX, tinyScreen.minX)
        XCTAssertEqual(frame.minY, tinyScreen.minY)
    }
}
