//
//  References.swift
//  Realtime
//
//  Created by Denis Koryttsev on 16/03/2018.
//

import Foundation

public extension RawRepresentable where RawValue == String {
    func references<C, Element>(in object: Object, elements: Node) -> C where C: References<Element> {
        return C(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .elementsNode: elements
            ]
        )
    }
    func references<C, Element>(in object: Object, elements: Node, elementOptions: [ValueOption: Any]) -> C where C: References<Element> {
        let db = object.database as Any
        return references(in: object, elements: elements, builder: { (node, options) in
            var compoundOptions = options.merging(elementOptions, uniquingKeysWith: { remote, local in remote })
            compoundOptions[.database] = db
            return Element(in: node, options: compoundOptions)
        })
    }
    func references<C, Element>(in object: Object, elements: Node, builder: @escaping RCElementBuilder<Element>) -> C where C: References<Element> {
        return C(
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
public class __References<Element, Ref: RCViewItem>: _RealtimeValue, WritableRealtimeCollection where Element: RealtimeValue {
    internal var storage: RCArrayStorage<Ref, Element>

    public override var version: Int? { return nil }
    public override var raw: RealtimeDataValue? { return nil }
    public override var payload: [String : RealtimeDataValue]? { return nil }
    public let view: SortedCollectionView<Ref>
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
    /// - elementsNode(**required**): Database node where source elements are located.
    /// - database: Database reference
    /// - elementBuilder: Closure that calls to build elements lazily.
    ///
    /// - Parameter node: Node location for value
    /// - Parameter options: Dictionary of options
    public required init(in node: Node?, options: [ValueOption : Any]) {
        guard case let elements as Node = options[.elementsNode] else { fatalError("Skipped required options") }
        let builder = options[.elementBuilder] as? RCElementBuilder<Element> ?? Element.init

        self.storage = RCArrayStorage(sourceNode: elements,
                                      elementBuilder: builder,
                                      elements: [:])
        self.view = SortedCollectionView(in: node, options: options)
        super.init(in: node, options: options)
    }

    /// Currently, no available.
    public required init(data: RealtimeDataProtocol, exactly: Bool) throws {
        #if DEBUG
        fatalError("References does not supported init(data:exactly:) yet.")
        #else
        throw RealtimeError(source: .collection, description: "References does not supported init(data:exactly:) yet.")
        #endif
    }

    public convenience init(data: RealtimeDataProtocol, exactly: Bool, elementsNode: Node) throws {
        self.init(in: data.node, options: [.elementsNode: elementsNode,
                                               .database: data.database as Any])
        try apply(data, exactly: exactly)
    }

    // Implementation

    public subscript(position: Int) -> Element { return storage.object(for: view[position]) }

    override public func apply(_ data: RealtimeDataProtocol, exactly: Bool) throws {
        try super.apply(data, exactly: exactly)
        try view.apply(data, exactly: exactly)
    }

    /// Collection does not respond for versions and raw value, and also payload.
    /// To change value version/raw can use enum, but use modified representer.
    override func _write(to transaction: Transaction, by node: Node) throws {
        /// skip the call of super
        try view._write(to: transaction, by: node)
    }

    public override func didSave(in database: RealtimeDatabase, in parent: Node, by key: String) {
        super.didSave(in: database, in: parent, by: key)
        view.didSave(in: database, in: parent)
    }

    public override func willRemove(in transaction: Transaction, from ancestor: Node) {
        super.willRemove(in: transaction, from: ancestor)
        view.willRemove(in: transaction, from: ancestor)
    }
    override public func didRemove(from ancestor: Node) {
        super.didRemove(from: ancestor)
        view.didRemove(from: ancestor)
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

public class References<Element: RealtimeValue>: __References<Element, RCItem> {}

// MARK: Mutating

public final class MutableReferences<Element: RealtimeValue>: References<Element>, MutableRealtimeCollection {
    override var _hasChanges: Bool { return view._hasChanges }

    private var shouldLinking = true // TODO: Fix it
    public func unlinked() -> MutableReferences<Element> { shouldLinking = false; return self }

    public func write(_ element: Element, to transaction: Transaction) throws {
        try write(element: element, with: count, in: transaction)
    }
    public func write(_ element: Element) throws -> Transaction {
        return try write(element: element, with: count, in: nil)
    }

    public func erase(at index: Int, in transaction: Transaction) {
        remove(at: index, in: transaction)
    }
    public func erase(at index: Int) -> Transaction {
        return remove(at: index, in: nil)
    }

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
    public func insert(element: Element, with priority: Int? = nil) {
        guard isStandalone else { fatalError("This method is available only for standalone objects. Use method write(element:at:in:)") }
        guard element.node?.parent == storage.sourceNode else { fatalError("Element must be located in elements node") }
        let contains = element.node.map { n in storage.elements[n.key] != nil } ?? false
        guard !contains else {
            fatalError("Element with such key already exists")
        }

        let index = priority ?? view.count
        storage.elements[element.dbKey] = element
        view.insert(RCItem(element: element, priority: index, linkID: nil))
    }

    public func delete(element: Element) {
        guard isStandalone else { fatalError("This method is available only for standalone objects. Use method write(element:at:in:)") }
        guard element.node?.parent == storage.sourceNode else { fatalError("Element must be located in elements node") }
        let contains = element.node.map { n in storage.elements[n.key] != nil } ?? false
        guard contains else {
            fatalError("Element with such key does not exist")
        }

        storage.elements.removeValue(forKey: element.dbKey)
        guard let index = view.index(where: { $0.dbKey == element.dbKey }) else {
            return
        }
        view.remove(at: index)
    }

    /// Removes element from collection if collection contains this element.
    ///
    /// - Parameters:
    ///   - element: The element to remove
    ///   - transaction: Write transaction or `nil`
    /// - Returns: A passed transaction or created inside transaction.
    @discardableResult
    public func remove(element: Element, in transaction: Transaction? = nil) -> Transaction? {
        guard isRooted, let database = self.database else { fatalError("This method is available only for rooted objects") }

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
        _remove(for: view[index], in: transaction)
        return transaction
    }

    @discardableResult
    internal func _write(
        _ element: Element, with priority: Int?,
        in database: RealtimeDatabase, in transaction: Transaction? = nil
        ) throws -> Transaction {
        let transaction = transaction ?? Transaction(database: database)
        try _write(element, with: priority ?? view.last.map { $0.priority + 1 } ?? 0, by: node!, in: transaction)
        return transaction
    }

    internal func _write(_ element: Element, with priority: Int,
                         by location: Node, in transaction: Transaction) throws {
        let itemNode = location.child(with: element.dbKey)
        var item = RCItem(element: element, priority: priority, linkID: nil)

        transaction.addReversion({ [weak self] in
            self?.storage.elements.removeValue(forKey: item.dbKey)
        })
        storage.store(value: element, by: item)
        if shouldLinking {
            let link = element.node!.generate(linkTo: itemNode)
            item.linkID = link.link.id
            transaction.addValue(link.link.rdbValue, by: link.node) // add link
        }
        transaction.addValue(item.rdbValue, by: itemNode) // add item element
    }

    private func _remove(_ element: Element, in transaction: Transaction) {
        if let item = view.first(where: { $0.dbKey == element.dbKey }) {
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
        if let linkID = item.linkID {
            let elementLinksNode = storage.sourceNode.child(with: item.dbKey).linksItemsNode.child(with: linkID)
            transaction.removeValue(by: elementLinksNode) /// remove link from element
        }
        transaction.removeValue(by: view.node!.child(with: item.dbKey)) /// remove item
    }
}

