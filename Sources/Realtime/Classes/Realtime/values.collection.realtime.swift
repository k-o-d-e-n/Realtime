//
//  Values.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 18/02/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation

public extension RawRepresentable where RawValue == String {
    func values<Element: Object>(in object: Object) -> Values<Element> {
        return Values(in: Node(key: rawValue, parent: object.node), database: object.database)
    }
    func values<Element>(in object: Object, builder: @escaping RCElementBuilder<RealtimeValueOptions, Element>) -> Values<Element> {
        return Values(
            in: Node(key: rawValue, parent: object.node),
            options: Values.Options(database: object.database, builder: builder)
        )
    }
}

public extension Values {
    convenience init(in node: Node?, elements: References<Element>) {
        let db = elements.database
        self.init(
            in: node,
            options: Options(database: db, builder: elements.builder),
            view: elements.view
        )
    }
}

public extension Values where Element: Object {
    /// Create new instance with default element builder
    ///
    /// - Parameter node: Database node
    convenience init(in node: Node?) {
        self.init(in: node, database: nil)
    }

    convenience init(in node: Node?, database: RealtimeDatabase?) {
        self.init(in: node, options: Options(database: database, builder: { node, database, options in
            let el = Element(in: node, options: RealtimeValueOptions(database: database, raw: options.raw, payload: options.payload))
            precondition(type(of: el) == Element.self, "Unexpected behavior")
            return el
        }))
    }
}

/// A Realtime database collection that stores elements in own database node as is, as full objects.
public final class Values<Element>: _RealtimeValue, ChangeableRealtimeValue, RealtimeCollection where Element: WritableRealtimeValue & RealtimeValueEvents {
    /// Stores collection values and responsible for lazy initialization elements
    var storage: RCKeyValueStorage<Element>
    fileprivate let builder: RCElementBuilder<RealtimeValueOptions, Element>
    override var _hasChanges: Bool { return view._hasChanges }

