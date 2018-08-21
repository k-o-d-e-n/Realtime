//
//  listenable.swift
//  Realtime_Tests
//
//  Created by Denis Koryttsev on 11/08/2018.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import XCTest
@testable import Realtime

class PropertyClass<T>: InsiderOwner, ValueWrapper {
    private var localPropertyValue: PropertyValue<T>
    var value: T {
        get { return localPropertyValue.get() }
        set { localPropertyValue.set(newValue); insider.dataDidChange() }
    }
    var insider: Insider<T>

    init(_ value: T) {
        localPropertyValue = PropertyValue(value)
        insider = Insider(source: localPropertyValue.get)
    }
}

class ListenableTests: XCTestCase {

    func testClosure() {
        var string = "Some string"
        let getString = { return string }

        XCTAssert(string == getString())
        string.append("with added here text.")
        string = "Other string"

        XCTAssert(string == getString())
    }

    func testPropertyValue() {
        let valueWrapper = PropertyValue<Int>(0)
        valueWrapper.set(1)
        XCTAssertTrue(valueWrapper.get() == 1)
        valueWrapper.set(20)
        XCTAssertTrue(valueWrapper.get() == 20)
    }

    func testWeakPropertyValue() {
        var object: NSObject? = NSObject()
        let valueWrapper = WeakPropertyValue<NSObject>(object)
        XCTAssertTrue(valueWrapper.get() == object)
        object = nil
        XCTAssertTrue(valueWrapper.get() == nil)
    }

    func testWeakPropertyValue2() {
        var object: NSObject? = NSObject()
        let valueWrapper = WeakPropertyValue<NSObject>(nil)
        XCTAssertTrue(valueWrapper.get() == nil)
        valueWrapper.set(object)
        XCTAssertTrue(valueWrapper.get() == object)
        object = nil
        XCTAssertTrue(valueWrapper.get() == nil)
    }

//    func testProperty() {
//        let view = UIView()
//        var backgroundProperty = Property<UIColor>(value: .white)
//        let bgToken = backgroundProperty.insider.listen(.just { view.backgroundColor = $0.value })
//
//        var weakowner: UIView? = UIView()
//        _ = backgroundProperty.insider.listen(.weak(weakowner!) { (color, owner) in
//            print(color, owner ?? "nil")
//            if color.value == .yellow {
//                XCTAssertNil(owner)
//            }
//            })
//
//        let unownedOwner: UIView? = UIView()
//        _ = backgroundProperty.insider.listen(.unowned(unownedOwner!) { (color, owner) in
//            owner.backgroundColor = color.value
//            })
//
//        XCTAssertTrue(bgToken.token == Int.min)
//        backgroundProperty <== .red
//        XCTAssertTrue(view.backgroundColor == .red)
//        backgroundProperty <== .green
//        XCTAssertTrue(view.backgroundColor == .green)
//
//        weakowner = nil
//
//        var copyBgProperty = backgroundProperty
//        copyBgProperty <== .yellow
//        XCTAssertTrue(view.backgroundColor == .yellow)
//
//        var otherColor: UIColor? = .black
//        _ = backgroundProperty.insider.listen(.just { otherColor = $0.value })
//        copyBgProperty <== .red
//        XCTAssertFalse(otherColor == .red)
//
//        backgroundProperty.insider.disconnect(with: bgToken.token)
//        backgroundProperty <== .black
//        XCTAssertTrue(view.backgroundColor == .red)
//    }

//    func testReadonlyProperty() {
//        var propertyIndexSet = Property<IndexSet>(value: IndexSet(integer: 0))
//        var readonlySum = ReadonlyProperty<Int>(property: propertyIndexSet) { (v) -> Int in
//            return v.reduce(0, +)
//        }
//        _ = propertyIndexSet.insider.listen(.just { _ in
//            readonlySum.fetch()
//            })
//        XCTAssertTrue(readonlySum.value == 0)
//        propertyIndexSet.value.insert(1)
//        XCTAssertTrue(readonlySum.value == 1)
//        propertyIndexSet.value.insert(integersIn: 100...500)
//        print(readonlySum.value)
//
//        var stringLength = 0
//        let observableEntity = ObservableEntityClass(propertyValue: "")
//        _ = observableEntity.readonlyProperty.insider.listen(.just { $0.map(to: &stringLength) })
//        _ = observableEntity.readonlyProperty.insider.listen(.just{ print($0) })
//        observableEntity.property <== "Denis Koryttsev"
//        XCTAssertTrue(stringLength == 15)
//    }

