import XCTest
import SystemConfiguration
@testable import Realtime

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
                                performBlock: (_ expectation: XCTestExpectation) -> Void,
                                onFulfill: XCWaitCompletionHandler? = nil) {
        let expectation = self.expectation(description: description)
        performBlock(expectation)
        waitForExpectations(timeout: timeout, handler: onFulfill)
    }

    func performWaitExpectation(_ description: String,
                                timeout: TimeInterval,
                                performBlock: (_ expectation: XCTestExpectation) -> Void) {
        performWaitExpectation(description, timeout: timeout, performBlock: performBlock, onFulfill: nil)
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

extension Error {
    var describingErrorDescription: String {
        return String(describing: self)
    }
}

public final class RealtimeTests: XCTestCase {
    var store: ListeningDisposeStore = ListeningDisposeStore()
    public static var allTestsSetUp: (() -> Void)?

    override public class func setUp() {
        super.setUp()
        if let testsSetUp = allTestsSetUp {
            testsSetUp()
        } else {
            let configuration = RealtimeApp.Configuration(linksNode: BranchNode(key: "___tests/__links"))
            RealtimeApp.initialize(with: RealtimeApp.cache, storage: RealtimeApp.cache, configuration: configuration)
        }
    }

    override public func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override public func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
        Cache.root.clear()
    }
}

// MARK: Realtime

class TestObject: Object {
    lazy var property: Property<String?> = "prop".property(in: self)
    lazy var readonlyProperty: ReadonlyProperty<Int64> = "readonlyProp".readonlyProperty(in: self, representer: .realtimeDataValue).defaultOnEmpty()
    lazy var linkedArray: MutableReferences<TestObject> = "linked_array".references(in: self, elements: .root)
    lazy var array: Values<TestObject> = "array".values(in: self)
    lazy var dictionary: AssociatedValues<TestObject, TestObject> = "dict".dictionary(in: self, keys: .root)
    lazy var nestedObject: NestedObject = "nestedObject".nested(in: self)
    lazy var readonlyFile: ReadonlyFile<Data?> = "readonlyFile".readonlyFile(in: self, representer: .realtimeDataValue)
    lazy var file: File<Data?> = "file".file(in: self, representer: Representer<Data>.realtimeDataValue, metadata: ["contentType": "text/plain"])

    override open class func lazyPropertyKeyPath(for label: String) -> AnyKeyPath? {
        switch label {
        case "property": return \TestObject.property
        case "readonlyProperty": return \TestObject.readonlyProperty
        case "linkedArray": return \TestObject.linkedArray
        case "array": return \TestObject.array
        case "dictionary": return \TestObject.dictionary
        case "nestedObject": return \TestObject.nestedObject
        case "readonlyFile": return \TestObject.readonlyFile
        case "file": return \TestObject.file
        default: return nil
        }
    }

    open class func keyPaths() -> [AnyKeyPath] { // TODO: Consider
        return [\TestObject.property, \TestObject.linkedArray, \TestObject.array, \TestObject.dictionary, \TestObject.nestedObject]
    }

    class NestedObject: Object {
        lazy var lazyProperty: Property<String?> = "lazyprop".property(in: self)
        var usualProperty: Property<String?>

        required init(in node: Node?, options: [ValueOption : Any]) {
            self.usualProperty = Property.optional(in: Node(key: "usualprop", parent: node),
                                                   representer: .realtimeDataValue,
                                                   options: [.database: options[.database] as Any])
            super.init(in: node, options: options)
        }

        required init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
            self.usualProperty = Property.optional(in: Node(key: "usualprop", parent: data.node),
                                                   representer: .realtimeDataValue,
                                                   options: [.database: data.database as Any])
            try super.init(data: data, event: event)
        }

        override func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
            try super.apply(data, event: event)
        }

        override open class func lazyPropertyKeyPath(for label: String) -> AnyKeyPath? {
            switch label {
            case "lazyProperty": return \NestedObject.lazyProperty
            default: return nil
            }
        }
    }
}

enum RVType {
    case unkeyed
    case keyed
    indirect case nested(parent: RVType)
    case rooted
}

enum RVEvent {
    case willSave(RVType), willRemove
    case didSave, didRemove(RVType)
}

func checkStates(in v: NewRealtimeValue, for event: RVEvent, _ line: Int = #line) {
    switch event {
    case .didSave, .willRemove:
        XCTAssertTrue(v.isReferred, "line: \(line)")
        XCTAssertTrue(v.isKeyed, "line: \(line)")
        XCTAssertTrue(v.isRooted, "line: \(line)")
        XCTAssertFalse(v.isStandalone, "line: \(line)")
    case .willSave(let t), .didRemove(let t):
        switch t {
        case .rooted: return
        case .unkeyed:
            XCTAssertFalse(v.isKeyed, "line: \(line)")
            XCTAssertFalse(v.isReferred, "line: \(line)")
        case .keyed:
            XCTAssertTrue(v.isKeyed, "line: \(line)")
            XCTAssertFalse(v.isReferred, "line: \(line)")
        case .nested(parent: let p):
            switch p {
            case .unkeyed: XCTAssertFalse(v.isReferred, "line: \(line)")
            default: XCTAssertTrue(v.isReferred, "line: \(line)")
            }
        }
        XCTAssertFalse(v.isRooted, "line: \(line)")
        XCTAssertTrue(v.isStandalone, "line: \(line)")
    }
}

func checkDidSave(_ v: NewRealtimeValue, nested: Bool = false, _ line: Int = #line) {
    checkStates(in: v, for: .didSave, line)
}

func checkDidRemove(_ v: NewRealtimeValue, value type: RVType = .unkeyed, _ line: Int = #line) {
    checkStates(in: v, for: .didRemove(type), line)
}

func checkWillSave(_ v: NewRealtimeValue, value type: RVType = .unkeyed, _ line: Int = #line) {
    checkStates(in: v, for: .willSave(type), line)
}

func checkWillRemove(_ v: NewRealtimeValue, nested: Bool = false, _ line: Int = #line) {
    checkStates(in: v, for: .willRemove, line)
}

extension RealtimeTests {
    func testReflector() {
        let object = TestObject()
        let reflector = Reflector(reflecting: object, to: Object.self)

        var calculator = 0
        reflector.forEach { (mirror) in
            XCTAssertTrue(mirror.subjectType == TestObject.self)
            calculator += 1
        }

        XCTAssertEqual(calculator, 1)
    }

    func testObjectSave() {
        let obj = TestObject()

        obj.property <== "value"
        XCTAssertTrue(obj.property.hasChanges)
        obj.file <== "file".data(using: .utf8)
        XCTAssertTrue(obj.file.hasChanges)
        obj.nestedObject.usualProperty <== "usual"
        XCTAssertTrue(obj.nestedObject.hasChanges)
        XCTAssertTrue(obj.nestedObject.usualProperty.hasChanges)
        obj.nestedObject.lazyProperty <== "lazy"
        XCTAssertTrue(obj.nestedObject.lazyProperty.hasChanges)

        XCTAssertTrue(obj.hasChanges)
        checkWillSave(obj)
        checkWillSave(obj.property, value: .nested(parent: .unkeyed))
        checkWillSave(obj.readonlyProperty, value: .nested(parent: .unkeyed))
        checkWillSave(obj.linkedArray, value: .nested(parent: .unkeyed))
        checkWillSave(obj.array, value: .nested(parent: .unkeyed))
        checkWillSave(obj.dictionary, value: .nested(parent: .unkeyed))
        checkWillSave(obj.file, value: .nested(parent: .unkeyed))
        checkWillSave(obj.readonlyFile, value: .nested(parent: .unkeyed))
        checkWillSave(obj.nestedObject, value: .nested(parent: .unkeyed))
        checkWillSave(obj.nestedObject.usualProperty, value: .nested(parent: .keyed))
        checkWillSave(obj.nestedObject.lazyProperty, value: .nested(parent: .keyed))
        do {
            let save = try obj.save(by: .root, in: Transaction(database: Cache.root, storage: Cache.root))
            save.commit(with: { _, errs in
                errs.map { _ in XCTFail() }

                XCTAssertFalse(obj.hasChanges)
                checkDidSave(obj)
                checkDidSave(obj.property, nested: true)
                checkDidSave(obj.readonlyProperty, nested: true)
                checkDidSave(obj.linkedArray, nested: true)
                checkDidSave(obj.array, nested: true)
                checkDidSave(obj.dictionary, nested: true)
                checkDidSave(obj.file, nested: true)
                checkDidSave(obj.readonlyFile, nested: true)
                checkDidSave(obj.nestedObject, nested: true)
                checkDidSave(obj.nestedObject.usualProperty, nested: true)
                checkDidSave(obj.nestedObject.lazyProperty, nested: true)
            })
        } catch let e {
            XCTFail(e.localizedDescription)
        }
    }
    func testPropertySetValue() {
        let property = Property<String>.required(
            in: Node(key: "value", parent: .root),
            representer: .realtimeDataValue
        )

        XCTAssertFalse(property.hasChanges)
        let transaction = Transaction(database: Cache.root)
        do {
            try property.setValue("Some string", in: transaction)
            XCTAssertTrue(property.hasChanges)

            transaction.commit(with: { _, errors in
                errors.map { _ in XCTFail() }

                XCTAssertFalse(property.hasChanges)
                checkDidSave(property)
            })
        } catch let e {
            XCTFail(e.localizedDescription)
        }
    }
    func testRemovePropertyValue() {
        let rootObj = Object(in: Node.root, options: [.database: Cache.root])
        let prop: Property<String?> = "prop".property(in: rootObj)

        prop.remove()
        let transaction = Transaction(database: Cache.root, storage: Cache.root)
        do {
            try rootObj.update(in: transaction)
        } catch let e {
            switch e {
            case _ as RealtimeError: break
            default: XCTFail("Unexpected error")
            }
        }
        transaction.cancel()
    }
    func testObjectRemove() {
        let obj = TestObject()

        obj.property <== "value"
        obj.file <== "file".data(using: .utf8)
        obj.nestedObject.usualProperty <== "usual"
        obj.nestedObject.lazyProperty <== "lazy"

        obj.didSave(in: Cache.root, in: .root, by: "obj")

        XCTAssertFalse(obj.hasChanges)
        checkWillRemove(obj)
        checkWillRemove(obj.property, nested: true)
        checkWillRemove(obj.readonlyProperty, nested: true)
        checkWillRemove(obj.linkedArray, nested: true)
        checkWillRemove(obj.array, nested: true)
        checkWillRemove(obj.dictionary, nested: true)
        checkWillRemove(obj.file, nested: true)
        checkWillRemove(obj.readonlyFile, nested: true)
        checkWillRemove(obj.nestedObject, nested: true)
        checkWillRemove(obj.nestedObject.usualProperty, nested: true)
        checkWillRemove(obj.nestedObject.lazyProperty, nested: true)

        let save = obj.delete(in: Transaction(database: Cache.root, storage: Cache.root))
        save.commit(with: { _, errs in
            errs.map { _ in XCTFail() }

            XCTAssertFalse(obj.hasChanges)
            checkDidRemove(obj, value: .keyed)
            checkDidRemove(obj.property, value: .nested(parent: .keyed))
            checkDidRemove(obj.readonlyProperty, value: .nested(parent: .keyed))
            checkDidRemove(obj.linkedArray, value: .nested(parent: .keyed))
            checkDidRemove(obj.array, value: .nested(parent: .keyed))
            checkDidRemove(obj.dictionary, value: .nested(parent: .keyed))
            checkDidRemove(obj.file, value: .nested(parent: .keyed))
            checkDidRemove(obj.readonlyFile, value: .nested(parent: .keyed))
            checkDidRemove(obj.nestedObject, value: .nested(parent: .keyed))
            checkDidRemove(obj.nestedObject.usualProperty, value: .nested(parent: .keyed))
            checkDidRemove(obj.nestedObject.lazyProperty, value: .nested(parent: .keyed))
        })
    }
}

