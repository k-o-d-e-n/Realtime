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

class Tests: XCTestCase {
    var store: ListeningDisposeStore = ListeningDisposeStore()

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

class TestObject: Object {
    lazy var property: Property<String?> = "prop".property(in: self)
    lazy var readonlyProperty: ReadonlyProperty<Int> = "readonlyProp".readonlyProperty(in: self).defaultOnEmpty()
    lazy var linkedArray: References<Object> = "linked_array".references(in: self, elements: .root)
    lazy var array: Values<TestObject> = "array".values(in: self)
    lazy var dictionary: AssociatedValues<Object, TestObject> = "dict".dictionary(in: self, keys: .root)
    lazy var nestedObject: NestedObject = "nestedObject".nested(in: self)
    lazy var readonlyFile: ReadonlyFile<UIImage> = "readonlyFile".readonlyFile(in: self, representer: .png)
    lazy var file: File<UIImage> = "file".file(in: self, representer: .jpeg())

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
            self.usualProperty = Property(in: Node(key: "usualprop", parent: node),
                                          representer: .any,
                                          options: [.database: options[.database] as Any])
            super.init(in: node, options: options)
        }

        required init(data: RealtimeDataProtocol, exactly: Bool) throws {
            self.usualProperty = Property(in: Node(key: "usualprop", parent: data.node),
                                          representer: .any,
                                          options: [.database: data.database as Any])
            try super.init(data: data, exactly: exactly)
        }