    func testOnce() {
        let exp = expectation(description: "")
        let view = UIView()
        var backgroundProperty = P<UIColor>(.white)

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
        var backgroundProperty = PropertyClass<UIColor>(.white)

        _ = backgroundProperty
            .onFire({
                XCTAssertEqual(view.backgroundColor, nil)
            })
            .once()
            .listening(onValue: {
                view.backgroundColor = $0
            })
        backgroundProperty <== .red

        XCTAssertTrue(view.backgroundColor == .red)
        XCTAssertFalse(backgroundProperty.insider.hasConnections)

        backgroundProperty <== .green
        XCTAssertTrue(view.backgroundColor == .red)
    }

    func testConcurrency() {
        let cache = NSCache<NSString, NSNumber>()
        var stringProperty = PropertyClass<NSString>("initial")
        let assignedValue = "New value"

        performWaitExpectation("async", timeout: 5) { (exp) in
            _ = stringProperty
                .queue(.global(qos: .background))
                .map { _ in Thread.isMainThread }
                .queue(.main)
                .do { _ in XCTAssertTrue(Thread.isMainThread) }
                .queue(.global())
                .listening(onValue: { value in
                    cache.setObject(value as NSNumber, forKey: "key")
                    XCTAssertFalse(Thread.isMainThread)
                    XCTAssertFalse(cache.object(forKey: "key")!.boolValue)
                    exp.fulfill()
                })

            stringProperty <== assignedValue as NSString
        }
    }

