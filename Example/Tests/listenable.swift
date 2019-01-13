//
//  listenable.swift
//  Realtime_Tests
//
//  Created by Denis Koryttsev on 11/08/2018.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import XCTest
@testable import Realtime

class ListenableTests: XCTestCase {
    var store: ListeningDisposeStore = ListeningDisposeStore()

    override func tearDown() {
        super.tearDown()
        store.dispose()
    }

    func testClosure() {
        var string = "Some string"
        let getString = { return string }

        XCTAssert(string == getString())
        string.append("with added here text.")
        string = "Other string"

        XCTAssert(string == getString())
    }

    func testStrongProperty() {
        let valueWrapper = ValueStorage<Int>.unsafe(strong: 0)
        valueWrapper.set(1)
        XCTAssertEqual(valueWrapper.value, 1)
        valueWrapper.set(20)
        XCTAssertEqual(valueWrapper.value, 20)
    }

    func testWeakProperty() {
        var object: NSObject? = NSObject()
        let valueWrapper = ValueStorage<NSObject?>.unsafe(weak: object)
        XCTAssertEqual(valueWrapper.value, object)
        object = nil
        XCTAssertEqual(valueWrapper.value, nil)
    }

    func testWeakProperty2() {
        var object: NSObject? = NSObject()
        let valueWrapper = ValueStorage<NSObject?>.unsafe(weak: nil)
        XCTAssertEqual(valueWrapper.value, nil)
        valueWrapper.set(object)
        XCTAssertEqual(valueWrapper.value, object)
        object = nil
        XCTAssertEqual(valueWrapper.value, nil)
    }

    func testProperty() {
        let exp = expectation(description: "")
        exp.expectedFulfillmentCount = 4

        var backgroundProperty = ValueStorage<UIColor>.unsafe(strong: .white)
        var counter = 0
        let bgToken = backgroundProperty.listening(onValue: { color in
            defer { counter += 1; exp.fulfill() }
            switch counter {
            case 0: XCTAssertEqual(color, .red)
            case 1: XCTAssertEqual(color, .green)
            case 2: XCTAssertEqual(color, .yellow)
            case 3: XCTAssertEqual(color, .red)
            default: XCTFail("Extra call")
            }
        })

        var weakowner: UIView? = UIView()
        _ = backgroundProperty.listening(.weak(weakowner!) { (color, owner) in
            print(color, owner ?? "nil")
            if color.value == .yellow {
                XCTAssertNil(owner)
            }
            })

        let unownedOwner: UIView? = UIView()
        _ = backgroundProperty.listening(.unowned(unownedOwner!) { (color, owner) in
            owner.backgroundColor = color.value
            })

        backgroundProperty <== .red
        backgroundProperty <== .green

        weakowner = nil

        var copyBgProperty = backgroundProperty
        copyBgProperty <== .yellow
        copyBgProperty <== .red

        bgToken.dispose()
        backgroundProperty <== .black

        waitForExpectations(timeout: 5) { (error) in
            error.map { XCTFail($0.localizedDescription) }
        }
    }

    func testReadonlyValue() {
        let exp = expectation(description: "")
        exp.expectedFulfillmentCount = 2

        var propertyIndexSet = ValueStorage<IndexSet>.unsafe(strong: IndexSet(integer: 0))
        let readonlySum = ReadonlyValue<Int>(propertyIndexSet) { (v) -> Int in
            return v.reduce(0, +)
        }
        var counter = 0
        readonlySum.listening(onValue: { v in
            defer { counter += 1; exp.fulfill() }
            switch counter {
            case 0: XCTAssertEqual(v, 1)
            case 1: XCTAssertEqual(v, IndexSet(integersIn: 100...500).reduce(0, +) + 1)
            default: XCTFail("Extra call")
            }
        }).add(to: store)

        propertyIndexSet.value.insert(1)
        propertyIndexSet.value.insert(integersIn: 100...500)

        waitForExpectations(timeout: 5) { (error) in
            error.map { XCTFail($0.localizedDescription) }
        }
    }

