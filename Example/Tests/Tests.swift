import UIKit
import XCTest
@testable import Realtime
@testable import Realtime_Example

extension XCTestCase {
    func XCTAssertThrows(block: () throws -> (), catchBlock: (Error?) -> Void) {
        do {
            try block()
        }
        catch let e {
            catchBlock(e)
        }
    }
}

extension XCTestCase {
    func performWaitExpectation(_ description: String,
                                timeout: TimeInterval,
                                performBlock:(_ expectation: XCTestExpectation) -> Void) {
        let expectation = self.expectation(description: description)
        performBlock(expectation)
        waitForExpectations(timeout: timeout, handler: nil)
    }

    func expectation(with description: String,
                     timeout: TimeInterval,
                     performBlock:() -> Void) -> XCTestExpectation {
        let expectation = self.expectation(description: description)
        performBlock()
        waitForExpectations(timeout: timeout, handler: nil)

        return expectation
    }
}

class Tests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    /// -------------------------------------------------------------------------------------------------------------

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

    class PropertyClass<T>: InsiderOwner {
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
                XCTAssertTrue(val == 1)
            } else if counter == 1 {
                XCTAssertTrue(val == 20)
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
        let bgToken = backgroundProperty.insider.listen(.just { view.backgroundColor = $0 })

        var weakowner: UIView? = UIView()
        _ = backgroundProperty.insider.listen(.weak(weakowner!) { (color, owner) in
            print(color, owner ?? "nil")
            if color == .yellow {
                XCTAssertNil(owner)
            }
        })

        let unownedOwner: UIView? = UIView()
        _ = backgroundProperty.insider.listen(.unowned(unownedOwner!) { (color, owner) in
            owner.backgroundColor = color
        })

        XCTAssertTrue(bgToken.token == Int.min)
        backgroundProperty <= .red
        XCTAssertTrue(view.backgroundColor == .red)
        backgroundProperty <= .green
        XCTAssertTrue(view.backgroundColor == .green)

        weakowner = nil

        var copyBgProperty = backgroundProperty
        copyBgProperty <= .yellow
        XCTAssertTrue(view.backgroundColor == .yellow)

        var otherColor: UIColor = .black
        _ = backgroundProperty.insider.listen(.just { otherColor = $0 })
        copyBgProperty <= .red
        XCTAssertFalse(otherColor == .red)

        backgroundProperty.insider.disconnect(with: bgToken.token)
        backgroundProperty <= .black
        XCTAssertTrue(view.backgroundColor == .red)
    }

    func testReadonlyProperty() {
        var propertyIndexSet = Property<IndexSet>(value: IndexSet(integer: 0))
        var readonlySum = ReadonlyProperty<Int>() {
            return propertyIndexSet.value.reduce(0, +) // TODO: Bad access
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
        _ = observableEntity.readonlyProperty.insider.listen(.just { stringLength = $0 })
        _ = observableEntity.readonlyProperty.insider.listen(.just{ print($0) })
        observableEntity.property <= "Denis Koryttsev"
        XCTAssertTrue(stringLength == 15)
    }

    func testOncePropertyListen() {
        let view = UIView()
        var backgroundProperty = Property<UIColor>(value: .white)

        let bgToken = backgroundProperty.insider.listen(as: { $0.once() }, .just {
            view.backgroundColor = $0
        })
        backgroundProperty <= .red

        XCTAssertTrue(view.backgroundColor == .red)
        XCTAssertFalse(backgroundProperty.insider.has(token: bgToken.token))

        backgroundProperty <= .green
        XCTAssertTrue(view.backgroundColor == .red)
    }

    func testIfPropertyListen() {
        let view = UIView()
        var backgroundProperty = Property<UIColor>(value: .white)

        let _ = backgroundProperty.insider.listen(as: { $0.if(!view.isHidden) }, .just {
            view.backgroundColor = $0
        })
        backgroundProperty <= .red

        XCTAssertTrue(view.backgroundColor == .red)
        view.isHidden = true

        backgroundProperty <= .green
        XCTAssertTrue(view.backgroundColor == .red)
    }

    func testPropertyFiredListening() {
        let view = UIView()
        var backgroundProperty = Property<UIColor>(value: .white)

        let bgToken = backgroundProperty.insider.listen(as: {
            $0.onFire {
                XCTAssertTrue(view.backgroundColor == .red)
                }.once()
        }, .just {
            view.backgroundColor = $0
        })
        backgroundProperty <= .red

        XCTAssertTrue(view.backgroundColor == .red)
        XCTAssertFalse(backgroundProperty.insider.has(token: bgToken.token))

        backgroundProperty <= .green
        XCTAssertTrue(view.backgroundColor == .red)
    }

    func testConcurrencyPropertyListen() {
        let cache = NSCache<NSString, NSString>()
        var stringProperty = Property<NSString>(value: "initial")
        let assignedValue = "New value"

        performWaitExpectation("async", timeout: 5) { (exp) in
            _ = stringProperty.insider.listen(as: { $0.queue(.global(qos: .background)) }, .just { (string) in
                cache.setObject(string, forKey: "key")
                XCTAssertFalse(Thread.isMainThread)
                XCTAssertTrue(cache.object(forKey: "key")! as String == assignedValue)
                exp.fulfill()
            })

            stringProperty <= assignedValue as NSString
        }
    }

    func testDeadlinePropertyListen() {
        var counter = 0
        var stringProperty = Property<String>(value: "initial")
        let beforeDeadlineValue = "First value"
        let afterDeadlineValue = "Second value"
        let inTimeValue = "Test"

        performWaitExpectation("async", timeout: 10) { (exp) in
            let token = stringProperty.insider.listen(as: { $0.deadline(.now() + .seconds(2)) }, .just { (string) in
                if counter == 0 {
                    XCTAssertTrue(string == beforeDeadlineValue)
                } else if counter == 1 {
                    XCTAssertTrue(string == inTimeValue)
                }

                counter += 1
            })

            stringProperty <= beforeDeadlineValue

            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                stringProperty <= inTimeValue
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(4)) {
                stringProperty <= afterDeadlineValue
                XCTAssertTrue(token.listening.isInvalidated)
                XCTAssertFalse(stringProperty.insider.has(token: token.token))
                XCTAssertTrue(counter == 2)
                exp.fulfill()
            }
        }
    }

    func testLivetimePropertyListen() {
        var counter = 0
        var stringProperty = Property<String>(value: "initial")
        let beforeDeadlineValue = "First value"
        let afterDeadlineValue = "Second value"
        let inTimeValue = "Test"

        var living: NSObject? = NSObject()

        performWaitExpectation("async", timeout: 10) { (exp) in
            let token = stringProperty.insider.listen(as: { $0.livetime(living!) }, .just { (string) in
                if counter == 0 {
                    XCTAssertTrue(string == beforeDeadlineValue)
                } else if counter == 1 {
                    XCTAssertTrue(string == inTimeValue)
                }

                counter += 1
            })

            stringProperty <= beforeDeadlineValue

            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                stringProperty <= inTimeValue
                living = nil
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(4)) {
                stringProperty <= afterDeadlineValue
                XCTAssertTrue(token.listening.isInvalidated)
                XCTAssertFalse(stringProperty.insider.has(token: token.token))
                XCTAssertTrue(counter == 2)
                exp.fulfill()
            }
        }
    }

    func testDebouncePropertyListen() {
        var counter = Property<Int>(value: 0)
        var receivedValues: [Int] = []

        _ = counter.insider.listen(as: { $0.debounce(.seconds(1)) }, .just { (value) in
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
                XCTAssertTrue(receivedValues == [1, 3, 6, 8])
                exp.fulfill()
            }
        }
    }

    func testListeningDisposable() {
        let propertyDouble = PropertyClass<Double>(.pi)

        var doubleValue = 0.0
        let dispose = propertyDouble.listening(.just { doubleValue = $0 })

        propertyDouble.value = 10.0
        XCTAssertTrue(doubleValue == 10.0)
        dispose.dispose()

        propertyDouble.value = .infinity
        XCTAssertTrue(doubleValue == 10.0)
    }

    func testListeningItem() {
        let propertyDouble = PropertyClass<Double>(.pi)

        var doubleValue = 0.0
        let item = propertyDouble.listeningItem(.just {
            doubleValue = $0
        })

        propertyDouble.value = 10.0
        XCTAssertTrue(doubleValue == 10.0)

        item.stop()
        XCTAssertFalse(item.isListen())
        propertyDouble.value = .infinity
        XCTAssertTrue(doubleValue == 10.0)

        item.start()
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
        propertyDouble.listening(.just { doubleValue = $0 }).add(to: &store)
        propertyDouble.value = 10.0
        XCTAssertTrue(doubleValue == 10.0)

        store.dispose()
        propertyDouble.value = .infinity
        XCTAssertTrue(doubleValue == 10.0)

        let item = propertyDouble.listeningItem(.just { doubleValue = $0 })
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

    func testFilterListening() {
        var stringValueLength = 0
        var property = Property<Double>(value: .pi)
        _ = property.insider.listen(preprocessor: { pp in
            return pp.filter { $0 >= 0 }.map(String.init).filter { $0.count > 1 }.map { v -> Int in debugPrint(v); return v.count }
        }, .just {
            stringValueLength = $0
        })

        property <= 0 // "0.0".length == 3
        XCTAssertTrue(stringValueLength == 3)
        property <= 21 // "21.0".length == 4
        XCTAssertTrue(stringValueLength == 4)
        property <= -100.5 // filtered
        XCTAssertTrue(stringValueLength == 4)
        XCTAssertTrue(property.value == -100.5)
    }

    func testDistinctUntilChangedListening() {
        var counter: Int = 0
        var property = Property<Double>(value: .pi)
        _ = property.insider.listen(preprocessor: { pp in
            return pp.distinctUntilChanged()
        }, .just { _ in
            counter += 1
        })

        property <= 0
        XCTAssertTrue(counter == 1)
        property <= 0
        XCTAssertTrue(counter == 1)
        property <= -100.5
        XCTAssertTrue(counter == 2)
        XCTAssertTrue(property.value == -100.5)
        property <= .pi
        XCTAssertTrue(counter == 3)
        property <= .pi
        XCTAssertTrue(counter == 3)
    }

    func testMapListening() {
        var exponentValue = 1
        var property = Property<Double>(value: .pi)
        _ = property.insider.listen(preprocessor: { pp in
            return pp.map { $0 + 0.5 }.filter { $0 > 0.5 }.map { v -> Int in debugPrint(v); return v.exponent }//.filter { $0 == 21.5 } // uncomment for filter input values, but this behavior illogical, therefore it use not recommended
        }, .just {
            exponentValue = $0
        })

        property <= 0
        XCTAssertTrue(property.value == 0)
        XCTAssertTrue(exponentValue == 1)
        property <= 21 // 21.5.exponent == 4
        XCTAssertTrue(exponentValue == 4)
        XCTAssertTrue(property.value == 21)
        property <= -100.5 // filtered
        XCTAssertTrue(exponentValue == 4)
        XCTAssertTrue(property.value == -100.5)
    }

    func testOnReceiveListening() {
        var exponentValue = 1
        var property = Property<Double>(value: .pi)
        //        _ = property.insider.listen(preprocessor: { pp in
        //            return pp.onReceive { v, exp in DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: { exp.fulfill() })  }
        //        }, {
        //            exponentValue = $0
        //        })
        _ = property.insider.listen(preprocessor: { (pp) in
            return pp.map { $0.exponent }.onReceive { v, exp in DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: { exp.fulfill() }) }
        }, .just {
            exponentValue = $0
        })

        let exp = expectation(description: "")
        property <= 0
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
            XCTAssertTrue(property.value == 0)
            XCTAssertTrue(exponentValue == property.value.exponent)
            property <= 21
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
                XCTAssertTrue(exponentValue == property.value.exponent)
                XCTAssertTrue(property.value == 21)
                property <= -100.5
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
                    XCTAssertTrue(exponentValue == property.value.exponent)
                    XCTAssertTrue(property.value == -100.5)
                    exp.fulfill()
                })
            })
        })

        waitForExpectations(timeout: 5, handler: nil)
    }

    func testFilterPropertyClass() {
        let propertyDouble = PropertyClass<Double>(.pi)

        var isChanged = false
        var doubleValue = 0.0 {
            didSet { isChanged = true }
        }
        _ = propertyDouble.filter { $0 != .infinity }.map { print($0); return $0 }.listening(.just { doubleValue = $0 })

        propertyDouble.value = 10.0
        XCTAssertTrue(doubleValue == 10.0)

        propertyDouble.value = .infinity
        XCTAssertTrue(doubleValue == 10.0)
    }

    func testMapPropertyClass() {
        let propertyDouble = PropertyClass<String>("Test")

        var value = ""
        _ = propertyDouble.map { $0 + " is successful" }.filter { print($0); return $0.count > 0 }.listening(.weak(self) { (v, owner) in
            print(owner ?? "nil")
            value = v
        })

        propertyDouble.value = "Test #1"
        XCTAssertTrue(value == "Test #1" + " is successful")

        propertyDouble.value = "Test #2154"
        XCTAssertTrue(value == "Test #2154" + " is successful")
    }