    func testDeadline() {
        var counter = 0
        var stringProperty = PropertyClass<String>("initial")
        let beforeDeadlineValue = "First value"
        let afterDeadlineValue = "Second value"
        let inTimeValue = "Test"

        performWaitExpectation("async", timeout: 10) { (exp) in
            _ = stringProperty.deadline(.now() + .seconds(2)).listening(onValue: { string in
                if counter == 0 {
                    XCTAssertTrue(string == beforeDeadlineValue)
                } else if counter == 1 {
                    XCTAssertTrue(string == inTimeValue)
                }

                counter += 1
            })

            stringProperty <== beforeDeadlineValue

            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                stringProperty <== inTimeValue
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(4)) {
                stringProperty <== afterDeadlineValue
                XCTAssertFalse(stringProperty.insider.hasConnections)
                XCTAssertTrue(counter == 2)
                exp.fulfill()
            }
        }
    }

    func testLivetime() {
        var counter = 0
        var stringProperty = PropertyClass<String>("initial")
        let beforeDeadlineValue = "First value"
        let afterDeadlineValue = "Second value"
        let inTimeValue = "Test"

        var living: NSObject? = NSObject()

        performWaitExpectation("async", timeout: 10) { (exp) in
            _ = stringProperty.livetime(living!).listening(onValue: { string in
                if counter == 0 {
                    XCTAssertTrue(string == beforeDeadlineValue)
                } else if counter == 1 {
                    XCTAssertTrue(string == inTimeValue)
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
                XCTAssertFalse(stringProperty.insider.hasConnections)
                XCTAssertTrue(counter == 2)
                exp.fulfill()
            }
        }
    }

    func testDebounce() {
        let counter = PropertyClass<Double>(0.0)
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
        let propertyDouble = PropertyClass<Double>(.pi)

        var doubleValue = 0.0
        let dispose = propertyDouble.listening(onValue: { doubleValue = $0 })

        propertyDouble.value = 10.0
        XCTAssertTrue(doubleValue == 10.0)
        dispose.dispose()

        propertyDouble.value = .infinity
        XCTAssertTrue(doubleValue == 10.0)
    }

    func testListeningItem() {
        let propertyDouble = PropertyClass<Double>(.pi)

        var doubleValue = 0.0
        let item = propertyDouble.listeningItem(onValue: {
            doubleValue = $0
        })

        propertyDouble.value = 10.0
        XCTAssertTrue(doubleValue == 10.0)

        item.stop()
        XCTAssertFalse(item.isListen())
        propertyDouble.value = .infinity
        XCTAssertTrue(doubleValue == 10.0)

        item.start(true)
        XCTAssertTrue(item.isListen())
        XCTAssertTrue(doubleValue == .infinity)
        propertyDouble.value = .pi
        XCTAssertTrue(doubleValue == .pi)

        item.stop()
        propertyDouble.value = 100.5

        item.start(false)
        XCTAssertTrue(item.isListen())
        XCTAssertTrue(doubleValue == .pi)
        propertyDouble.value = 504.8
        XCTAssertTrue(doubleValue == 504.8)
    }

    func testListeningStore() {
        var store = ListeningDisposeStore()
        let propertyDouble = PropertyClass<Double>(.pi)

        var doubleValue = 0.0
        propertyDouble.listening(onValue: { doubleValue = $0 }).add(to: &store)
        propertyDouble.value = 10.0
        XCTAssertTrue(doubleValue == 10.0)

        store.dispose()
        propertyDouble.value = .infinity
        XCTAssertTrue(doubleValue == 10.0)

        let item = propertyDouble.listeningItem(onValue: { doubleValue = $0 })
        item.add(to: &store)

        propertyDouble.value = .pi
        XCTAssertTrue(doubleValue == .pi)
        XCTAssertTrue(item.isListen())

        store.pause()
        propertyDouble.value = 55.4
        XCTAssertFalse(doubleValue == 55.4)
        XCTAssertFalse(item.isListen())

        store.resume()
        XCTAssertTrue(item.isListen())
        XCTAssertTrue(doubleValue == 55.4)

        propertyDouble.value = 150.5
        XCTAssertTrue(doubleValue == 150.5)

        store.pause()
        propertyDouble.value = 25.1

        store.resume(false)
        XCTAssertTrue(doubleValue == 150.5)
    }

    //    func testUnsafeMutablePointer() {
    //        struct PropertyRetainer {
    //            var property = Property<Double>(value: .pi)
    //        }
    //
    //        var property = PropertyRetainer()
    //        var prop = Property<Double>(value: .pi)
    //        let unsafePointer = UnsafeMutablePointer(&property.property.insider)//UnsafeMutablePointer<Insider<Double>>.allocate(capacity: 1)
    ////        unsafePointer.initialize(to: property.property.insider)
    //        defer {
    //            unsafePointer.deinitialize()
    //            unsafePointer.deallocate(capacity: 1)
    //        }
    //        let otherPointer = unsafePointer
    //
    //        let token = unsafePointer.pointee.listening(with: { print($0) }).token
    //
    ////        XCTAssertTrue(prop.insider.has(token: token))
    //        XCTAssertTrue(property.property.insider.has(token: token))
    //        XCTAssertTrue(otherPointer.pointee.has(token: token))
    //    }

    //    func testUnsafeMutablePointer2() {
    //        var property = Property<Double>(value: .pi)
    //
    //        let filter = property.insider.filter { $0 > 1 }
    ////        let token = filter.listening(once: false, on: nil, with: { print($0) }).token
    //
    ////        XCTAssertTrue(property.insider.has(token: token))
    ////        XCTAssertTrue(otherPointer.pointee.has(token: token))
    //    }

    func testFilterPropertyClass() {
        let propertyDouble = PropertyClass<Double>(.pi)

        var isChanged = false
        var doubleValue = 0.0 {
            didSet { isChanged = true }
        }
        _ = propertyDouble.filter { $0 != .infinity }.map { print($0); return $0 }.listening(onValue: { doubleValue = $0 })

        propertyDouble.value = 10.0
        XCTAssertTrue(doubleValue == 10.0)

        propertyDouble.value = .infinity
        XCTAssertTrue(doubleValue == 10.0)
    }

    func testDistinctUntilChangedPropertyClass() {
        var counter: Int = 0
        var property = PropertyClass<Double>(.pi)
        _ = property.distinctUntilChanged().listening({ (v) in
            counter += 1
        })

        property <== 0
        XCTAssertTrue(counter == 1)
        property <== 0
        XCTAssertTrue(counter == 1)
        property <== -100.5
        XCTAssertTrue(counter == 2)
        XCTAssertTrue(property.value == -100.5)
        property <== .pi
        XCTAssertTrue(counter == 3)
        property <== .pi
        XCTAssertTrue(counter == 3)
    }

    func testMapPropertyClass() {
        let propertyDouble = PropertyClass<String>("Test")

        var value = ""
        _ = propertyDouble.map { $0 + " is successful" }.filter { print($0); return $0.count > 0 }.listening(onValue: .weak(self) { (v, owner) in
            print(owner ?? "nil")
            value = v
            })

        propertyDouble.value = "Test #1"
        XCTAssertTrue(value == "Test #1" + " is successful")

        propertyDouble.value = "Test #2154"
        XCTAssertTrue(value == "Test #2154" + " is successful")
    }

    func testPreprocessorAsListenable() {
        func map<T: Listenable, U>(_ listenable: T, _ transform: @escaping (T.OutData) -> U) -> Preprocessor<T.OutData, U> {
            return listenable.map(transform)
        }

        let propertyDouble = PropertyClass<Double>(.pi)

        var isChanged = false
        var doubleValue = 0.0 {
            didSet { isChanged = true }
        }
        _ = map(propertyDouble.filter { $0 != .infinity }, { print($0); return $0 }).listening(onValue: .just { doubleValue = $0 })

        propertyDouble.value = 10.0
        XCTAssertTrue(doubleValue == 10.0)

        propertyDouble.value = .infinity
        XCTAssertTrue(doubleValue == 10.0)
    }

    func testDoubleFilterPropertyClass() {
        let property = PropertyClass("")

        var textLength = 0
        _ = property
            .filter { !$0.isEmpty }
            .filter { $0.count <= 10 }
            .map { $0.count }
            .listening { textLength = $0 }

        property.value = "10.0"
        XCTAssertTrue(textLength == 4)

        property.value = ""
        XCTAssertTrue(textLength == 4)

        property.value = "Text with many characters"
        XCTAssertTrue(textLength == 4)

        property.value = "Passed"
        XCTAssertTrue(textLength == 6)
    }

    func testDoubleMapPropertyClass() {
        let property = PropertyClass("")

        var textLength = "0"
        _ = property
            .filter { !$0.isEmpty }
            .map { $0.count }
            .map(String.init)
            .listening { textLength = $0 }

        property.value = "10.0"
        XCTAssertTrue(textLength == "4")

        property.value = ""
        XCTAssertTrue(textLength == "4")

        property.value = "Text with many characters"
        XCTAssertTrue(textLength == "\(property.value.count)")

        property.value = "Passed"
        XCTAssertTrue(textLength == "6")
    }

    func testOnReceivePropertyClass() {
        var exponentValue = 1
        var property = PropertyClass<Double>(.pi)
        _ = property
            .map { $0.exponent }
            .onReceive { v, exp in
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: { exp.fulfill() })
            }
            .listening(onValue: {
                exponentValue = $0
            })

        let exp = expectation(description: "")
        property <== 0
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
            XCTAssertTrue(property.value == 0)
            XCTAssertTrue(exponentValue == property.value.exponent)
            property <== 21
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
                XCTAssertTrue(exponentValue == property.value.exponent)
                XCTAssertTrue(property.value == 21)
                property <== -100.5
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
                    XCTAssertTrue(exponentValue == property.value.exponent)
                    XCTAssertTrue(property.value == -100.5)
                    exp.fulfill()
                })
            })
        })

        waitForExpectations(timeout: 5, handler: nil)
    }

    func testDoubleOnReceivePropertyClass() {
        var exponentValue = 1
        var property = PropertyClass<Double>(.pi)
        _ = property
            .map { $0.exponent }
            .onReceive { v, exp in
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: { exp.fulfill() })
            }
            .onReceive({ (v, promise) in
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: { promise.fulfill() })
            })
            .listening(onValue: {
                exponentValue = $0
            })

        let exp = expectation(description: "")
        property <== 0
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2) + .milliseconds(100), execute: {
            XCTAssertTrue(property.value == 0)
            XCTAssertEqual(exponentValue, property.value.exponent)
            property <== 21
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2) + .milliseconds(100), execute: {
                XCTAssertEqual(exponentValue, property.value.exponent)
                XCTAssertTrue(property.value == 21)
                property <== -100.5
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2) + .milliseconds(100), execute: {
                    XCTAssertEqual(exponentValue, property.value.exponent)
                    XCTAssertTrue(property.value == -100.5)
                    exp.fulfill()
                })
            })
        })

        waitForExpectations(timeout: 10, handler: nil)
    }

    func testOnReceiveMapPropertyClass() {
        var exponentValue = "1"
        var property = PropertyClass<Double>(.pi)
        _ = property
            .map { $0.exponent }
            .onReceiveMap { v, exp in
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: { exp.fulfill("\(v)") })
            }
            .listening(onValue: {
                exponentValue = $0
            })

        let exp = expectation(description: "")
        property <== 0
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
            XCTAssertTrue(property.value == 0)
            XCTAssertTrue(exponentValue == "\(property.value.exponent)")
            property <== 21
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
                XCTAssertTrue(exponentValue == "\(property.value.exponent)")
                XCTAssertTrue(property.value == 21)
                property <== -100.5
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
                    XCTAssertTrue(exponentValue == "\(property.value.exponent)")
                    XCTAssertTrue(property.value == -100.5)
                    exp.fulfill()
                })
            })
        })

        waitForExpectations(timeout: 5, handler: nil)
    }

    func testDoubleOnReceiveMapPropertyClass() {
        var exponentValue = 0
        var property = PropertyClass<Double>(.pi)
        _ = property
            .map { $0.exponent }
            .onReceiveMap { v, exp in
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: { exp.fulfill("\(v)") })
            }
            .onReceiveMap({ (v, promise) in
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: { promise.fulfill(v.count) })
            })
            .listening(onValue: {
                exponentValue = $0
            })

        let exp = expectation(description: "")
        property <== 0
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2) + .milliseconds(100), execute: {
            XCTAssertTrue(property.value == 0)
            XCTAssertEqual(exponentValue, "\(property.value.exponent)".count)
            property <== 21
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2) + .milliseconds(100), execute: {
                XCTAssertEqual(exponentValue, "\(property.value.exponent)".count)
                XCTAssertTrue(property.value == 21)
                property <== -100.5
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2) + .milliseconds(100), execute: {
                    XCTAssertEqual(exponentValue, "\(property.value.exponent)".count)
                    XCTAssertTrue(property.value == -100.5)
                    exp.fulfill()
                })
            })
        })

        waitForExpectations(timeout: 10, handler: nil)
    }

