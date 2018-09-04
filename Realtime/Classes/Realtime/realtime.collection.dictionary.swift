//
//  AssociatedValues.swift
//  Realtime
//
//  Created by Denis Koryttsev on 16/03/2018.
//

import Foundation
import FirebaseDatabase

public extension RawRepresentable where RawValue == String {
    func dictionary<Key, Value>(from node: Node?, keys: Node) -> AssociatedValues<Key, Value> {
        return AssociatedValues(in: Node(key: rawValue, parent: node), options: [.keysNode: keys])
    }
    func dictionary<Key, Value>(from node: Node?, keys: Node, elementOptions: [ValueOption: Any]) -> AssociatedValues<Key, Value> {
        return dictionary(from: node, keys: keys, builder: { (node, options) in
            let compoundOptions = options.merging(elementOptions, uniquingKeysWith: { remote, local in remote })
            return Value(in: node, options: compoundOptions)
        })
    }
    func dictionary<Key, Value>(from node: Node?, keys: Node, builder: @escaping RCElementBuilder<Value>) -> AssociatedValues<Key, Value> {
        return AssociatedValues(in: Node(key: rawValue, parent: node), options: [.keysNode: keys, .elementBuilder: builder])
    }
}

public struct RCDictionaryStorage<K, V>: MutableRCStorage where K: HashableValue {
    public typealias Value = V
    var sourceNode: Node!
    let keysNode: Node
    let elementBuilder: (Node, [ValueOption: Any]) -> Value
    var elements: [K: Value] = [:]

    func buildElement(with key: K) -> V {
        return elementBuilder(sourceNode.child(with: key.dbKey), key.payload.map { [.payload: $0] } ?? [:])
    }

    mutating func store(value: Value, by key: K) { elements[for: key] = value }
    func storedValue(by key: K) -> Value? { return elements[for: key] }

    internal mutating func element(by key: String) -> (Key, Value) {
        guard let element = storedElement(by: key) else {
            let storeKey = Key(in: keysNode.child(with: key), options: [:])
            let value = buildElement(with: storeKey)
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
    public var keepSynced: Bool = false {
        didSet {
            guard oldValue != keepSynced else { return }
            if keepSynced { runObserving() }
            else { stopObserving() }
        }
    }

    let _view: AnyRealtimeCollectionView<SortedArray<RCItem>, AssociatedValues>

    /// Creates new instance associated with database node
    ///
    /// Available options:
    /// - keysNode(**required**): Database node where keys elements are located
    /// - database: Database reference
    /// - elementBuilder: Closure that calls to build elements lazily.
    ///
    /// - Parameter node: Node location for value
    /// - Parameter options: Dictionary of options
    public required init(in node: Node?, options: [ValueOption: Any]) {
        guard case let keysNode as Node = options[.keysNode] else { fatalError("Skipped required options") }
        guard keysNode.isRooted else { fatalError("Keys must has rooted location") }

        let viewParentNode = node.flatMap { $0.isRooted ? $0.linksNode : nil }
        let builder = options[.elementBuilder] as? RCElementBuilder<Value> ?? Value.init
        self.storage = RCDictionaryStorage(sourceNode: node, keysNode: keysNode, elementBuilder: builder, elements: [:])
        self._view = AnyRealtimeCollectionView(
            InternalKeys.items.property(
                from: viewParentNode,
                representer: Representer<SortedArray<RCItem>>(collection: Representer.realtimeData)
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

    public typealias Element = (key: Key, value: Value)

    private var shouldLinking = true // TODO: Fix it
    public func unlinked() -> AssociatedValues<Key, Value> { shouldLinking = false; return self }

    public func makeIterator() -> IndexingIterator<AssociatedValues> { return IndexingIterator(_elements: self) }
    public subscript(position: Int) -> Element { return storage.element(by: _view[position].dbKey) }
    public subscript(key: Key) -> Value? { return contains(valueBy: key) ? storage.object(for: key) : nil }
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
            _view.load(.just { _ in })
        }
        return added && removed && changed
    }

    public func stopObserving() {
        _view.source._stopObserving(.child(.added))
        _view.source._stopObserving(.child(.removed))
        _view.source._stopObserving(.child(.changed))
        if !_view.source.isObserved {
            _view.isSynced = false
        }
    }

    public lazy var changes: AnyListenable<RCEvent> = {
        guard _view.source.isRooted else {
            fatalError("Can`t get reference")
        }

        return Accumulator(repeater: .unsafe(), _view.source.dataObserver
            .filter({ [unowned self] e in self._view.isSynced || e.1 == .value })
            .map { [unowned self] (value) -> RCEvent in
                switch value.1 {
                case .value:
                    return .initial
                case .child(.added):
                    let item = try RCItem(data: value.0)
                    let index: Int = self._view.insertRemote(item)
                    return .updated((deleted: [], inserted: [index], modified: [], moved: []))
                case .child(.removed):
                    let item = try RCItem(data: value.0)
                    if let index = self._view.removeRemote(item) {
                        if let key = self.storage.elements.keys.first(where: { $0.dbKey == item.dbKey }) {
                            self.storage.elements.removeValue(forKey: key)
                        }
                        return .updated((deleted: [index], inserted: [], modified: [], moved: []))
                    } else {
                        throw RealtimeError(source: .coding, description: "Element has been removed in remote collection, but couldn`t find in local storage.")
                    }
                case .child(.changed):
                    let item = try RCItem(data: value.0)
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
                let keyEntity = Key(in: storage.keysNode.child(with: key.dbKey), options: [:])
                storage.elements[keyEntity] = try Value(data: childData, exactly: exactly)
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
        {
            ref: \(node?.rootPath ?? "not referred"),
            synced: \(isSynced), keep: \(keepSynced),
            elements: \(_view.value.map { (key: $0.dbKey, index: $0.index) })
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

        _ = _view.insert(RCItem(element: element, key: key.dbKey, linkID: "", index: _view.count))
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
        let needLink = shouldLinking
        let itemNode = location.itms.child(with: key.dbKey)
        let elementNode = location.storage.child(with: key.dbKey)
        let link = key.node!.generate(linkTo: [itemNode, elementNode, elementNode.linksNode])
        let item = RCItem(element: key, linkID: link.link.id, index: count)

        transaction.addReversion({ [weak self] in
            self?.storage.elements.removeValue(forKey: key)
        })
        storage.store(value: element, by: key)

        if needLink {
            transaction.addValue(link.link.rdbValue, by: link.node)
            let valueLink = elementNode.generate(linkKeyedBy: link.link.id,
                                                 to: [itemNode, link.node])
            transaction.addValue(valueLink.link.rdbValue, by: valueLink.node)
        }
        transaction.addValue(item.rdbValue, by: itemNode) /// add item of element
        try transaction.set(element, by: elementNode) /// add element
    }

    func _remove(for item: RCItem, key: Key, in transaction: Transaction) {
        var removedElement: Value {
            if let element = storage.elements.removeValue(forKey: key) {
                return element
            } else {
                return storage.buildElement(with: key)
            }
        }
        let element = removedElement
        element.willRemove(in: transaction, from: storage.sourceNode)

        transaction.addReversion { [weak self] in
            self?.storage.elements[key] = element
        }
        transaction.removeValue(by: _view.source.node!.child(with: item.dbKey)) // remove item element
        transaction.removeValue(by: storage.sourceNode.child(with: item.dbKey)) // remove element
        transaction.removeValue(by: key.node!.linksNode.child(with: item.linkID)) // remove link from key object
        transaction.addCompletion { result in
            if result {
                element.didRemove()
            }
        }
    }
}
