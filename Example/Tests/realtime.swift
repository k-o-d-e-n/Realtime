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
}

// MARK: Realtime

class TestObject: RealtimeObject {
    lazy var property: RealtimeProperty<String?> = "prop".property(from: self.node)
    lazy var readonlyProperty: ReadonlyRealtimeProperty<Int> = "readonlyProp".readonlyProperty(from: self.node).defaultOnEmpty()
    lazy var linkedArray: LinkedRealtimeArray<RealtimeObject> = "linked_array".linkedArray(from: self.node, elements: .root)
    lazy var array: RealtimeArray<TestObject> = "array".array(from: self.node)
    lazy var dictionary: RealtimeDictionary<RealtimeObject, TestObject> = "dict".dictionary(from: self.node, keys: .root)
    lazy var nestedObject: NestedObject = "nestedObject".nested(in: self)
    lazy var readonlyFile: ReadonlyStorageProperty<UIImage> = ReadonlyStorageProperty(in: Node(key: "readonlyFile", parent: self.node), representer: .png)
    lazy var file: StorageProperty<UIImage> = StorageProperty(in: Node(key: "file", parent: self.node), representer: .jpeg())

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

    class NestedObject: RealtimeObject {
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

        override open class func lazyPropertyKeyPath(for label: String) -> AnyKeyPath? {
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

        testObject.property <== "string"
        testObject.nestedObject.lazyProperty <== "nested_string"

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

        testObject.property <== "string"
        testObject.nestedObject.lazyProperty <== "nested_string"

        let element = TestObject(in: Node.root.child(with: "element_1"))
        element.property <== "element #1"
        element.nestedObject.lazyProperty <== "value"

        do {
            let elementTransaction = try element.update()
            let objectTransaction = try testObject.update()
            try elementTransaction.merge(objectTransaction)

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
        linkedObject.property <== "#1"
        testObject.linkedArray._view.isPrepared = true
        XCTAssertNoThrow(try testObject.linkedArray.write(element: linkedObject, in: transaction))

        let object = TestObject(in: Node(key: "elem_1"))
        object.property <== "prop"
        testObject.array._view.isPrepared = true
        XCTAssertNoThrow(try testObject.array.write(element: object, in: transaction))

        let element = TestObject()
        element.property <== "element #1"
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
        linkedObject.property <== "#1"
        testObject.linkedArray.insert(element: linkedObject)

        let object = TestObject(in: Node(key: "elem_1"))
        object.property <== "prop"
        testObject.array.insert(element: object)

        let element = TestObject()
        element.property <== "element #1"
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
            element.property <== "element #1"
            element.nestedObject.lazyProperty <== "value"
            let child = TestObject()
            child.property <== "element #1"
            element.array._view.isPrepared = true
            try element.array.write(element: child, in: transaction)
            transaction.removeValue(by: element.readonlyProperty.node!)
            let imgData = UIImagePNGRepresentation(#imageLiteral(resourceName: "pw"))!
            transaction.addFile(imgData, by: element.readonlyFile.node!)
            element.file <== #imageLiteral(resourceName: "pw")

            let data = try element.update(in: transaction).updateNode

            let object = try TestObject(fireData: data.child(forPath: element.node!.rootPath), strongly: false)
            try object.array._view.source.apply(data.child(forPath: object.array._view.source.node!.rootPath), strongly: true)

            XCTAssertNotNil(object.file.wrapped)
//            XCTAssertEqual(object.file.wrapped.flatMap { UIImageJPEGRepresentation($0, 1.0) }, UIImageJPEGRepresentation(#imageLiteral(resourceName: "pw"), 1.0))
            XCTAssertNotNil(object.readonlyFile.wrapped)
            XCTAssertEqual(object.readonlyFile.wrapped.flatMap(UIImagePNGRepresentation), imgData)
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

    func testRelationOneToOne() {
        let transaction = RealtimeTransaction()

        do {
            let user = RealtimeUser(in: Node(key: "user", parent: .root))
            let group = RealtimeGroup(in: Node(key: "group", parent: .root))
            user.ownedGroup <== group

            let data = try user.update(in: transaction).updateNode

            let userCopy = try RealtimeUser(fireData: data.child(forPath: user.node!.rootPath), strongly: false)

            try group.apply(data.child(forPath: group.node!.rootPath), strongly: false)

            XCTAssertTrue(group.manager.unwrapped.dbKey == user.dbKey)
            XCTAssertTrue(user.ownedGroup.unwrapped?.dbKey == group.dbKey)
            XCTAssertTrue(userCopy.ownedGroup.unwrapped?.dbKey == group.dbKey)
        } catch let e {
            XCTFail(e.localizedDescription)
        }

        transaction.revert()
    }

    func testRelationOneToMany() {
        let transaction = RealtimeTransaction()

        do {
            let user = RealtimeUser(in: Node(key: "user", parent: .root))
            let group = RealtimeGroup(in: Node(key: "group", parent: .root))
            group._manager <== user

            let data = try group.update(in: transaction).updateNode

            let groupCopy = try RealtimeGroup(fireData: data.child(forPath: group.node!.rootPath), strongly: false)

            let groupBackwardRelation: RealtimeRelation<RealtimeGroup> = group._manager.options.property.path(for: group.node!).relation(from: user.node, rootLevelsUp: nil, .oneToOne("_manager"))
            try groupBackwardRelation.apply(data.child(forPath: groupBackwardRelation.node!.rootPath), strongly: false)

            XCTAssertTrue(groupBackwardRelation.wrapped?.dbKey == group.dbKey)
            XCTAssertTrue(group._manager.wrapped?.dbKey == user.dbKey)
            XCTAssertTrue(groupCopy._manager.wrapped?.dbKey == user.dbKey)
        } catch let e {
            XCTFail(e.localizedDescription)
        }

        transaction.revert()
    }

    func testOptionalRelation() {
        let transaction = RealtimeTransaction()

        do {
            let user = RealtimeUser(in: Node(key: "user", parent: .root))
            user.ownedGroup <== nil

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
            conversation.secretary <== nil

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
        let options = RealtimeRelation<TestObject>.Options(rootLevelsUp: nil, ownerLevelsUp: 1, property: .oneToOne("prop"))
        let representer = Representer<TestObject>.relation(options.property, rootLevelsUp: options.rootLevelsUp, ownerNode: options.ownerNode).optional()
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

            do {
                try a.write(element: .one(TestObject()), in: transaction)
                try a.write(element: .two(TestObject()), in: transaction)
            } catch let e {
                XCTFail(e.localizedDescription)
            }

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

    func testLocalDatabase() {
        let transaction = RealtimeTransaction(database: CacheNode.root)
        let testObject = TestObject(in: .root)

        testObject.property <== "string"
        testObject.nestedObject.lazyProperty <== "nested_string"

        do {
            try testObject.update(in: transaction)

            transaction.commit(with: { (state, errs) in
                if let e = errs?.first {
                    XCTFail(e.localizedDescription)
                } else {
                    do {
                        let restoredObj = try TestObject(fireData: CacheNode.root, strongly: false)

                        XCTAssertEqual(testObject.property.unwrapped, restoredObj.property.unwrapped)
                        XCTAssertEqual(testObject.nestedObject.lazyProperty.unwrapped,
                                       restoredObj.nestedObject.lazyProperty.unwrapped)
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
        let transaction = RealtimeTransaction(database: CacheNode.root)
        let testObject = TestObject(in: .root)

        testObject.property <== "string"
        testObject.nestedObject.lazyProperty <== "nested_string"
        testObject.file <== #imageLiteral(resourceName: "pw")

        do {
            try testObject.update(in: transaction)

            let imgData = UIImagePNGRepresentation(#imageLiteral(resourceName: "pw"))!
            transaction.addFile(imgData, by: testObject.readonlyFile.node!)

            transaction.commit(with: { (state, errs) in
                if let e = errs?.first {
                    XCTFail(e.localizedDescription)
                } else {
                    let restoredObj = TestObject(in: .root, options: [.database: CacheNode.root])
                    restoredObj.load(completion: .just { e in
                        e.map { XCTFail($0.localizedDescription) }

                        XCTAssertEqual(testObject.property.unwrapped, restoredObj.property.unwrapped)
                        XCTAssertEqual(testObject.nestedObject.lazyProperty.unwrapped,
                                       restoredObj.nestedObject.lazyProperty.unwrapped)
                    })
                }
            })
        } catch let e {
            XCTFail(e.localizedDescription)
        }
    }
}