    func testAsyncReadonlyValue() {
        let exp = expectation(description: "")
        exp.expectedFulfillmentCount = 2

        var counter = 0
        let propertyIndexSet = ValueStorage<IndexSet>.unsafe(strong: IndexSet(integer: 0))
        let readonlySum = AsyncReadonlyValue<(Int, Int)>(propertyIndexSet, storage: ValueStorage.unsafe(strong: nil)) { (v, promise) in
            let c = counter
            counter += 1
            DispatchQueue.global(qos: .background).async {
                promise.fulfill((c, v.reduce(0, +)))
            }
        }
        readonlySum.listening(onValue: { (c, v) in
            switch c {
            case 0: XCTAssertEqual(v, 1)
            case 1: XCTAssertEqual(v, IndexSet(integersIn: 100...500).reduce(0, +) + 1)
            default: XCTFail("Extra call")
            }
            exp.fulfill()
        }).add(to: store)

        propertyIndexSet.value.insert(1)
        propertyIndexSet.value.insert(integersIn: 100...500)

        waitForExpectations(timeout: 5) { (error) in
            error.map { XCTFail($0.localizedDescription) }
        }
    }

    func testOnce() {
        let exp = expectation(description: "")
        let view = UIView()
        var backgroundProperty = ValueStorage<UIColor>.unsafe(strong: .white)

        _ = backgroundProperty.once().listening(onValue: {
            view.backgroundColor = $0
        })

        backgroundProperty <== .red
        backgroundProperty <== .green

        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2), execute: exp.fulfill)

        waitForExpectations(timeout: 5) { (err) in
            err.map { XCTFail($0.localizedDescription) }

            XCTAssertEqual(view.backgroundColor, .red)
        }
    }

    func testOnFire() {
        let view = UIView()
        var backgroundProperty = ValueStorage<UIColor>.unsafe(strong: .white)

        backgroundProperty
            .onFire({
                XCTAssertEqual(view.backgroundColor, nil)
            })
            .once()
            .listening(onValue: {
                view.backgroundColor = $0
            })
            .add(to: store)

        backgroundProperty <== .red
        XCTAssertEqual(view.backgroundColor, .red)

        backgroundProperty <== .green
        XCTAssertEqual(view.backgroundColor, .red)
    }

    func testConcurrency() {
        let cache = NSCache<NSString, NSNumber>()
        var stringProperty = ValueStorage<NSString>.unsafe(strong: "initial")
        let assignedValue = "New value"

        performWaitExpectation("async", timeout: 5) { (exp) in
            _ = stringProperty
                .queue(.global(qos: .background))
                .map { _ in Thread.isMainThread }
                .queue(.main)
                .do({ _ in XCTAssertTrue(Thread.isMainThread) })
                .queue(.global())
                .listening(onValue: { value in
                    cache.setObject(value as NSNumber, forKey: "key")
                    XCTAssertFalse(Thread.isMainThread)
                    XCTAssertFalse(cache.object(forKey: "key")!.boolValue)
                    exp.fulfill()
                })
                .add(to: store)

            stringProperty <== assignedValue as NSString
        }
    }

    func testDeadline() {
        var counter = 0
        var stringProperty = ValueStorage<String>.unsafe(strong: "initial")
        let beforeDeadlineValue = "First value"
        let afterDeadlineValue = "Second value"
        let inTimeValue = "Test"

        performWaitExpectation("async", timeout: 10) { (exp) in
            _ = stringProperty.deadline(.now() + .seconds(2)).listening(onValue: { string in
                if counter == 0 {
                    XCTAssertEqual(string, beforeDeadlineValue)
                } else if counter == 1 {
                    XCTAssertEqual(string, inTimeValue)
                }

                counter += 1
            })

            stringProperty <== beforeDeadlineValue
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                stringProperty <== inTimeValue
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(4)) {
                stringProperty <== afterDeadlineValue
                XCTAssertEqual(counter, 2)
                exp.fulfill()
            }
        }
    }

    func testLivetime() {
        var counter = 0
        var stringProperty = ValueStorage<String>.unsafe(strong: "initial")
        let beforeDeadlineValue = "First value"
        let afterDeadlineValue = "Second value"
        let inTimeValue = "Test"

        var living: NSObject? = NSObject()

        performWaitExpectation("async", timeout: 10) { (exp) in
            _ = stringProperty.livetime(living!).listening(onValue: { string in
                if counter == 0 {
                    XCTAssertEqual(string, beforeDeadlineValue)
                } else if counter == 1 {
                    XCTAssertEqual(string, inTimeValue)
                }

                counter += 1
            })

            stringProperty <== beforeDeadlineValue
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                stringProperty <== inTimeValue
                living = nil
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(4)) {
                stringProperty <== afterDeadlineValue
                XCTAssertEqual(counter, 2)
                exp.fulfill()
            }
        }
    }

    func testDebounce() {
        let counter = ValueStorage<Double>.unsafe(strong: 0.0)
        var receivedValues: [Double] = []

        _ = counter.debounce(.seconds(1)).listening(onValue: { value in
            receivedValues.append(value)
            print(value)
        })

        let timer: Timer
        if #available(iOS 10.0, *) {
            timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { (_) in
                counter.value += 1
            }
        } else {
            fatalError()
        }

        performWaitExpectation("async", timeout: 10) { (exp) in
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(4)) {
                timer.invalidate()
                zip(receivedValues, [1, 3, 6, 8]).forEach({ (arg: (Double, Double)) in
                    let (received, must) = arg
                    XCTAssertEqual(received, must, accuracy: 1.0)
                })
                exp.fulfill()
            }
        }
    }

    func testListeningDisposable() {
        let propertyDouble = ValueStorage<Double>.unsafe(strong: .pi)

        var doubleValue = 0.0
        let dispose = propertyDouble.listening(onValue: { doubleValue = $0 })

        propertyDouble.value = 10.0
        XCTAssertEqual(doubleValue, 10.0)
        dispose.dispose()

        propertyDouble.value = .infinity
        XCTAssertEqual(doubleValue, 10.0)
    }

    func testListeningItem() {
        let propertyDouble = ValueStorage<Double>.unsafe(strong: .pi)

        var doubleValue = 0.0
        var item: ListeningItem? = propertyDouble.listeningItem(onValue: {
            doubleValue = $0
        })

        XCTAssertTrue(item!.isListen)
        propertyDouble.value = 10.0
        XCTAssertEqual(doubleValue, 10.0)

        item?.pause()
        XCTAssertFalse(item!.isListen)
        propertyDouble.value = .infinity
        XCTAssertEqual(doubleValue, 10.0)

        item?.resume()
        XCTAssertTrue(item!.isListen)
        propertyDouble.value = .pi
        XCTAssertEqual(doubleValue, .pi)

        item?.pause()
        XCTAssertFalse(item!.isListen)
        propertyDouble.value = 100.5

        item?.resume()
        XCTAssertTrue(item!.isListen)
        XCTAssertEqual(doubleValue, .pi)
        propertyDouble.value = 504.8
        XCTAssertEqual(doubleValue, 504.8)

        item = nil
        propertyDouble.value = 1000
        XCTAssertEqual(doubleValue, 504.8)
    }

    func testListeningStore() {
        let store = ListeningDisposeStore()
        let propertyDouble = ValueStorage<Double>.unsafe(strong: .pi)

        var doubleValue = 0.0
        propertyDouble.listening(onValue: { doubleValue = $0 }).add(to: store)
        propertyDouble.value = 10.0
        XCTAssertEqual(doubleValue, 10.0)

        store.dispose()
        propertyDouble.value = .infinity
        XCTAssertEqual(doubleValue, 10.0)

        let item = propertyDouble.listeningItem(onValue: { doubleValue = $0 })
        item.add(to: store)

        propertyDouble.value = .pi
        XCTAssertEqual(doubleValue, .pi)
        XCTAssertTrue(item.isListen)

        store.pause()
        propertyDouble.value = 55.4
        XCTAssertNotEqual(doubleValue, 55.4)
        XCTAssertFalse(item.isListen)

        store.resume()
        XCTAssertTrue(item.isListen)

        propertyDouble.value = 150.5
        XCTAssertEqual(doubleValue, 150.5)

        store.pause()
        propertyDouble.value = 25.1

        store.resume()
        XCTAssertEqual(doubleValue, 150.5)
    }

    func testFilterPropertyClass() {
        let propertyDouble = ValueStorage<Double>.unsafe(strong: .pi)

        var isChanged = false
        var doubleValue = 0.0 {
            didSet { isChanged = true }
        }
        propertyDouble.filter { $0 != .infinity }.map { print($0); return $0 }.listening(onValue: { doubleValue = $0 }).add(to: store)

        propertyDouble.value = 10.0
        XCTAssertEqual(doubleValue, 10.0)

        propertyDouble.value = .infinity
        XCTAssertEqual(doubleValue, 10.0)
    }

    func testDistinctUntilChangedPropertyClass() {
        var counter: Int = 0
        var property = ValueStorage<Double>.unsafe(strong: .pi)
        property.distinctUntilChanged().listening({ (v) in
            counter += 1
        }).add(to: store)

        property <== 0
        XCTAssertEqual(counter, 1)
        property <== 0
        XCTAssertEqual(counter, 1)
        property <== -100.5
        XCTAssertEqual(counter, 2)
        XCTAssertEqual(property.value, -100.5)
        property <== .pi
        XCTAssertEqual(counter, 3)
        property <== .pi
        XCTAssertEqual(counter, 3)
    }

    func testMapPropertyClass() {
        let propertyDouble = ValueStorage<String>.unsafe(strong: "Test")

        var value = ""
        propertyDouble
            .map { $0 + " is successful" }
            .filter { print($0); return $0.count > 0 }
            .listening(onValue: .weak(self) { (v, owner) in
                print(owner ?? "nil")
                value = v
            })
            .add(to: store)

        propertyDouble.value = "Test #1"
        XCTAssertEqual(value, "Test #1" + " is successful")

        propertyDouble.value = "Test #2154"
        XCTAssertEqual(value, "Test #2154" + " is successful")
    }

    func testPreprocessorAsListenable() {
        func map<T: Listenable, U>(_ listenable: T, _ transform: @escaping (T.Out) -> U) -> Preprocessor<T.Out, U> {
            return listenable.map(transform)
        }

        let propertyDouble = ValueStorage<Double>.unsafe(strong: .pi)

        var isChanged = false
        var doubleValue = 0.0 {
            didSet { isChanged = true }
        }
        map(propertyDouble.filter { $0 != .infinity }, { print($0); return $0 }).listening(onValue: .just { doubleValue = $0 }).add(to: store)

        propertyDouble.value = 10.0
        XCTAssertEqual(doubleValue, 10.0)

        propertyDouble.value = .infinity
        XCTAssertEqual(doubleValue, 10.0)
    }

    func testDoubleFilterPropertyClass() {
        let property = ValueStorage.unsafe(strong: "")

        var textLength = 0
        property
            .filter { !$0.isEmpty }
            .filter { $0.count <= 10 }
            .map { $0.count }
            .listening { textLength = $0 }
            .add(to: store)

        property.value = "10.0"
        XCTAssertEqual(textLength, 4)

        property.value = ""
        XCTAssertEqual(textLength, 4)

        property.value = "Text with many characters"
        XCTAssertEqual(textLength, 4)

        property.value = "Passed"
        XCTAssertEqual(textLength, 6)
    }

    func testDoubleMapPropertyClass() {
        let property = ValueStorage.unsafe(strong: "")

        var textLength = "0"
        property
            .filter { !$0.isEmpty }
            .map { $0.count }
            .map(String.init)
            .listening { textLength = $0 }
            .add(to: store)

        property.value = "10.0"
        XCTAssertEqual(textLength, "4")

        property.value = ""
        XCTAssertEqual(textLength, "4")

        property.value = "Text with many characters"
        XCTAssertEqual(textLength, "\(property.value.count)")

        property.value = "Passed"
        XCTAssertEqual(textLength, "6")
    }

    func testOnReceivePropertyClass() {
        var exponentValue = 1
        var property = ValueStorage<Double>.unsafe(strong: .pi)
        property
            .map { $0.exponent }
            .doAsync { v, exp in
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: { exp.fulfill() })
            }
            .listening(onValue: {
                exponentValue = $0
            })
            .add(to: store)

        let exp = expectation(description: "")
        property <== 0
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
            XCTAssertEqual(property.value, 0)
            XCTAssertEqual(exponentValue, property.value.exponent)
            property <== 21
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
                XCTAssertEqual(exponentValue, property.value.exponent)
                XCTAssertEqual(property.value, 21)
                property <== -100.5
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
                    XCTAssertEqual(exponentValue, property.value.exponent)
                    XCTAssertEqual(property.value, -100.5)
                    exp.fulfill()
                })
            })
        })

        waitForExpectations(timeout: 5, handler: nil)
    }

    func testDoubleOnReceivePropertyClass() {
        var exponentValue = 1
        var property = ValueStorage<Double>.unsafe(strong: .pi)
        property
            .map { $0.exponent }
            .doAsync { v, exp in
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: { exp.fulfill() })
            }
            .doAsync({ (v, promise) in
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: { promise.fulfill() })
            })
            .listening(onValue: {
                exponentValue = $0
            })
            .add(to: store)

        let exp = expectation(description: "")
        property <== 0
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2) + .milliseconds(100), execute: {
            XCTAssertEqual(property.value, 0)
            XCTAssertEqual(exponentValue, property.value.exponent)
            property <== 21
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2) + .milliseconds(100), execute: {
                XCTAssertEqual(exponentValue, property.value.exponent)
                XCTAssertEqual(property.value, 21)
                property <== -100.5
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2) + .milliseconds(100), execute: {
                    XCTAssertEqual(exponentValue, property.value.exponent)
                    XCTAssertEqual(property.value, -100.5)
                    exp.fulfill()
                })
            })
        })

        waitForExpectations(timeout: 10, handler: nil)
    }

    func testOnReceiveMapPropertyClass() {
        var exponentValue = "1"
        var property = ValueStorage<Double>.unsafe(strong: .pi)
        property
            .map { $0.exponent }
            .mapAsync { v, exp in
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: { exp.fulfill("\(v)") })
            }
            .listening(onValue: {
                exponentValue = $0
            })
            .add(to: store)

        let exp = expectation(description: "")
        property <== 0
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
            XCTAssertEqual(property.value, 0)
            XCTAssertEqual(exponentValue, "\(property.value.exponent)")
            property <== 21
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
                XCTAssertEqual(exponentValue, "\(property.value.exponent)")
                XCTAssertEqual(property.value, 21)
                property <== -100.5
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
                    XCTAssertEqual(exponentValue, "\(property.value.exponent)")
                    XCTAssertEqual(property.value, -100.5)
                    exp.fulfill()
                })
            })
        })

        waitForExpectations(timeout: 5, handler: nil)
    }

    func testDoubleOnReceiveMapPropertyClass() {
        var exponentValue = 0
        var property = ValueStorage<Double>.unsafe(strong: .pi)
        property
            .map { $0.exponent }
            .mapAsync { v, exp in
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: { exp.fulfill("\(v)") })
            }
            .mapAsync({ (v, promise) in
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: { promise.fulfill(v.count) })
            })
            .listening(onValue: {
                exponentValue = $0
            })
            .add(to: store)

        let exp = expectation(description: "")
        property <== 0
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2) + .milliseconds(100), execute: {
            XCTAssertEqual(property.value, 0)
            XCTAssertEqual(exponentValue, "\(property.value.exponent)".count)
            property <== 21
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2) + .milliseconds(100), execute: {
                XCTAssertEqual(exponentValue, "\(property.value.exponent)".count)
                XCTAssertEqual(property.value, 21)
                property <== -100.5
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2) + .milliseconds(100), execute: {
                    XCTAssertEqual(exponentValue, "\(property.value.exponent)".count)
                    XCTAssertEqual(property.value, -100.5)
                    exp.fulfill()
                })
            })
        })

        waitForExpectations(timeout: 10, handler: nil)
    }

    func testBindProperty() {
        var backgroundProperty = ValueStorage<UIColor>.unsafe(strong: .white)
        let otherBackgroundProperty = ValueStorage<UIColor>.unsafe(strong: .black)
        backgroundProperty.bind(to: otherBackgroundProperty).add(to: store)

        backgroundProperty <== .red

        XCTAssertEqual(otherBackgroundProperty.value, .red)
    }
}

