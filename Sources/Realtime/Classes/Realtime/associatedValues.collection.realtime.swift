//
//  AssociatedValues.swift
//  Realtime
//
//  Created by Denis Koryttsev on 16/03/2018.
//

import Foundation

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
    func dictionary<Key, Value: RealtimeValue>(in object: Object, keys: Node, elementOptions: [ValueOption: Any]) -> AssociatedValues<Key, Value> {
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
    public static let keysNode = ValueOption("realtime.dictionary.keys")
}

/// A type that can used as key in `AssociatedValues` collection.
public typealias HashableValue = Hashable & NewRealtimeValue

/// A Realtime database collection that stores elements in own database node as is,
/// as full objects, that keyed by database key of `Key` element.
public final class AssociatedValues<Key, Value>: _RealtimeValue, ChangeableRealtimeValue, RealtimeCollection
where Value: NewWritableRealtimeValue & RealtimeValueEvents, Key: HashableValue & Comparable {
    override var _hasChanges: Bool { return view._hasChanges }
    var storage: RCDictionaryStorage<Key, Value>
    internal private(set) var valueBuilder: RealtimeValueBuilder<Value>
    internal private(set) var keyBuilder: RealtimeValueBuilder<Key>

    public override var raw: RealtimeDatabaseValue? { return nil }
    public override var payload: RealtimeDatabaseValue? { return nil }
    public let view: SortedCollectionView<RDItem>
    public var isSynced: Bool { return view.isSynced }
    public override var isObserved: Bool { return view.isObserved }
    public override var canObserve: Bool { return view.canObserve }
    public var keepSynced: Bool {
        set { view.keepSynced = newValue }
        get { return view.keepSynced }
    }
    public lazy var changes: AnyListenable<RCEvent> = self.view.changes
        .map { [unowned self] (data, e) in
            switch e {
            case .initial: break
            case .updated(let deleted, _, _, _):
                if !deleted.isEmpty {
                    if deleted.count == 1 {
                        self.didRemoveElement(by: data.key!)
                    } else {
                        data.forEach({ child in
                            self.didRemoveElement(by: child.key!)
                        })
                    }
                }
            }
            return e
        }
        .shared(connectionLive: .continuous)
        .asAny()
    public var dataExplorer: RCDataExplorer = .view(ascending: false) {
        didSet { view.didChange(dataExplorer: dataExplorer) }
    }

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
        guard
            case let keysNode as Node = options[.keysNode],
            let keyBuilder = options[.keyBuilder] as? RCElementBuilder<Key>,
            let valueBuilder = options[.elementBuilder] as? RCElementBuilder<Value>
        else { fatalError("Skipped required options") }
        guard keysNode.isRooted else { fatalError("Keys must has rooted location") }

        let viewParentNode = node.flatMap { $0.isRooted ? $0.linksNode : nil }
        self.valueBuilder = RealtimeValueBuilder(spaceNode: node, impl: valueBuilder)
        self.keyBuilder = RealtimeValueBuilder(spaceNode: keysNode, impl: keyBuilder)
        self.storage = RCDictionaryStorage()
        self.view = SortedCollectionView(in: Node(key: InternalKeys.items, parent: viewParentNode), options: RealtimeValueOptions(database: options[.database] as? RealtimeDatabase))
        super.init(in: node, options: RealtimeValueOptions(from: options))
    }

    /// Currently no available
    public required convenience init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        #if DEBUG
        fatalError("AssociatedValues does not supported init(data:event:) yet. Use `init(data:event:options:)` instead")
        #else
        throw RealtimeError(source: .collection, description: "AssociatedValues does not supported init(data:event:) yet.")
        #endif
    }

    // MARK: Implementation

    public typealias Element = (key: Key, value: Value)

    private var shouldLinking = true // TODO: Fix it
    public func unlinked() -> AssociatedValues<Key, Value> { shouldLinking = false; return self }

    public func makeIterator() -> IndexingIterator<AssociatedValues> { return IndexingIterator(_elements: self) } // iterator is not safe
    public subscript(position: Int) -> Element {
        let item = view[position]
        guard let element = storage.element(for: item.dbKey) else {
            let key = keyBuilder.buildKey(with: item)
            let value = valueBuilder.buildValue(with: item)
            storage.set(value: value, for: key)
            return (key, value)
        }
        return element
    }
    public subscript(key: Key) -> Value? {
        guard let v = storage.value(for: key) else {
            guard let item = view.first(where: { $0.dbKey == key.dbKey }) else {
                return nil
            }
            let value = valueBuilder.buildValue(with: item)
            storage.set(value: value, for: key)
            return value
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
            return storage.value(for: key) != nil
        } else {
            return view.contains(where: { $0.dbKey == key.dbKey })
        }
    }

    var _snapshot: (RealtimeDataProtocol, DatabaseDataEvent)?
    override public func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        guard view.isSynced else {
            _snapshot = (data, event)
            return
        }
        _snapshot = nil
        try view.forEach { key in
            guard data.hasChild(key.dbKey) else {
                if event == .value, let contained = storage.first(where: { $0.0.dbKey == key.dbKey }) { _ = storage.remove(for: contained.key) }
                return
            }
            let childData = data.child(forPath: key.dbKey)
            if var element = storage.first(where: { $0.0.dbKey == key.dbKey })?.value {
                try element.apply(childData, event: event)
            } else {
                let keyEntity = keyBuilder.buildKey(with: key)
                var value = valueBuilder.buildValue(with: key)
                try value.apply(childData, event: event)
                storage.set(value: value, for: keyEntity)
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
        for (key: key, value: value) in storage {
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
            valueBuilder.spaceNode = node
        }
        storage.forEach { $0.value.didSave(in: database, in: valueBuilder.spaceNode, by: $0.key.dbKey) }
    }

    public override func willRemove(in transaction: Transaction, from ancestor: Node) {
        super.willRemove(in: transaction, from: ancestor)
        if ancestor == node?.parent {
            /// remove view if remove action is applying on collection
            transaction.delete(view)
        }
        storage.forEach { $1.willRemove(in: transaction, from: ancestor) }
    }
    override public func didRemove(from ancestor: Node) {
        super.didRemove(from: ancestor)
        view.didRemove()
        storage.forEach { $0.value.didRemove(from: valueBuilder.spaceNode) }
    }

    private func didRemoveElement(by key: String) {
        _ = self.storage
            .element(for: key)
            .map({ self.storage.remove(for: $0.key) })
    }

    override public var debugDescription: String {
        return """
        \(type(of: self)): \(ObjectIdentifier(self).memoryAddress) {
            ref: \(node?.absolutePath ?? "not referred"),
            synced: \(isSynced), keep: \(keepSynced),
            elements: \(view.map { (key: $0.dbKey, index: $0.priority) })
        }
        """
    }
}
extension AssociatedValues {
    public typealias Keys = RepresentableCollection<Key, RDItem>
    /// Returns `RealtimeCollection` that has itself storage
    ///
    /// Use it if you need only key objects, and you want to avoid allocating `Value` values.
    /// Else you can use usual `MapRealtimeCollection` collection.
    ///
    /// - Returns: `RealtimeCollection` of key objects
    public func keys() -> Keys {
        return Keys(
            view: view,
            options: RepresentableCollection<Key, RDItem>.Options(
                baseOptions: RealtimeValueOptions(database: database),
                builder: keyBuilder.buildKey(with:)
            )
        )
    }
    /// Returns `RealtimeCollection` that has itself storage
    ///
    /// Use it if you need only value objects, and you want to avoid allocating `Key` values.
    /// Else you can use usual `MapRealtimeCollection` collection.
    ///
    /// - Returns: `RealtimeCollection` of key objects
    public func values() -> Values<Value> {
        // TODO: avoid using `Values` type because it is mutable
        return Values(
            in: node,
            options: [.database: database as Any,
                      .elementBuilder: valueBuilder.impl]
        )
    }
}

