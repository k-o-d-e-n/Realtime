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

struct RDItem: Hashable, Comparable, DatabaseKeyRepresentable, RealtimeDataRepresented, RealtimeDataValueRepresented {
    var rcItem: RCItem
    let keyPayload: RealtimeValuePayload

    var dbKey: String! { return rcItem.dbKey }
    var priority: Int { return rcItem.priority }
    var linkID: String? {
        set { rcItem.linkID = newValue }
        get { return rcItem.linkID }
    }

    init<V: RealtimeValue, K: RealtimeValue>(value: V, key: K, priority: Int, linkID: String?) {
        self.rcItem = RCItem(element: value, key: key.dbKey, priority: priority, linkID: linkID)
        self.keyPayload = RealtimeValuePayload((key.version, key.raw), key.payload)
    }

    init(data: RealtimeDataProtocol, exactly: Bool) throws {
        self.rcItem = try RCItem(data: data, exactly: exactly)
        let keyData = InternalKeys.key.child(from: data)
        self.keyPayload = RealtimeValuePayload(
            try (InternalKeys.modelVersion.map(from: keyData), InternalKeys.raw.map(from: keyData)),
            try InternalKeys.payload.map(from: keyData)
        )
    }

    var rdbValue: RealtimeDataValue {
        var value: [String: RealtimeDataValue] = [:]
        value[InternalKeys.value.rawValue] = databaseValue(of: rcItem.payload)
        value[InternalKeys.key.rawValue] = databaseValue(of: keyPayload)
        value[InternalKeys.link.rawValue] = rcItem.linkID
        value[InternalKeys.index.rawValue] = rcItem.priority

        return value
    }

    var hashValue: Int { return dbKey.hashValue }

    static func ==(lhs: RDItem, rhs: RDItem) -> Bool {
        return lhs.dbKey == rhs.dbKey
    }

    static func < (lhs: RDItem, rhs: RDItem) -> Bool {
        if lhs.priority < rhs.priority {
            return true
        } else if lhs.priority > rhs.priority {
            return false
        } else {
            return lhs.dbKey < rhs.dbKey
        }
    }
}

public struct RCDictionaryStorage<K, V>: MutableRCStorage where K: HashableValue {
    public typealias Value = V
    var sourceNode: Node!
    let keysNode: Node
    let elementBuilder: (Node, [ValueOption: Any]) -> Value
    let keyBuilder: (Node, [ValueOption: Any]) -> Key
    var elements: [K: Value] = [:]

    func buildElement(with item: RDItem) -> V {
        return elementBuilder(sourceNode.child(with: item.dbKey), [.systemPayload: item.rcItem.payload.system,
                                                                   .userPayload: item.rcItem.payload.user as Any])
    }

    func buildKey(with item: RDItem) -> K {
        return keyBuilder(keysNode.child(with: item.dbKey), [.systemPayload: item.keyPayload.system,
                                                             .userPayload: item.keyPayload.user as Any])
    }

    mutating func store(value: Value, by key: K) { elements[for: key] = value }
    func storedValue(by key: K) -> Value? { return elements[for: key] }

    internal mutating func element(by key: RDItem) -> (Key, Value) {
        guard let element = storedElement(by: key.dbKey) else {
            let storeKey = buildKey(with: key)
            let value = buildElement(with: key)
            store(value: value, by: storeKey)

            return (storeKey, value)
        }

        return element
    }
    fileprivate func storedElement(by key: String) -> (Key, Value)? {
        return elements.first(where: { $0.key.dbKey == key })
    }
}

extension ValueOption {
    static let keysNode = ValueOption("realtime.dictionary.keys")
}

/// A type that can used as key in `AssociatedValues` collection.
public typealias HashableValue = Hashable & RealtimeValue

