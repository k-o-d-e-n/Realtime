//
//  AssociatedValues.swift
//  Realtime
//
//  Created by Denis Koryttsev on 16/03/2018.
//

import Foundation
import FirebaseDatabase

public extension RawRepresentable where RawValue == String {
    func dictionary<Key, Value>(in object: Object, keys: Node) -> AssociatedValues<Key, Value> {
        return AssociatedValues(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .keysNode: keys
            ]
        )
    }
    func dictionary<Key, Value>(in object: Object, keys: Node, elementOptions: [ValueOption: Any]) -> AssociatedValues<Key, Value> {
        let db = object.database as Any
        return dictionary(in: object, keys: keys, builder: { (node, options) in
            var compoundOptions = options.merging(elementOptions, uniquingKeysWith: { remote, local in remote })
            compoundOptions[.database] = db
            return Value(in: node, options: compoundOptions)
        })
    }
    func dictionary<Key, Value>(in object: Object, keys: Node, builder: @escaping RCElementBuilder<Value>) -> AssociatedValues<Key, Value> {
        return AssociatedValues(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .keysNode: keys,
                .elementBuilder: builder
            ]
        )
    }
}

extension ValueOption {
    static let keysNode = ValueOption("realtime.dictionary.keys")
}

/// A type that can used as key in `AssociatedValues` collection.
public typealias HashableValue = Hashable & RealtimeValue

