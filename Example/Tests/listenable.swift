//
//  listenable.swift
//  Realtime_Tests
//
//  Created by Denis Koryttsev on 11/08/2018.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import XCTest
@testable import Realtime

/// -------------------------------------------------------------------------------------------------------------

class ListenableTests: XCTestCase {
    class ObservableEntityClass {
        var property: Property<String>
        lazy var readonlyProperty = ReadonlyProperty() { [weak self] () -> Int in
            return self!.property.value.count
        }

        init(propertyValue: String) {
            self.property = Property(value: propertyValue)
            _ = property.insider.listen(.weak(self) { _, _self in
                _self?.readonlyProperty.fetch()
                })
        }
    }

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

    /// -------------------------------------------------------------------------------------------------------------

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

    func testListenableValue() {
        var counter = 0
        var valueWrapper = ListenableValue<Int>(0)
        _ = valueWrapper.insider.listen(.just { (val) in
            if counter == 0 {
                XCTAssertTrue(val.value == 1)
            } else if counter == 1 {
                XCTAssertTrue(val.value == 20)
            }
            counter += 1
            })
        valueWrapper.set(1)
        XCTAssertTrue(valueWrapper.get() == 1)
        valueWrapper.set(20)
        XCTAssertTrue(valueWrapper.get() == 20)
    }

    func testProperty() {
        let view = UIView()
        var backgroundProperty = Property<UIColor>(value: .white)
        let bgToken = backgroundProperty.insider.listen(.just { view.backgroundColor = $0.value })

        var weakowner: UIView? = UIView()
        _ = backgroundProperty.insider.listen(.weak(weakowner!) { (color, owner) in
            print(color, owner ?? "nil")
            if color.value == .yellow {
                XCTAssertNil(owner)
            }
            })

        let unownedOwner: UIView? = UIView()
        _ = backgroundProperty.insider.listen(.unowned(unownedOwner!) { (color, owner) in
            owner.backgroundColor = color.value
            })

        XCTAssertTrue(bgToken.token == Int.min)
        backgroundProperty <== .red
        XCTAssertTrue(view.backgroundColor == .red)
        backgroundProperty <== .green
        XCTAssertTrue(view.backgroundColor == .green)

        weakowner = nil

        var copyBgProperty = backgroundProperty
        copyBgProperty <== .yellow
        XCTAssertTrue(view.backgroundColor == .yellow)

        var otherColor: UIColor? = .black
        _ = backgroundProperty.insider.listen(.just { otherColor = $0.value })
        copyBgProperty <== .red
        XCTAssertFalse(otherColor == .red)

        backgroundProperty.insider.disconnect(with: bgToken.token)
        backgroundProperty <== .black
        XCTAssertTrue(view.backgroundColor == .red)
    }

    func testReadonlyProperty() {
        var propertyIndexSet = Property<IndexSet>(value: IndexSet(integer: 0))
        var readonlySum = ReadonlyProperty<Int>(property: propertyIndexSet) { (v) -> Int in
            return v.reduce(0, +)
        }
        _ = propertyIndexSet.insider.listen(.just { _ in
            readonlySum.fetch()
            })
        XCTAssertTrue(readonlySum.value == 0)
        propertyIndexSet.value.insert(1)
        XCTAssertTrue(readonlySum.value == 1)
        propertyIndexSet.value.insert(integersIn: 100...500)
        print(readonlySum.value)

        var stringLength = 0
        let observableEntity = ObservableEntityClass(propertyValue: "")
        _ = observableEntity.readonlyProperty.insider.listen(.just { $0.map(to: &stringLength) })
        _ = observableEntity.readonlyProperty.insider.listen(.just{ print($0) })
        observableEntity.property <== "Denis Koryttsev"
        XCTAssertTrue(stringLength == 15)
    }

