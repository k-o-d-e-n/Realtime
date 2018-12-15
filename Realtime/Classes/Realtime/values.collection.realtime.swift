//
//  Values.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 18/02/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation
import FirebaseDatabase

public extension RawRepresentable where RawValue == String {
    func values<Element>(in object: Object) -> Values<Element> {
        return Values(in: Node(key: rawValue, parent: object.node), options: [.database: object.database as Any])
    }
    func values<Element>(in object: Object, elementOptions: [ValueOption: Any]) -> Values<Element> {
        let db = object.database as Any
        return values(in: object, builder: { (node, options) in
            var compoundOptions = options.merging(elementOptions, uniquingKeysWith: { remote, local in remote })
            compoundOptions[.database] = db
            return Element(in: node, options: compoundOptions)
        })
    }
    func values<Element>(in object: Object, builder: @escaping RCElementBuilder<Element>) -> Values<Element> {
        return Values(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .elementBuilder: builder
            ]
        )
    }
}
public extension Node {
    func array<Element>() -> Values<Element> {
        return Values(in: self)
    }
}

public extension Values {
    convenience init<E>(in node: Node?, elements: References<E>) {
        self.init(in: node,
                  options: [.elementBuilder: elements.builder.impl],
                  view: elements.view)
    }
}

/// A Realtime database collection that stores elements in own database node as is, as full objects.
public final class Values<Element>: _RealtimeValue, ChangeableRealtimeValue, RealtimeCollection where Element: WritableRealtimeValue & RealtimeValueEvents {
    /// Stores collection values and responsible for lazy initialization elements
    internal(set) var storage: RCKeyValueStorage<Element>
    internal private(set) var builder: RealtimeValueBuilder<Element>
    override var _hasChanges: Bool { return view._hasChanges }

    public override var raw: RealtimeDataValue? { return nil }
    public override var payload: [String : RealtimeDataValue]? { return nil }
    /// Stores an abstract elements
    public let view: SortedCollectionView<RCItem> 
    public var isSynced: Bool { return view.isSynced }
    public override var isObserved: Bool { return view.isObserved }
    public override var canObserve: Bool { return view.canObserve }
    public var keepSynced: Bool {
        set { view.keepSynced = newValue }
        get { return view.keepSynced }
    }
    public var changes: AnyListenable<RCEvent> { return view.changes }

    /// Create new instance with default element builder
    ///
    /// - Parameter node: Database node
    public convenience required init(in node: Node?) {
        self.init(in: node, options: [:])
    }
    /// Creates new instance associated with database node
    ///
    /// Available options:
    /// - database: Database reference
    /// - elementBuilder: Closure that calls to build elements lazily.
    ///
    /// - Parameter node: Node location for value
    /// - Parameter options: Dictionary of options
    public required convenience init(in node: Node?, options: [ValueOption: Any]) {
        let viewParentNode = node.flatMap { $0.isRooted ? $0.linksNode : nil }
        let viewNode = Node(key: InternalKeys.items, parent: viewParentNode)
        let view = SortedCollectionView<RCItem>(in: viewNode, options: [.database: options[.database] as Any])
        self.init(in: node, options: options, view: view)
    }

    public required init(data: RealtimeDataProtocol, exactly: Bool) throws {
        let node = data.node
        let viewParentNode = node.flatMap { $0.isRooted ? $0.linksNode : nil }
        let viewNode = Node(key: InternalKeys.items, parent: viewParentNode)
        self.builder = RealtimeValueBuilder(spaceNode: node, impl: Element.init)
        self.storage = RCKeyValueStorage()
        self.view = SortedCollectionView(in: viewNode, options: [.database: data.database as Any])
        try super.init(data: data, exactly: exactly)
    }

    init(in node: Node?, options: [ValueOption: Any], view: SortedCollectionView<RCItem>) {
        let builder = options[.elementBuilder] as? RCElementBuilder<Element> ?? Element.init
        self.builder = RealtimeValueBuilder(spaceNode: node, impl: builder)
        self.storage = RCKeyValueStorage()
        self.view = view
        super.init(in: node, options: options)
    }

