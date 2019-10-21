import XCTest
import RealtimeTestLib

#if !os(macOS)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(RealtimeTests.allTests),
        testCase(ListenableTests.allTests)
    ]
}
#endif