/// A Realtime database collection that stores elements in own database node as is,
/// as full objects, that keyed by database key of `Key` element.
public final class AssociatedValues<Key, Value>: _RealtimeValue, ChangeableRealtimeValue, RealtimeCollection
where Value: WritableRealtimeValue & RealtimeValueEvents, Key: HashableValue {
    override var _hasChanges: Bool { return view._hasChanges }
    internal(set) var storage: RCDictionaryStorage<Key, Value>

    public override var version: Int? { return nil }
    public override var raw: RealtimeDataValue? { return nil }
    public override var payload: [String : RealtimeDataValue]? { return nil }
    public let view: SortedCollectionView<RDItem>
    public var isSynced: Bool { return view.isSynced }
    public override var isObserved: Bool { return view.isObserved }
    public override var canObserve: Bool { return view.canObserve }
    public var keepSynced: Bool {
        set { view.keepSynced = newValue }
        get { return view.keepSynced }
    }
    public var changes: AnyListenable<RCEvent> { return view.changes }

    /// Creates new instance associated with database node
    ///
    /// Available options:
    /// - keysNode(**required**): Database node where keys elements are located
    /// - database: Database reference
    /// - elementBuilder: Closure that calls to build elements lazily.
    /// - keyBuilder: Closure that calls to build key lazily.
    ///
    /// - Parameter node: Node location for value
    /// - Parameter options: Dictionary of options
    public required init(in node: Node?, options: [ValueOption: Any]) {
        guard case let keysNode as Node = options[.keysNode] else { fatalError("Skipped required options") }
        guard keysNode.isRooted else { fatalError("Keys must has rooted location") }

        let viewParentNode = node.flatMap { $0.isRooted ? $0.linksNode : nil }
        let valueBuilder = options[.elementBuilder] as? RCElementBuilder<Value> ?? Value.init
        let keyBuilder = options[.keyBuilder] as? RCElementBuilder<Key> ?? Key.init
        self.storage = RCDictionaryStorage(sourceNode: node, keysNode: keysNode, elementBuilder: valueBuilder, keyBuilder: keyBuilder, elements: [:])
        self.view = SortedCollectionView(in: Node(key: InternalKeys.items, parent: viewParentNode), options: [.database: options[.database] as Any])
        super.init(in: node, options: options)
    }

    /// Currently no available
    public required convenience init(data: RealtimeDataProtocol, exactly: Bool) throws {
        #if DEBUG
        fatalError("AssociatedValues does not supported init(data:exactly:) yet.")
        #else
        throw RealtimeError(source: .collection, description: "AssociatedValues does not supported init(data:exactly:) yet.")
        #endif
    }

    public convenience init(data: RealtimeDataProtocol, exactly: Bool, keysNode: Node) throws {
        self.init(in: data.node, options: [.keysNode: keysNode, .database: data.database as Any])
        try apply(data, exactly: exactly)
    }

    // MARK: Implementation

    public typealias Element = (key: Key, value: Value)

    private var shouldLinking = true // TODO: Fix it
    public func unlinked() -> AssociatedValues<Key, Value> { shouldLinking = false; return self }

    public func makeIterator() -> IndexingIterator<AssociatedValues> { return IndexingIterator(_elements: self) } // iterator is not safe
    public subscript(position: Int) -> Element { return storage.element(by: view[position]) }
    public subscript(key: Key) -> Value? {
        guard let v = storage.storedValue(by: key) else {
            guard let i = view.index(where: { $0.dbKey == key.dbKey }) else {
                return nil
            }
            return storage.element(by: view[i]).1
        }
        return v
    }
    /// Returns a Boolean value indicating whether the sequence contains an
    /// element by passed key.
    ///
    /// - Parameter key: The key element to check for containment.
    /// - Returns: `true` if element is contained in the range; otherwise,
    ///   `false`.
    public func contains(valueBy key: Key) -> Bool {
        if isStandalone {
            return storage.elements[key] != nil
        } else {
            return view.contains(where: { $0.dbKey == key.dbKey })
        }
    }

    var _snapshot: (RealtimeDataProtocol, Bool)?
    override public func apply(_ data: RealtimeDataProtocol, exactly: Bool) throws {
        guard view.isSynced else {
            _snapshot = (data, exactly)
            return
        }
        _snapshot = nil
        try view.forEach { key in
            guard data.hasChild(key.dbKey) else {
                if exactly, let contained = storage.elements.first(where: { $0.0.dbKey == key.dbKey }) { storage.elements.removeValue(forKey: contained.key) }
                return
            }
            let childData = data.child(forPath: key.dbKey)
            if var element = storage.elements.first(where: { $0.0.dbKey == key.dbKey })?.value {
                try element.apply(childData, exactly: exactly)
            } else {
                let keyEntity = storage.buildKey(with: key)
                var value = storage.buildElement(with: key)
                try value.apply(childData, exactly: exactly)
                storage.elements[keyEntity] = value
            }
        }
    }

    /// Collection does not respond for versions and raw value, and also payload.
    /// To change value version/raw can use enum, but use modified representer.
    override func _write(to transaction: Transaction, by node: Node) throws {
        /// skip the call of super (_RealtimeValue)
        let view = self.view.elements
        transaction.addReversion { [weak self] in
            self?.view.elements = view
        }
        self.view.removeAll()
        for (key: key, value: value) in storage.elements {
            try _write(value,
                       for: key,
                       by: (storage: node,
                            itms: Node(key: InternalKeys.items, parent: node.linksNode)),
                       in: transaction)
        }
    }

    public override func didSave(in database: RealtimeDatabase, in parent: Node, by key: String) {
        super.didSave(in: database, in: parent, by: key)
        if let node = self.node {
            view.didSave(in: database, in: node.linksNode)
            storage.sourceNode = node
        }
        storage.elements.forEach { $1.didSave(in: database, in: storage.sourceNode, by: $0.dbKey) }
    }

    public override func willRemove(in transaction: Transaction, from ancestor: Node) {
        super.willRemove(in: transaction, from: ancestor)
        if ancestor == node?.parent {
            transaction.removeValue(by: node!.linksNode)
        }
        storage.elements.forEach { $1.willRemove(in: transaction, from: ancestor) }
    }
    override public func didRemove(from ancestor: Node) {
        super.didRemove(from: ancestor)
        view.didRemove()
        storage.elements.values.forEach { $0.didRemove(from: storage.sourceNode) }
    }

    override public var debugDescription: String {
        return """
        \(type(of: self)): \(ObjectIdentifier(self).memoryAddress) {
            ref: \(node?.rootPath ?? "not referred"),
            synced: \(isSynced), keep: \(keepSynced),
            elements: \(view.map { (key: $0.dbKey, index: $0.priority) })
        }
        """
    }
}
extension AssociatedValues {
    public typealias Keys = __References<Key, RDItem>
    /// Returns `RealtimeCollection` that has itself storage
    ///
    /// Use it if you need only key objects, and you want to avoid allocating `Value` values.
    /// Else you can use usual `MapRealtimeCollection` collection.
    ///
    /// - Returns: `RealtimeCollection` of key objects
    public func keys() -> Keys {
        return Keys(
            in: view.node,
            options: [.database: database as Any, .elementsNode: storage.keysNode]
        )
    }
    /// Returns `RealtimeCollection` that has itself storage
    ///
    /// Use it if you need only value objects, and you want to avoid allocating `Key` values.
    /// Else you can use usual `MapRealtimeCollection` collection.
    ///
    /// - Returns: `RealtimeCollection` of key objects
    public func values() -> Values<Value> {
        return Values(
            in: node,
            options: [.database: database as Any, .elementBuilder: storage.elementBuilder]
        )
    }
}

// MARK: Mutating

extension AssociatedValues {
    /// Writes element to collection by database key of `Key` element.
    ///
    /// This method is available only if collection is **standalone**,
    /// otherwise use **func write(element:for:in:)**
    ///
    /// - Parameters:
    ///   - element: The element to write
    ///   - key: The element to get database key.
    public func set(element: Value, for key: Key) {
        guard isStandalone else { fatalError("This method is available only for standalone objects. Use method write(element:for:in:)") }
        guard storage.keysNode == key.node?.parent else { fatalError("Key is not contained in keys node") }
        guard element.node.map({ $0.parent == nil && $0.key == key.dbKey }) ?? true
            else { fatalError("Element is referred to incorrect location") }

        _ = view.insert(RDItem(value: element, key: key, priority: view.count, linkID: nil))
        storage.store(value: element, by: key)
    }

