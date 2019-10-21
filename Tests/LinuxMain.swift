import XCTest
import Realtime
import RealtimeTestLib

var tests = [XCTestCaseEntry]()
RealtimeTests.allTestsSetUp = {
    let configuration = RealtimeApp.Configuration(linksNode: BranchNode(key: "___tests/__links"))
    RealtimeApp.initialize(with: RealtimeApp.cache, storage: RealtimeApp.cache, configuration: configuration)
}
tests += RealtimeTestLib.__allTests()

XCTMain(tests)