    public override var raw: RealtimeDatabaseValue? { return nil }
    public override var payload: RealtimeDatabaseValue? { return nil }
    /// Stores an abstract elements
    public let view: SortedCollectionView<RCItem> 
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
                        self.storage.remove(for: data.key!)
                    } else {
                        data.forEach({ child in
                            self.storage.remove(for: child.key!)
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

    public struct Options {
        let base: RealtimeValueOptions
        let builder: RCElementBuilder<RealtimeValueOptions, Element>

        public init(database: RealtimeDatabase?, builder: @escaping RCElementBuilder<RealtimeValueOptions, Element>) {
            self.base = RealtimeValueOptions(database: database)
            self.builder = builder
        }
    }

    /// Creates new instance associated with database node
    ///
    /// Available options:
    /// - database: Database reference
    /// - elementBuilder: Closure that calls to build elements lazily.
    ///
    /// - Parameter node: Node location for value
    /// - Parameter options: Dictionary of options
    public required convenience init(in node: Node?, options: Options) {
        let viewParentNode = node.flatMap { $0.isRooted ? $0.linksNode : nil }
        let viewNode = Node(key: InternalKeys.items, parent: viewParentNode)
        let view = SortedCollectionView<RCItem>(node: viewNode, options: options.base)
        self.init(in: node, options: options, view: view)
    }

    public required init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        fatalError("Values does not supported init(data:event:) yet. Use `init(data:event:options:)` instead")
    }

    init(in node: Node?, options: Options, view: SortedCollectionView<RCItem>) {
        self.builder = options.builder
        self.storage = RCKeyValueStorage()
        self.view = view
        super.init(node: node, options: options.base)
    }

    // Implementation

    fileprivate func _build(_ item: RCItem) -> Element {
        return builder(node?.child(with: item.dbKey), database, RealtimeValueOptions(database: database, raw: item.raw, payload: item.payload))
    }

    public subscript(position: Int) -> Element {
        let item = view[position]
        guard let element = storage.value(for: item.dbKey) else {
            let element = _build(item)
            storage.set(value: element, for: item.dbKey)
            return element
        }
        return element
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
                if event == .value { storage.remove(for: key.dbKey) }
                return
            }
            let childData = data.child(forPath: key.dbKey)
            if var element = storage[key.dbKey] {
                try element.apply(childData, event: event)
            } else {
                var value = _build(key)
                try value.apply(childData, event: event)
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
                       with: item.priority ?? 0,
                       by: (storage: node,
                            itms: Node(key: InternalKeys.items, parent: node.linksNode)),
                       in: transaction)
        }
    }

    public override func didSave(in database: RealtimeDatabase, in parent: Node, by key: String) {
        super.didSave(in: database, in: parent, by: key)
        if let node = self.node {
            view.didSave(in: database, in: node.linksNode)
            storage.forEach { $0.value.didSave(in: database, in: node, by: $0.key) }
        }
    }

    public override func willRemove(in transaction: Transaction, from ancestor: Node) {
        super.willRemove(in: transaction, from: ancestor)
        if ancestor == node?.parent {
            /// remove view if remove action is applying on collection
            transaction.delete(view)
        }
        storage.values.forEach { $0.willRemove(in: transaction, from: ancestor) }
    }
    override public func didRemove(from ancestor: Node) {
        super.didRemove(from: ancestor)
        view.didRemove()
        storage.values.forEach { $0.didRemove() }
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
    public func write(element: Element, with priority: Int64? = nil, in transaction: Transaction? = nil) throws -> Transaction {
        guard isRooted, let database = self.database else { fatalError("This method is available only for rooted objects. Use method insert(element:at:)") }
        guard !element.isReferred || element.node!.parent == node
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
    public func insert(element: Element, with priority: Int64? = nil) {
        guard isStandalone else { fatalError("This method is available only for standalone objects. Use method write(element:at:in:)") }
        guard !element.isReferred || element.node!.parent == node
            else { fatalError("Element must not be referred in other location") }
        let contains = element.node.map { n in storage[n.key] != nil } ?? false
        guard !contains else {
            fatalError("Element with such key already exists")
        }

        let index = priority ?? Int64(view.count)
        let key = element.node.map { $0.key } ?? Node(parent: nil).key
        storage[key] = element
        var item = RCItem(key: key, value: element)
        item.priority = index
        _ = view.insert(item)
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
        _ element: Element, with priority: Int64? = nil,
        in database: RealtimeDatabase, in transaction: Transaction? = nil
        ) throws -> Transaction {
        let transaction = transaction ?? Transaction(database: database)
        try _write(element, with: priority ?? (isAscending ? view.last : view.first).flatMap { $0.priority.map { $0 + 1 } } ?? 0,
                   by: (storage: node!, itms: view.node!), in: transaction)
        return transaction
    }

    func _write(_ element: Element, with priority: Int64,
                by location: (storage: Node, itms: Node), in transaction: Transaction) throws {
        let elementNode = element.node.map { $0.moveTo(location.storage); return $0 } ?? location.storage.childByAutoId()
        let itemNode = location.itms.child(with: elementNode.key)
        let link = elementNode.generate(linkTo: itemNode)
        var item = RCItem(key: elementNode.key, value: element)
        item.priority = priority
        item.linkID = link.link.id

        transaction.addReversion({ [weak self] in
            self?.storage.removeValue(forKey: item.dbKey)
        })
        storage.set(value: element, for: item.dbKey)
        try item.write(to: transaction, by: itemNode) /// add item element
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
                return _build(item)
            }
        }
        let element = removedElement
        element.willRemove(in: transaction)
        transaction.addReversion { [weak self] in
            self?.storage[item.dbKey] = element
        }
        transaction.removeValue(by: view.node!.child(with: item.dbKey)) /// remove item element
        transaction.removeValue(by: node!.child(with: item.dbKey)) /// remove element
        // TODO: Why element does not remove through his API? Therefore does not remove 'link_items'. The same in AssociatedValues
        transaction.addCompletion { result in
            if result {
                element.didRemove()
            }
        }
    }
}

