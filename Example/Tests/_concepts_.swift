//
//  _concepts_.swift
//  Realtime_Tests
//
//  Created by Denis Koryttsev on 18/11/2018.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import XCTest
import Foundation
@testable import Realtime

class ConceptTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
}

// MARK: - Constants

struct Constants {
    static let iterationCount = 10_000
}

// MARK: - Helpers

func print(from function: String = #function, average time: UInt64) {
    print(String(format: "\(function) = Average time: %.10lf", Double(time) / Double(NSEC_PER_SEC)))
}

func print(from function: String = #function, total time: TimeInterval) {
    print(String(format: "\(function) = Total time: %.10lf", time))
}
/*
extension ConceptTests {
    typealias TestingPromise<T> = __Promise<T>

    // MARK: GCD

    /// Measures the average time needed to get into a dispatch_async block.
    func testDispatchAsyncOnSerialQueue() {
        // Arrange.
        let expectation = self.expectation(description: "")
        expectation.expectedFulfillmentCount = Constants.iterationCount
        let queue = DispatchQueue(label: #function, qos: .userInitiated)
        let semaphore = DispatchSemaphore(value: 0)

        // Act.
        DispatchQueue.main.async {
            let time = dispatch_benchmark(Constants.iterationCount) {
                queue.async {
                    semaphore.signal()
                    expectation.fulfill()
                }
                semaphore.wait()
            }
            print(average: time)
        }

        // Assert.
        waitForExpectations(timeout: 10)
    }

    /// Measures the average time needed to get into a doubly nested dispatch_async block.
    func testDoubleDispatchAsyncOnSerialQueue() {
        // Arrange.
        let expectation = self.expectation(description: "")
        expectation.expectedFulfillmentCount = Constants.iterationCount
        let queue = DispatchQueue(label: #function, qos: .userInitiated)
        let semaphore = DispatchSemaphore(value: 0)

        // Act.
        DispatchQueue.main.async {
            let time = dispatch_benchmark(Constants.iterationCount) {
                queue.async {
                    queue.async {
                        semaphore.signal()
                        expectation.fulfill()
                    }
                }
                semaphore.wait()
            }
            print(average: time)
        }

        // Assert.
        waitForExpectations(timeout: 10)
    }

    /// Measures the average time needed to get into a triply nested dispatch_async block.
    func testTripleDispatchAsyncOnSerialQueue() {
        // Arrange.
        let expectation = self.expectation(description: "")
        expectation.expectedFulfillmentCount = Constants.iterationCount
        let queue = DispatchQueue(label: #function, qos: .userInitiated)
        let semaphore = DispatchSemaphore(value: 0)

        // Act.
        DispatchQueue.main.async {
            let time = dispatch_benchmark(Constants.iterationCount) {
                queue.async {
                    queue.async {
                        queue.async {
                            semaphore.signal()
                            expectation.fulfill()
                        }
                    }
                }
                semaphore.wait()
            }
            print(average: time)
        }

        // Assert.
        waitForExpectations(timeout: 10)
    }

    /// Measures the total time needed to perform a lot of `DispatchQueue.async` blocks on
    /// a concurrent queue.
    func testDispatchAsyncOnConcurrentQueue() {
        // Arrange.
        let queue = DispatchQueue(label: #function, qos: .userInitiated, attributes: .concurrent)
        let group = DispatchGroup()
        var blocks = [() -> Void]()
        for _ in 0..<Constants.iterationCount {
            group.enter()
            blocks.append({
                group.leave()
            })
        }
        let startDate = Date()

        // Act.
        for block in blocks {
            queue.async {
                block()
            }
        }

        // Assert.
        XCTAssert(group.wait(timeout: .now() + 1) == .success)
        let endDate = Date()
        print(total: endDate.timeIntervalSince(startDate))
    }

    // MARK: TestingPromise

    /// Measures the average time needed to create a resolved `Promise` and get into a `then` block
    /// chained to it.
    func testThenOnSerialQueue() {
        // Arrange.
        let expectation = self.expectation(description: "")
        expectation.expectedFulfillmentCount = Constants.iterationCount
        let queue = DispatchQueue(label: #function, qos: .userInitiated)
        let semaphore = DispatchSemaphore(value: 0)

        // Act.
        DispatchQueue.main.async {
            let time = dispatch_benchmark(Constants.iterationCount) {
                TestingPromise<Bool>(true).then(on: queue) { _ in
                    semaphore.signal()
                    expectation.fulfill()
                }
                semaphore.wait()
            }
            print(average: time)
        }

        // Assert.
        waitForExpectations(timeout: 10)
    }

    /// Measures the average time needed to create a resolved `Promise`, chain two `then` blocks on
    /// it and get into the last `then` block.
    func testDoubleThenOnSerialQueue() {
        // Arrange.
        let expectation = self.expectation(description: "")
        expectation.expectedFulfillmentCount = Constants.iterationCount
        let queue = DispatchQueue(label: #function, qos: .userInitiated)
        let semaphore = DispatchSemaphore(value: 0)

        // Act.
        DispatchQueue.main.async {
            var fulfilled_counter = 0
            var expected_counter = 0
            let time = dispatch_benchmark(Constants.iterationCount) {
                TestingPromise<Bool>(true)
                    .then(on: queue) { $0 }
                    .then(on: queue) { _ in
                        fulfilled_counter += 1
                        semaphore.signal()
                        expectation.fulfill()
                }
                expected_counter += 1
                semaphore.wait()
            }
            print(average: time)
        }

        // Assert.
        waitForExpectations(timeout: 10) { (err) in
            err.map({ XCTFail($0.localizedDescription) })
        }
    }

    /// Measures the average time needed to create a resolved `Promise`, chain three `then` blocks on
    /// it and get into the last `then` block.
    func testTripleThenOnSerialQueue() {
        // Arrange.
        let expectation = self.expectation(description: "")
        expectation.expectedFulfillmentCount = Constants.iterationCount
        let queue = DispatchQueue(label: #function, qos: .userInitiated)
        let semaphore = DispatchSemaphore(value: 0)

        // Act.
        DispatchQueue.main.async {
            let time = dispatch_benchmark(Constants.iterationCount) {
                TestingPromise<Bool>(true).then(on: queue) { _ in
                    }.then(on: queue) { _ in
                    }.then(on: queue) { _ in
                        semaphore.signal()
                        expectation.fulfill()
                }
                semaphore.wait()
            }
            print(average: time)
        }

        // Assert.
        waitForExpectations(timeout: 10)
    }

    /// Measures the total time needed to resolve a lot of pending `Promise` with chained `then`
    /// blocks on them on a concurrent queue and wait for each of them to get into chained block.
    func testThenOnConcurrentQueue() {
        // Arrange.
        let queue = DispatchQueue(label: #function, qos: .userInitiated, attributes: .concurrent)
        let group = DispatchGroup()
        var promises = [TestingPromise<Bool>]()
        for _ in 0..<Constants.iterationCount {
            group.enter()
            let promise = TestingPromise<Bool>()
            promise.then(on: queue) { _ in
                group.leave()
            }
            promises.append(promise)
        }
        let startDate = Date()

        // Act.
        for promise in promises {
            promise.fulfill(true)
        }

        // Assert.
        XCTAssert(group.wait(timeout: .now() + 60) == .success)
        let endDate = Date()
        print(total: endDate.timeIntervalSince(startDate))
    }
}
*/