// MARK: Mutating

extension AssociatedValues {
    public func removeAll() {
        guard isStandalone else { return }
        view.removeAll()
        storage.removeAll()
    }

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
        guard keyBuilder.spaceNode == key.node?.parent else { fatalError("Key is not contained in keys node") }
        guard element.node.map({ $0.parent == nil && $0.key == key.dbKey }) ?? true
            else { fatalError("Element is referred to incorrect location") }

        var item = RDItem(key: key, value: element)
        item.priority = Int64(view.count)
        _ = view.insert(item)
        storage.set(value: element, for: key)
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
        guard keyBuilder.spaceNode == key.node?.parent else { fatalError("Key is not contained in keys node") }
        guard element.node.map({ $0.parent == nil && $0.key == key.dbKey }) ?? true
            else { fatalError("Element is referred to incorrect location") }

        let transaction = transaction ?? Transaction(database: database)
        guard isSynced else {
            transaction.addPrecondition { [unowned transaction] promise in
                self.view._contains(with: key.dbKey) { contains, err in
                    if let e = err {
                        promise.reject(RealtimeError(external: e, in: .collection))
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
    public func remove(for key: Key, in transaction: Transaction? = nil) -> Transaction {
        guard isRooted, let database = self.database else { fatalError("This method is available only for rooted objects") }
        guard keyBuilder.spaceNode == key.node?.parent else { fatalError("Key is not contained in keys node") }
        let transaction = transaction ?? Transaction(database: database)
        guard isSynced else {
            transaction.addPrecondition { [unowned transaction] promise in
                self.view._item(for: key.dbKey) { item, err in
                    if let e = err {
                        promise.reject(RealtimeError(external: e, in: .collection))
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
        var item = RDItem(key: key, value: element)
        item.priority = Int64(count)

        transaction.addReversion({ [weak self] in
            _ = self?.storage.remove(for: key)
        })
        storage.set(value: element, for: key)

        if shouldLinking {
            let keyLink = key.node!.generate(linkTo: [itemNode, elementNode, elementNode.linksNode])
            transaction.addValue(try keyLink.link.defaultRepresentation(), by: keyLink.node) /// add link to key object
            let valueLink = elementNode.generate(linkKeyedBy: keyLink.link.id, to: [itemNode, keyLink.node])
            item.linkID = valueLink.link.id
            transaction.addValue(try valueLink.link.defaultRepresentation(), by: valueLink.node) /// add link to value object
        } else {
            let valueLink = elementNode.generate(linkTo: itemNode)
            item.linkID = valueLink.link.id
            transaction.addValue(try valueLink.link.defaultRepresentation(), by: valueLink.node) /// add link to value object
        }
        try item.write(to: transaction, by: itemNode) /// add item of element
        try transaction.set(element, by: elementNode) /// add element
    }

    func _remove(for item: RDItem, key: Key, in transaction: Transaction) {
        var removedValue: Value {
            if let element = storage.remove(for: key) {
                return element
            } else {
                return valueBuilder.buildValue(with: item)
            }
        }
        let value = removedValue
        value.willRemove(in: transaction, from: valueBuilder.spaceNode)

        transaction.addReversion { [weak self] in
            self?.storage.set(value: value, for: key)
        }
        transaction.removeValue(by: view.node!.child(with: item.dbKey)) // remove item element
        transaction.removeValue(by: valueBuilder.spaceNode.child(with: item.dbKey)) // remove element
        if let linkID = item.linkID {
            transaction.removeValue(by: key.node!.linksItemsNode.child(with: linkID)) // remove link from key object
        }
        transaction.addCompletion { result in
            if result {
                value.didRemove()
            }
        }
    }
}

public final class ExplicitAssociatedValues<Key, Value>: _RealtimeValue, ChangeableRealtimeValue, RealtimeCollection
where Value: WritableRealtimeValue & Comparable, Key: HashableValue & Comparable {
    override var _hasChanges: Bool { return view._hasChanges }
    var storage: RCDictionaryStorage<Key, Value>
    internal private(set) var keyBuilder: RealtimeValueBuilder<Key>

    public override var raw: RealtimeDatabaseValue? { return nil }
    public override var payload: RealtimeDatabaseValue? { return nil }
    public let view: SortedCollectionView<Value>
    public var isSynced: Bool { return view.isSynced }
    public override var isObserved: Bool { return view.isObserved }
    public override var canObserve: Bool { return view.canObserve }
    public var keepSynced: Bool {
        set { view.keepSynced = newValue }
        get { return view.keepSynced }
    }
    public lazy var changes: AnyListenable<RCEvent> = self.view.changes
        .map { [unowned self] (data, e) in
            switch e {
            case .initial: break
            case .updated(let deleted, _, let modified, _):
                if !deleted.isEmpty {
                    if deleted.count == 1 {
                        self.didRemoveElement(by: data.key!)
                    } else {
                        data.forEach({ child in
                            self.didRemoveElement(by: child.key!)
                        })
                    }
                }
                modified.forEach({ (i) in
                    let value = self.view[i]
                    self.storage
                        .element(for: value.dbKey)
                        .map({ self.storage.set(value: value, for: $0.key) })
                })
            }
            return e
        }
        .shared(connectionLive: .continuous)
        .asAny()
    public var dataExplorer: RCDataExplorer = .view(ascending: false) {
        didSet { view.didChange(dataExplorer: dataExplorer) }
    }

    /// Creates new instance associated with database node
    ///
    /// Available options:
    /// - keysNode(**required**): Database node where keys elements are located
    /// - database: Database reference
    /// - keyBuilder: Closure that calls to build key lazily.
    ///
    /// - Parameter node: Node location for value
    /// - Parameter options: Dictionary of options
    public required init(in node: Node?, options: [ValueOption: Any]) {
        guard case let keysNode as Node = options[.keysNode], let keyBuilder = options[.keyBuilder] as? RCElementBuilder<Key> else { fatalError("Skipped required options") }
        guard keysNode.isRooted else { fatalError("Keys must has rooted location") }

        self.keyBuilder = RealtimeValueBuilder(spaceNode: keysNode, impl: keyBuilder)
        self.storage = RCDictionaryStorage()
        self.view = SortedCollectionView(in: node, options: RealtimeValueOptions(database: options[.database] as? RealtimeDatabase))
        super.init(in: node, options: RealtimeValueOptions(from: options))
    }

    /// Currently no available
    public required convenience init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        #if DEBUG
        fatalError("AssociatedValues does not supported init(data:event:) yet.")
        #else
        throw RealtimeError(source: .collection, description: "AssociatedValues does not supported init(data:event:) yet.")
        #endif
    }

    public convenience init(data: RealtimeDataProtocol, event: DatabaseDataEvent, keysNode: Node) throws {
        self.init(in: data.node, options: [.keysNode: keysNode, .database: data.database as Any])
        try apply(data, event: event)
    }

    // MARK: Implementation

    public typealias Element = (key: Key, value: Value)

    public func makeIterator() -> IndexingIterator<ExplicitAssociatedValues> {
        return IndexingIterator(_elements: self)
    } // iterator is not safe
    public subscript(position: Int) -> Element {
        if isStandalone {
            return storage[position]
        } else {
            let value = view[position]
            guard let element = storage.element(for: value.dbKey) else {
                // TODO: Payload does not write, and values are not always object
//                let keyPayload = value.payload?[InternalKeys.key.rawValue] as? [String: RealtimeDataValue]
                let key = keyBuilder.build(with: value.dbKey, options: [:])
//                    .rawValue: keyPayload?[InternalKeys.raw.rawValue] as Any,
//                    .payload: keyPayload?[InternalKeys.payload.rawValue] as Any
//                ])
                storage.set(value: value, for: key)
                return (key, value)
            }
            return (element.key, value)
        }
    }
    public subscript(key: Key) -> Value? {
        guard let v = storage.value(for: key) else {
            guard let value = view.first(where: { $0.dbKey == key.dbKey }) else {
                return nil
            }
            storage.set(value: value, for: key)
            return value
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
            return storage.value(for: key) != nil
        } else {
            return view.contains(where: { $0.dbKey == key.dbKey })
        }
    }

    override public func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        try super.apply(data, event: event)
        try view.apply(data, event: event)
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
        for (key: key, value: value) in storage {
            try transaction._set(value, by: Node(key: key.dbKey, parent: node))
        }
    }
    public override func didSave(in database: RealtimeDatabase, in parent: Node, by key: String) {
        super.didSave(in: database, in: parent, by: key)
        view.didSave(in: database, in: parent, by: key)
    }
    override public func didRemove(from ancestor: Node) {
        super.didRemove(from: ancestor)
        view.didRemove()
    }

    private func didRemoveElement(by key: String) {
        _ = self.storage
            .element(for: key)
            .map({ self.storage.remove(for: $0.key) })
    }

    override public var debugDescription: String {
        return """
        \(type(of: self)): \(ObjectIdentifier(self).memoryAddress) {
        ref: \(node?.absolutePath ?? "not referred"),
        synced: \(isSynced), keep: \(keepSynced),
        elements: \(view.map { $0.dbKey })
        }
        """
    }
}
extension ExplicitAssociatedValues {
    public func value(for key: Key, completion: @escaping (Value?, Error?) -> Void) {
        view._item(for: key.dbKey, completion: completion)
    }

    public func removeAll() {
        view.removeAll()
        storage.removeAll()
    }

    @discardableResult
    public func set(_ value: Value, for key: Key) -> Int {
        guard isStandalone else { fatalError("Cannot be written, because collection is rooted") }
        storage.set(value: value, for: key)
        guard let index = view.index(of: value) else { return view.insert(value) }
        return index
    }
    @discardableResult
    public func remove(at index: Int) -> Value {
        guard isStandalone else { fatalError("Cannot be written, because collection is rooted") }
        let value = view.remove(at: index)
        // TODO: Method is not correct, need use ordered storage
        if let node = value.node, let key = storage.element(for: node.key)?.key {
            _ = storage.remove(for: key)
        }
        return value
    }
    @discardableResult
    public func remove(for key: Key, in transaction: Transaction? = nil) -> Transaction {
        guard isRooted else { fatalError("Cannot be written, because collection is not rooted") }
        guard let valueNode = view.first(where: { $0.dbKey == key.dbKey }).node else { fatalError("Value is not found") }

        let transaction = transaction ?? Transaction()
        transaction.removeValue(by: valueNode)
        return transaction
    }
    @discardableResult
    public func remove(at index: Int, in transaction: Transaction?) -> Transaction {
        guard isRooted else { fatalError("Cannot be written, because collection is not rooted") }
        guard let valueNode = view[index].node else { fatalError("Value is not found") }

        let transaction = transaction ?? Transaction()
        transaction.removeValue(by: valueNode)
        return transaction
    }
    public func write(_ value: Value, for key: Key, in transaction: Transaction) throws {
        guard let parentNode = self.node, parentNode.isRooted
            else { fatalError("Cannot be written, because collection is not rooted") }
        try transaction._set(
            value,
            by: Node(key: key.dbKey ?? transaction.database.generateAutoID(), parent: parentNode)
        )
    }

    public func insertionIndex(for value: Value) -> Int {
        return view.elements.insertionIndex(for: value)
    }
}

extension AnyRealtimeCollection: RealtimeCollectionView {}

class KeyedCollection<Key, Value>: _RealtimeValue, RealtimeCollection where Key: NewRealtimeValue, Value: RealtimeValue {
    typealias View = AnyRealtimeCollection<Key>
    typealias Element = (key: Key, value: Value)
    var storage: RCKeyValueStorage<Value> = [:]

    public override var raw: RealtimeDatabaseValue? { return nil }
    public override var payload: RealtimeDatabaseValue? { return nil }
    public let view: View
    public var isSynced: Bool { return view.isSynced }
    public override var isObserved: Bool { return view.isObserved }
    public override var canObserve: Bool { return view.canObserve }
    var dataExplorer: RCDataExplorer {
        set { view.dataExplorer = newValue }
        get { return view.dataExplorer }
    }
    var keepSynced: Bool {
        set { view.keepSynced = newValue }
        get { return view.keepSynced }
    }
    lazy var changes: AnyListenable<RCEvent> = self.view.changes

    required init(in node: Node?, options: [ValueOption : Any]) {
        guard case let keys as AnyRealtimeCollection<Key> = options[.keysNode] else { fatalError("Unexpected parameter") }
        self.view = keys
        super.init(in: node, options: RealtimeValueOptions(from: options))
    }

    public required init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        fatalError("init(data:event:) has not been implemented")
    }

    subscript(position: RealtimeCollectionIndex) -> Element {
        let key = view[position]
        if let value = storage.value(for: key.dbKey) {
            return (key, value)
        } else {
            let value = Value(in: Node(key: key.dbKey, parent: node), options: [:])
            storage.set(value: value, for: key.dbKey)
            return (key, value)
        }
    }
    public subscript(key: Key) -> Value? {
        guard let v = storage.value(for: key.dbKey) else {
            guard view.contains(key) else { return nil }
            let value = Value(in: Node(key: key.dbKey, parent: node), options: [:])
            storage.set(value: value, for: key.dbKey)
            return value
        }
        return v
    }
}
