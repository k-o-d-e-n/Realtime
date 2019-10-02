import XCTest

import RealtimeTestLib

var tests = [XCTestCaseEntry]()
tests += RealtimeTestLib.__allTests()

XCTMain(tests)