extension RealtimeTests {
    func testNestedObjectChanges() {
        let testObject = TestObject(in: Node(key: "t_obj"))

        testObject.property <== "string"
        testObject.nestedObject.lazyProperty <== "nested_string"

        do {
            let trans = try testObject.save(in: .root)
            let value = trans.updateNode.debugValue
            let expectedValue = ["t_obj/prop":"string", "t_obj/nestedObject/lazyprop":"nested_string"] as [String: Any?]

            XCTAssertTrue((value as NSDictionary) == (expectedValue as NSDictionary))
            trans.revert()
        } catch let e {
            XCTFail(e.localizedDescription)
        }
    }

    func testMergeTransactions() {
        let exp = expectation(description: "")
        let testObject = TestObject(in: .root, options: [.database: Cache.root])

        testObject.property <== "string"
        testObject.nestedObject.lazyProperty <== "nested_string"

        let element = TestObject(in: Node.root.child(with: "element_1"), options: [.database: Cache.root])
        element.property <== "element #1"
        element.nestedObject.lazyProperty <== "value"

        do {
            let elementTransaction = try element.update()
            let objectTransaction = try testObject.update()
            try elementTransaction.merge(objectTransaction)

            elementTransaction.commit { (_, err) in
                err?.forEach { XCTFail($0.describingErrorDescription) }
                let value = Cache.root.debugValue
                let expectedValue = ["prop":"string", "nestedObject/lazyprop":"nested_string",
                                     "element_1/prop":"element #1", "element_1/nestedObject/lazyprop":"value"] as [String: Any?]

                XCTAssertEqual((value as NSDictionary), (expectedValue as NSDictionary))
                exp.fulfill()
            }
        } catch let e {
            XCTFail(e.describingErrorDescription)
        }

        waitForExpectations(timeout: 5) { (err) in
            err.map({ XCTFail($0.describingErrorDescription) })
        }
    }

    func testCollectionOnRootObject() {
        let testObject = TestObject(in: .root)

        let transaction = Transaction()

        let linkedObject = TestObject(in: Node.root.child(with: "linked"))
        linkedObject.property <== "#1"
        testObject.linkedArray.view.isSynced = true
        XCTAssertNoThrow(try testObject.linkedArray.write(linkedObject, in: transaction))

        let object = TestObject(in: Node(key: "elem_1"))
        object.file <== "file".data(using: .utf8)
        object.property <== "prop"
        testObject.array.view.isSynced = true
        XCTAssertNoThrow(try testObject.array.write(element: object, in: transaction))

        let element = TestObject()
        element.file <== "file".data(using: .utf8)
        element.property <== "element #1"
        testObject.dictionary.view.isSynced = true
        XCTAssertNoThrow(try testObject.dictionary.write(element: element, for: linkedObject, in: transaction))

        XCTAssertTrue(transaction.updateNode.hasChild("linked_array/linked"))
        XCTAssertEqual(try transaction.updateNode.child(forPath: "array/elem_1/prop").decode(String.self), "prop")
        XCTAssertEqual(try transaction.updateNode.child(forPath: "dict/linked/prop").decode(String.self), "element #1")
        transaction.revert()
    }

    func testCollectionOnStandaloneObject() {
        let testObject = TestObject(in: Node(key: "test_obj"))
        testObject.file <== "file".data(using: .utf8)

        let linkedObject = TestObject(in: Node.root.child(with: "linked"))
        linkedObject.property <== "#1"
        testObject.linkedArray.insert(element: linkedObject)

        let object = TestObject(in: Node(key: "elem_1"))
        object.file <== "file".data(using: .utf8)
        object.property <== "prop"
        testObject.array.insert(element: object)

        let element = TestObject()
        element.file <== "file".data(using: .utf8)
        element.property <== "element #1"
        testObject.dictionary.set(element: element, for: linkedObject)

        do {
            let transaction = try testObject.save(in: .root)

            XCTAssertTrue(transaction.updateNode.hasChild("test_obj/linked_array/linked"))
            XCTAssertEqual(try transaction.updateNode.child(forPath: "test_obj/array/elem_1/prop").decode(String.self), "prop")
            XCTAssertEqual(try transaction.updateNode.child(forPath: "test_obj/dict/linked/prop").decode(String.self), "element #1")
            transaction.revert()
        } catch let e {
            XCTFail(e.localizedDescription)
        }
    }

    func testDecoding() {
        let transaction = Transaction()

        do {
            let element = TestObject(in: Node.root.child(with: "element_1"))
            element.property <== "element #1"
            element.nestedObject.lazyProperty <== "value"
            let child = TestObject()
            child.property <== "element #1"
            let fileData = "file".data(using: .utf8)
            child.file <== fileData
            element.array.view.isSynced = true
            try element.array.write(element: child, in: transaction)
            transaction.removeValue(by: element.readonlyProperty.node!)
            let rofileData = "readonlyFile".data(using: .utf8)!
            transaction.addFile(rofileData, by: element.readonlyFile.node!)
            element.file <== rofileData

            let data = try element.update(in: transaction).updateNode

            let object = try TestObject(data: data.child(forNode: element.node!), event: .child(.added))

            XCTAssertNotNil(object.file.unwrapped)
//            XCTAssertEqual(object.file.unwrapped.flatMap { UIImageJPEGRepresentation($0, 1.0) }, UIImageJPEGRepresentation(#imageLiteral(resourceName: "pw"), 1.0))
            XCTAssertNotNil(object.readonlyFile.unwrapped)
            XCTAssertEqual(object.readonlyFile.unwrapped, rofileData)
            XCTAssertEqual(object.readonlyProperty.wrapped, Int64())
            XCTAssertEqual(object.property.unwrapped, element.property.unwrapped)
            XCTAssertEqual(object.nestedObject.lazyProperty.unwrapped, element.nestedObject.lazyProperty.unwrapped)
        } catch let e {
            XCTFail(String(describing: e))
        }

        transaction.revert()
    }

    func testRemoveFile() {
        let exp = expectation(description: "")
        let file: File<Data?> = "file.txt".file(in: Object(in: .root), representer: Representer.realtimeDataValue)

        let writeTrans = Transaction(storage: Cache.root)
        do {
            try file.setValue("text".data(using: .utf8), in: writeTrans).commit { (_, errs) in
                errs?.forEach({ XCTFail($0.describingErrorDescription) })

                XCTAssertTrue(Cache.root.child(forNode: file.node!).exists())
                let deleteTrans = Transaction(storage: Cache.root)
                do {
                    try file.setValue(nil, in: deleteTrans).commit(with: { (state, errors) in
                        errors?.forEach({ XCTFail($0.describingErrorDescription) })

                        XCTAssertFalse(Cache.root.child(forNode: file.node!).exists())
                        exp.fulfill()
                    })
                } catch let e {
                    deleteTrans.cancel()
                    XCTFail(e.describingErrorDescription)
                }
            }
        } catch let e {
            writeTrans.cancel()
            XCTFail(e.describingErrorDescription)
        }

        waitForExpectations(timeout: 4) { (err) in
            err.map({ XCTFail($0.describingErrorDescription) })
        }
    }

