//
//  References.swift
//  Realtime
//
//  Created by Denis Koryttsev on 16/03/2018.
//

import Foundation

public extension RawRepresentable where RawValue == String {
    func references<Element>(in object: Object, elements: Node) -> References<Element> {
        return References(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .elementsNode: elements
            ]
        )
    }
    func references<Element>(in object: Object, elements: Node, elementOptions: [ValueOption: Any]) -> References<Element> {
        let db = object.database as Any
        return references(in: object, elements: elements, builder: { (node, options) in
            var compoundOptions = options.merging(elementOptions, uniquingKeysWith: { remote, local in remote })
            compoundOptions[.database] = db
            return Element(in: node, options: compoundOptions)
        })
    }
    func references<Element>(in object: Object, elements: Node, builder: @escaping RCElementBuilder<Element>) -> References<Element> {
        return References(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .elementsNode: elements,
                .elementBuilder: builder
            ]
        )
    }
}

public extension ValueOption {
    static let elementsNode = ValueOption("realtime.linkedarray.elements")
}

/// A Realtime database collection that stores elements in own database node as references.
public final class References<Element>: _RealtimeValue, ChangeableRealtimeValue, RC where Element: RealtimeValue {
    public override var version: Int? { return nil }
    public override var raw: RealtimeDataValue? { return nil }
    public override var payload: [String : RealtimeDataValue]? { return nil }
    override var _hasChanges: Bool { return isStandalone && storage.elements.count > 0 }
    public internal(set) var storage: RCArrayStorage<Element>
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

    let _view: AnyRealtimeCollectionView<SortedArray<RCItem>, References>

    /// Creates new instance associated with database node
    ///
    /// Available options:
    /// - elementsNode(**required**): Database node where source elements are located.
    /// - database: Database reference
    /// - elementBuilder: Closure that calls to build elements lazily.
    ///
    /// - Parameter node: Node location for value
    /// - Parameter options: Dictionary of options
    public required init(in node: Node?, options: [ValueOption: Any]) {
        guard case let elements as Node = options[.elementsNode] else { fatalError("Skipped required options") }
        let builder = options[.elementBuilder] as? RCElementBuilder<Element> ?? Element.init

        self.storage = RCArrayStorage(sourceNode: elements,
                                      elementBuilder: builder,
                                      elements: [:])
        self._view = AnyRealtimeCollectionView(
            Property<SortedArray<RCItem>>(
                in: node,
                options: [
                    .database: options[.database] as Any,
                    .representer: Representer<SortedArray<RCItem>>(collection: Representer.realtimeData).requiredProperty()
                ]
            ).defaultOnEmpty()
        )
        super.init(in: node, options: options)
    }

    public convenience init(data: RealtimeDataProtocol, exactly: Bool, elementsNode: Node) throws {
        self.init(in: data.node, options: [.elementsNode: elementsNode,
                                               .database: data.database as Any])
        try apply(data, exactly: exactly)
    }

    /// Currently, no available.
    public required init(data: RealtimeDataProtocol, exactly: Bool) throws {
        #if DEBUG
            fatalError("References does not supported init(data:exactly:) yet.")
        #else
            throw RealtimeError(source: .collection, description: "References does not supported init(data:exactly:) yet.")
        #endif
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

    override public func apply(_ data: RealtimeDataProtocol, exactly: Bool) throws {
        try super.apply(data, exactly: exactly)
        try _view.source.apply(data, exactly: exactly)
    }

    /// Collection does not respond for versions and raw value, and also payload.
    /// To change value version/raw can use enum, but use modified representer.
    override func _write(to transaction: Transaction, by node: Node) throws {
        /// skip the call of super
        let view = _view.value
        transaction.addReversion { [weak self] in
            self?._view.source <== view
        }
        _view.removeAll()
        for item in view {
            try _write(storage.elements[item.dbKey]!, with: item.priority, by: node, in: transaction)
        }
    }

    public override func didSave(in database: RealtimeDatabase, in parent: Node, by key: String) {
        super.didSave(in: database, in: parent, by: key)
        _view.source.didSave(in: database, in: parent)
    }

    public override func willRemove(in transaction: Transaction, from ancestor: Node) {
        super.willRemove(in: transaction, from: ancestor)
        _view.source.willRemove(in: transaction, from: ancestor)
    }
    override public func didRemove(from ancestor: Node) {
        super.didRemove(from: ancestor)
        _view.source.didRemove(from: ancestor)
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

public extension References {
    /// Adds element to collection at passed priority,
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
    func write(element: Element, with priority: Int? = nil,
                in transaction: Transaction? = nil) throws -> Transaction {
        guard isRooted, let database = self.database else { fatalError("This method is available only for rooted objects. Use method insert(element:at:)") }
        guard element.node?.parent == storage.sourceNode else { fatalError("Element must be located in elements node") }
        guard isSynced else {
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
                            try self._write(element, with: priority, in: database, in: transaction)
                            promise.fulfill()
                        } catch let e {
                            promise.reject(e)
                        }
                    }
                }
            }
            return transaction
        }

