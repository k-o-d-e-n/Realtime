import XCTest
import RealtimeTestLib

#if !os(macOS)
public func allTests() -> [XCTestCaseEntry] {
    return RealtimeTestLib.__allTests()
}
#endif