//    func testRealtimeTextField() {
//        let textField = UITextField()
//        let propertyValue = PropertyValue<String?>(unowned: textField, getter: { $0.text }, setter: { $0.text = $1 })
//        var property = Property(propertyValue)
//
//        _ = textField.realtimeText.insider.listen(.just { print($0 ?? "nil") })
//
//        property.value = "Text"
//        XCTAssertTrue(property.value == textField.text)
//
//        textField.realtimeText.value = "Some text"
//
//        XCTAssertTrue(textField.text == "Some text")
//
//        property.value = "new text"
//        XCTAssertTrue(textField.text == "new text")
//    }

//    func testRealtimeTextField2() {
//        let textField = UITextField()
//        let realtimeTF = textField.rt
//        _ = realtimeTF.text.insider.listen(.just {
//            print($0 ?? "nil")
//        })
//
//        realtimeTF.text.value = "Text"
//        XCTAssertTrue(realtimeTF.text.value == textField.text)
//
//        textField.realtimeText.value = "Some text"
//        textField.sendActions(for: .valueChanged)
//
//        XCTAssertTrue(textField.text == "Some text")
//        XCTAssertTrue(realtimeTF.text~ == "Some text")
//
//        realtimeTF.text <= "new text"
//        XCTAssertTrue(textField.text == "new text")
//    }

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
        valueWrapper <= 20
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
     frameProperty <= CGRect(x: 50, y: 20, width: 100, height: 10)
     XCTAssertTrue(view.frame == CGRect(x: 50, y: 20, width: 100, height: 10))

     weakowner = nil

     var copyFrameProperty = frameProperty
     copyFrameProperty <= CGRect(origin: .zero, size: CGSize(width: 10, height: 10))
     XCTAssertTrue(view.frame == CGRect(origin: .zero, size: CGSize(width: 10, height: 10)))
     XCTAssertTrue(frameProperty.value == CGRect(x: 50, y: 20, width: 100, height: 10))

     var otherFrame: CGRect = .zero
     _ = frameProperty.insider.listening(with: { otherFrame = $0 })
     copyFrameProperty <= CGRect(x: 1, y: 2, width: 3, height: 4)
     XCTAssertFalse(otherFrame == .zero)

     frameProperty.insider.disconnect(with: bgToken.token)
     frameProperty <= CGRect(x: 4, y: 3, width: 2, height: 1)
     XCTAssertTrue(view.frame == CGRect(x: 1, y: 2, width: 3, height: 4))
     }
     */

    func testBindProperty() {
        var backgroundProperty = Property<UIColor>(value: .white)
        var otherBackgroundProperty = Property<UIColor>(value: .black)
        _ = otherBackgroundProperty.bind(to: &backgroundProperty)

        backgroundProperty <= .red

        XCTAssertTrue(otherBackgroundProperty.value == .red)
    }

    func testBindReadonlyProperty() {
        var backgroundProperty = Property<UIColor>(value: .white)
        var otherBackgroundProperty = ReadonlyProperty<UIColor>(getter: { .red })
        _ = otherBackgroundProperty.bind(to: &backgroundProperty)

        backgroundProperty <= .white

        XCTAssertTrue(otherBackgroundProperty.value == .white)
    }
}