extension ListenableTests {
    func testRepeater() {
        let exp = expectation(description: "")
        exp.expectedFulfillmentCount = 4

        var backgroundProperty = Repeater<UIColor>.unsafe()
        var counter = 0
        let bgToken = backgroundProperty.listening(onValue: { color in
            defer { counter += 1; exp.fulfill() }
            switch counter {
            case 0: XCTAssertEqual(color, .red)
            case 1: XCTAssertEqual(color, .green)
            case 2: XCTAssertEqual(color, .yellow)
            case 3: XCTAssertEqual(color, .red)
            default: XCTFail("Extra call")
            }
        })

        var weakowner: UIView? = UIView()
        _ = backgroundProperty.listening(.weak(weakowner!) { (color, owner) in
            print(color, owner ?? "nil")
            if color.value == .yellow {
                XCTAssertNil(owner)
            }
        })

        let unownedOwner: UIView? = UIView()
        _ = backgroundProperty.listening(.unowned(unownedOwner!) { (color, owner) in
            owner.backgroundColor = color.value
        })

        backgroundProperty.send(.value(.red))
        backgroundProperty.send(.value(.green))

        weakowner = nil

        let copyBgProperty = backgroundProperty
        copyBgProperty.send(.value(.yellow))
        copyBgProperty.send(.value(.red))

        bgToken.dispose()
        backgroundProperty.send(.value(.black))

        waitForExpectations(timeout: 5) { (error) in
            error.map { XCTFail($0.localizedDescription) }
        }
    }

