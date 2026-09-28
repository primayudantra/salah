import XCTest
@testable import SalahCore

final class SemanticVersionTests: XCTestCase {
    func testParsing() {
        XCTAssertEqual(SemanticVersion("1.2.3"), SemanticVersion(1, 2, 3))
        XCTAssertEqual(SemanticVersion("v1.10"), SemanticVersion(1, 10, 0))
        XCTAssertEqual(SemanticVersion("V2"), SemanticVersion(2, 0, 0))
        XCTAssertEqual(SemanticVersion("1.2.0-beta.1"), SemanticVersion(1, 2, 0))
        XCTAssertNil(SemanticVersion("latest"))
        XCTAssertNil(SemanticVersion("1..2"))
        XCTAssertNil(SemanticVersion("1.2.3.4"))
    }

    func testOrdering() {
        XCTAssertLessThan(SemanticVersion("1.0.0")!, SemanticVersion("1.1.0")!)
        XCTAssertLessThan(SemanticVersion("1.9.9")!, SemanticVersion("1.10.0")!)
        XCTAssertLessThan(SemanticVersion("1.2.3")!, SemanticVersion("2.0.0")!)
        XCTAssertFalse(SemanticVersion("1.1.0")! < SemanticVersion("v1.1.0")!)
    }
}