// MARK: Realtime

class TestObject: RealtimeObject {
    lazy var property: RealtimeProperty<String?> = "prop".property(from: self.node)
    lazy var readonlyProperty: ReadonlyRealtimeProperty<Int> = "readonlyProp".readonlyProperty(from: self.node).defaultOnEmpty()
    lazy var linkedArray: LinkedRealtimeArray<RealtimeObject> = "linked_array".linkedArray(from: self.node, elements: .root)
    lazy var array: RealtimeArray<TestObject> = "array".array(from: self.node)
    lazy var dictionary: RealtimeDictionary<RealtimeObject, TestObject> = "dict".dictionary(from: self.node, keys: .root)
    lazy var nestedObject: NestedObject = "nestedObject".nested(in: self)

    override open class func keyPath(for label: String) -> AnyKeyPath? {
        switch label {
        case "property": return \TestObject.property
        case "readonlyProperty": return \TestObject.readonlyProperty
        case "linkedArray": return \TestObject.linkedArray
        case "array": return \TestObject.array
        case "dictionary": return \TestObject.dictionary
        case "nestedObject": return \TestObject.nestedObject
        default: return nil
        }
    }

    open class func keyPaths() -> [AnyKeyPath] { // TODO: Consider
        return [\TestObject.property, \TestObject.linkedArray, \TestObject.array, \TestObject.dictionary, \TestObject.nestedObject]
    }