    func testTrivial() {
        let exp = expectation(description: "")
        exp.expectedFulfillmentCount = 4

        var backgroundProperty = Trivial<UIColor>(.white)
        var counter = 0
        let bgToken = backgroundProperty.listening(onValue: { color in
            defer { counter += 1; exp.fulfill() }
            switch counter {
            case 0: XCTAssertEqual(color, .red)
            case 1: XCTAssertEqual(color, .green)
            case 2: XCTAssertEqual(color, .yellow)
            case 3: XCTAssertEqual(color, .red)
            default: XCTFail("Extra call")
            }
        })

        var weakowner: UIView? = UIView()
        _ = backgroundProperty.listening(.weak(weakowner!) { (color, owner) in
            print(color, owner ?? "nil")
            if color.value == .yellow {
                XCTAssertNil(owner)
            }
            })

        let unownedOwner: UIView? = UIView()
        _ = backgroundProperty.listening(.unowned(unownedOwner!) { (color, owner) in
            owner.backgroundColor = color.value
            })

        backgroundProperty <== .red
        backgroundProperty <== .green

        weakowner = nil

        var copyBgProperty = backgroundProperty
        copyBgProperty <== .yellow
        copyBgProperty <== .red

        bgToken.dispose()
        backgroundProperty <== .black

        waitForExpectations(timeout: 5) { (error) in
            error.map { XCTFail($0.localizedDescription) }
        }
    }