    func testUpdateFileAfterSave() {
        let group = Group(in: Node(key: "group", parent: Global.rtGroups.node))
        let user = User(in: Node(key: "user"))
        group.manager <== user
        user.name <== "name"
        user.age <== 0
        user.photo <== "image".data(using: .utf8)
        user.groups.insert(element: group)
        user.ownedGroup <== group

        do {
            let cache = Transaction(database: Cache.root, storage: Cache.root)
            let transaction = try user.save(in: .root, in: cache)
            transaction.commit(with: { (_, errors) in
                errors.map { _ in XCTFail() }

                XCTAssertFalse(user.hasChanges)

                user.photo <== "image".data(using: .utf8)
                do {
                    let update = try user.update(in: Transaction(database: Cache.root, storage: Cache.root))
                    XCTAssertTrue(update.updateNode.debugValue.isEmpty)
                    update.commit(with: { _, errors in
                        errors.map { _ in XCTFail() }

                        XCTAssertFalse(user.hasChanges)
                        XCTAssertTrue(group.manager ==== user)
                    })
                } catch let e {
                    XCTFail(e.localizedDescription)
                }
            })
        } catch let e {
            XCTFail(e.localizedDescription)
        }
    }

    func testRelationOneToOne() {
        let transaction = Transaction()

        do {
            let user = User(in: Node(key: "user", parent: .root))
            let group = Group(in: Node(key: "group", parent: .root))
            user.ownedGroup <== group
            group.manager <== user

            try group.update(in: transaction)
            let data = try user.update(in: transaction).updateNode

            let userCopy = try User(data: data.child(forNode: user.node!), event: .child(.added))
            let groupCopy = try Group(data: data.child(forNode: group.node!), event: .child(.added))

            XCTAssertTrue(groupCopy.manager.unwrapped.dbKey == user.dbKey)
            XCTAssertTrue(user.ownedGroup.unwrapped?.dbKey == groupCopy.dbKey)
            XCTAssertTrue(userCopy.ownedGroup.unwrapped?.dbKey == groupCopy.dbKey)
        } catch let e {
            XCTFail(e.localizedDescription)
        }

        transaction.revert()
    }

    func testRelationOneToMany() {
        let exp = expectation(description: "")
        let transaction = Transaction(database: Cache.root)

        do {
            let user = User(in: Node(key: "user", parent: .root))
            let group = Group(in: Node(key: "group", parent: .root))

            group._manager <== user
            try user.ownedGroups.write(group, in: transaction)

            try group.update(in: transaction)
            transaction.commit(with: { (state, errors) in
                errors?.forEach({ XCTFail($0.describingErrorDescription) })

                do {
                    let groupCopy = try Group(data: Cache.root.child(forNode: group.node!), event: .child(.added))
                    let userCopy = try User(data: Cache.root.child(forNode: user.node!), event: .child(.added))

                    XCTAssertTrue(userCopy.ownedGroups.first?.dbKey == group.dbKey)
                    XCTAssertTrue(group._manager.wrapped?.dbKey == userCopy.dbKey)
                    XCTAssertTrue(groupCopy._manager.wrapped?.dbKey == userCopy.dbKey)

                    let remove = Transaction(database: Cache.root)
                    try groupCopy._manager.setValue(nil, in: remove)
                    userCopy.ownedGroups.remove(element: groupCopy, in: remove)
                    remove.commit(with: { (state, errors) in
                        errors?.forEach({ XCTFail($0.describingErrorDescription) })

                        do {
                            try groupCopy._manager.apply(Cache.root.child(forNode: groupCopy._manager.node!), event: .value)
                            try userCopy.ownedGroups.apply(Cache.root.child(forNode: userCopy.ownedGroups.node!), event: .value)

                            XCTAssertNil(groupCopy._manager.unwrapped)
                            XCTAssertEqual(userCopy.ownedGroups.count, 0)
                            exp.fulfill()
                        } catch let e {
                            XCTFail(e.describingErrorDescription)
                        }
                    })
                } catch let e {
                    XCTFail(e.describingErrorDescription)
                }
            })
        } catch let e {
            transaction.cancel()
            XCTFail(e.describingErrorDescription)
        }

        waitForExpectations(timeout: 3) { (err) in
            err.map({ XCTFail($0.describingErrorDescription) })
        }
    }

    func testRelationManyToOne() {
        let exp = expectation(description: "")
        let transaction = Transaction(database: Cache.root)

        do {
            let user = User(in: Node(key: "user", parent: .root), options: [.database: Cache.root])
            let group = Group(in: Node(key: "group", parent: .root), options: [.database: Cache.root])

            group._manager <== user
            try user.ownedGroups.write(group, in: transaction)

            try group.update(in: transaction)
            transaction.commit(with: { (_, errors) in
                errors?.first.map({ XCTFail($0.describingErrorDescription) })

                do {
                    let userCopy = try User(data: Cache.root.child(forNode: user.node!), event: .child(.added))
                    let groupCopy = try Group(data: Cache.root.child(forNode: group.node!), event: .child(.added))

                    XCTAssertTrue(groupCopy._manager.unwrapped?.dbKey == userCopy.dbKey)
                    XCTAssertTrue(userCopy.ownedGroups.first?.dbKey == groupCopy.dbKey)

                    // removing must also remove related value
                    let remove = Transaction(database: Cache.root)
                    userCopy.ownedGroups.remove(element: groupCopy, in: remove)
                    try groupCopy._manager.setValue(nil, in: remove)
                    remove.commit(with: { (state, errors) in
                        errors?.forEach({ XCTFail($0.describingErrorDescription) })

                        do {
                            try groupCopy._manager.apply(Cache.root.child(forNode: groupCopy._manager.node!), event: .value)
                            try userCopy.ownedGroups.apply(Cache.root.child(forNode: userCopy.ownedGroups.node!), event: .value)

                            XCTAssertNil(groupCopy._manager.unwrapped)
                            XCTAssertEqual(userCopy.ownedGroups.count, 0)
                            exp.fulfill()
                        } catch let e {
                            XCTFail(e.describingErrorDescription)
                        }
                    })
                } catch let e {
                    XCTFail(e.describingErrorDescription)
                }
            })
        } catch let e {
            transaction.cancel()
            XCTFail(e.localizedDescription)
        }

        waitForExpectations(timeout: 5) { (err) in
            err.map({ XCTFail($0.describingErrorDescription) })
        }
    }

    func testOptionalRelation() {
        let transaction = Transaction()

        do {
            let user = User(in: Node(key: "user", parent: .root))
            user.ownedGroup <== nil

            let data = try user.update(in: transaction).updateNode

            let userCopy = try User(data: data.child(forNode: user.node!), event: .child(.added))

            if case .error(let e, _) = userCopy.ownedGroup.state {
                XCTFail(e.localizedDescription)
            } else {
                XCTAssertTrue(userCopy.ownedGroup.unwrapped?.dbKey == userCopy.ownedGroup.unwrapped?.dbKey)
            }
        } catch let e {
            XCTFail(e.localizedDescription)
        }

        transaction.revert()
    }

    func testRelationPayload() {
        let exp = expectation(description: "")
        let payload = RealtimeDatabaseValue([RealtimeDatabaseValue(("key", "value"))])
        let obj = Object(in: Node.root("obj"), options: [.database: Cache.root, .rawValue: RealtimeDatabaseValue(2), .payload: payload])
        let relation: Relation<Object> = "relation".relation(in: Object(in: .root), .one(name: "obj"))
        relation <== obj

        let transaction = Transaction(database: Cache.root)
        do {
            try transaction.set(relation, by: relation.node!)
            transaction.commit { (_, errors) in
                _ = errors?.map({ XCTFail($0.describingErrorDescription) })

                let copyRelation: Relation<Object> = "relation".relation(in: Object(in: .root), .one(name: "obj"))
                do {
                    try copyRelation.apply(Cache.root.child(by: copyRelation.node!)!.asUpdateNode(), event: .value)

                    XCTAssertEqual(copyRelation.wrapped, relation.wrapped)
                    XCTAssertEqual(copyRelation.wrapped.raw?.debug as? Int, relation.wrapped.raw?.debug as? Int)
                    XCTAssertEqual(copyRelation.wrapped.payload, relation.wrapped.payload)
                    exp.fulfill()
                } catch let e {
                    XCTFail(e.describingErrorDescription)
                }
            }
        } catch let e {
            XCTFail(e.describingErrorDescription)
        }

        waitForExpectations(timeout: 4) { (err) in
            err.map({ XCTFail($0.describingErrorDescription) })
        }
    }

    func testOptionalReference() {
        let transaction = Transaction()

        do {
            let conversation = Conversation(in: Node(key: "conv_1", parent: .root))
            conversation.secretary <== nil

            let data = try conversation.update(in: transaction).updateNode

            let conversationCopy = try Conversation(data: data.child(forNode: conversation.node!), event: .child(.added))

            if case .error(let e, _) = conversation.chairman.state {
                XCTFail(e.localizedDescription)
            } else {
                XCTAssertTrue(conversationCopy.secretary.unwrapped?.dbKey == conversation.secretary.unwrapped?.dbKey)
            }
        } catch let e {
            XCTFail(e.localizedDescription)
        }

        transaction.revert()
    }