        override func apply(_ data: RealtimeDataProtocol, exactly: Bool) throws {
            try super.apply(data, exactly: exactly)
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

func checkStates(in v: RealtimeValue, for event: RVEvent, _ line: Int = #line) {
    switch event {
    case .didSave, .willRemove:
        XCTAssertTrue(v.isReferred, "line: \(line)")
        XCTAssertTrue(v.isInserted, "line: \(line)")
        XCTAssertTrue(v.isRooted, "line: \(line)")
        XCTAssertFalse(v.isStandalone, "line: \(line)")
    case .willSave(let t), .didRemove(let t):
        switch t {
        case .rooted: return
        case .unkeyed: XCTAssertFalse(v.isReferred, "line: \(line)")
        case .keyed: XCTAssertFalse(v.isReferred, "line: \(line)")
        case .nested(parent: let p):
            switch p {
            case .unkeyed: XCTAssertFalse(v.isReferred, "line: \(line)")
            default: XCTAssertTrue(v.isReferred, "line: \(line)")
            }
        }
        XCTAssertFalse(v.isInserted, "line: \(line)")
        XCTAssertFalse(v.isRooted, "line: \(line)")
        XCTAssertTrue(v.isStandalone, "line: \(line)")
    }
}

func checkDidSave(_ v: RealtimeValue, nested: Bool = false, _ line: Int = #line) {
    checkStates(in: v, for: .didSave, line)
}

func checkDidRemove(_ v: RealtimeValue, value type: RVType = .unkeyed, _ line: Int = #line) {
    checkStates(in: v, for: .didRemove(type), line)
}

func checkWillSave(_ v: RealtimeValue, value type: RVType = .unkeyed, _ line: Int = #line) {
    checkStates(in: v, for: .willSave(type), line)
}

func checkWillRemove(_ v: RealtimeValue, nested: Bool = false, _ line: Int = #line) {
    checkStates(in: v, for: .willRemove, line)
}

extension Tests {
    func testObjectSave() {
        let obj = TestObject()

        obj.property <== "value"
        XCTAssertTrue(obj.property.hasChanges)
        obj.file <== #imageLiteral(resourceName: "pw")
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
            let save = try obj.save(by: .root, in: Transaction(database: CacheNode.root))
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
        let property = Property<String>(in: Node(key: "value", parent: .root),
                                        representer: Representer<String>.any,
                                        options: [:])

        XCTAssertFalse(property.hasChanges)
        let transaction = Transaction(database: CacheNode.root)
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
    func testObjectRemove() {
        let obj = TestObject()

        obj.property <== "value"
        obj.file <== #imageLiteral(resourceName: "pw")
        obj.nestedObject.usualProperty <== "usual"
        obj.nestedObject.lazyProperty <== "lazy"

        obj.didSave(in: CacheNode.root, in: .root, by: "obj")

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
        do {
            let save = try obj.delete()
            save.commit(with: { _, errs in
                errs.map { _ in XCTFail() }

                XCTAssertFalse(obj.hasChanges)
                checkDidRemove(obj)
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
        } catch let e {
            XCTFail(e.localizedDescription)
        }
    }
}

extension Tests {
    func testNestedObjectChanges() {
        let testObject = TestObject(in: Node(key: "t_obj"))

        testObject.property <== "string"
        testObject.nestedObject.lazyProperty <== "nested_string"
        testObject.file <== #imageLiteral(resourceName: "pw")

        do {
            let trans = try testObject.save(in: .root)
            let value = trans.updateNode.updateValue
            let expectedValue = ["t_obj/prop":"string", "t_obj/nestedObject/lazyprop":"nested_string"] as [String: Any?]

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
            let expectedValue = ["prop":"string", "nestedObject/lazyprop":"nested_string",
                                 "element_1/prop":"element #1", "element_1/nestedObject/lazyprop":"value"] as [String: Any?]

            XCTAssertTrue((value as NSDictionary) == (expectedValue as NSDictionary))
            elementTransaction.revert()
        } catch let e {
            XCTFail(e.localizedDescription)
        }
    }

    func testCollectionOnRootObject() {
        let testObject = TestObject(in: .root)

        let transaction = Transaction()

        let linkedObject = TestObject(in: Node.root.child(with: "linked"))
        linkedObject.property <== "#1"
        testObject.linkedArray._view.isSynced = true
        XCTAssertNoThrow(try testObject.linkedArray.write(element: linkedObject, in: transaction))

        let object = TestObject(in: Node(key: "elem_1"))
        object.file <== #imageLiteral(resourceName: "pw")
        object.property <== "prop"
        testObject.array._view.isSynced = true
        XCTAssertNoThrow(try testObject.array.write(element: object, in: transaction))

        let element = TestObject()
        element.file <== #imageLiteral(resourceName: "pw")
        element.property <== "element #1"
        testObject.dictionary._view.isSynced = true
        XCTAssertNoThrow(try testObject.dictionary.write(element: element, for: linkedObject, in: transaction))

        let value = transaction.updateNode.updateValue

        let linkedItem = value["linked_array/linked"] as? [String: Any]
        XCTAssertTrue(linkedItem != nil)
        XCTAssertTrue(value["array/elem_1/prop"] as? String == "prop")
        XCTAssertTrue(value["dict/linked/prop"] as? String == "element #1")
        transaction.revert()
    }

    func testCollectionOnStandaloneObject() {
        let testObject = TestObject(in: Node(key: "test_obj"))
        testObject.file <== #imageLiteral(resourceName: "pw")

        let linkedObject = TestObject(in: Node.root.child(with: "linked"))
        linkedObject.property <== "#1"
        testObject.linkedArray.insert(element: linkedObject)

        let object = TestObject(in: Node(key: "elem_1"))
        object.file <== #imageLiteral(resourceName: "pw")
        object.property <== "prop"
        testObject.array.insert(element: object)

        let element = TestObject()
        element.file <== #imageLiteral(resourceName: "pw")
        element.property <== "element #1"
        testObject.dictionary.set(element: element, for: linkedObject)

        do {
            let transaction = try testObject.save(in: .root)
            let value = transaction.updateNode.updateValue

            let linkedItem = value["test_obj/linked_array/linked"] as? [String: Any]
            XCTAssertTrue(linkedItem != nil)
            XCTAssertTrue(value["test_obj/array/elem_1/prop"] as? String == "prop")
            XCTAssertTrue(value["test_obj/dict/linked/prop"] as? String == "element #1")
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
            child.file <== #imageLiteral(resourceName: "pw")
            element.array._view.isSynced = true
            try element.array.write(element: child, in: transaction)
            transaction.removeValue(by: element.readonlyProperty.node!)
            let imgData = UIImagePNGRepresentation(#imageLiteral(resourceName: "pw"))!
            transaction.addFile(imgData, by: element.readonlyFile.node!)
            element.file <== #imageLiteral(resourceName: "pw")

            let data = try element.update(in: transaction).updateNode

            let object = try TestObject(data: data.child(forPath: element.node!.rootPath), exactly: false)
            
            XCTAssertNotNil(object.file.wrapped)
//            XCTAssertEqual(object.file.wrapped.flatMap { UIImageJPEGRepresentation($0, 1.0) }, UIImageJPEGRepresentation(#imageLiteral(resourceName: "pw"), 1.0))
            XCTAssertNotNil(object.readonlyFile.wrapped)
            XCTAssertEqual(object.readonlyFile.wrapped.flatMap(UIImagePNGRepresentation), imgData)
            XCTAssertEqual(object.readonlyProperty.wrapped, Int())
            XCTAssertEqual(object.property.unwrapped, element.property.unwrapped)
            XCTAssertEqual(object.nestedObject.lazyProperty.unwrapped, element.nestedObject.lazyProperty.unwrapped)
        } catch let e {
            XCTFail(e.localizedDescription)
        }

        transaction.revert()
    }

    func testUpdateFileAfterSave() {
        let group = Group(in: Node(key: "group", parent: Global.rtGroups.node))
        let user = User(in: Node(key: "user"))
        group.manager <== user
        user.name <== "name"
        user.age <== 0
        user.photo <== #imageLiteral(resourceName: "pw")
        user.groups.insert(element: group)
        user.ownedGroup <== group

        do {
            let cache = Transaction(database: CacheNode.root)
            let transaction = try user.save(in: .root, in: cache)
            transaction.commit(with: { (_, errors) in
                errors.map { _ in XCTFail() }

                XCTAssertFalse(user.hasChanges)

                user.photo <== #imageLiteral(resourceName: "pw")
                do {
                    let update = try user.update()
                    XCTAssertTrue(update.updateNode.updateValue.isEmpty)
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

            let data = try user.update(in: transaction).updateNode

            let userCopy = try User(data: data.child(forPath: user.node!.rootPath), exactly: false)

            try group.apply(data.child(forPath: group.node!.rootPath), exactly: false)

            XCTAssertTrue(group.manager.unwrapped.dbKey == user.dbKey)
            XCTAssertTrue(user.ownedGroup.unwrapped?.dbKey == group.dbKey)
            XCTAssertTrue(userCopy.ownedGroup.unwrapped?.dbKey == group.dbKey)
        } catch let e {
            XCTFail(e.localizedDescription)
        }

        transaction.revert()
    }

    func testRelationOneToMany() {
        let transaction = Transaction()

        do {
            let user = User(in: Node(key: "user", parent: .root))
            let group = Group(in: Node(key: "group", parent: .root))
            group._manager <== user

            let data = try group.update(in: transaction).updateNode

            let groupCopy = try Group(data: data.child(forPath: group.node!.rootPath), exactly: false)

            let groupBackwardRelation: Relation<Group> = group._manager.options.property.path(for: group.node!).relation(in: user, rootLevelsUp: nil, .oneToOne("_manager"))
            try groupBackwardRelation.apply(data.child(forPath: groupBackwardRelation.node!.rootPath), exactly: true)

            XCTAssertTrue(groupBackwardRelation.wrapped?.dbKey == group.dbKey)
            XCTAssertTrue(group._manager.wrapped?.dbKey == user.dbKey)
            XCTAssertTrue(groupCopy._manager.wrapped?.dbKey == user.dbKey)
        } catch let e {
            XCTFail(e.localizedDescription)
        }

        transaction.revert()
    }

    func testOptionalRelation() {
        let transaction = Transaction()

        do {
            let user = User(in: Node(key: "user", parent: .root))
            user.ownedGroup <== nil

            let data = try user.update(in: transaction).updateNode

            let userCopy = try User(data: data.child(forPath: user.node!.rootPath), exactly: false)

            if case .error(let e, _)? = userCopy.ownedGroup.lastEvent {
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
        let transaction = Transaction()

        do {
            let conversation = Conversation(in: Node(key: "conv_1", parent: .root))
            conversation.secretary <== nil

            let data = try conversation.update(in: transaction).updateNode

            let conversationCopy = try Conversation(data: data.child(forPath: conversation.node!.rootPath), exactly: false)

            if case .error(let e, _)? = conversation.chairman.lastEvent {
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
        let property = WriteRequiredProperty<String>(in: Node(key: "prop"), representer: Representer<String>.any)

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
        let property = WriteRequiredProperty<String>(in: Node(key: "prop"), representer: Representer<String>.any)

        do {
            let data = ValueNode(node: Node(key: "prop"), value: nil)
            try property.apply(data, exactly: true)
        } catch let e {
            XCTFail(e.localizedDescription)
        }
    }

    func testRepresenterOptional() {
        let representer = Representer<TestObject>.relation(.oneToOne("prop"), rootLevelsUp: nil, ownerNode: .unsafe(strong: nil)).optional()
        do {
            let object = try representer.decode(ValueNode(node: Node(key: ""), value: nil))
            XCTAssertNil(object)
        } catch let e {
            XCTFail(e.localizedDescription)
        }
    }

    func testReferenceRepresentationPayload() {
        let value = ValueWithPayload.two(TestObject(in: Node(key: "path/subpath", parent: .root), options: [.userPayload: ["foo": "bar"]]))
        let representer = Representer<ValueWithPayload>.reference(.fullPath, options: [:])

        do {
            let result = try representer.encode(value)

            XCTAssertEqual(result as? NSDictionary, ["ref": "path/subpath",
                                                     InternalKeys.raw.rawValue: 1,
                                                     InternalKeys.payload.rawValue: ["foo": "bar"]])
        } catch let e {
            XCTFail(e.localizedDescription)
        }
    }

    func testNode() {
        let first = Node(key: "first", parent: .root)

        let second = Node(key: "second", parent: first)
        XCTAssertEqual(second.rootPath, "first/second")
        XCTAssertEqual(second.path(from: first), "second")
        XCTAssertTrue(second.hasAncestor(node: first))
        XCTAssertTrue(second.isRooted)

        let third = second.child(with: "third")
        XCTAssertEqual(third.rootPath, "first/second/third")
        XCTAssertEqual(third.path(from: first), "second/third")
        XCTAssertTrue(third.hasAncestor(node: first))
        XCTAssertTrue(third.isRooted)

        let fourth = third.child(with: "fourth")
        XCTAssertEqual(fourth.rootPath, "first/second/third/fourth")
        XCTAssertEqual(fourth.path(from: first), "second/third/fourth")
        XCTAssertTrue(fourth.hasAncestor(node: first))
        XCTAssertTrue(fourth.isRooted)
    }

    func testLinksNode() {
        let fourth = Node.root.child(with: "first/second/third/fourth")
        let linksNode = fourth.linksNode
        XCTAssertEqual(linksNode.rootPath, RealtimeApp.app.linksNode.child(with: "first/second/third/fourth").rootPath)
    }

    func testConnectNode() {
        let testObject = TestObject(in: Node())

        XCTAssertTrue(testObject.isStandalone)
        XCTAssertTrue(testObject.property.isStandalone)
        XCTAssertTrue(testObject.linkedArray.isStandalone)
        XCTAssertTrue(testObject.array.isStandalone)
        XCTAssertTrue(testObject.dictionary.isStandalone)

        let node = Node(key: "testObjects", parent: .root)
        testObject.didSave(in: CacheNode.root, in: node)

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

    enum ValueWithPayload: WritableRealtimeValue, RealtimeDataRepresented, RealtimeValueActions {
        var version: Int? { return value.version }
        var raw: RealtimeDataValue? {
            switch self {
            case .two: return 1
            default: return nil
            }
        }
        var node: Node? { return value.node }
        var payload: [String : RealtimeDataValue]? { return value.payload }
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
            let raw = options.rawValue as? Int ?? 0

            switch raw {
            case 1: self = .two(TestObject(in: node, options: options))
            default: self = .one(TestObject(in: node, options: options))
            }
        }

        init(data: RealtimeDataProtocol, exactly: Bool) throws {
            let raw: CShort = try data.rawValue() as? CShort ?? 0

            switch raw {
            case 1: self = .two(try TestObject(data: data, exactly: exactly))
            default: self = .one(try TestObject(data: data, exactly: exactly))
            }
        }

        mutating func apply(_ data: RealtimeDataProtocol, exactly: Bool) throws {
            try value.apply(data, exactly: exactly)
            let r = try data.rawValue() as? Int ?? 0
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
            one.file <== #imageLiteral(resourceName: "pw")
            try array.write(element: .one(one), in: transaction)
            let two = TestObject()
            two.file <== #imageLiteral(resourceName: "pw")
            try array.write(element: .two(two), in: transaction)
        } catch let e {
            XCTFail(e.localizedDescription)
        }
        
        transaction.revert()
    }

    func testInitializeWithPayload() {
        let value = TestObject(in: .root, options: [.userPayload: ["key": "val"]])
        XCTAssertTrue((value.payload as NSDictionary?) == ["key": "val"])
    }

    func testInitializeWithPayload2() {
        let payload: [String: Any] = ["key": "val"]
        let value = TestObject(in: .root, options: [.userPayload: payload])
        XCTAssertTrue((value.payload as NSDictionary?) == (payload as NSDictionary))
    }

    func testInitializeWithPayload3() {
        let payload: Any = ["key": "val"]
        let value = TestObject(in: .root, options: [.userPayload: payload])
        XCTAssertTrue((value.payload as NSDictionary?) == (payload as? NSDictionary))
    }

    func testReferenceFireValue() {
        let ref = ReferenceRepresentation(ref: Node.root.child(with: "first/two").rootPath, payload: ((nil, nil), nil))
        let fireValue = ref.rdbValue
        XCTAssertTrue((fireValue as? NSDictionary) == ["ref": "first/two"])
    }

    func testLocalDatabase() {
        let transaction = Transaction(database: CacheNode.root)
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
                        let restoredObj = try TestObject(data: CacheNode.root, exactly: false)

                        XCTAssertEqual(testObject.property, restoredObj.property)
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
        let transaction = Transaction(database: CacheNode.root)
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

                        XCTAssertEqual(testObject.property, restoredObj.property)
                        XCTAssertEqual(testObject.nestedObject.lazyProperty,
                                       restoredObj.nestedObject.lazyProperty)
                    })
                }
            })
        } catch let e {
            XCTFail(e.localizedDescription)
        }
    }
}

// MARK: Collections

extension References: Reverting {
    public func revert() {
        guard _hasChanges else { return }
        storage.elements.removeAll()
        _view.removeAll()
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
        storage.elements.removeAll()
        _view.removeAll()
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
        storage.elements.removeAll()
        _view.removeAll()
    }

    public func currentReversion() -> () -> Void {
        return { [weak self] in
            self?.revert()
        }
    }
}

extension Tests {
    func testLocalChangesLinkedArray() {
        let linkedArray: References<TestObject> = References(in: Node(key: "l_array"), options: [.elementsNode: Node.root])

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
            try transaction._update(linkedArray, by: .root)
            XCTAssertEqual(linkedArray.storage.elements.count, 2)
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
        one.file <== #imageLiteral(resourceName: "pw")
        array.insert(element: one)
        let two = TestObject()
        two.file <== #imageLiteral(resourceName: "pw")
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
            XCTAssertEqual(array.storage.elements.count, 2)
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
        one.file <== #imageLiteral(resourceName: "pw")
        dict.set(element: one, for: TestObject(in: Node.root.childByAutoId()))
        let two = TestObject()
        two.file <== #imageLiteral(resourceName: "pw")
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
            XCTAssertEqual(dict.storage.elements.count, 2)
            /// after write to transaction array switches to remote
            XCTAssertEqual(dict.count, 0)
        } catch let e {
            XCTFail(e.localizedDescription)
        }
        transaction.revert()
    }

    func testListeningCollectionChangesOnInsert() {
        let exp = expectation(description: "")
        let array = Values<User>(in: .root, options: [.database: CacheNode.root])

        array.changes.listening({ (event) in
            guard let value = event.value else {
                XCTFail(event.error?.localizedDescription ?? "")
                return
            }
            switch value {
            case .initial:
                XCTFail(".initial does not should call")
            case .updated(_, let inserted, _, _):
                XCTAssertEqual(inserted.count, 1)
                exp.fulfill()
            }
        }).add(to: &store)
        array.changes.listening { err in
            XCTFail(err.localizedDescription)
        }.add(to: &store)

        let element = User()
        element.name <== "User"
        element.age <== 100
        element.photo <== #imageLiteral(resourceName: "pw")

        do {
            let transaction = Transaction(database: CacheNode.root)
            let elementNode = array.storage.sourceNode.childByAutoId()
            let itemNode = array.storage.sourceNode.child(with: InternalKeys.items).linksNode.child(with: elementNode.key)
            let link = elementNode.generate(linkTo: itemNode)
            let item = RCItem(element: element, key: elementNode.key, linkID: link.link.id, priority: 0)

            transaction.addValue(item.rdbValue, by: itemNode)
            transaction.addValue(link.link.rdbValue, by: link.node)
            try transaction.set(element, by: elementNode)

            /// simulate notification
            transaction.commit { (state, errors) in
                errors.map { e in XCTFail(e.reduce("") { $0 + $1.localizedDescription }) }
                array._view.isSynced = true
                array._view.source.dataObserver.send(.value((CacheNode.root.child(forPath: itemNode.rootPath), .child(.added))))
            }
        } catch let e {
            XCTFail(e.localizedDescription)
        }

        waitForExpectations(timeout: 4) { (error) in
            error.map { XCTFail($0.localizedDescription) }
        }
    }

    func testReadonlyRelation() {
        let exp = expectation(description: "")
        let user = User(in: Node(key: "user", parent: .root), options: [.database: CacheNode.root])
        let group = Group(in: Node(key: "group", parent: .root), options: [.database: CacheNode.root])
        user.ownedGroup <== group

        do {
            let transaction = try user.update()
            transaction.commit { (state, errors) in
                errors.map { XCTFail($0.description) }

                let ownedGroup = Relation<Group?>.readonly(in: user.ownedGroup.node, config: user.ownedGroup.options)
                do {
                    try ownedGroup.apply(CacheNode.root.child(forPath: user.ownedGroup.node!.rootPath), exactly: true)
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
        CacheNode.root.clear()
        let exp = expectation(description: "")
        let user = User(in: Node(key: "user", parent: .root), options: [.database: CacheNode.root])
        let conversation = Conversation(in: Node(key: "conversation", parent: .root), options: [.database: CacheNode.root])
        conversation.chairman <== user

        do {
            let transaction = try conversation.update()
            transaction.commit { (state, errors) in
                errors.map { XCTFail($0.description) }

                let chairman = Reference<User>.readonly(
                    in: conversation.chairman.node,
                    mode: Reference<User>.Mode.required(.fullPath, options: [.database: CacheNode.root])
                )
                do {
                    try chairman.apply(CacheNode.root.child(forPath: conversation.chairman.node!.rootPath), exactly: true)
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
        let testObject = TestObject(in: .root, options: [.database: CacheNode.root])
        testObject.forceEnumerateAllChilds { (_, value: _RealtimeValue) in
            if value.database === CacheNode.root {
                XCTAssertTrue(true)
            } else {
                XCTFail("value: \(value), database: \(value.database as Any)")
            }
        }
    }
}

// MARK: Operators

extension Tests {
    func testEqualFailsRequiredPropertyWithoutValueAndValue() {
        let property = Property<String>(in: .root, options: [.representer: Representer<String>.any.requiredProperty()])
        XCTAssertFalse(property ==== "")
        XCTAssertFalse("" ==== property)
    }
    func testNotEqualRequiredPropertyWithoutValueAndValue() {
        let property = Property<String>(in: .root, options: [.representer: Representer<String>.any.requiredProperty()])
        XCTAssertTrue(property !=== "")
        XCTAssertTrue("" !=== property)
    }
    func testEqualRequiredPropertyWithoutValueAndNil() {
        let property = Property<String>(in: .root, options: [.representer: Representer<String>.any.requiredProperty()])
        XCTAssertTrue(property ==== nil)
        XCTAssertTrue(nil ==== property)
    }
    func testEqualFailsRequiredPropertyWithValueAndValue() {
        let property = Property<String>(in: .root, options: [.representer: Representer<String>.any.requiredProperty()])
        property <== "string"
        XCTAssertFalse(property ==== "")
        XCTAssertFalse("" ==== property)
    }
    func testNotEqualRequiredPropertyWithValueAndValue() {
        let property = Property<String>(in: .root, options: [.representer: Representer<String>.any.requiredProperty()])
        property <== "string"
        XCTAssertTrue(property !=== "")
        XCTAssertTrue("" !=== property)
    }
    func testNotEqualRequiredPropertyWithValueAndNil() {
        let property = Property<String>(in: .root, options: [.representer: Representer<String>.any.requiredProperty()])
        property <== "string"
        XCTAssertFalse(property ==== nil)
        XCTAssertFalse(nil ==== property)
    }
    func testEqualFailsOptionalPropertyWithoutValueAndValue() {
        let property = Property<String?>(in: .root, options: [.representer: Representer<String>.any.optionalProperty()])
        XCTAssertFalse(property ==== "")
        XCTAssertFalse("" ==== property)
    }
    func testNotEqualOptionalPropertyWithoutValueAndValue() {
        let property = Property<String?>(in: .root, options: [.representer: Representer<String>.any.optionalProperty()])
        XCTAssertTrue(property !=== "")
        XCTAssertTrue("" !=== property)
    }
    func testEqualOptionalPropertyWithNilValueAndNil() {
        let property = Property<String?>(in: .root, options: [.representer: Representer<String>.any.optionalProperty()])
        property <== nil
        XCTAssertTrue(property ==== nil)
        XCTAssertTrue(nil ==== property)
    }
    func testEqualFailsOptionalPropertyWithValueAndValue() {
        let property = Property<String?>(in: .root, options: [.representer: Representer<String>.any.optionalProperty()])
        property <== "string"
        XCTAssertFalse(property ==== "")
        XCTAssertFalse("" ==== property)
    }
    func testNotEqualOptionalPropertyWithValueAndValue() {
        let property = Property<String?>(in: .root, options: [.representer: Representer<String>.any.optionalProperty()])
        property <== "string"
        XCTAssertTrue(property !=== "")
        XCTAssertTrue("" !=== property)
    }
    func testNotEqualOptionalPropertyWithValueAndNil() {
        let property = Property<String?>(in: .root, options: [.representer: Representer<String>.any.optionalProperty()])
        property <== "string"
        XCTAssertFalse(property ==== nil)
        XCTAssertFalse(nil ==== property)
    }
}