    func testRepeaterListeiningItem() {
        let exp = expectation(description: "")
        exp.expectedFulfillmentCount = 4

        let repeater = Repeater<Int>(lockedBy: NSRecursiveLock(), dispatcher: .queue(DispatchQueue(label: "repeater")))
        var counter = 0
        let bgItem = repeater.listeningItem(onValue: { v in
            print(v)
            defer { counter += 1; exp.fulfill() }
            switch counter {
            case 0: XCTAssertEqual(v, 4)
            case 1: XCTAssertEqual(v, 5)
            case 2: XCTAssertEqual(v, 20)
            case 3: XCTAssertEqual(v, 999)
            default: XCTFail("Extra call")
            }
        })

        repeater.send(.value(4))
        repeater.send(.value(5))

        bgItem.pause()

        repeater.send(.value(100))

        DispatchQueue.global().async {
            XCTAssertFalse(Thread.isMainThread)
            bgItem.resume()

            repeater.send(.value(20))

            bgItem.pause()

            repeater.send(.value(1000))

            bgItem.resume()

            repeater.send(.value(999))
        }

        waitForExpectations(timeout: 5) { (error) in
            error.map { XCTFail($0.localizedDescription) }
        }
    }

    func testAvoidSimultaneousAccessInP() {
        let backgroundProperty = ValueStorage<UIColor>.unsafe(strong: .white)
        _ = backgroundProperty.listening { val in
            XCTAssertEqual(val, backgroundProperty.value)
        }

        backgroundProperty.value = .red // backgroundProperty <== .red will be crash with simultaneous access error, because inout parameter
    }