    // Implementation

    public subscript(position: Int) -> Element {
        let item = view[position]
        guard let element = storage.value(for: item.dbKey) else {
            let element = builder.build(with: item)
            storage.set(value: element, for: item.dbKey)
            return element
        }
        return element
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
                if exactly { storage.remove(for: key.dbKey) }
                return
            }
            let childData = data.child(forPath: key.dbKey)
            if var element = storage[key.dbKey] {
                try element.apply(childData, exactly: exactly)
            } else {
                var value = builder.build(with: key)
                try value.apply(childData, exactly: exactly)
                storage[key.dbKey] = value
            }
        }
    }

    /// Collection does not respond for versions and raw value, and also payload.
    /// To change value version/raw can use enum, but use modified representer.
    override func _write(to transaction: Transaction, by node: Node) throws {
        /// skip the call of super (_RealtimeValue)
        let elems = storage
        storage.removeAll()
        let view = self.view.elements
        transaction.addReversion { [weak self] in
            self?.view.elements = view
        }
        self.view.removeAll()
        for item in view {
            try _write(elems[item.dbKey]!,
                       with: item.priority,
                       by: (storage: node,
                            itms: Node(key: InternalKeys.items, parent: node.linksNode)),
                       in: transaction)
        }
    }

    public override func didSave(in database: RealtimeDatabase, in parent: Node, by key: String) {
        super.didSave(in: database, in: parent, by: key)
        if let node = self.node {
            view.didSave(in: database, in: node.linksNode)
            builder.spaceNode = node
        }
        storage.forEach { $0.value.didSave(in: database, in: builder.spaceNode, by: $0.key) }
    }

    public override func willRemove(in transaction: Transaction, from ancestor: Node) {
        super.willRemove(in: transaction, from: ancestor)
        if ancestor == node?.parent {
            transaction.removeValue(by: node!.linksNode)
        }
        storage.values.forEach { $0.willRemove(in: transaction, from: ancestor) }
    }
    override public func didRemove(from ancestor: Node) {
        super.didRemove(from: ancestor)
        view.didRemove()
        storage.values.forEach { $0.didRemove(from: builder.spaceNode) }
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

// MARK: Mutating

extension Values {
    /// Adds element to collection with default sorting priority,
    /// and writes a changes to transaction.
    ///
    /// If collection is standalone, use **func insert(element:with:)** instead.
    ///
    /// - Parameters:
    ///   - element: The element to write
    ///   - priority: Priority value or `nil` if you want to add to end of collection.
    ///   - transaction: Write transaction to keep the changes
    /// - Returns: A passed transaction or created inside transaction.
    @discardableResult
    public func write(element: Element, with priority: Int? = nil, in transaction: Transaction? = nil) throws -> Transaction {
        guard isRooted, let database = self.database else { fatalError("This method is available only for rooted objects. Use method insert(element:at:)") }
        guard !element.isReferred || element.node!.parent == builder.spaceNode
            else { fatalError("Element must not be referred in other location") }
        guard isSynced || element.node == nil else {
            let transaction = transaction ?? Transaction(database: database)
            transaction.addPrecondition { [unowned transaction] promise in
                self.view._contains(with: element.dbKey) { contains, err in
                    if let e = err {
                        promise.reject(e)
                    } else if contains {
                        promise.reject(RealtimeError(
                            source: .collection,
                            description: "Element cannot be inserted, because already exists"
                        ))
                    } else {
                        do {
                            try self._insert(element, with: priority, in: database, in: transaction)
                            promise.fulfill()
                        } catch let e {
                            promise.reject(e)
                        }
                    }
                }
            }
            return transaction
        }

        guard
            element.node.map({ _ in !contains(element) }) ?? true
            else {
                fatalError("Element with such key already exists")
        }

        return try _insert(element, with: priority, in: database, in: transaction)
    }

    /// Adds element with default sorting priority or if `nil` to end of collection
    ///
    /// This method is available only if collection is **standalone**,
    /// otherwise use **func write(element:with:in:)**
    ///
    /// - Parameters:
    ///   - element: The element to write
    ///   - priority: Priority value or `nil` if you want to add to end of collection.
    public func insert(element: Element, with priority: Int? = nil) {
        guard isStandalone else { fatalError("This method is available only for standalone objects. Use method write(element:at:in:)") }
        guard !element.isReferred || element.node!.parent == builder.spaceNode
            else { fatalError("Element must not be referred in other location") }
        let contains = element.node.map { n in storage[n.key] != nil } ?? false
        guard !contains else {
            fatalError("Element with such key already exists")
        }

        let index = priority ?? view.count
        let key = element.node.map { $0.key } ?? String(index)
        storage[key] = element
        _ = view.insert(RCItem(element: element, key: key, priority: index, linkID: nil))
    }

    @discardableResult
    public func delete(at index: Int) -> Element {
        guard isStandalone else { fatalError("This method is available only for standalone objects. Use method write(element:at:in:)") }
        guard view.count >= index else {
            fatalError("Index out of range")
        }

        guard let element = storage.removeValue(forKey: view.remove(at: index).dbKey) else {
            fatalError("Internal exception: Element is not found")
        }
        return element
    }

    /// Removes element from collection if collection contains this element.
    ///
    /// - Parameters:
    ///   - element: The element to remove
    ///   - transaction: Write transaction or `nil`
    /// - Returns: A passed transaction or created inside transaction.
    @discardableResult
    public func remove(element: Element, in transaction: Transaction? = nil) -> Transaction {
        guard isRooted, let database = self.database else {
            fatalError("This method is available only for rooted objects")
        }

        let transaction = transaction ?? Transaction(database: database)
        guard isSynced else {
            transaction.addPrecondition { [unowned transaction] promise in
                self.view._item(for: element.dbKey) { item, err in
                    if let e = err {
                        promise.reject(e)
                    } else if let item = item {
                        self._remove(for: item, in: transaction)
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

        _remove(element, in: transaction)
        return transaction
    }

    /// Removes element from collection at index.
    ///
    /// - Parameters:
    ///   - index: Index value.
    ///   - transaction: Write transaction or `nil`.
    /// - Returns: A passed transaction or created inside transaction.
    @discardableResult
    public func remove(at index: Int, in transaction: Transaction? = nil) -> Transaction {
        guard isRooted, let database = self.database else { fatalError("This method is available only for rooted objects") }
        guard isSynced else { fatalError("Cannot be removed at index, because collection is not synced.") }

        let transaction = transaction ?? Transaction(database: database)
        _remove(for: view[index], in: transaction)
        return transaction
    }

    @discardableResult
    func _insert(
        _ element: Element, with priority: Int? = nil,
        in database: RealtimeDatabase, in transaction: Transaction? = nil
        ) throws -> Transaction {
        let transaction = transaction ?? Transaction(database: database)
        try _write(element, with: priority ?? view.last.map { $0.priority + 1 } ?? 0, by: (storage: node!, itms: view.node!), in: transaction)
        return transaction
    }

    func _write(_ element: Element, with priority: Int,
                by location: (storage: Node, itms: Node), in transaction: Transaction) throws {
        let elementNode = element.node.map { $0.moveTo(location.storage); return $0 } ?? location.storage.childByAutoId()
        let itemNode = location.itms.child(with: elementNode.key)
        let link = elementNode.generate(linkTo: itemNode)
        let item = RCItem(element: element, key: elementNode.key, priority: priority, linkID: link.link.id)

        transaction.addReversion({ [weak self] in
            self?.storage.removeValue(forKey: item.dbKey)
        })
        storage.set(value: element, for: item.dbKey)
        transaction.addValue(try item.defaultRepresentation(), by: itemNode) /// add item element
        transaction.addValue(try link.link.defaultRepresentation(), by: link.node) /// add link
        try transaction.set(element, by: elementNode) /// add element
    }

    func _remove(_ element: Element, in transaction: Transaction) {
        if let item = view.first(where: { $0.dbKey == element.dbKey }) {
            return _remove(for: item, in: transaction)
        } else {
            debugFatalError("Tries to remove not existed value")
        }
    }

    func _remove(for item: RCItem, in transaction: Transaction) {
        var removedElement: Element {
            if let element = storage.removeValue(forKey: item.dbKey) {
                return element
            } else {
                return builder.build(with: item)
            }
        }
        let element = removedElement
        element.willRemove(in: transaction, from: builder.spaceNode)
        transaction.addReversion { [weak self] in
            self?.storage[item.dbKey] = element
        }
        transaction.removeValue(by: view.node!.child(with: item.dbKey)) /// remove item element
        transaction.removeValue(by: builder.spaceNode.child(with: item.dbKey)) /// remove element
        transaction.addCompletion { result in
            if result {
                element.didRemove()
            }
        }
    }
}

public final class ExplicitValues<Element>: _RealtimeValue, ChangeableRealtimeValue, RealtimeCollection
where Element: RealtimeValue & RCViewItem & Comparable {
    override var _hasChanges: Bool { return view._hasChanges }

    public override var raw: RealtimeDataValue? { return nil }
    public override var payload: [String : RealtimeDataValue]? { return nil }
    public let view: SortedCollectionView<Element>
    public var isSynced: Bool { return view.isSynced }
    public override var isObserved: Bool { return view.isObserved }
    public override var canObserve: Bool { return view.canObserve }
    public var keepSynced: Bool {
        set { view.keepSynced = newValue }
        get { return view.keepSynced }
    }
    public var changes: AnyListenable<RCEvent> {
        return view.changes
    }

    /// Create new instance with default element builder
    ///
    /// - Parameter node: Database node
    public convenience required init(in node: Node?) {
        self.init(in: node, options: [:])
    }
    /// Creates new instance associated with database node
    ///
    /// Available options:
    /// - database: Database reference
    /// - elementBuilder: Closure that calls to build elements lazily.
    ///
    /// - Parameter node: Node location for value
    /// - Parameter options: Dictionary of options
    public required convenience init(in node: Node?, options: [ValueOption: Any]) {
        let view = SortedCollectionView<Element>(in: node, options: [.database: options[.database] as Any])
        self.init(in: node, options: options, view: view)
    }

    public required init(data: RealtimeDataProtocol, exactly: Bool) throws {
        let node = data.node
        self.view = SortedCollectionView(in: node, options: [.database: data.database as Any])
        try super.init(data: data, exactly: exactly)
    }

    init(in node: Node?, options: [ValueOption: Any], view: SortedCollectionView<Element>) {
        self.view = view
        super.init(in: node, options: options)
    }

    // Implementation

    public subscript(position: Int) -> Element {
        return view[position]
    }

    override public func apply(_ data: RealtimeDataProtocol, exactly: Bool) throws {
        try view.apply(data, exactly: exactly)
    }

    /// Collection does not respond for versions and raw value, and also payload.
    /// To change value version/raw can use enum, but use modified representer.
    override func _write(to transaction: Transaction, by node: Node) throws {
        /// readonly
    }

    public override func didSave(in database: RealtimeDatabase, in parent: Node, by key: String) {
        super.didSave(in: database, in: parent, by: key)
        if let node = self.node {
            view.didSave(in: database, in: node)
        }
//        storage.forEach { $0.value.didSave(in: database, in: builder.spaceNode, by: $0.key) }
    }

    public override func willRemove(in transaction: Transaction, from ancestor: Node) {
        super.willRemove(in: transaction, from: ancestor)
        if ancestor == node?.parent {
            transaction.removeValue(by: node!)
        }
//        storage.values.forEach { $0.willRemove(in: transaction, from: ancestor) }
    }
    override public func didRemove(from ancestor: Node) {
        super.didRemove(from: ancestor)
        view.didRemove()
//        storage.values.forEach { $0.didRemove(from: builder.spaceNode) }
    }

    override public var debugDescription: String {
        return """
        \(type(of: self)): \(ObjectIdentifier(self).memoryAddress) {
        ref: \(node?.rootPath ?? "not referred"),
        synced: \(isSynced), keep: \(keepSynced),
        elements: \(view.map { $0.dbKey })
        }
        """
    }
}