    func testWriteRequiredPropertyFailsOnSave() {
        let property = Property<String?>.writeRequired(in: Node(key: "prop"), representer: .realtimeDataValue)

        do {
            let transaction = Transaction()
            defer { transaction.revert() }
            _ = try transaction.set(property, by: .root)
            XCTFail("Must throw error")
        } catch let e {
            switch e {
            case let error as RealtimeError:
                switch error.source {
                case .coding: break
                default: XCTFail("Unexpected error")
                }
            default: XCTFail("Unexpected error")
            }
        }
    }

    func testWriteRequiredPropertySuccessOnDecode() {
        let _: String! = ""
        let property = Property<String?>.writeRequired(in: Node(key: "prop"), representer: .realtimeDataValue)

        do {
            let data = ValueNode(node: Node(key: "prop"), value: nil)
            try property.apply(data, event: .value)
        } catch let e {
            XCTFail(e.localizedDescription)
        }
    }

    func testRepresenterOptional() {
        let representer = Representer<TestObject>.relation(.one(name: "prop"), rootLevelsUp: nil, ownerNode: .unsafe(strong: nil)).optional()
        do {
            let object = try representer.decode(ValueNode(node: Node(key: ""), value: nil))
            XCTAssertNil(object)
        } catch let e {
            XCTFail(e.localizedDescription)
        }
    }

    func testReferenceRepresentationPayload() {
        let userPayload = RealtimeDatabaseValue([RealtimeDatabaseValue(("foo", "bar"))])
        let value = ValueWithPayload.two(TestObject(in: Node(key: "path/subpath", parent: .root), options: [.payload: userPayload]))
        let representer = Representer<ValueWithPayload>.reference(.fullPath)

        do {
            let result = try representer.encode(value)

            var builder = RealtimeDatabaseValue.Dictionary()
            builder.setValue("path/subpath", forKey: InternalKeys.source.rawValue)
            builder.setValue(RealtimeDatabaseValue([
                RealtimeDatabaseValue((RealtimeDatabaseValue(InternalKeys.raw.rawValue), value.raw!)),
                RealtimeDatabaseValue((RealtimeDatabaseValue(InternalKeys.payload.rawValue), userPayload))
                ]), forKey: InternalKeys.value.rawValue)
            XCTAssertEqual(result, builder.build())
        } catch let e {
            XCTFail(e.localizedDescription)
        }
    }

    func testNode() {
        let first = Node(key: "first", parent: .root)

        let second = Node(key: "second", parent: first)
        XCTAssertEqual(second.absolutePath, "first/second")
        XCTAssertEqual(second.path(from: first), "second")
        XCTAssertTrue(second.hasAncestor(node: first))
        XCTAssertTrue(second.isRooted)

        let third = second.child(with: "third")
        XCTAssertEqual(third.absolutePath, "first/second/third")
        XCTAssertEqual(third.path(from: first), "second/third")
        XCTAssertTrue(third.hasAncestor(node: first))
        XCTAssertTrue(third.isRooted)

        let fourth = third.child(with: "fourth")
        XCTAssertEqual(fourth.absolutePath, "first/second/third/fourth")
        XCTAssertEqual(fourth.path(from: first), "second/third/fourth")
        XCTAssertTrue(fourth.hasAncestor(node: first))
        XCTAssertTrue(fourth.isRooted)
    }

    func testLinksNode() {
        let fourth = Node.root.child(with: "first/second/third/fourth")
        let linksNode = fourth.linksNode
        XCTAssertEqual(linksNode.absolutePath, RealtimeApp.app.configuration.linksNode.child(with: "first/second/third/fourth").absolutePath)
    }

    func testConnectNode() {
        let testObject = TestObject(in: Node())

        XCTAssertTrue(testObject.isStandalone)
        XCTAssertTrue(testObject.property.isStandalone)
        XCTAssertTrue(testObject.linkedArray.isStandalone)
        XCTAssertTrue(testObject.array.isStandalone)
        XCTAssertTrue(testObject.dictionary.isStandalone)

        let node = Node(key: "testObjects", parent: .root)
        testObject.didSave(in: Cache.root, in: node)

        XCTAssertTrue(testObject.isRooted)
        XCTAssertTrue(testObject.property.isRooted)
        XCTAssertTrue(testObject.linkedArray.isRooted)
        XCTAssertTrue(testObject.array.isRooted)
        XCTAssertTrue(testObject.dictionary.isRooted)
    }

    func testDisconnectNode() {
        let node = Node(key: "testObjects", parent: .root).childByAutoId()
        let testObject = TestObject(in: node)

        XCTAssertTrue(testObject.isRooted)
        XCTAssertTrue(testObject.property.isRooted)
        XCTAssertTrue(testObject.linkedArray.isRooted)
        XCTAssertTrue(testObject.array.isRooted)
        XCTAssertTrue(testObject.dictionary.isRooted)

        testObject.didRemove()

        XCTAssertTrue(testObject.isStandalone)
        XCTAssertTrue(testObject.property.isStandalone)
        XCTAssertTrue(testObject.linkedArray.isStandalone)
        XCTAssertTrue(testObject.array.isStandalone)
        XCTAssertTrue(testObject.dictionary.isStandalone)
    }

    enum ValueWithPayload: WritableRealtimeValue, RealtimeDataRepresented, RealtimeValueActions {
        var raw: RealtimeDatabaseValue? {
            switch self {
            case .two: return RealtimeDatabaseValue(UInt8(1))
            default: return nil
            }
        }
        var node: Node? { return value.node }
        var payload: RealtimeDatabaseValue? { return value.payload }
        var canObserve: Bool { return value.canObserve }
        var keepSynced: Bool {
            get { return value.keepSynced }
            set { value.keepSynced = newValue }
        }

        var value: TestObject {
            switch self {
            case .one(let v): return v
            case .two(let v): return v
            }
        }

        case one(TestObject)
        case two(TestObject)

        init(in node: Node?, options: [ValueOption : Any]) {
            let raw = try? options.rawValue?.typed(as: UInt8.self) ?? 0

            switch raw {
            case 1: self = .two(TestObject(in: node, options: options))
            default: self = .one(TestObject(in: node, options: options))
            }
        }

        init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
            let raw: CShort = try data.rawValue()?.typed(as: CShort.self) ?? 0

            switch raw {
            case 1: self = .two(try TestObject(data: data, event: event))
            default: self = .one(try TestObject(data: data, event: event))
            }
        }

        mutating func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
            try value.apply(data, event: event)
            let r = try data.rawValue()?.typed(as: Int.self) ?? 0
            if raw?.debug as? Int != r {
                switch r {
                case 1: self = .two(value)
                default: self = .one(value)
                }
            }
        }

        func load(timeout: DispatchTimeInterval) -> RealtimeTask {
            return value.load(timeout: timeout)
        }

        func runObserving() -> Bool {
            return value.runObserving()
        }

        func stopObserving() {
            value.stopObserving()
        }

        func willSave(in transaction: Transaction, in parent: Node, by key: String) {
            value.willSave(in: transaction, in: parent, by: key)
        }

        func didSave(in database: RealtimeDatabase, in parent: Node, by key: String) {
            value.didSave(in: database, in: parent, by: key)
        }

        func willUpdate(through ancestor: Node, in transaction: Transaction) {
            value.willUpdate(through: ancestor, in: transaction)
        }

        func didUpdate(through ancestor: Node) {
            value.didUpdate(through: ancestor)
        }

        func didRemove(from ancestor: Node) {
            value.didRemove(from: ancestor)
        }

        func willRemove(in transaction: Transaction, from ancestor: Node) {
            value.willRemove(in: transaction, from: ancestor)
        }

        func write(to transaction: Transaction, by node: Node) throws {
            try value.write(to: transaction, by: node)
        }
    }

    func testPayload() {
        let array = Values<ValueWithPayload>(in: Node.root.child(with: "__tests/array"))
        let transaction = Transaction()

        do {
            let one = TestObject()
            one.file <== "file".data(using: .utf8)
            try array.write(element: .one(one), in: transaction)
            let two = TestObject()
            two.file <== "file".data(using: .utf8)
            try array.write(element: .two(two), in: transaction)
        } catch let e {
            XCTFail(e.localizedDescription)
        }

        transaction.revert()
    }

    func testInitializeWithPayload() {
        var payloadBuilder = RealtimeDatabaseValue.Dictionary()
        payloadBuilder.setValue("val", forKey: "key")
        let payload = payloadBuilder.build()
        let value = TestObject(in: .root, options: [.payload: payload])
        XCTAssertEqual(value.payload, payload)
    }

    func testInitializeWithPayload3() {
        var payloadBuilder = RealtimeDatabaseValue.Dictionary()
        payloadBuilder.setValue("val", forKey: "key")
        let payload: Any = payloadBuilder.build()
        let value = TestObject(in: .root, options: [.payload: payload])
        XCTAssertEqual(value.payload, payload as? RealtimeDatabaseValue)
    }

    func testInitializeWithPayload4() {
        let exp = expectation(description: "")
        let rawValue = RealtimeDatabaseValue(5)
        let user = User2(in: nil, options: [.database: Cache.root, .rawValue: rawValue])
        XCTAssertEqual(user.raw, rawValue)

        user.name <== "User name"
        user.age <== 50
        user.human <== ""
        do {
            let transaction = try user.save(by: .root)
            transaction.commit { (_, errs) in
                errs?.first.map({ XCTFail($0.describingErrorDescription) })

                do {
                    let copyUser = try User2(data: Cache.root, event: .value)
                    XCTAssertEqual(copyUser.raw, rawValue)
                } catch let e {
                    XCTFail(e.describingErrorDescription)
                }
                exp.fulfill()
            }
        } catch let e {
            XCTFail(e.describingErrorDescription)
        }

        waitForExpectations(timeout: 5) { (err) in
            err.map({ XCTFail($0.describingErrorDescription) })
        }
    }

    func testReferenceFireValue() {
        let ref = ReferenceRepresentation(ref: Node.root.child(with: "first/two").absolutePath, payload: (nil, nil))
        let fireValue = try? ref.defaultRepresentation()
        XCTAssertEqual((fireValue?.debug as? [(String, String)])?.reduce(into: [:], { $0[$1.0] = $1.1 }), [InternalKeys.source.rawValue: "first/two"])
    }

    func testLocalDatabase() {
        let transaction = Transaction(database: Cache.root)
        let testObject = TestObject(in: .root)

        testObject.property <== "string"
        testObject.nestedObject.lazyProperty <== "nested_string"

        XCTAssertTrue(testObject.hasChanges)
        do {
            try testObject.update(in: transaction)

            transaction.commit(with: { (state, errs) in
                if let e = errs?.first {
                    XCTFail(e.localizedDescription)
                } else {
                    do {
                        let restoredObj = try TestObject(data: Cache.root, event: .child(.added))

                        XCTAssertEqual(testObject.property, restoredObj.property)
                        XCTAssertEqual(testObject.nestedObject.lazyProperty,
                                       restoredObj.nestedObject.lazyProperty)
                    } catch let e {
                        XCTFail(e.localizedDescription)
                    }
                }
            })
        } catch let e {
            XCTFail(e.localizedDescription)
        }
    }

    func testCacheObject() {
        let cache = Cache(node: .root)
        let transaction = Transaction(database: cache, storage: cache)
        let testObject = TestObject(in: .root)

        testObject.property <== "string"
        testObject.nestedObject.lazyProperty <== "nested_string"
        testObject.file <== "file".data(using: .utf8)

        do {
            try testObject.update(in: transaction)

            let textData = "text".data(using: .utf8)!
            transaction.addFile(textData, by: testObject.readonlyFile.node!)

            transaction.commit(with: { (state, errs) in
                if let e = errs?.first {
                    XCTFail(e.localizedDescription)
                } else {
                    XCTAssertTrue(cache.hasChildren(), "FAIL CACHE")
                    let restoredObj = TestObject(in: testObject.node, options: [.database: cache])
                    _ = restoredObj.load().completion.listening(.just { e in
                        e.error.map { XCTFail($0.localizedDescription) }

                        XCTAssertEqual(testObject.property, restoredObj.property, "FAIL \(Cache.root)")
                        XCTAssertEqual(testObject.nestedObject.lazyProperty,
                                       restoredObj.nestedObject.lazyProperty, "FAIL \(Cache.root)")
                        })
                }
            })
        } catch let e {
            XCTFail(e.localizedDescription)
        }
    }
}