    /// Sets element to collection by database key of `Key` element,
    /// and writes a changes to transaction.
    ///
    /// If collection is standalone, use **func insert(element:at:)** instead.
    ///
    /// - Parameters:
    ///   - element: The element to write
    ///   - key: The element to get database key.
    ///   - transaction: Write transaction to keep the changes
    /// - Returns: A passed transaction or created inside transaction.
    @discardableResult
    public func write(element: Value, for key: Key, in transaction: Transaction? = nil) throws -> Transaction {
        guard isRooted, let database = self.database else { fatalError("This method is available only for rooted objects. Use method set(element:for:)") }
        guard storage.keysNode == key.node?.parent else { fatalError("Key is not contained in keys node") }
        guard element.node.map({ $0.parent == nil && $0.key == key.dbKey }) ?? true
            else { fatalError("Element is referred to incorrect location") }

        let transaction = transaction ?? Transaction(database: database)
        guard isSynced else {
            transaction.addPrecondition { [unowned transaction] promise in
                self.view._contains(with: key.dbKey) { contains, err in
                    if let e = err {
                        promise.reject(e)
                    } else if contains {
                        promise.reject(RealtimeError(
                            source: .collection,
                            description: "Element cannot be inserted, because already exists"
                        ))
                    } else {
                        do {
                            try self._write(element, for: key, in: transaction)
                            promise.fulfill()
                        } catch let e {
                            promise.reject(e)
                        }
                    }
                }
            }
            return transaction
        }

        guard !contains(valueBy: key) else {
            throw RealtimeError(source: .collection, description: "Value by key \(key) already exists. Replacing is not supported yet.")
        }

        try _write(element, for: key, in: transaction)
        return transaction
    }

    /// Removes element from collection if collection contains this element.
    ///
    /// - Parameters:
    ///   - element: The element to remove
    ///   - transaction: Write transaction or `nil`
    /// - Returns: A passed transaction or created inside transaction.
    @discardableResult
    public func remove(for key: Key, in transaction: Transaction? = nil) -> Transaction? {
        guard isRooted, let database = self.database else { fatalError("This method is available only for rooted objects") }
        guard storage.keysNode == key.node?.parent else { fatalError("Key is not contained in keys node") }
        let transaction = transaction ?? Transaction(database: database)
        guard isSynced else {
            transaction.addPrecondition { [unowned transaction] promise in
                self.view._item(for: key.dbKey) { item, err in
                    if let e = err {
                        promise.reject(e)
                    } else if let item = item {
                        self._remove(for: item, key: key, in: transaction)
                        promise.fulfill()
                    } else {
                        promise.reject(
                            RealtimeError(source: .collection, description: "Element is not found")
                        )
                    }
                }
            }
            return transaction
        }

        guard let item = view.first(where: { $0.dbKey == key.dbKey }) else {
            debugFatalError("Tries to remove not existed value")
            return transaction
        }

        _remove(for: item, key: key, in: transaction)
        return transaction
    }

    func _write(_ element: Value, for key: Key, in transaction: Transaction) throws {
        try _write(element, for: key,
                   by: (storage: node!, itms: view.node!), in: transaction)
    }

    func _write(_ element: Value, for key: Key,
                by location: (storage: Node, itms: Node), in transaction: Transaction) throws {
        let itemNode = location.itms.child(with: key.dbKey)
        let elementNode = location.storage.child(with: key.dbKey)
        var item = RDItem(value: element, key: key, priority: count, linkID: nil)

        transaction.addReversion({ [weak self] in
            self?.storage.elements.removeValue(forKey: key)
        })
        storage.store(value: element, by: key)

        if shouldLinking {
            let keyLink = key.node!.generate(linkTo: [itemNode, elementNode, elementNode.linksNode])
            transaction.addValue(keyLink.link.rdbValue, by: keyLink.node) /// add link to key object
            let valueLink = elementNode.generate(linkKeyedBy: keyLink.link.id, to: [itemNode, keyLink.node])
            item.linkID = valueLink.link.id
            transaction.addValue(valueLink.link.rdbValue, by: valueLink.node) /// add link to value object
        } else {
            let valueLink = elementNode.generate(linkTo: itemNode)
            item.linkID = valueLink.link.id
            transaction.addValue(valueLink.link.rdbValue, by: valueLink.node) /// add link to value object
        }
        transaction.addValue(item.rdbValue, by: itemNode) /// add item of element
        try transaction.set(element, by: elementNode) /// add element
    }

    func _remove(for item: RDItem, key: Key, in transaction: Transaction) {
        var removedElement: Value {
            if let element = storage.elements.removeValue(forKey: key) {
                return element
            } else {
                return storage.buildElement(with: item)
            }
        }
        let element = removedElement
        element.willRemove(in: transaction, from: storage.sourceNode)

        transaction.addReversion { [weak self] in
            self?.storage.elements[key] = element
        }
        transaction.removeValue(by: view.node!.child(with: item.dbKey)) // remove item element
        transaction.removeValue(by: storage.sourceNode.child(with: item.dbKey)) // remove element
        if let linkID = item.linkID {
            transaction.removeValue(by: key.node!.linksItemsNode.child(with: linkID)) // remove link from key object
        }
        transaction.addCompletion { result in
            if result {
                element.didRemove()
            }
        }
    }
}
