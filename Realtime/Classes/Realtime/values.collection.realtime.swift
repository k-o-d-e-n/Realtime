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

// MARK: Implementation RealtimeCollection`s

public extension Values {
    convenience init<E>(in node: Node?, elements: References<E>) {
        self.init(in: node,
                  options: [.elementBuilder: elements.storage.elementBuilder],
                  viewSource: elements._view.source)
    }
}

/// A Realtime database collection that stores elements in own database node as is, as full objects.
public final class Values<Element>: _RealtimeValue, ChangeableRealtimeValue, RC where Element: WritableRealtimeValue & RealtimeValueEvents {
    public override var version: Int? { return nil }
    public override var raw: RealtimeDataValue? { return nil }
    public override var payload: [String : RealtimeDataValue]? { return nil }
    override var _hasChanges: Bool { return isStandalone && storage.elements.count > 0 }
    /// Stores collection values and responsible for lazy initialization elements
    public internal(set) var storage: RCArrayStorage<Element>
    /// Stores an abstract elements
    public var view: RealtimeCollectionView { return _view }
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

    let _view: AnyRealtimeCollectionView<SortedArray<RCItem>, Values>

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
    public convenience required init(in node: Node?, options: [ValueOption: Any]) {
        let viewParentNode = node.flatMap { $0.isRooted ? $0.linksNode : nil }
        self.init(
            in: node,
            options: options,
            viewSource: Property<SortedArray<RCItem>>(
                in: Node(key: InternalKeys.items, parent: viewParentNode),
                options: [
                    .database: options[.database] as Any,
                    .representer: Representer<SortedArray<RCItem>>(collection: Representer.realtimeData).requiredProperty()
                ]
            ).defaultOnEmpty()
        )
    }

    init(in node: Node?,
         options: [ValueOption: Any],
         viewSource: Property<SortedArray<RCItem>>) {
        let builder = options[.elementBuilder] as? RCElementBuilder<Element> ?? Element.init
        self.storage = RCArrayStorage(sourceNode: node, elementBuilder: builder, elements: [:])
        self._view = AnyRealtimeCollectionView(viewSource)
        super.init(in: node, options: options)
    }

    public required init(data: RealtimeDataProtocol, exactly: Bool) throws {
        let node = data.node
        let viewParentNode = node.flatMap { $0.isRooted ? $0.linksNode : nil }
        self.storage = RCArrayStorage(sourceNode: node, elementBuilder: Element.init, elements: [:])
        self._view = AnyRealtimeCollectionView(
            Property<SortedArray<RCItem>>(
                in: Node(key: InternalKeys.items, parent: viewParentNode),
                options: [
                    .database: data.database as Any,
                    .representer: Representer<SortedArray<RCItem>>(collection: Representer.realtimeData).requiredProperty()
                ]
            ).defaultOnEmpty()
        )
        try super.init(data: data, exactly: exactly)
    }

    // Implementation

    /// Returns a Boolean value indicating whether the sequence contains an
    /// element that has the same key.
    ///
    /// - Parameter element: The element to check for containment.
    /// - Returns: `true` if `element` is contained in the range; otherwise,
    ///   `false`.
    public func contains(_ element: Element) -> Bool {
        return _view.contains { $0.dbKey == element.dbKey }
    }
    public subscript(position: Int) -> Element { return storage.object(for: _view[position]) }
    public var startIndex: Int { return _view.startIndex }
    public var endIndex: Int { return _view.endIndex }
    public func index(after i: Int) -> Int { return _view.index(after: i) }
    public func index(before i: Int) -> Int { return _view.index(before: i) }