//    func testBindProperty() {
//        var backgroundProperty = Property<UIColor>(value: .white)
//        var otherBackgroundProperty = Property<UIColor>(value: .black)
//        _ = otherBackgroundProperty.bind(to: &backgroundProperty)
//
//        backgroundProperty <== .red
//
//        XCTAssertTrue(otherBackgroundProperty.value == .red)
//    }
//
//    func testBindReadonlyProperty() {
//        var backgroundProperty = Property<UIColor>(value: .white)
//        var otherBackgroundProperty = ReadonlyProperty<UIColor>(getter: { .red })
//        _ = otherBackgroundProperty.bind(to: &backgroundProperty)
//
//        backgroundProperty <== .white
//
//        XCTAssertTrue(otherBackgroundProperty.value == .white)
//    }
}

// MARK: Concepts

extension ListenableTests {
    func testRepeater() {
        let exp = expectation(description: "")
        exp.expectedFulfillmentCount = 4

        var backgroundProperty = Repeater<UIColor>.unmanaged()
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

        var copyBgProperty = backgroundProperty
        backgroundProperty.send(.value(.yellow))
        backgroundProperty.send(.value(.red))

        bgToken.dispose()
        backgroundProperty.send(.value(.black))

        waitForExpectations(timeout: 5) { (error) in
            error.map { XCTFail($0.localizedDescription) }
        }
    }