        guard !contains(element) else {
            throw RealtimeError(
                source: .collection,
                description: "Element already contains. Element: \(element)"
            )
        }
        return try _write(element, with: priority, in: database, in: transaction)
    }

    /// Adds element with default sorting priority index or if `nil` to end of collection
    ///
    /// This method is available only if collection is **standalone**,
    /// otherwise use **func write(element:with:in:)**
    ///
    /// - Parameters:
    ///   - element: The element to write
    ///   - index: Priority value or `nil` if you want to add to end of collection.
    func insert(element: Element, with priority: Int? = nil) {
        guard isStandalone else { fatalError("This method is available only for standalone objects. Use method write(element:at:in:)") }
        guard element.node?.parent == storage.sourceNode else { fatalError("Element must be located in elements node") }
        let contains = element.node.map { n in storage.elements[n.key] != nil } ?? false
        guard !contains else {
            fatalError("Element with such key already exists")
        }

        let index = priority ?? _view.count
        storage.elements[element.dbKey] = element
        _ = _view.insert(RCItem(element: element, linkID: "", priority: index))
    }

    func delete(element: Element) {
        guard isStandalone else { fatalError("This method is available only for standalone objects. Use method write(element:at:in:)") }
        guard element.node?.parent == storage.sourceNode else { fatalError("Element must be located in elements node") }
        let contains = element.node.map { n in storage.elements[n.key] != nil } ?? false
        guard contains else {
            fatalError("Element with such key does not exist")
        }

        storage.elements.removeValue(forKey: element.dbKey)
        guard let index = _view.index(where: { $0.dbKey == element.dbKey }) else {
            return
        }
        _ = _view.remove(at: index)
    }

    /// Removes element from collection if collection contains this element.
    ///
    /// - Parameters:
    ///   - element: The element to remove
    ///   - transaction: Write transaction or `nil`
    /// - Returns: A passed transaction or created inside transaction.
    @discardableResult
    func remove(element: Element, in transaction: Transaction? = nil) -> Transaction? {
        guard isRooted, let database = self.database else { fatalError("This method is available only for rooted objects") }

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
                        promise.reject(RealtimeError(
                            source: .collection,
                            description: "Element is not found"
                        ))
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
    func remove(at index: Int, in transaction: Transaction? = nil) -> Transaction {
        guard isRooted, let database = self.database else { fatalError("This method is available only for rooted objects") }
        guard isSynced else { fatalError("Cannot be removed at index, because collection is not synced.") }

        let transaction = transaction ?? Transaction(database: database)
        _remove(for: _view[index], in: transaction)
        return transaction
    }

    @discardableResult
    internal func _write(
        _ element: Element, with priority: Int? = nil,
        in database: RealtimeDatabase, in transaction: Transaction? = nil
        ) throws -> Transaction {
        let transaction = transaction ?? Transaction(database: database)
        try _write(element, with: priority ?? _view.last.map { $0.priority + 1 } ?? 0, by: node!, in: transaction)
        return transaction
    }

    internal func _write(_ element: Element, with priority: Int,
                         by location: Node, in transaction: Transaction) throws {
        let itemNode = location.child(with: element.dbKey)
        let link = element.node!.generate(linkTo: itemNode)
        let item = RCItem(element: element, linkID: link.link.id, priority: priority)

        transaction.addReversion({ [weak self] in
            self?.storage.elements.removeValue(forKey: item.dbKey)
        })
        storage.store(value: element, by: item)
        transaction.addValue(item.rdbValue, by: itemNode)
        transaction.addValue(link.link.rdbValue, by: link.node)
    }

    private func _remove(_ element: Element, in transaction: Transaction) {
        if let item = _view.first(where: { $0.dbKey == element.dbKey }) {
            _remove(for: item, in: transaction)
        } else {
            debugFatalError("Tries to remove not existed value")
        }
    }

    private func _remove(for item: RCItem, in transaction: Transaction) {
        let element = storage.elements.removeValue(forKey: item.dbKey)
        transaction.addReversion { [weak self] in
            self?.storage.elements[item.dbKey] = element
        }
        let elementLinksNode = storage.sourceNode.child(with: item.dbKey).linksItemsNode.child(
            with: item.linkID
        )
        transaction.removeValue(by: _view.source.node!.child(with: item.dbKey)) /// remove item
        transaction.removeValue(by: elementLinksNode) /// remove link from element
    }
}