    @available(iOS 10.0, *)
    func testRepeaterOnQueue() {
        let exp = expectation(description: "")
        exp.expectedFulfillmentCount = 20
        exp.assertForOverFulfill = true
        var store = ListeningDisposeStore()
        let repeater = Repeater<Int>(lockedBy: NSRecursiveLock(), dispatcher: .queue(DispatchQueue(label: "repeater")))
        let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { (_) in
            repeater.send(.value(5))
        }
        let storeLock = NSLock()
        func put(_ dispose: Disposable) {
            storeLock.lock(); defer { storeLock.unlock() }
            store.add(dispose)
        }

        (0..<20).forEach { (i) in
            DispatchQueue.global(qos: .background).async {
                _ = repeater.once().listening({ _ in
                    exp.fulfill()
                })
            }
        }

        waitForExpectations(timeout: 5) { (error) in
            error.map { XCTFail($0.localizedDescription) }
            timer.invalidate()
        }
    }

    @available(iOS 10.0, *)
    func testRepeaterLocked() {
        let exp = expectation(description: "")
        exp.expectedFulfillmentCount = 20
        exp.assertForOverFulfill = true
        var store = ListeningDisposeStore()
        let repeater = Repeater<Int>.locked(by: NSRecursiveLock())
        let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { (_) in
            DispatchQueue.global().async {
                repeater.send(.value(5))
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
            }
        }
        let storeLock = NSRecursiveLock()
        func put(_ dispose: Disposable) {
            storeLock.lock(); defer { storeLock.unlock() }
            store.add(dispose)
        }

        (0..<20).forEach { (i) in
            DispatchQueue.global(qos: .background).async {
                put(repeater.once().listening({ _ in
                    exp.fulfill()
                }))
            }
        }

        waitForExpectations(timeout: 10) { (error) in
            error.map { XCTFail($0.localizedDescription) }
            timer.invalidate()
        }
    }

    @available(iOS 10.0, *)
    func testRepeaterOnRunloop() {
        let exp = expectation(description: "")
        var value: Int?
        let repeater = Repeater<Int>(dispatcher: .custom({ (assign, e) in
            RunLoop.current.perform {
                assign.assign(e)
            }
        }))
        repeater.listening({
            value = $0.value
            exp.fulfill()
        }).add(to: store)

        DispatchQueue.global().async {
            repeater.send(.value(4))
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 4))
        }
        waitForExpectations(timeout: 5) { (error) in
            error.map { XCTFail($0.localizedDescription) }
            XCTAssertEqual(4, value)
        }
    }
}

// MARK: Concepts

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
            .map(arc4random_uniform)
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
            .map(arc4random_uniform)
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
            .map(arc4random_uniform)
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
            .map(arc4random_uniform)
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