// MARK: Node

extension RealtimeTests {
    func testGetAncestorOnLevelUp() {
        let node = Node.root("collection/id/otherColl/id");
        XCTAssertEqual(Node.root("collection/id"), node.ancestor(onLevelUp: 2))
    }
}

// MARK: RealtimeDatabaseValue

extension RealtimeTests {
    func testRealtimeDatabaseValue() {
        let dbValue = RealtimeDatabaseValue(true)
        XCTAssertEqual(try? dbValue.typed(as: Bool.self), true)
    }
    func testRealtimeDatabaseValueExtractBool() {
        let value = true
        let dbValue = RealtimeDatabaseValue(value)
        do {
            let extracted: Bool? = try dbValue.extract(
                bool: { $0 },
                int8: { _ in nil },
                int16: { _ in nil },
                int32: { _ in nil },
                int64: { _ in nil },
                uint8: { _ in nil },
                uint16: { _ in nil },
                uint32: { _ in nil },
                uint64: { _ in nil },
                double: { _ in nil },
                float: { _ in nil },
                string: { _ in nil },
                data: { _ in nil },
                pair: { (_, _) in nil },
                collection: { _ in nil }
            )

            XCTAssertEqual(extracted, value)
        } catch let e {
            XCTFail(e.localizedDescription)
        }
    }
    func testRealtimeDatabaseValueExtractData() {
        let value = "Some text that converted to data".data(using: .utf8)!
        let dbValue = RealtimeDatabaseValue(value)
        do {
            let extracted: Data? = try dbValue.extract(
                bool: { _ in nil },
                int8: { _ in nil },
                int16: { _ in nil },
                int32: { _ in nil },
                int64: { _ in nil },
                uint8: { _ in nil },
                uint16: { _ in nil },
                uint32: { _ in nil },
                uint64: { _ in nil },
                double: { _ in nil },
                float: { _ in nil },
                string: { _ in nil },
                data: { $0 },
                pair: { (_, _) in nil },
                collection: { _ in nil }
            )

            XCTAssertEqual(extracted, value)
        } catch let e {
            XCTFail(e.localizedDescription)
        }
    }
}

// MARK: Collections

extension References: Reverting {
    public func revert() {
        guard _hasChanges else { return }
        storage.removeAll()
        view.removeAll()
    }

    public func currentReversion() -> () -> Void {
        return { [weak self] in
            self?.revert()
        }
    }
}
extension Values: Reverting {
    public func revert() {
        guard _hasChanges else { return }
        storage.removeAll()
        view.removeAll()
    }

    public func currentReversion() -> () -> Void {
        return { [weak self] in
            self?.revert()
        }
    }
}
extension AssociatedValues: Reverting {
    public func revert() {
        guard _hasChanges else { return }
        storage.removeAll()
        view.removeAll()
    }

    public func currentReversion() -> () -> Void {
        return { [weak self] in
            self?.revert()
        }
    }
}

extension RealtimeTests {
    func testLocalChangesLinkedArray() {
        let linkedArray: MutableReferences<TestObject> = MutableReferences(
            in: Node(key: "l_array"),
            options: .init(baseOptions: RealtimeValueOptions(database: Cache.root), elementsNode: .root, builder: TestObject.init)
        )

        linkedArray.insert(element: TestObject(in: Node.root.childByAutoId()))
        linkedArray.insert(element: TestObject(in: Node.root.childByAutoId()))

        var counter = 0
        linkedArray.forEach { (obj) in
            counter += 1
        }

        XCTAssertEqual(linkedArray.count, 2)
        XCTAssertEqual(counter, 2)

        let transaction = Transaction()
        do {
            try transaction.set(linkedArray, by: .root)
            XCTAssertEqual(linkedArray.storage.count, 2)
            /// after write to transaction array switches to remote
            XCTAssertEqual(linkedArray.count, 0)
        } catch let e {
            XCTFail(e.localizedDescription)
        }
        transaction.revert()
    }
    func testLocalChangesArray() {
        let array: Values<TestObject> = Values(in: Node(key: "array"))

        let one = TestObject()
        one.file <== "file".data(using: .utf8)
        array.insert(element: one)
        let two = TestObject()
        two.file <== "file".data(using: .utf8)
        array.insert(element: two)

        var counter = 0
        array.forEach { (obj) in
            counter += 1
        }

        XCTAssertEqual(array.count, 2)
        XCTAssertEqual(counter, 2)

        let transaction = Transaction()
        do {
            try transaction._update(array, by: .root)
            XCTAssertEqual(array.storage.count, 2)
            /// after write to transaction array switches to remote
            XCTAssertEqual(array.count, 0)
        } catch let e {
            XCTFail(e.localizedDescription)
        }
        transaction.revert()
    }
    func testLocalChangesDictionary() {
        let dict: AssociatedValues<TestObject, TestObject> = AssociatedValues(in: Node(key: "dict"),
                                                                              options: [.keysNode: Node.root])

        let one = TestObject()
        one.file <== "file".data(using: .utf8)
        dict.set(element: one, for: TestObject(in: Node.root.childByAutoId()))
        let two = TestObject()
        two.file <== "file".data(using: .utf8)
        dict.set(element: two, for: TestObject(in: Node.root.childByAutoId()))

        var counter = 0
        dict.forEach { (obj) in
            counter += 1
        }

        XCTAssertEqual(dict.count, 2)
        XCTAssertEqual(counter, 2)

        let transaction = Transaction()
        do {
            try transaction._update(dict, by: .root)
            XCTAssertEqual(dict.storage.count, 2)
            /// after write to transaction array switches to remote
            XCTAssertEqual(dict.count, 0)
        } catch let e {
            XCTFail(e.localizedDescription)
        }
        transaction.revert()
    }

    func testListeningCollectionChangesOnInsert() {
        let exp = expectation(description: "")
        let array = Values<User>(in: .root, options: [.database: Cache.root])

        array.runObserving()
        array.changes.listening(onValue: { (event) in
            switch event {
            case .initial:
                XCTFail(".initial does not should call")
            case .updated(_, let inserted, _, _):
                XCTAssertEqual(inserted.count, 1)
                exp.fulfill()
            }
        }).add(to: store)
        array.changes.listening { err in
            XCTFail(err.localizedDescription)
            }.add(to: store)

        let element = User()
        element.name <== "User"
        element.age <== 100
        element.photo <== "photo".data(using: .utf8)

        do {
            let transaction = Transaction(database: Cache.root)
            try array.write(element: element, in: transaction)

            /// simulate notification
            transaction.commit { (state, errors) in
                errors.map { e in XCTFail(e.reduce("") { $0 + $1.describingErrorDescription }) }
            }
        } catch let e {
            XCTFail(e.describingErrorDescription)
        }

        waitForExpectations(timeout: 10) { (error) in
            error.map { XCTFail($0.describingErrorDescription) }
        }
    }

