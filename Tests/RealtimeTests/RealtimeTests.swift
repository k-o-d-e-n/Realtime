import XCTest
@testable import Realtime

final class RealtimeTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        // XCTAssertEqual(realtime().text, "Hello, World!")
    }


    static var allTests = [
        ("testExample", testExample),
    ]
}

final class ListenableTests: XCTestCase {
    var store = ListeningDisposeStore()

    static var allTests = [
        ("testAccumulator", testAccumulator),
        ("testAccumulator2", testAccumulator2),
        ("testCombine", testCombine),
        ("testSharedContinuous", testSharedContinuous),
        ("testSharedRepeatable", testSharedRepeatable),
        ("testShareRepeatable", testShareRepeatable),
        ("testShareContinuous", testShareContinuous),
    ]
}

func getRandomNum(_ value: UInt32) -> UInt32 {
    #if os(Linux)
        return UInt32(random())
    #else
        return arc4random_uniform(value)
    #endif
}

extension ListenableTests {
    func testAccumulator() {
        let source1 = Repeater<Int>.unsafe()
        let source2 = Repeater<Int>.unsafe()

        let accumulator = Accumulator<Int>(repeater: Repeater.unsafe(), source1, source2)

        var value_counter = 0
        accumulator.listening(onValue: { v in
            defer { value_counter += 1 }
            switch value_counter {
            case 0: XCTAssertEqual(v, 5)
            case 1: XCTAssertEqual(v, 199)
            default: XCTFail()
            }
        }).add(to: store)

        source1.send(.value(5))
        source2.send(.value(199))

        var error_counter = 0
        accumulator.listening(onError: { e in
            defer { error_counter += 1 }
            switch error_counter {
            case 0: XCTAssertTrue(e is RealtimeError) //XCTAssertEqual(e.localizedDescription, "Source1 error")
            case 1: XCTAssertTrue(e is RealtimeError) //XCTAssertEqual(e.localizedDescription, "Source2 error")
            default: XCTFail()
            }
        }).add(to: store)

        source1.send(.error(RealtimeError(source: .listening, description: "Source1 error")))
        source1.send(.error(RealtimeError(source: .listening, description: "Source2 error")))
    }

    func testAccumulator2() {
        let source1 = Repeater<Int>.unsafe()
        let source2 = Repeater<String>.unsafe()

        let accumulator = Accumulator<(Int, String)>(repeater: Repeater.unsafe(), source1, source2)

//        var value_counter = 0
        accumulator.listening(onValue: { v in
//            defer { value_counter += 1 }
            switch v {
            case (5, "199"): print("true")
            default: XCTFail()
            }
        }).add(to: store)

        source1.send(.value(5))
        source2.send(.value("199"))

        var error_counter = 0
        accumulator.listening(onError: { e in
            defer { error_counter += 1 }
            switch error_counter {
            case 0: XCTAssertTrue(e is RealtimeError) //XCTAssertEqual(e.localizedDescription, "Source1 error")
            case 1: XCTAssertTrue(e is RealtimeError) //XCTAssertEqual(e.localizedDescription, "Source2 error")
            default: XCTFail()
            }
        }).add(to: store)

        source1.send(.error(RealtimeError(source: .listening, description: "Source1 error")))
        source1.send(.error(RealtimeError(source: .listening, description: "Source2 error")))
    }

    func testCombine() {
        let exp = expectation(description: "")

        let source1 = Repeater<Int>.unsafe()
        let source2 = Repeater<Int>.unsafe()

        var value_counter = 0
        source1.combine(with: source2).listening(onValue: { v in
            defer { value_counter += 1 }
            switch value_counter {
            case 0:
                XCTAssertEqual(v.0, 5)
                XCTAssertEqual(v.1, 199)
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                    exp.fulfill()
                }
            default: XCTFail()
            }
        }).add(to: store)