    class NestedObject: TestObject {
        lazy var lazyProperty: RealtimeProperty<String?> = "lazyprop".property(from: self.node)
        var usualProperty: RealtimeProperty<String?>?

        required init(in node: Node?, options: [RealtimeValueOption : Any]) {
            self.usualProperty = "usualprop".property(from: node)
            super.init(in: node, options: options)
        }

        required convenience init(fireData: FireDataProtocol) throws {
            self.init(in: fireData.dataRef.map(Node.from))
            try apply(fireData, strongly: true)
        }

        override func apply(_ data: FireDataProtocol, strongly: Bool) throws {
            try super.apply(data, strongly: strongly)
        }

        override open class func keyPath(for label: String) -> AnyKeyPath? {
            switch label {
            case "lazyProperty": return \NestedObject.lazyProperty
            default: return nil
            }
        }
    }
}

extension Tests {
    func testNestedObjectChanges() {
        let testObject = TestObject(in: .root)

        testObject.property <= "string"
        testObject.nestedObject.lazyProperty <= "nested_string"

        do {
            let trans = try testObject.update()
            let value = trans.updateNode.updateValue
            let expectedValue = ["/prop":"string", "/nestedObject/lazyprop":"nested_string"] as [String: Any?]

            XCTAssertTrue((value as NSDictionary) == (expectedValue as NSDictionary))
            trans.revert()
        } catch let e {
            XCTFail(e.localizedDescription)
        }
    }

