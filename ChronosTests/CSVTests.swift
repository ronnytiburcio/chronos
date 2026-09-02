import XCTest
@testable import Chronos

final class CSVTests: XCTestCase {
    func testPlainFieldsAreLeftAlone() {
        XCTAssertEqual(CSV.field("Client Work"), "Client Work")
        XCTAssertEqual(CSV.field(""), "")
        XCTAssertEqual(CSV.field("2026-09-02"), "2026-09-02")
    }

    func testCommasAreQuoted() {
        XCTAssertEqual(CSV.field("Admin, Finance"), "\"Admin, Finance\"")
    }

    func testQuotesAreDoubledAndTheFieldIsQuoted() {
        XCTAssertEqual(CSV.field("Admin, \"Finance\""), "\"Admin, \"\"Finance\"\"\"")
        // A quote on its own still forces the wrapping, or the doubling would
        // be read as literal text.
        XCTAssertEqual(CSV.field("say \"hi\""), "\"say \"\"hi\"\"\"")
    }

    func testNewlinesAreQuoted() {
        XCTAssertEqual(CSV.field("two\nlines"), "\"two\nlines\"")
        XCTAssertEqual(CSV.field("two\r\nlines"), "\"two\r\nlines\"")
    }

    func testRowJoinsEscapedFieldsAndEndsWithANewline() {
        XCTAssertEqual(
            CSV.row(["2026-09-02", "Admin, \"Finance\"", "3600", "1.00"]),
            "2026-09-02,\"Admin, \"\"Finance\"\"\",3600,1.00\n"
        )
    }
}