        source1.send(.value(5))
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
            source2.send(.value(199))
        }

        waitForExpectations(timeout: 5) { (err) in
            err.map({ XCTFail($0.localizedDescription) })
        }
    }

    func testSharedContinuous() {
        let source = Repeater<Int>.unsafe()

        var value_counter = 0
        var sharedSource: Shared<UInt32>? = source
            .do(onValue: {
                if value_counter == 3 {
                    XCTAssertTrue($0 == 0 || $0 == 1000)
                }
            })
            .map(UInt32.init)
            .map(getRandomNum)
            .do(onValue: { print($0) })
            .shared(connectionLive: .continuous)
        let disposable1 = sharedSource!.listening(onValue: { value in
            value_counter += 1
        })
        let disposable2 = sharedSource!.listening(onValue: { value in
            value_counter += 1
        })

        source.send(.value(10))
        XCTAssertEqual(value_counter, 2)
        disposable1.dispose()
        source.send(.value(100))
        XCTAssertEqual(value_counter, 3)
        disposable2.dispose()
        source.send(.value(0))
        XCTAssertEqual(value_counter, 3)

        switch sharedSource!.liveStrategy {
        case .continuous(let dispose): XCTAssertFalse((dispose as? ListeningDispose)?.isDisposed ?? true)
        case .repeatable: XCTFail("Unexpected strategy")
        }

        let disposable3 = sharedSource!.listening(onValue: { value in
            value_counter += 1
        })
        sharedSource = nil // connection must dispose
        source.send(.value(1000))
        XCTAssertEqual(value_counter, 3)
        disposable3.dispose()
    }

    func testSharedRepeatable() {
        let source = Repeater<Int>.unsafe()

        var value_counter = 0
        var shareSource: Shared<UInt32>? = source
            .do(onValue: {
                if $0 == 0 {
                    XCTFail("Must not call")
                }
            })
            .map(UInt32.init)
            .map(getRandomNum)
            .do(onValue: { print($0) })
            .shared(connectionLive: .repeatable)
        let disposable1 = shareSource!.listening(onValue: { value in
            value_counter += 1
        })
        let disposable2 = shareSource!.listening(onValue: { value in
            value_counter += 1
        })

        source.send(.value(10))
        XCTAssertEqual(value_counter, 2)
        disposable1.dispose()
        source.send(.value(100))
        XCTAssertEqual(value_counter, 3)
        disposable2.dispose()
        source.send(.value(1000))
        XCTAssertEqual(value_counter, 3)
        source.send(.value(0))
        XCTAssertEqual(value_counter, 3)

        switch shareSource!.liveStrategy {
        case .continuous: XCTFail("Unexpected strategy")
        case .repeatable(_, let disposeStorage, _):
            XCTAssertNil(disposeStorage.value.1, "\(disposeStorage.value as Any)")
        }

        let disposable3 = shareSource!.listening(onValue: { value in
            value_counter += 1
        })
        shareSource = nil // connection must dispose
        source.send(.value(10000))
        XCTAssertEqual(value_counter, 3)
        disposable3.dispose()
    }

    func testShareRepeatable() {
        let source = Repeater<Int>.unsafe()

        var value_counter = 0
        var shareSource: Share<UInt32>? = source
            .do(onValue: {
                if $0 == 0 {
                    XCTFail("Must not call")
                }
                if value_counter == 4 {
                    XCTFail("Must not call")
                }
            })
            .map(UInt32.init)
            .map(getRandomNum)
            .do(onValue: { print($0) })
            .share(connectionLive: .repeatable)
        let disposable1 = shareSource!.listening(onValue: { value in
            value_counter += 1
        })
        let disposable2 = shareSource!.listening(onValue: { value in
            value_counter += 1
        })

        source.send(.value(10))
        XCTAssertEqual(value_counter, 2)
        disposable1.dispose()
        source.send(.value(100))
        XCTAssertEqual(value_counter, 3)
        disposable2.dispose()
        source.send(.value(1000))
        XCTAssertEqual(value_counter, 3)
        source.send(.value(0))
        XCTAssertEqual(value_counter, 3)

        switch shareSource!.liveStrategy {
        case .continuous: XCTFail("Unexpected strategy")
        case .repeatable(_, let disposeStorage):
            XCTAssertNil(disposeStorage.value, "\(disposeStorage.value as Any)")
        }

        let disposable3 = shareSource!.listening(onValue: { value in
            value_counter += 1
        })
        shareSource = nil // connection must keep
        source.send(.value(10000))
        XCTAssertEqual(value_counter, 4)
        disposable3.dispose()
        source.send(.value(0))
    }

    func testShareContinuous() {
        let source = Repeater<Int>.unsafe()

        var value_counter = 0
        var shareSource: Share<UInt32>? = source
            .do(onValue: {
                if value_counter == 3 {
                    XCTAssertTrue($0 == 1000 || $0 == 0 || $0 == 10000)
                }
                if value_counter == 4 {
                    XCTFail("Must not call")
                }
            })
            .map(UInt32.init)
            .map(getRandomNum)
            .do(onValue: { print($0) })
            .share(connectionLive: .continuous)
        let disposable1 = shareSource!.listening(onValue: { value in
            value_counter += 1
        })
        let disposable2 = shareSource!.listening(onValue: { value in
            value_counter += 1
        })

        source.send(.value(10))
        XCTAssertEqual(value_counter, 2)
        disposable1.dispose()
        source.send(.value(100))
        XCTAssertEqual(value_counter, 3)
        disposable2.dispose()
        source.send(.value(1000))
        XCTAssertEqual(value_counter, 3)
        source.send(.value(0))
        XCTAssertEqual(value_counter, 3)

        switch shareSource!.liveStrategy {
        case .continuous(let dispose): XCTAssertFalse(dispose.isDisposed)
        case .repeatable: XCTFail("Unexpected strategy")
        }

        let disposable3 = shareSource!.listening(onValue: { value in
            value_counter += 1
        })
        shareSource = nil // connection must keep
        source.send(.value(10000))
        XCTAssertEqual(value_counter, 4)
        disposable3.dispose()
        source.send(.value(0))
    }
}