    @discardableResult
    public func runObserving() -> Bool {
        let isNeedLoadFull = !_view.source.isObserved
        let added = _view.source._runObserving(.child(.added))
        let removed = _view.source._runObserving(.child(.removed))
        let changed = _view.source._runObserving(.child(.changed))
        if isNeedLoadFull {
            // overhead if often switches run/stop
            _view.load(.just { [weak self] e in
                self.map { this in
                    this._view.isSynced = this._view.source.isObserved && e == nil
                }
            })
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
                        self.storage.elements.removeValue(forKey: item.dbKey)
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
                if exactly { storage.elements.removeValue(forKey: key.dbKey) }
                return
            }
            let childData = data.child(forPath: key.dbKey)
            if var element = storage.elements[key.dbKey] {
                try element.apply(childData, exactly: exactly)
            } else {
                storage.elements[key.dbKey] = try Element(data: childData, exactly: exactly)
            }
        }
    }

    /// Collection does not respond for versions and raw value, and also payload.
    /// To change value version/raw can use enum, but use modified representer.
    override func _write(to transaction: Transaction, by node: Node) throws {
        /// skip the call of super (_RealtimeValue)
        let elems = storage.elements
        storage.elements.removeAll()
        let view = _view.value
        transaction.addReversion { [weak self] in
            self?._view.source <== view
        }
        _view.removeAll()
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
            _view.source.didSave(in: database, in: node.linksNode)
            storage.sourceNode = node
        }
        storage.elements.forEach { $1.didSave(in: database, in: storage.sourceNode, by: $0) }
    }

    public override func willRemove(in transaction: Transaction, from ancestor: Node) {
        super.willRemove(in: transaction, from: ancestor)
        if ancestor == node?.parent {
            transaction.removeValue(by: node!.linksNode)
        }
        storage.elements.values.forEach { $0.willRemove(in: transaction, from: ancestor) }
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
        guard !element.isReferred || element.node!.parent == storage.sourceNode
            else { fatalError("Element must not be referred in other location") }
        guard isSynced || element.node == nil else {
            let transaction = transaction ?? Transaction(database: database)
            transaction.addPrecondition { [unowned transaction] promise in
                self._view._contains(with: element.dbKey) { contains, err in
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
        guard !element.isReferred || element.node!.parent == storage.sourceNode
            else { fatalError("Element must not be referred in other location") }
        let contains = element.node.map { n in storage.elements[n.key] != nil } ?? false
        guard !contains else {
            fatalError("Element with such key already exists")
        }

        let index = priority ?? _view.count
        let key = element.node.map { $0.key } ?? String(index)
        storage.elements[key] = element
        _ = _view.insert(RCItem(element: element, key: key, linkID: "", priority: index))
    }

    @discardableResult
    public func delete(at index: Int) -> Element {
        guard isStandalone else { fatalError("This method is available only for standalone objects. Use method write(element:at:in:)") }
        guard _view.count >= index else {
            fatalError("Index out of range")
        }

        guard let element = storage.elements.removeValue(forKey: _view.remove(at: index).dbKey) else {
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
                self._view._item(for: element.dbKey) { item, err in
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
        _remove(for: _view[index], in: transaction)
        return transaction
    }

    @discardableResult
    func _insert(
        _ element: Element, with priority: Int? = nil,
        in database: RealtimeDatabase, in transaction: Transaction? = nil
        ) throws -> Transaction {
        let transaction = transaction ?? Transaction(database: database)
        try _write(element, with: priority ?? _view.last.map { $0.priority + 1 } ?? 0, by: (storage: node!, itms: _view.source.node!), in: transaction)
        return transaction
    }

    func _write(_ element: Element, with priority: Int,
                by location: (storage: Node, itms: Node), in transaction: Transaction) throws {
        let elementNode = element.node.map { $0.moveTo(location.storage); return $0 } ?? location.storage.childByAutoId()
        let itemNode = location.itms.child(with: elementNode.key)
        let link = elementNode.generate(linkTo: itemNode)
        let item = RCItem(element: element, key: elementNode.key, linkID: link.link.id, priority: priority)

        transaction.addReversion({ [weak self] in
            self?.storage.elements.removeValue(forKey: item.dbKey)
        })
        storage.store(value: element, by: item)
        transaction.addValue(item.rdbValue, by: itemNode)
        transaction.addValue(link.link.rdbValue, by: link.node)
        try transaction.set(element, by: elementNode)
    }

    func _remove(_ element: Element, in transaction: Transaction) {
        if let item = _view.first(where: { $0.dbKey == element.dbKey }) {
            return _remove(for: item, in: transaction)
        } else {
            debugFatalError("Tries to remove not existed value")
        }
    }

    func _remove(for item: RCItem, in transaction: Transaction) {
        var removedElement: Element {
            if let element = storage.elements.removeValue(forKey: item.dbKey) {
                return element
            } else {
                return storage.buildElement(with: item)
            }
        }
        let element = removedElement
        element.willRemove(in: transaction, from: storage.sourceNode)
        transaction.addReversion { [weak self] in
            self?.storage.elements[item.dbKey] = element
        }
        transaction.removeValue(by: _view.source.node!.child(with: item.dbKey)) /// remove item element
        transaction.removeValue(by: storage.sourceNode.child(with: item.dbKey)) /// remove element
        transaction.addCompletion { result in
            if result {
                element.didRemove()
            }
        }
    }
}