    func testReadonlyRelation() {
        let exp = expectation(description: "")
        let user = User(in: Node(key: "user", parent: .root), options: [.database: Cache.root])
        let group = Group(in: Node(key: "group", parent: .root), options: [.database: Cache.root])
        user.ownedGroup <== group

        do {
            let transaction = try user.update()
            transaction.commit { (state, errors) in
                errors.map { XCTFail($0.description) }

                let ownedGroup = Relation<Group?>.readonly(in: user.ownedGroup.node, config: user.ownedGroup.options)
                do {
                    try ownedGroup.apply(Cache.root.child(forNode: user.ownedGroup.node!), event: .value)
                    XCTAssertEqual(ownedGroup.wrapped, user.ownedGroup.wrapped)
                    exp.fulfill()
                } catch let e {
                    XCTFail(e.localizedDescription)
                }
            }
        } catch let e {
            XCTFail(e.localizedDescription)
        }

        waitForExpectations(timeout: 4.0) { (error) in
            error.map { XCTFail($0.localizedDescription) }
        }
    }

    func testReadonlyReference() {
        Cache.root.clear()
        let exp = expectation(description: "")
        let user = User(in: Node(key: "user", parent: .root), options: [.database: Cache.root])
        let conversation = Conversation(in: Node(key: "conversation", parent: .root), options: [.database: Cache.root])
        conversation.chairman <== user

        do {
            let transaction = try conversation.update()
            transaction.commit { (state, errors) in
                errors.map { XCTFail($0.description) }

                let chairman = Reference<User>.readonly(
                    in: conversation.chairman.node,
                    mode: Reference<User>.Mode.required(.fullPath, db: Cache.root)
                )
                do {
                    try chairman.apply(Cache.root.child(forNode: conversation.chairman.node!), event: .value)
                    XCTAssertEqual(chairman.wrapped, conversation.chairman.wrapped)
                    exp.fulfill()
                } catch let e {
                    XCTFail(e.localizedDescription)
                }
            }
        } catch let e {
            XCTFail(e.localizedDescription)
        }

        waitForExpectations(timeout: 4.0) { (error) in
            error.map { XCTFail($0.localizedDescription) }
        }
    }

    func testDatabaseBinding() {
        let testObject = TestObject(in: .root, options: [.database: Cache.root])
        testObject.forceEnumerateAllChilds { (_, value: _RealtimeValue) in
            if value.database === Cache.root {
                XCTAssertTrue(true)
            } else {
                XCTFail("value: \(value), database: \(value.database as Any)")
            }
        }
    }

    func testAssociatedValuesWithVersionAndRawValues() {
        let exp = expectation(description: "")
        let assocValues = AssociatedValues<TestObject, TestObject>(in: Node.root("values"), options: [.database: Cache.root, .keysNode: Node.root("keys")])
        let keyRaw = RealtimeDatabaseValue(2)
        let key = TestObject(in: Node.root("keys").child(with: "key"), options: [.database: Cache.root, .rawValue: keyRaw])
        let valueRaw = RealtimeDatabaseValue(5)
        let value = TestObject(in: nil, options: [.database: Cache.root, .rawValue: valueRaw])
        do {
            let trans = Transaction(database: Cache.root)
            try assocValues.write(element: value, for: key, in: trans)
            trans.commit { (_, errors) in
                _ = errors?.compactMap({ XCTFail($0.describingErrorDescription) })

                /// we can use Values for readonly access to values, AssociatedValues and Values must be compatible
                let copyAssocitedValues = AssociatedValues<Object, Object>(
                    in: Node.root("values"),
                    options: [.keysNode: Node.root("keys"), .database: Cache.root]
                )
                let copyValues = copyAssocitedValues.values()
                /// we can use References for readonly access to keys
                let copyKeys = copyAssocitedValues.keys()
                _ = copyValues.view.load().completion.listening(.just({ (v_err) in
                    v_err.error.map { XCTFail($0.describingErrorDescription) }
                    _ = copyKeys.view.load().completion.listening(.just({ k_err in
                        k_err.error.map { XCTFail($0.describingErrorDescription) }
                        _ = copyAssocitedValues.view.load().completion.listening(.just({ av_err in
                            av_err.error.map { XCTFail($0.describingErrorDescription) }

                            if let copyValue = copyValues.first, let copyAValue = copyAssocitedValues.first, let copyKey = copyKeys.first {
                                XCTAssertEqual(copyAValue.key, key)
                                XCTAssertEqual(copyAValue.key.raw, keyRaw)
                                XCTAssertEqual(copyValue, value)
                                XCTAssertEqual(copyValue.raw, valueRaw)
                                XCTAssertEqual(copyKey, key)
                                XCTAssertEqual(copyKey.raw, keyRaw)
                            } else {
                                XCTFail("No element")
                            }
                            exp.fulfill()
                        }))
                    }))
                }))
            }
        } catch let e {
            XCTFail(e.describingErrorDescription)
        }

        waitForExpectations(timeout: 2) { (e) in
            e.map({ XCTFail($0.describingErrorDescription) })
        }
    }

    func testTimoutOnLoad() {
        func isNetworkReachable(with flags: SCNetworkReachabilityFlags) -> Bool {
            let isReachable = flags.contains(.reachable)
            let needsConnection = flags.contains(.connectionRequired)
            let canConnectAutomatically = flags.contains(.connectionOnDemand) || flags.contains(.connectionOnTraffic)
            let canConnectWithoutUserInteraction = canConnectAutomatically && !flags.contains(.interventionRequired)

            return isReachable && (!needsConnection || canConnectWithoutUserInteraction)
        }
        guard let reachability = SCNetworkReachabilityCreateWithName(nil, "www.google.com") else { return }

        var flags = SCNetworkReachabilityFlags()
        SCNetworkReachabilityGetFlags(reachability, &flags)

        if isNetworkReachable(with: flags) {
            print("Error: Test available only without internet connection")
            return
        }

        let exp = expectation(description: "")
        let prop = ReadonlyProperty<String>(
            in: Node.root("___tests/prop"),
            options: ReadonlyProperty<String>.PropertyOptions(RealtimeValueOptions(), availability: Availability.required(Representer<String>.realtimeDataValue), initial: nil)
        )

        _ = prop.load(timeout: .seconds(3)).completion.listening(.just { err in
            guard let e = err.error else { return XCTFail("Must be timout error") }
            switch e {
            case let re as RealtimeError:
                if case .database = re.source {
                    exp.fulfill()
                } else {
                    XCTFail("Unexpected error")
                }
            default:
                XCTFail("Unexpected error")
            }
            })

        waitForExpectations(timeout: 10) { (e) in
            e.map { XCTFail($0.describingErrorDescription) }
        }
    }
}

// MARK: Operators

extension RealtimeTests {
    func testEqualFailsRequiredPropertyWithoutValueAndValue() {
        let property = Property<String>.required(in: .root, representer: .realtimeDataValue)
        XCTAssertFalse(property ==== "")
        XCTAssertFalse("" ==== property)
    }
    func testNotEqualRequiredPropertyWithoutValueAndValue() {
        let property = Property<String>.required(in: .root, representer: .realtimeDataValue)
        XCTAssertTrue(property !=== "")
        XCTAssertTrue("" !=== property)
    }
    func testEqualRequiredPropertyWithoutValueAndNil() {
        let property = Property<String>.required(in: .root, representer: .realtimeDataValue)
        XCTAssertTrue(property ==== nil)
        XCTAssertTrue(nil ==== property)
    }
    func testEqualFailsRequiredPropertyWithValueAndValue() {
        let property = Property<String>.required(in: .root, representer: .realtimeDataValue)
        property <== "string"
        XCTAssertFalse(property ==== "")
        XCTAssertFalse("" ==== property)
    }
    func testNotEqualRequiredPropertyWithValueAndValue() {
        let property = Property<String>.required(in: .root, representer: .realtimeDataValue)
        property <== "string"
        XCTAssertTrue(property !=== "")
        XCTAssertTrue("" !=== property)
    }
    func testNotEqualRequiredPropertyWithValueAndNil() {
        let property = Property<String>.required(in: .root, representer: .realtimeDataValue)
        property <== "string"
        XCTAssertFalse(property ==== nil)
        XCTAssertFalse(nil ==== property)
    }
    func testEqualFailsOptionalPropertyWithoutValueAndValue() {
        let property = Property<String?>.optional(in: .root, representer: .realtimeDataValue)
        XCTAssertFalse(property ==== "")
        XCTAssertFalse("" ==== property)
    }
    func testNotEqualOptionalPropertyWithoutValueAndValue() {
        let property = Property<String?>.optional(in: .root, representer: .realtimeDataValue)
        XCTAssertTrue(property !=== "")
        XCTAssertTrue("" !=== property)
    }
    func testEqualOptionalPropertyWithNilValueAndNil() {
        let property = Property<String?>.optional(in: .root, representer: .realtimeDataValue)
        property <== nil
        XCTAssertTrue(property ==== nil)
        XCTAssertTrue(nil ==== property)
    }
    func testEqualFailsOptionalPropertyWithValueAndValue() {
        let property = Property<String?>.optional(in: .root, representer: .realtimeDataValue)
        property <== "string"
        XCTAssertFalse(property ==== "")
        XCTAssertFalse("" ==== property)
    }
    func testNotEqualOptionalPropertyWithValueAndValue() {
        let property = Property<String?>.optional(in: .root, representer: .realtimeDataValue)
        property <== "string"
        XCTAssertTrue(property !=== "")
        XCTAssertTrue("" !=== property)
    }
    func testNotEqualOptionalPropertyWithValueAndNil() {
        let property = Property<String?>.optional(in: .root, representer: .realtimeDataValue)
        property <== "string"
        XCTAssertFalse(property ==== nil)
        XCTAssertFalse(nil ==== property)
    }
}