    func testP() {
        let exp = expectation(description: "")
        exp.expectedFulfillmentCount = 4

        var backgroundProperty = P<UIColor>(.white)
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

    func testAvoidSimultaneousAccessInP() {
        let backgroundProperty = P<UIColor>(.white)
        _ = backgroundProperty.listening { val in
            XCTAssertEqual(val, backgroundProperty.value)
        }

        backgroundProperty.value = .red // backgroundProperty <== .red will be crash with simultaneous access error, because inout parameter
    }

    func testAvoidSimultaneousAccessInTrivial() {
        var backgroundProperty = Trivial<UIColor>(.white)
        _ = backgroundProperty.listening({ val in
//            XCTAssertEqual(val, backgroundProperty.value) will be crash with simultaneous access error, because setter of `value` property mutating
        })

        backgroundProperty.value = .red
    }

    @available(iOS 10.0, *)
    func testRepeaterOnQueue() {
        let exp = expectation(description: "")
        exp.expectedFulfillmentCount = 20
        exp.assertForOverFulfill = true
        var store = ListeningDisposeStore()
        let repeater = Repeater<Int>(lockedBy: NSRecursiveLock(), queue: DispatchQueue(label: "repeater"))
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
        let repeater = Repeater<Int>(lockedBy: NSRecursiveLock())
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
        let repeater = Repeater<Int> { (e, assign) in
            RunLoop.current.perform {
                assign.assign(e)
            }
        }
        _ = repeater.listening({
            value = $0.value
            exp.fulfill()
        })

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
