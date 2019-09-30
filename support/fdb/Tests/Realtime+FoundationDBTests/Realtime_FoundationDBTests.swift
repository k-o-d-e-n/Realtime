import XCTest
@testable import Realtime_FoundationDB

final class Realtime_FoundationDBTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(Realtime_FoundationDB().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
