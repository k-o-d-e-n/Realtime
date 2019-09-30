import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(Realtime_FoundationDBTests.allTests),
    ]
}
#endif