    func testMergeTransactions() {
        let testObject = TestObject(in: .root)

        testObject.property <= "string"
        testObject.nestedObject.lazyProperty <= "nested_string"

        let element = TestObject(in: Node.root.child(with: "element_1"))
        element.property <= "element #1"
        element.nestedObject.lazyProperty <= "value"

        do {
            let elementTransaction = try element.update()
            let objectTransaction = try testObject.update()
            elementTransaction.merge(objectTransaction)

            let value = elementTransaction.updateNode.updateValue
            let expectedValue = ["/prop":"string", "/nestedObject/lazyprop":"nested_string",
                                 "/element_1/prop":"element #1", "/element_1/nestedObject/lazyprop":"value"] as [String: Any?]

            XCTAssertTrue((value as NSDictionary) == (expectedValue as NSDictionary))
            elementTransaction.revert()
        } catch let e {
            XCTFail(e.localizedDescription)
        }
    }

    func testCollectionOnRootObject() {
        let testObject = TestObject(in: .root)

        let transaction = RealtimeTransaction()

        let linkedObject = TestObject(in: Node.root.child(with: "linked"))
        linkedObject.property <= "#1"
        testObject.linkedArray._view.isPrepared = true
        XCTAssertNoThrow(try testObject.linkedArray.write(element: linkedObject, in: transaction))

        let object = TestObject(in: Node(key: "elem_1"))
        object.property <= "prop"
        testObject.array._view.isPrepared = true
        XCTAssertNoThrow(try testObject.array.write(element: object, in: transaction))

        let element = TestObject()
        element.property <= "element #1"
        testObject.dictionary._view.isPrepared = true
        XCTAssertNoThrow(try testObject.dictionary.write(element: element, for: linkedObject, in: transaction))

        let value = transaction.updateNode.updateValue

        let linkedItem = value["/linked_array/linked"] as? [String: Any]
        XCTAssertTrue(linkedItem != nil)
        XCTAssertTrue(value["/array/elem_1/prop"] as? String == "prop")
        XCTAssertTrue(value["/dict/linked/prop"] as? String == "element #1")
        transaction.revert()
    }

    func testCollectionOnStandaloneObject() {
        let testObject = TestObject(in: Node(key: "test_obj"))

        let linkedObject = TestObject(in: Node.root.child(with: "linked"))
        linkedObject.property <= "#1"
        testObject.linkedArray.insert(element: linkedObject)

        let object = TestObject(in: Node(key: "elem_1"))
        object.property <= "prop"
        testObject.array.insert(element: object)

        let element = TestObject()
        element.property <= "element #1"
        testObject.dictionary.set(element: element, for: linkedObject)

        do {
            let transaction = try testObject.save(in: .root)
            let value = transaction.updateNode.updateValue

            let linkedItem = value["/test_obj/linked_array/linked"] as? [String: Any]
            XCTAssertTrue(linkedItem != nil)
            XCTAssertTrue(value["/test_obj/array/elem_1/prop"] as? String == "prop")
            XCTAssertTrue(value["/test_obj/dict/linked/prop"] as? String == "element #1")
            transaction.revert()
        } catch let e {
            XCTFail(e.localizedDescription)
        }
    }

    func testDecoding() {
        let transaction = RealtimeTransaction()

        do {
            let element = TestObject(in: Node.root.child(with: "element_1"))
            element.property <= "element #1"
            element.nestedObject.lazyProperty <= "value"
            let child = TestObject()
            child.property <= "element #1"
            element.array._view.isPrepared = true
            try element.array.write(element: child, in: transaction)
            transaction.removeValue(by: element.readonlyProperty.node!)

            let data = try element.update(in: transaction).updateNode

            let object = try TestObject(fireData: data.child(forPath: element.node!.rootPath), strongly: false)
            try object.array._view.source.apply(data.child(forPath: object.array._view.source.node!.rootPath), strongly: true)

            XCTAssertEqual(object.readonlyProperty.wrapped, Int())
            XCTAssertEqual(object.property.unwrapped, element.property.unwrapped)
            XCTAssertEqual(object.nestedObject.lazyProperty.unwrapped, element.nestedObject.lazyProperty.unwrapped)
            XCTAssertTrue(object.array.isPrepared)
            XCTAssertEqual(object.array.first?.property.unwrapped, element.array.first?.property.unwrapped)
        } catch let e {
            XCTFail(e.localizedDescription)
        }

        transaction.revert()
    }