/// A Realtime database collection that stores elements in own database node as is,
/// as full objects, that keyed by database key of `Key` element.
public final class AssociatedValues<Key, Value>: _RealtimeValue, ChangeableRealtimeValue, RC
where Value: WritableRealtimeValue & RealtimeValueEvents, Key: HashableValue {
    public override var version: Int? { return nil }
    public override var raw: RealtimeDataValue? { return nil }
    public override var payload: [String : RealtimeDataValue]? { return nil }
    override var _hasChanges: Bool { return isStandalone && storage.elements.count > 0 }
    public var view: RealtimeCollectionView { return _view }
    public internal(set) var storage: RCDictionaryStorage<Key, Value>
    public var isSynced: Bool { return _view.isSynced }
    public override var isObserved: Bool { return _view.source.isObserved }
    public override var canObserve: Bool { return _view.source.canObserve }
    public var keepSynced: Bool = false {
        didSet {
            guard oldValue != keepSynced else { return }
            if keepSynced { runObserving() }
            else { stopObserving() }
        }
    }

    let _view: AnyRealtimeCollectionView<SortedArray<RDItem>, AssociatedValues>

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
        self._view = AnyRealtimeCollectionView(
            Property<SortedArray<RDItem>>(
                in: Node(key: InternalKeys.items, parent: viewParentNode),
                options: [
                    .database: options[.database] as Any,
                    .representer: Representer<SortedArray<RDItem>>(collection: Representer.realtimeData).requiredProperty()
                ]
            ).defaultOnEmpty()
        )
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

    /// not implemented, currently returns values
    public func keys() -> References<Key> {
        fatalError("In future release")
        return References(
            in: _view.source.node,
            options: [.database: database as Any, .elementsNode: storage.keysNode]
        )
    }

    public func values() -> Values<Value> {
        return Values(
            in: node,
            options: [.database: database as Any, .elementBuilder: storage.elementBuilder]
        )
    }

    public typealias Element = (key: Key, value: Value)

    private var shouldLinking = true // TODO: Fix it
    public func unlinked() -> AssociatedValues<Key, Value> { shouldLinking = false; return self }

    public func makeIterator() -> IndexingIterator<AssociatedValues> { return IndexingIterator(_elements: self) } // iterator is not safe
    public subscript(position: Int) -> Element { return storage.element(by: _view[position]) }
    public subscript(key: Key) -> Value? {
        guard let v = storage.storedValue(by: key) else {
            guard let i = _view.index(where: { $0.dbKey == key.dbKey }) else {
                return nil
            }
            return storage.element(by: _view[i]).1
        }
        return v
    }
    public var startIndex: Int { return _view.startIndex }
    public var endIndex: Int { return _view.endIndex }
    public func index(after i: Int) -> Int { return _view.index(after: i) }
    public func index(before i: Int) -> Int { return _view.index(before: i) }
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
            return _view.contains(where: { $0.dbKey == key.dbKey })
        }
    }

    @discardableResult
    public func runObserving() -> Bool {
        let isNeedLoadFull = !self._view.source.isObserved
        let added = _view.source._runObserving(.child(.added))
        let removed = _view.source._runObserving(.child(.removed))
        let changed = _view.source._runObserving(.child(.changed))
        if isNeedLoadFull {
            _view.load(.just { [weak self] e in
                self.map { this in
                    this._view.isSynced = this._view.source.isObserved && e == nil
                }
            })
        }
        return added && removed && changed
    }

    public func stopObserving() {
        // checks 'added' only, can lead to error
        guard !keepSynced || (observing[.child(.added)].map({ $0.counter > 1 }) ?? true) else {
            return
        }

        _view.source._stopObserving(.child(.added))
        _view.source._stopObserving(.child(.removed))
        _view.source._stopObserving(.child(.changed))
        if !_view.source.isObserved {
            _view.isSynced = false
        }
    }

    public lazy var changes: AnyListenable<RCEvent> = {
        return Accumulator(repeater: .unsafe(), _view.source.dataObserver
            .filter({ [unowned self] e in self._view.isSynced || e.1 == .value })
            .map { [unowned self] (value) -> RCEvent in
                switch value.1 {
                case .value:
                    return .initial
                case .child(.added):
                    let item = try RDItem(data: value.0)
                    let index: Int = self._view.insertRemote(item)
                    return .updated((deleted: [], inserted: [index], modified: [], moved: []))
                case .child(.removed):
                    let item = try RDItem(data: value.0)
                    if let index = self._view.removeRemote(item) {
                        if let key = self.storage.elements.keys.first(where: { $0.dbKey == item.dbKey }) {
                            self.storage.elements.removeValue(forKey: key)
                        }
                        return .updated((deleted: [index], inserted: [], modified: [], moved: []))
                    } else {
                        throw RealtimeError(source: .coding, description: "Element has been removed in remote collection, but couldn`t find in local storage.")
                    }
                case .child(.changed):
                    let item = try RDItem(data: value.0)
                    let indexes = self._view.moveRemote(item)
                    return .updated((deleted: [], inserted: [], modified: [], moved: indexes.map { [$0] } ?? []))
                default:
                    throw RealtimeError(source: .collection, description: "Unexpected data event: \(value)")
                }
            })
            .asAny()
    }()

    var _snapshot: (RealtimeDataProtocol, Bool)?
    override public func apply(_ data: RealtimeDataProtocol, exactly: Bool) throws {
        guard _view.isSynced else {
            _snapshot = (data, exactly)
            return
        }
        _snapshot = nil
        try _view.forEach { key in
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
        let view = _view.value
        transaction.addReversion { [weak self] in
            self?._view.source <== view
        }
        _view.removeAll()
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
            _view.source.didSave(in: database, in: node.linksNode)
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
        _view.source.didRemove()
        storage.elements.values.forEach { $0.didRemove(from: storage.sourceNode) }
    }

    override public var debugDescription: String {
        return """
        \(type(of: self)): \(ObjectIdentifier(self).memoryAddress) {
            ref: \(node?.rootPath ?? "not referred"),
            synced: \(isSynced), keep: \(keepSynced),
            elements: \(_view.value.map { (key: $0.dbKey, index: $0.priority) })
        }
        """
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

        _ = _view.insert(RDItem(value: element, key: key, priority: _view.count, linkID: nil))
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
                self._view._contains(with: key.dbKey) { contains, err in
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
                self._view._item(for: key.dbKey) { item, err in
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

        guard let item = _view.first(where: { $0.dbKey == key.dbKey }) else {
            debugFatalError("Tries to remove not existed value")
            return transaction
        }

        _remove(for: item, key: key, in: transaction)
        return transaction
    }

    func _write(_ element: Value, for key: Key, in transaction: Transaction) throws {
        try _write(element, for: key,
                   by: (storage: node!, itms: _view.source.node!), in: transaction)
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
        transaction.removeValue(by: _view.source.node!.child(with: item.dbKey)) // remove item element
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