// MARK: Migration

@available(*, deprecated)
class VersionableObject: Object {
    // removed
    @available(*, deprecated)
    lazy var nullVersionVariable: ReadonlyProperty<String?> = "nullVersionVariable".readonlyProperty(in: self, representer: Representer.realtimeDataValue)

    // added
    lazy var firstMinorVersionVariable: Property<String?> = Property.writeRequired(
        in: Node(key: "firstMinorVersionVariable", parent: self.node),
        representer: Representer<String>.realtimeDataValue,
        options: [.database: self.database as Any]
    )

    // renamed
    @available(*, deprecated)
    lazy var renamedFromVariable: ReadonlyProperty<String?> = "renamedFromVariable".readonlyProperty(in: self, representer: Representer.realtimeDataValue)
    lazy var renamedToVariable: Property<String?> = Property.writeRequired(
        in: Node(key: "renamedToVariable", parent: self.node),
        representer: Representer<String>.realtimeDataValue,
        options: [.database: self.database as Any]
    )

    override var ignoredLabels: [String] {
        return ["_calledMigration"]
    }

    override class func lazyPropertyKeyPath(for label: String) -> AnyKeyPath? {
        switch label {
        case "nullVersionVariable": return \VersionableObject.nullVersionVariable
        case "firstMinorVersionVariable": return \VersionableObject.firstMinorVersionVariable
        case "renamedFromVariable": return \VersionableObject.renamedFromVariable
        case "renamedToVariable": return \VersionableObject.renamedToVariable
        default: return nil
        }
    }

    override func conditionForWrite(of property: _RealtimeValue) -> Bool {
        //        if property === nullVersionVariable {
        //            return false
        //        }
        return super.conditionForWrite(of: property)
    }

    static var modelVersion: Version { return Version(1, 0) }
    override func putVersion(into versioner: inout Versioner) {
        super.putVersion(into: &versioner)
        versioner.enqueue(VersionableObject.modelVersion)
    }

    var _calledMigration = false

    override func performMigration(from oldVersion: inout Versioner, to newVersion: inout Versioner, in transaction: Transaction) throws {
        try super.performMigration(from: &oldVersion, to: &newVersion, in: transaction)
        let old = (try? oldVersion.dequeue()) ?? Version(0, 0)
        let new = try newVersion.dequeue()
        guard old < new else { return }

        if old.major == 0 {
            if !renamedToVariable.hasChanges {
                if let renamedValue = renamedFromVariable.unwrapped {
                    // migration called before update operation because value doesn't add explicitly to transaction
                    renamedToVariable <== renamedValue
                } else {
                    transaction.addPrecondition { [unowned self] (promise) in
                        _ = self.renamedFromVariable.loadValue().listening({ event in
                            switch event {
                            case .value(let value):
                                // updates already added to transaction because add migration changes explicitly
                                try! self.renamedToVariable.setValue(value, in: transaction)
                                promise.fulfill()
                            case .error(let e): promise.reject(e)
                            }
                        })
                    }
                }
                transaction.removeValue(by: renamedFromVariable.node!)
            }
        }

        _calledMigration = true
    }
}

extension Representer where V == Date {
    static func dateV2() -> Representer<Date> {
        let oldBase = Representer.date(.secondsSince1970)
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        let newBase = Representer.date(DateCodingStrategy.formatted(formatter))
        return Representer.init(
            encoding: newBase.encode,
            decoding: { (data) -> Date in
                guard let value = try? data.decode(String.self) else {
                    return try oldBase.decode(data)
                }
                guard let date = formatter.date(from: value) else {
                    throw NSError(domain: "tests", code: 0, userInfo: nil)
                }
                return date
        }
        )
    }
}

class VersionableObjectV2: Object {
    lazy var requiredPropertyV2: Property<Date> = "requiredPropertyV2".property(in: self, representer: .dateV2())

    override class func lazyPropertyKeyPath(for label: String) -> AnyKeyPath? {
        switch label {
        case "requiredPropertyV2": return \VersionableObjectV2.requiredPropertyV2
        default: return nil
        }
    }

    override func putVersion(into versioner: inout Versioner) {
        super.putVersion(into: &versioner)
        versioner.enqueue(Version(2, 1))
    }

    override func performMigration(from currentVersion: inout Versioner, to newVersion: inout Versioner, in transaction: Transaction) throws {
        try super.performMigration(from: &currentVersion, to: &newVersion, in: transaction)

        let old = (try? currentVersion.dequeue()) ?? Version(0, 0)
        let new = try newVersion.dequeue()

        guard old < new else { return }

        if old.major == 2 {
            if old.minor == 0 {
                if !requiredPropertyV2.hasChanges {
                    if let value = requiredPropertyV2.wrapped {
                        // migration called before update operation because value doesn't add explicitly to transaction
                        requiredPropertyV2 <== value
                    } else {
                        transaction.addPrecondition { [unowned self] (promise) in
                            _ = self.requiredPropertyV2.loadValue().listening({ event in
                                switch event {
                                case .value(let value):
                                    // updates already added to transaction because add migration changes explicitly
                                    try! self.requiredPropertyV2.setValue(value, in: transaction)
                                    promise.fulfill()
                                case .error(let e): promise.reject(e)
                                }
                            })
                        }
                    }
                }
            }
        }
    }
}

/// Version over model
///
/// - v1: Model in first major version
/// - v2: Model in second major version
enum VersionableValue: WritableRealtimeValue, RealtimeDataRepresented, RealtimeValueActions {
    case v1(VersionableObject)
    case v2(VersionableObjectV2)

    var node: Node? { return value.node }
    var raw: RealtimeDatabaseValue? { return value.raw }
    var payload: RealtimeDatabaseValue? { return value.payload }
    var canObserve: Bool { return value.canObserve }
    var keepSynced: Bool {
        get { return value.keepSynced }
        set { value.keepSynced = newValue }
    }

    var value: Object {
        switch self {
        case .v1(let v): return v
        case .v2(let v): return v
        }
    }

    init(in node: Node?, options: [ValueOption : Any]) {
        self = .v2(VersionableObjectV2(in: node, options: options))
    }

    init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        guard var versioner = try data.versioner() else {
            self = .v1(try VersionableObject(data: data, event: event))
            return
        }
        var version: Version?
        while let v = try? versioner.dequeue() {
            version = v
        }

        switch version?.major {
        case 2: self = .v2(try VersionableObjectV2(data: data, event: event))
        default: self = .v1(try VersionableObject(data: data, event: event))
        }
    }

    mutating func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        try value.apply(data, event: event)
    }
    func load(timeout: DispatchTimeInterval) -> RealtimeTask { return value.load(timeout: timeout) }
    func runObserving() -> Bool { return value.runObserving() }
    func stopObserving() { value.stopObserving() }
    func willSave(in transaction: Transaction, in parent: Node, by key: String) { value.willSave(in: transaction, in: parent, by: key) }
    func didSave(in database: RealtimeDatabase, in parent: Node, by key: String) { value.didSave(in: database, in: parent, by: key) }
    func willUpdate(through ancestor: Node, in transaction: Transaction) { value.willUpdate(through: ancestor, in: transaction) }
    func didUpdate(through ancestor: Node) { value.didUpdate(through: ancestor) }
    func didRemove(from ancestor: Node) { value.didRemove(from: ancestor) }
    func willRemove(in transaction: Transaction, from ancestor: Node) { value.willRemove(in: transaction, from: ancestor) }
    func write(to transaction: Transaction, by node: Node) throws { try value.write(to: transaction, by: node) }
}

extension RealtimeTests {
    func testVersioner() {
        var versioner1 = Versioner()
        versioner1.enqueue(Version(0, 0))
        versioner1.enqueue(Version(3, 5))
        var versioner2 = Versioner()
        versioner2.enqueue(Version(1, 0))

        XCTAssertTrue(versioner1 < versioner2)
    }

    func testVersioner2() {
        var versioner = Versioner()
        versioner.enqueue(Version(46, 23))
        versioner.enqueue(Version(24, 43))

        let versionValue = versioner.finalize()
        let copyVersioner = Versioner(version: versionValue)

        XCTAssertTrue(versioner == copyVersioner)
    }

    func testObjectVersionerEmpty() {
        let obj = Object(in: nil)

        XCTAssertTrue(obj.modelVersion.isEmpty)
    }
    func testVersionableObject() {
        let exp = expectation(description: "")
        let versionableObj = VersionableObject(
            in: Node(key: "obj", parent: .root),
            options: [.database: Cache.root]
        )

        let preconditionTransaction = Transaction(database: Cache.root)
        preconditionTransaction.addValue("renamed", by: versionableObj.renamedFromVariable.node!)
        preconditionTransaction.commit { (_, errs) in
            errs?.first.map({ XCTFail($0.describingErrorDescription) })
            XCTAssertNotNil(Cache.root.child(by: versionableObj.renamedFromVariable.node!))

            versionableObj.firstMinorVersionVariable <== "null"
            let transaction = Transaction(database: Cache.root)
            do {
                try versionableObj.update(in: transaction)
                transaction.commit { (state, errs) in
                    errs?.first.map({ XCTFail($0.describingErrorDescription) })

                    exp.fulfill()
                }
            } catch let e {
                transaction.cancel()
                XCTFail(e.describingErrorDescription)
            }
        }

        waitForExpectations(timeout: 5) { (err) in
            err.map({ XCTFail($0.describingErrorDescription) })

            XCTAssertTrue(versionableObj._calledMigration)
            XCTAssertNotNil(versionableObj._version)
            XCTAssertTrue(versionableObj.renamedToVariable.wrapped == "renamed")
        }
    }

