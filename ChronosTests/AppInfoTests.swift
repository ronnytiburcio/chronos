import XCTest
@testable import Chronos

final class AppInfoTests: XCTestCase {
    func testAppNameIsChronos() {
        XCTAssertEqual(AppInfo.name, "Chronos")
    }

    func testVersionLooksSemantic() {
        let parts = AppInfo.version.split(separator: ".")
        XCTAssertEqual(parts.count, 3, "expected MAJOR.MINOR.PATCH, got \(AppInfo.version)")
        XCTAssertTrue(parts.allSatisfy { Int($0) != nil })
    }
}