    func testOnce() {
        let view = UIView()
        var backgroundProperty = P<UIColor>(.white)

        _ = backgroundProperty.once().listening(onValue: {
            view.backgroundColor = $0
        })
        backgroundProperty <== .red

        XCTAssertTrue(view.backgroundColor == .red)
//        XCTAssertFalse(backgroundProperty.insider.hasConnections)

        backgroundProperty <== .green
        XCTAssertTrue(view.backgroundColor == .red)
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

    func testPrimitiveValue() {
        let referencedValue = PropertyValue<Int>(10)
        let newReferencedValue = referencedValue
        var value = PrimitiveValue<Int>(5)
        let newValue = value

        value.set(6)
        referencedValue.set(20)

        print(value.get())
        XCTAssertTrue(value.get() == 6)
        print(newValue.get())
        XCTAssertTrue(newValue.get() == 5)

        XCTAssertTrue(referencedValue.get() == 20)
        XCTAssertTrue(newReferencedValue.get() == 20)
        XCTAssertTrue(newReferencedValue.get() == referencedValue.get())
    }

    func testPrimitivePropertyValue() {
        var valueWrapper = PrimitiveProperty<Int>(value: -1)
        XCTAssertTrue(valueWrapper.value == -1)
        valueWrapper.value = 1
        XCTAssertTrue(valueWrapper.value == 1)
        valueWrapper <== 20
        XCTAssertTrue(valueWrapper.value == 20)
    }

    func testPrimitive() {
        let valueWrapper = Primitive<Int>(-1)
        XCTAssertTrue(valueWrapper.get() == -1)
        valueWrapper.set(1)
        let newValue = valueWrapper
        XCTAssertTrue(valueWrapper.get() == 1)
        valueWrapper.set(20)
        performWaitExpectation("wait", timeout: 20) { exp in
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 5.0, execute: {
                XCTAssertTrue(valueWrapper.get() == 20)
                XCTAssertTrue(newValue.get() == 20)
                newValue.set(100)
                XCTAssertTrue(valueWrapper.get() == 100)
                exp.fulfill()
            })
        }
    }

    /* // failed
     func testPrimitiveProperty() {
     let view = UIView()
     var frameProperty = PrimitiveProperty<CGRect>(value: .zero)
     let bgToken = frameProperty.insider.listening(with: { view.frame = $0 })

     var weakowner: UIView? = UIView()
     _ = frameProperty.insider.listening(owner: .weak(weakowner!), with: { (frame, owner) in
     print(frame, owner ?? "nil")
     if frame == CGRect(origin: .zero, size: CGSize(width: 10, height: 10)) {
     XCTAssertNil(owner)
     }
     })

     let unownedOwner: UIView? = UIView()
     _ = frameProperty.insider.listening(owner: .unowned(unownedOwner!), with: { (frame, owner) in
     owner?.frame = frame
     })

     XCTAssertTrue(bgToken.token == Int.min)
     frameProperty.value = CGRect(x: 50, y: 20, width: 0, height: 10)
     XCTAssertTrue(view.frame == CGRect(x: 50, y: 20, width: 0, height: 10))
     frameProperty <== CGRect(x: 50, y: 20, width: 100, height: 10)
     XCTAssertTrue(view.frame == CGRect(x: 50, y: 20, width: 100, height: 10))

     weakowner = nil

     var copyFrameProperty = frameProperty
     copyFrameProperty <== CGRect(origin: .zero, size: CGSize(width: 10, height: 10))
     XCTAssertTrue(view.frame == CGRect(origin: .zero, size: CGSize(width: 10, height: 10)))
     XCTAssertTrue(frameProperty.value == CGRect(x: 50, y: 20, width: 100, height: 10))

     var otherFrame: CGRect = .zero
     _ = frameProperty.insider.listening(with: { otherFrame = $0 })
     copyFrameProperty <== CGRect(x: 1, y: 2, width: 3, height: 4)
     XCTAssertFalse(otherFrame == .zero)

     frameProperty.insider.disconnect(with: bgToken.token)
     frameProperty <== CGRect(x: 4, y: 3, width: 2, height: 1)
     XCTAssertTrue(view.frame == CGRect(x: 1, y: 2, width: 3, height: 4))
     }
     */

    func testBindProperty() {
        var backgroundProperty = Property<UIColor>(value: .white)
        var otherBackgroundProperty = Property<UIColor>(value: .black)
        _ = otherBackgroundProperty.bind(to: &backgroundProperty)

        backgroundProperty <== .red

        XCTAssertTrue(otherBackgroundProperty.value == .red)
    }

    func testBindReadonlyProperty() {
        var backgroundProperty = Property<UIColor>(value: .white)
        var otherBackgroundProperty = ReadonlyProperty<UIColor>(getter: { .red })
        _ = otherBackgroundProperty.bind(to: &backgroundProperty)

        backgroundProperty <== .white

        XCTAssertTrue(otherBackgroundProperty.value == .white)
    }
}