    func testVersionableValue() {
        let exp = expectation(description: "")
        let versionableObj = VersionableObject(
            in: Node(key: "obj", parent: .root),
            options: [.database: Cache.root]
        )

        let preconditionTransaction = Transaction(database: Cache.root)
        preconditionTransaction.addValue("renamed", by: versionableObj.renamedFromVariable.node!)
        preconditionTransaction.commit { (_, errs) in
            errs?.first.map({ XCTFail($0.describingErrorDescription) })

            versionableObj.firstMinorVersionVariable <== "null"
            let transaction = Transaction(database: Cache.root)
            do {
                try versionableObj.update(in: transaction)
                transaction.commit { (state, errs) in
                    errs?.first.map({ XCTFail($0.describingErrorDescription) })

                    do {
                        let versionableValue = try VersionableValue(data: Cache.root.child(by: versionableObj.node!)!.asUpdateNode())
                        switch versionableValue {
                        case .v1(let obj):
                            XCTAssertNotNil(obj._version)
                            XCTAssertTrue(obj.firstMinorVersionVariable.wrapped == "null")
                            XCTAssertTrue(obj.renamedToVariable.wrapped == "renamed")
                            exp.fulfill()
                        case .v2: XCTFail("Unexpected version")
                        }
                    } catch let e {
                        XCTFail(e.describingErrorDescription)
                    }
                }
            } catch let e {
                transaction.cancel()
                XCTFail(e.describingErrorDescription)
            }
        }

        waitForExpectations(timeout: 5) { (err) in
            err.map({ XCTFail($0.describingErrorDescription) })

            XCTAssertTrue(versionableObj._calledMigration)
            XCTAssertNotNil(versionableObj._version)
            XCTAssertTrue(versionableObj.renamedToVariable.wrapped == "renamed")
        }
    }

    func testVersionableValue2() {
        let exp = expectation(description: "")
        let versionableObj = VersionableObjectV2(
            in: Node(key: "obj", parent: nil),
            options: [.database: Cache.root]
        )

        let now = Date()
        versionableObj.requiredPropertyV2 <== now
        let transaction = Transaction(database: Cache.root)
        do {
            try versionableObj.save(in: .root, in: transaction)
            transaction.commit { (state, errs) in
                errs?.first.map({ XCTFail($0.describingErrorDescription) })

                do {
                    let versionableValue = try VersionableValue(data: Cache.root.child(by: versionableObj.node!)!.asUpdateNode())
                    switch versionableValue {
                    case .v1: XCTFail("Unexpected version")
                    case .v2(let obj):
                        let representer = Representer.dateV2()
                        XCTAssertNotNil(obj._version)
                        XCTAssertEqual(
                            obj.requiredPropertyV2.wrapped?.timeIntervalSince1970.rounded(),
                            try! representer.encode(now).map({ try! representer.decode(ValueNode(node: .root, value: $0)) })?
                                .timeIntervalSince1970.rounded()
                        )
                        exp.fulfill()
                    }
                } catch let e {
                    XCTFail(e.describingErrorDescription)
                }
            }
        } catch let e {
            transaction.cancel()
            XCTFail(e.describingErrorDescription)
        }

        waitForExpectations(timeout: 5) { (err) in
            err.map({ XCTFail($0.describingErrorDescription) })

            XCTAssertNotNil(versionableObj._version)
        }
    }

    func testVersionableValue3() {
        let exp = expectation(description: "")
        let representer = Representer.dateV2()
        let now = Date()
        let transaction = Transaction(database: Cache.root)
        let objNode = Node(key: "obj", parent: .root)
        do {
            var versioner = Versioner()
            versioner.enqueue(Version(2, 0))
            transaction.addValue(RealtimeDatabaseValue(versioner.finalize()), by: objNode.child(with: InternalKeys.modelVersion.rawValue))
            transaction.addValue(try representer.encode(now), by: Node(key: "requiredPropertyV2", parent: objNode))
            transaction.commit { (state, errs) in
                errs?.first.map({ XCTFail($0.describingErrorDescription) })

                do {
                    let versionableValue = try VersionableValue(data: Cache.root.child(by: objNode)!.asUpdateNode())
                    switch versionableValue {
                    case .v1: XCTFail("Unexpected version")
                    case .v2(let obj):
                        XCTAssertNotNil(obj._version)
                        XCTAssertEqual(
                            obj.requiredPropertyV2.wrapped?.timeIntervalSince1970.rounded(),
                            try! representer.encode(now).map({ try! representer.decode(ValueNode(node: .root, value: $0)) })?
                                .timeIntervalSince1970.rounded()
                        )
                        exp.fulfill()
                    }
                } catch let e {
                    XCTFail(e.describingErrorDescription)
                }
            }
        } catch let e {
            transaction.cancel()
            XCTFail(e.describingErrorDescription)
        }

        waitForExpectations(timeout: 5) { (err) in
            err.map({ XCTFail($0.describingErrorDescription) })
        }
    }
}

extension RealtimeTests {
    func testLoadTask() {
        let exp = expectation(description: "")
        let object = TestObject(in: .root)
        _ = object.load().completion.listening(onValue: { _ in
            exp.fulfill()
        })

        waitForExpectations(timeout: 2) { (err) in
            err.map({ XCTFail($0.describingErrorDescription) })
        }
    }

    func testLoadValue() {
        let exp = expectation(description: "")
        let object = TestObject(in: .root)
        _ = object.property.loadValue().listening(onValue: { _ in
            exp.fulfill()
        })

        waitForExpectations(timeout: 2) { (err) in
            err.map({ XCTFail($0.describingErrorDescription) })
        }
    }

    func testLoadFileState() {
        let exp = expectation(description: "")
        let object = TestObject(in: .root)
        _ = object.file.loadState().listening(onValue: { _ in
            exp.fulfill()
        })

        waitForExpectations(timeout: 2) { (err) in
            err.map({ XCTFail($0.describingErrorDescription) })
        }
    }
}

extension RealtimeTests {
    func testCacheFileDownloadTask() {
        struct RSCache: RealtimeStorageCache {
            let nsCache: NSCache<NSString, NSData> = NSCache()

            init() {}

            public func put(_ file: Data, for node: Node, completion: ((Error?) -> Void)?) {
                nsCache.setObject(file as NSData, forKey: node.absolutePath as NSString)
                completion?(nil)
            }

            public func file(for node: Node, completion: @escaping (Data?) -> Void) {
                let cached = nsCache.object(forKey: node.absolutePath as NSString)
                completion(cached as Data?)
            }
        }
        class NextLevelTask: RealtimeStorageTask {
            let _completion: (Data?, Bool) -> Void

            init(_ completion: @escaping (Data?, Bool) -> Void) {
                self._completion = completion
            }

            func pause() {}
            func cancel() {}
            func resume() {
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
                    let data = "Realtime".data(using: .utf8)
                    self._completion(data, false)
                    self.delayed.send(.value(["Realtime": data as Any]))
                })
            }

            let delayed = Repeater<RealtimeMetadata?>.unsafe()
            var progress: AnyListenable<Progress> { return Constant(Progress(totalUnitCount: 100)).asAny() }
            var success: AnyListenable<RealtimeMetadata?> {
                return delayed.asAny()
            }

            static func running(completion: @escaping (Data?, Bool) -> Void) -> NextLevelTask { let t = NextLevelTask(completion); t.resume(); return t }
        }

        let exp = expectation(description: "")
        let cacheTask = CachedFileDownloadTask(nextLevel: NextLevelTask.running, cache: RSCache(), node: .root) { (data, cached) in
        }

        cacheTask.success.listening(onValue: { metadata in
            XCTAssertEqual("Realtime", String(data: metadata!["Realtime"] as! Data, encoding: .utf8))
            exp.fulfill()
        }).add(to: self.store)

        waitForExpectations(timeout: 5) { (err) in
            err.map({ XCTFail($0.describingErrorDescription) })
            XCTAssertEqual(cacheTask.state, .finish)
        }
    }
}

extension RealtimeTests {
    func testObserveCache() {
        var handles: [UInt] = []
        let mutationNode = Node.root("path/to/observed/node")

        let valueExp = expectation(description: "value")
        handles += [Cache.root.observe(
            .value, on: mutationNode,
            onUpdate: { _, _ in valueExp.fulfill() },
            onCancel: { _ in valueExp.fulfill() }
            )]
        let parentChildExp = expectation(description: "value")
        handles += [Cache.root.observe(
            .child(.added), on: mutationNode.parent!,
            onUpdate: { _, _ in parentChildExp.fulfill() },
            onCancel: { _ in parentChildExp.fulfill() }
            )]

        let transaction = Transaction(database: Cache.root, storage: Cache.root)
        transaction.addValue(true, by: mutationNode)
        transaction.commit(with: { (_, errs) in
            _ = errs?.map({ XCTFail($0.localizedDescription) })
        })

        waitForExpectations(timeout: 5.0) { (err) in
            err.map({ XCTFail($0.localizedDescription) })
        }
    }
}