    func testRelation() {
        let transaction = RealtimeTransaction()

        do {
            let user = RealtimeUser(in: Node(key: "user", parent: .root))
            let group = RealtimeGroup(in: Node(key: "group", parent: .root))
            user.ownedGroup <= group

            let data = try user.update(in: transaction).updateNode

            let userCopy = try RealtimeUser(fireData: data.child(forPath: user.node!.rootPath), strongly: false)

            XCTAssertTrue(user.ownedGroup.unwrapped?.dbKey == group.dbKey)
            XCTAssertTrue(userCopy.ownedGroup.unwrapped?.dbKey == group.dbKey)
        } catch let e {
            XCTFail(e.localizedDescription)
        }

        transaction.revert()
    }

    func testOptionalRelation() {
        let transaction = RealtimeTransaction()

        do {
            let user = RealtimeUser(in: Node(key: "user", parent: .root))
            user.ownedGroup <= nil

            let data = try user.update(in: transaction).updateNode

            let userCopy = try RealtimeUser(fireData: data.child(forPath: user.node!.rootPath), strongly: false)

            if case .error(let e, _) = userCopy.ownedGroup.lastEvent {
                XCTFail(e.localizedDescription)
            } else {
                XCTAssertTrue(userCopy.ownedGroup.unwrapped?.dbKey == userCopy.ownedGroup.unwrapped?.dbKey)
            }
        } catch let e {
            XCTFail(e.localizedDescription)
        }

        transaction.revert()
    }

    func testOptionalReference() {
        let transaction = RealtimeTransaction()

        do {
            let conversation = Conversation(in: Node(key: "conv_1", parent: .root))
            conversation.secretary <= nil

            let data = try conversation.update(in: transaction).updateNode

            let conversationCopy = try Conversation(fireData: data.child(forPath: conversation.node!.rootPath), strongly: false)

            if case .error(let e, _) = conversation.chairman.lastEvent {
                XCTFail(e.localizedDescription)
            } else {
                XCTAssertTrue(conversationCopy.secretary.unwrapped?.dbKey == conversation.secretary.unwrapped?.dbKey)
            }
        } catch let e {
            XCTFail(e.localizedDescription)
        }

        transaction.revert()
    }

    func testRepresenterOptional() {
        let representer = Representer<TestObject>.relation("prop").optional()
        do {
            let object = try representer.decode(ValueNode(node: Node(key: ""), value: nil))
            XCTAssertNil(object)
        } catch let e {
            XCTFail(e.localizedDescription)
        }
    }

    func testNode() {
        let first = Node(key: "first", parent: .root)

        let second = Node(key: "second", parent: first)
        XCTAssertEqual(second.rootPath, "/first/second")
        XCTAssertEqual(second.path(from: first), "/second")
        XCTAssertTrue(second.hasParent(node: first))
        XCTAssertTrue(second.isRooted)

        let third = second.child(with: "third")
        XCTAssertEqual(third.rootPath, "/first/second/third")
        XCTAssertEqual(third.path(from: first), "/second/third")
        XCTAssertTrue(third.hasParent(node: first))
        XCTAssertTrue(third.isRooted)

        let fourth = third.child(with: "fourth")
        XCTAssertEqual(fourth.rootPath, "/first/second/third/fourth")
        XCTAssertEqual(fourth.path(from: first), "/second/third/fourth")
        XCTAssertTrue(fourth.hasParent(node: first))
        XCTAssertTrue(fourth.isRooted)
    }

    func testLinksNode() {
        let fourth = Node.root.child(with: "/first/second/third/fourth")
        let linksNode = fourth.linksNode
        XCTAssertEqual(linksNode.rootPath, "/__links/first/second/third/fourth")
    }

    func testConnectNode() {
        let testObject = TestObject(in: Node())

        XCTAssertTrue(testObject.isStandalone)
        XCTAssertTrue(testObject.property.isStandalone)
        XCTAssertTrue(testObject.linkedArray.isStandalone)
        XCTAssertTrue(testObject.array.isStandalone)
        XCTAssertTrue(testObject.dictionary.isStandalone)

        let node = Node(key: "testObjects", parent: .root)
        testObject.didSave(in: node)

        XCTAssertTrue(testObject.isInserted)
        XCTAssertTrue(testObject.property.isInserted)
        XCTAssertTrue(testObject.linkedArray.isInserted)
        XCTAssertTrue(testObject.array.isInserted)
        XCTAssertTrue(testObject.dictionary.isInserted)
    }

