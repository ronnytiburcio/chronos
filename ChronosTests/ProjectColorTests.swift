import XCTest
@testable import Chronos

final class ProjectColorTests: XCTestCase {
    func testParsesSixDigitHexWithAndWithoutTheHash() {
        XCTAssertEqual(PaletteColor(hexString: "#D7262F"), Palette.scarlet)
        XCTAssertEqual(PaletteColor(hexString: "D7262F"), Palette.scarlet)
    }

    func testParsingIsCaseInsensitive() {
        XCTAssertEqual(PaletteColor(hexString: "#d7262f"), Palette.scarlet)
        XCTAssertEqual(PaletteColor(hexString: "#f2b233"), Palette.gold)
    }

    func testSurroundingWhitespaceIsIgnored() {
        XCTAssertEqual(PaletteColor(hexString: "  #15171C "), Palette.ink)
    }

    func testComponentsMapToTheRightChannels() {
        let white = PaletteColor(hexString: "#FFFFFF")
        XCTAssertEqual(white?.red, 1)
        XCTAssertEqual(white?.green, 1)
        XCTAssertEqual(white?.blue, 1)

        let red = PaletteColor(hexString: "#FF0000")
        XCTAssertEqual(red?.red, 1)
        XCTAssertEqual(red?.green, 0)
        XCTAssertEqual(red?.blue, 0)
    }

    func testMalformedHexIsRejected() {
        XCTAssertNil(PaletteColor(hexString: ""))
        XCTAssertNil(PaletteColor(hexString: "#"))
        XCTAssertNil(PaletteColor(hexString: "#FFF"))          // shorthand is not supported
        XCTAssertNil(PaletteColor(hexString: "#FFFFFFF"))      // too long
        XCTAssertNil(PaletteColor(hexString: "#GGGGGG"))       // not hex digits
        XCTAssertNil(PaletteColor(hexString: "#FF 00 00"))     // inner spaces
        XCTAssertNil(PaletteColor(hexString: "rebeccapurple"))
    }

    func testProjectFallsBackToScarlet() {
        XCTAssertEqual(project(colorHex: nil).paletteColor, Palette.scarlet)
        XCTAssertEqual(project(colorHex: "not a color").paletteColor, Palette.scarlet)
        XCTAssertEqual(project(colorHex: "#12345").paletteColor, Palette.scarlet)
    }

    func testProjectUsesItsOwnColorWhenItParses() {
        XCTAssertEqual(project(colorHex: "#F2B233").paletteColor, Palette.gold)
    }

    func testEveryColorMenuOptionParses() {
        for option in ProjectColorOptions.all {
            guard let hex = option.hex else { continue }  // "Default" carries no hex
            XCTAssertNotNil(PaletteColor(hexString: hex), "\(option.name) (\(hex)) does not parse")
        }
    }

    func testColorMenuOptionsAreUnique() {
        let ids = ProjectColorOptions.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    private func project(colorHex: String?) -> Project {
        Project(name: "Test", colorHex: colorHex, sortOrder: 0)
    }
}