public final class ExplicitValues<Element>: _RealtimeValue, ChangeableRealtimeValue, RealtimeCollection
where Element: WritableRealtimeValue & Comparable {
    override var _hasChanges: Bool { return view._hasChanges }

    public override var raw: RealtimeDatabaseValue? { return nil }
    public override var payload: RealtimeDatabaseValue? { return nil }
    public let view: SortedCollectionView<Element>
    public var isSynced: Bool { return view.isSynced }
    public override var isObserved: Bool { return view.isObserved }
    public override var canObserve: Bool { return view.canObserve }
    public var keepSynced: Bool {
        set { view.keepSynced = newValue }
        get { return view.keepSynced }
    }
    public lazy var changes: AnyListenable<RCEvent> = self.view.changes
        .map({ $1 })
        .shared(connectionLive: .continuous)
        .asAny()
    public var dataExplorer: RCDataExplorer = .view(ascending: false) {
        didSet { view.didChange(dataExplorer: dataExplorer) }
    }

    /// Create new instance with default element builder
    ///
    /// - Parameter node: Database node
    public convenience required init(in node: Node?) {
        self.init(in: node, options: RealtimeValueOptions())
    }
    /// Creates new instance associated with database node
    ///
    /// Available options:
    /// - database: Database reference
    /// - elementBuilder: Closure that calls to build elements lazily.
    ///
    /// - Parameter node: Node location for value
    /// - Parameter options: Dictionary of options
    public convenience init(in node: Node?, options: RealtimeValueOptions) {
        let view = SortedCollectionView<Element>(node: node, options: options)
        self.init(in: node, options: options, view: view)
    }
    public convenience init(in object: _RealtimeValue, keyedBy key: String, options: RealtimeValueOptions = .init()) {
        self.init(
            in: Node(key: key, parent: object.node),
            options: options.with(db: object.database)
        )
    }

    public required init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        let node = data.node
        self.view = SortedCollectionView(node: node, options: RealtimeValueOptions(database: data.database))
        try super.init(data: data, event: event)
    }

    init(in node: Node?, options: RealtimeValueOptions, view: SortedCollectionView<Element>) {
        self.view = view
        super.init(node: node, options: options)
    }

    // Implementation

    public subscript(position: Int) -> Element {
        return view[position]
    }

    override public func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        try view.apply(data, event: event)
    }

    /// Collection does not respond for versions and raw value, and also payload.
    /// To change value version/raw can use enum, but use modified representer.
    override func _write(to transaction: Transaction, by node: Node) throws {
        try view._write(to: transaction, by: node)
    }

    // TODO: Events are not call for elements
    public override func didSave(in database: RealtimeDatabase, in parent: Node, by key: String) {
        super.didSave(in: database, in: parent, by: key)
        view.didSave(in: database, in: parent, by: key)
    }
    public override func willRemove(in transaction: Transaction, from ancestor: Node) {
        super.willRemove(in: transaction, from: ancestor)
        view.willRemove(in: transaction, from: ancestor)
    }
    override public func didRemove(from ancestor: Node) {
        super.didRemove(from: ancestor)
        view.didRemove()
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
extension ExplicitValues {
    @discardableResult
    public func insert(_ element: Element) -> Int {
        guard isStandalone else { fatalError("Cannot be written, because collection is rooted") }
        return view.insert(element)
    }
    @discardableResult
    public func remove(at index: Int) -> Element {
        guard isStandalone else { fatalError("Cannot be written, because collection is rooted") }
        return view.remove(at: index)
    }
    public func write(_ element: Element, in transaction: Transaction) throws {
        guard let parentNode = self.node, parentNode.isRooted
        else { fatalError("Cannot be written, because collection is not rooted") }
        try transaction._set(
            element,
            by: Node(key: element.node?.key ?? transaction.database.generateAutoID(), parent: parentNode)
        )
    }
    @discardableResult
    public func remove(at index: Int, in transaction: Transaction) -> Element {
        guard isRooted else { fatalError("Cannot be written, because collection is not rooted") }
        guard isSynced else { fatalError("Cannot be removed at index, because collection is not synced.") }

        let element = view[index]
        transaction.removeValue(by: element.node!)
        return element
    }
}
extension ExplicitValues where Element: RealtimeValueEvents {
    public func write(_ element: Element, in transaction: Transaction) throws {
        guard let parentNode = self.node, parentNode.isRooted
        else { fatalError("Cannot be written, because collection is not rooted") }
        try transaction.set(
            element,
            by: Node(key: element.node?.key ?? transaction.database.generateAutoID(), parent: self.node)
        )
    }
}