    func testDisconnectNode() {
        let node = Node(key: "testObjects", parent: .root).childByAutoId()
        let testObject = TestObject(in: node)

        XCTAssertTrue(testObject.isInserted)
        XCTAssertTrue(testObject.property.isInserted)
        XCTAssertTrue(testObject.linkedArray.isInserted)
        XCTAssertTrue(testObject.array.isInserted)
        XCTAssertTrue(testObject.dictionary.isInserted)

        testObject.didRemove()

        XCTAssertTrue(testObject.isStandalone)
        XCTAssertTrue(testObject.property.isStandalone)
        XCTAssertTrue(testObject.linkedArray.isStandalone)
        XCTAssertTrue(testObject.array.isStandalone)
        XCTAssertTrue(testObject.dictionary.isStandalone)
    }

    enum ValueWithPayload: WritableRealtimeValue, FireDataRepresented, RealtimeValueActions {
        var version: Int? { return value.version }
        var raw: FireDataValue? {
            switch self {
            case .two: return 1
            default: return nil
            }
        }
        var node: Node? { return value.node }
        var payload: [String : FireDataValue]? { return value.payload }
        var value: TestObject {
            switch self {
            case .one(let v): return v
            case .two(let v): return v
            }
        }

        case one(TestObject)
        case two(TestObject)

        init(in node: Node?, options: [RealtimeValueOption : Any]) {
            let raw = options.rawValue as? Int ?? 0

            switch raw {
            case 1: self = .two(TestObject(in: node, options: options))
            default: self = .one(TestObject(in: node, options: options))
            }
        }

        init(fireData: FireDataProtocol) throws {
            let raw: CShort = fireData.rawValue as? CShort ?? 0

            switch raw {
            case 1: self = .two(try TestObject(fireData: fireData))
            default: self = .one(try TestObject(fireData: fireData))
            }
        }

        mutating func apply(_ data: FireDataProtocol, strongly: Bool) throws {
            try value.apply(data, strongly: strongly)
            let r = data.rawValue as? Int ?? 0
            if raw as? Int != r {
                switch r {
                case 1: self = .two(value)
                default: self = .one(value)
                }
            }
        }

        func load(completion: Assign<Error?>?) {
            value.load(completion: completion)
        }

        var canObserve: Bool { return value.canObserve }

        func runObserving() -> Bool {
            return value.runObserving()
        }

        func stopObserving() {
            value.stopObserving()
        }

        func willSave(in transaction: RealtimeTransaction, in parent: Node, by key: String) {
            value.willSave(in: transaction, in: parent, by: key)
        }

        func didSave(in parent: Node, by key: String) {
            value.didSave(in: parent, by: key)
        }

        func didRemove(from ancestor: Node) {
            value.didRemove(from: ancestor)
        }

        func willRemove(in transaction: RealtimeTransaction, from ancestor: Node) {
            value.willRemove(in: transaction, from: ancestor)
        }

        func write(to transaction: RealtimeTransaction, by node: Node) throws {
            try value.write(to: transaction, by: node)
        }
    }

    func testPayload() {
        let array = RealtimeArray<ValueWithPayload>(in: Node.root.child(with: "__tests/array"))
        let exp = expectation(description: "")
        let transaction = RealtimeTransaction()

        array.prepare(forUse: .just { (a, err) in
            XCTAssertNil(err)
            XCTAssertTrue(a.isPrepared)

            try! a.write(element: .one(TestObject()), in: transaction)
            try! a.write(element: .two(TestObject()), in: transaction)

            exp.fulfill()
        })

        waitForExpectations(timeout: 40) { (err) in
            XCTAssertNil(err)
            XCTAssertTrue(array.count == 2)
//            XCTAssertNoThrow(array.storage.buildElement(with: array._view.last!))
            transaction.revert()
        }
    }

    func testInitializeWithPayload() {
        let value = TestObject(in: .root, options: [.payload: ["key": "val"]])
        XCTAssertTrue((value.payload as NSDictionary?) == ["key": "val"])
    }

    func testInitializeWithPayload2() {
        let payload: [String: Any] = ["key": "val"]
        let value = TestObject(in: .root, options: [.payload: payload])
        XCTAssertTrue((value.payload as NSDictionary?) == (payload as NSDictionary))
    }

    func testInitializeWithPayload3() {
        let payload: Any = ["key": "val"]
        let value = TestObject(in: .root, options: [.payload: payload])
        XCTAssertTrue((value.payload as NSDictionary?) == (payload as? NSDictionary))
    }

    func testReferenceFireValue() {
        let ref = Reference(ref: Node.root.child(with: "first/two").rootPath)
        let fireValue = ref.fireValue
        XCTAssertTrue((fireValue as? NSDictionary) == ["ref": "/first/two"])
    }
}

// UIKit support

extension Tests {
    func testControlListening() {
        var counter = 0
        let control = UIControl()

        let disposable = control.listening(events: .touchUpInside, .just {
            counter += 1
        })

        control.sendActions(for: .touchUpInside)

        XCTAssertTrue(counter == 1)

        control.sendActions(for: .touchUpInside)
        control.sendActions(for: .touchDown)

        XCTAssertTrue(counter == 2)

        disposable.dispose()

        control.sendActions(for: .touchUpInside)

        XCTAssertTrue(counter == 2)
    }
}

// MARK: Other

extension Tests {
    func testAnyOf() {
        XCTAssertTrue(2 ∈ [1,2,3]) // true
        XCTAssertTrue("Two" ∈ ["One", "Two", "Three"])

        XCTAssertTrue(any(of: 1,2,3)(2)) // true
        XCTAssertTrue(any(of: "One", "Two", "Three")("Two"))
    }
    func testAnyCollection() {
        var calculator: Int = 0
        let mapValue: (Int) -> Int = { _ in calculator += 1; return calculator }
        let source = RealtimeProperty<[Int]>(in: .root, options: [.representer: Representer<[Int]>.any, .initialValue: [0]])
        let one = AnyRealtimeCollectionView<[Int], RealtimeArray<RealtimeObject>>(source)//SharedCollection([1])

        let lazyOne = one.lazy.map(mapValue)
        _ = lazyOne.first
        XCTAssertTrue(calculator == 1)
        let anyLazyOne = AnySharedCollection(lazyOne)
        XCTAssertTrue(calculator == 1)
        source._setValue([0, 0])
        XCTAssertTrue(one.count == 2)
        XCTAssertTrue(lazyOne.count == 2)
        XCTAssertTrue(anyLazyOne.count == 2)
    }
    func testMirror() {
        let object = RealtimeObject(in: .root)
        let mirror = Mirror(reflecting: object)

        XCTAssert(mirror.children.count > 0)
        mirror.children.forEach { (child) in
            print(child.label as Any, child.value)
        }

        mirror.children.forEach { (child) in
            print(child.label as Any, child.value)
        }

        let id = ObjectIdentifier.init(object)
        print(id)
    }
    func testReflectEnum() {
        enum Test {
            case one(Any), two(Any)
        }
        let one = Test.one(false)
        let oneMirror = Mirror(reflecting: one)
        let testMirror = Mirror(reflecting: Test.self)

        print(oneMirror, testMirror)
    }

    func testCodableEnum() {
        struct Err: Error {
            var localizedDescription: String { return "" }
        }
        struct News: Codable {
            let date: TimeInterval
        }
        enum Feed: Codable {
            case common(News)

            enum Key: CodingKey {
                case raw
            }

            init(from decoder: Decoder) throws {
                let rawContainer = try decoder.container(keyedBy: Key.self)
                let container = try decoder.singleValueContainer()
                let rawValue = try rawContainer.decode(Int.self, forKey: .raw)
                switch rawValue {
                case 0:
                    self = .common(try container.decode(News.self))
                default:
                    throw Err()
                }
            }

            func encode(to encoder: Encoder) throws {
                switch self {
                case .common(let news):
                    var container = encoder.singleValueContainer()
                    try container.encode(news)
                    var rawContainer = encoder.container(keyedBy: Key.self)
                    try rawContainer.encode(0, forKey: .raw)
                }
            }
        }

        let news = News(date: 0.0)
        let feed: Feed = .common(news)

        let data = try! JSONEncoder().encode(feed)

        let json = try! JSONSerialization.jsonObject(with: data, options: .allowFragments) as! NSDictionary
        let decodedFeed = try! JSONDecoder().decode(Feed.self, from: data)

        XCTAssertTrue(["raw": 0, "date": 0.0] as NSDictionary == json)
        switch decodedFeed {
        case .common(let n):
            XCTAssertTrue(n.date == news.date)
        }
    }

    func testEnumStringInterpolation() {
        XCTAssertNotEqual("__raw/__mv", "\(InternalKeys.raw)/\(InternalKeys.modelVersion)")
    }
}

final class SharedCollection<Base: MutableCollection>: MutableCollection {
    func index(after i: Base.Index) -> Base.Index {
        return base.index(after: i)
    }

    subscript(position: Base.Index) -> Base.Iterator.Element {
        get {
            return base[position]
        }
        set(newValue) {
            base[position] = newValue
        }
    }

    var endIndex: Base.Index { return base.endIndex }
    var startIndex: Base.Index { return base.startIndex }

    typealias Index = Base.Index

    /// Returns an iterator over the elements of this sequence.
    func makeIterator() -> Base.Iterator {
        return base.makeIterator()
    }

    var base: Base

    init(_ base: Base) {
        self.base = base
    }
}
extension SharedCollection where Base == Array<Int> {
    func append(_ elem: Int) {
        base.append(elem)
    }
}

infix operator ∈
func ∈ <T: Equatable>(lhs: T, rhs: [T]) -> Bool {
    return rhs.contains(lhs)
}

func any<T: Equatable>(of values: T...) -> (T) -> Bool {
    return { values.contains($0) }
}
