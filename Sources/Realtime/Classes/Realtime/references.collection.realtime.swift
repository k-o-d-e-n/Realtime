//
//  References.swift
//  Realtime
//
//  Created by Denis Koryttsev on 16/03/2018.
//

import Foundation

public extension RawRepresentable where RawValue == String {
    func references<C, Element: Object>(in parentNode: Node?, elements: Node, database: RealtimeDatabase?) -> C where C: References<Element> {
        return C(
            in: Node(key: rawValue, parent: parentNode),
            options: C.Options(database: database, elements: elements, builder: { node, database, options in
                return Element(in: node, options: RealtimeValueOptions(database: database, raw: options.raw, payload: options.payload))
            })
        )
    }
    func references<C, Element: Object>(in object: Object, elements: Node) -> C where C: References<Element> {
        return references(in: object.node, elements: elements, database: object.database)
    }
    func references<C, Element>(in object: Object, elements: Node, builder: @escaping RCElementBuilder<RealtimeValueOptions, Element>) -> C where C: References<Element> {
        return C(
            in: Node(key: rawValue, parent: object.node),
            options: C.Options(database: object.database, elements: elements, builder: builder)
        )
    }
}

/// A Realtime database collection that stores elements in own database node as references.
public class __RepresentableCollection<Element, Ref: WritableRealtimeValue & Comparable>: _RealtimeValue, RealtimeCollection where Element: RealtimeValue {
    internal var storage: RCKeyValueStorage<Element>

    public override var raw: RealtimeDatabaseValue? { return nil }
    public override var payload: RealtimeDatabaseValue? { return nil }
    public let view: SortedCollectionView<Ref>
    public var isSynced: Bool { return view.isSynced }
    public override var isObserved: Bool { return view.isObserved }
    public override var canObserve: Bool { return view.canObserve }
    public var keepSynced: Bool {
        set { view.keepSynced = newValue }
        get { return view.keepSynced }
    }
    public lazy var changes: AnyListenable<RCEvent> = self.view.changes
        .map({ [unowned self] (data, e) in
            switch e {
            case .initial: return e
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
        })
        .shared(connectionLive: .continuous)
        .asAny()
    public var dataExplorer: RCDataExplorer = .view(ascending: false) {
        didSet { view.didChange(dataExplorer: dataExplorer) }
    }

    init(in node: Node?, options: RealtimeValueOptions) {
        self.storage = RCKeyValueStorage()
        self.view = SortedCollectionView(node: node, options: RealtimeValueOptions(database: options.database))
        super.init(node: node, options: options)
    }

    /// Creates new instance associated with database node
    ///
    /// Available options:
    /// - database: Database reference
    ///
    /// - Parameter node: Node location for value
    /// - Parameter options: Dictionary of options
    init(view: SortedCollectionView<Ref>, options: RealtimeValueOptions) {
        self.storage = RCKeyValueStorage()
        self.view = view
        super.init(node: view.node, options: options)
    }

    public required init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        self.storage = RCKeyValueStorage()
        self.view = SortedCollectionView(node: data.node, options: RealtimeValueOptions(database: data.database))
        try super.init(data: data, event: event)
    }

    // Implementation

    public subscript(position: Int) -> Element {
        let item = view[position]
        guard let element = storage.value(for: item.dbKey) else {
            let element = buildElement(with: item)
            storage.set(value: element, for: item.dbKey)
            return element
        }
        return element
    }

    override public func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        try super.apply(data, event: event)
        try view.apply(data, event: event)
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
        \(type(of: self)): \(withUnsafePointer(to: self, String.init(describing:))) {
            ref: \(node?.absolutePath ?? "not referred"),
            synced: \(isSynced), keep: \(keepSynced),
            elements: \(view.map { $0.dbKey })
        }
        """
    }

    internal func buildElement(with item: Ref) -> Element {
        fatalError("Override")
    }
}

// TODO: DistributedReferences has the same target, but has no linking with source object. This has, but is not used.
public class References<Element: RealtimeValue>: __RepresentableCollection<Element, RCItem>, WritableRealtimeCollection {
    internal let builder: RCElementBuilder<RealtimeValueOptions, Element>
    internal let spaceNode: Node

    public struct Options {
        let base: RealtimeValueOptions
        let elementsNode: Node
        let builder: RCElementBuilder<RealtimeValueOptions, Element>

        public init(database: RealtimeDatabase?, elements: Node, builder: @escaping RCElementBuilder<RealtimeValueOptions, Element>) {
            self.base = RealtimeValueOptions(database: database)
            self.elementsNode = elements
            self.builder = builder
        }
    }

    /// Creates new instance associated with database node
    ///
    /// Available options:
    /// - elementsNode(**required**): Database node where source elements are located.
    /// - database: Database reference
    /// - elementBuilder: Closure that calls to build elements lazily.
    ///
    /// - Parameter node: Node location for value
    /// - Parameter options: Dictionary of options
    public required init(in node: Node?, options: Options) {
        self.builder = options.builder
        self.spaceNode = options.elementsNode
        super.init(view: SortedCollectionView(node: node, options: options.base), options: options.base)
    }

    init(view: SortedCollectionView<RCItem>, options: Options) {
        self.builder = options.builder
        self.spaceNode = options.elementsNode
        super.init(view: view, options: options.base)
    }

    override func buildElement(with item: RCItem) -> Element {
        return builder(spaceNode.child(with: item.dbKey), database, RealtimeValueOptions(database: database, raw: item.raw, payload: item.payload))
    }

    /// Currently, no available.
    public required init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        #if DEBUG
        fatalError("References does not supported init(data:event:) yet. Use `init(data:event:options:)` instead")
        #else
        throw RealtimeError(source: .collection, description: "References does not supported init(data:event:) yet.")
        #endif
    }
}

// MARK: Mutating

public final class MutableReferences<Element: RealtimeValue>: References<Element>, MutableRealtimeCollection {
    override var _hasChanges: Bool { return view._hasChanges }

    public func write(_ element: Element, in transaction: Transaction) throws {
        try write(element: element, with: Int64(count), in: transaction)
    }
    public func write(_ element: Element) throws -> Transaction {
        return try write(element: element, with: Int64(count), in: nil)
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
    func write(element: Element, with priority: Int64? = nil,
                in transaction: Transaction? = nil) throws -> Transaction {
        guard isRooted, let database = self.database else { fatalError("This method is available only for rooted objects. Use method insert(element:at:)") }
        guard element.node?.parent == spaceNode else { fatalError("Element must be located in elements node") }
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
    public func insert(element: Element, with priority: Int64? = nil) {
        guard isStandalone else { fatalError("This method is available only for standalone objects. Use method write(element:at:in:)") }
        guard element.node?.parent == spaceNode else { fatalError("Element must be located in elements node") }
        let contains = element.node.map { n in storage[n.key] != nil } ?? false
        guard !contains else {
            fatalError("Element with such key already exists")
        }

        let index = priority ?? Int64(view.count)
        var item = RCItem(key: nil, value: element)
        item.priority = index
        storage.set(value: element, for: item.dbKey)
        view.insert(item)
    }

    public func delete(element: Element) {
        guard isStandalone else { fatalError("This method is available only for standalone objects. Use method write(element:at:in:)") }
        guard element.node?.parent == spaceNode else { fatalError("Element must be located in elements node") }
        let contains = element.node.map { n in storage[n.key] != nil } ?? false
        guard contains else {
            fatalError("Element with such key does not exist")
        }

        storage.remove(for: element.dbKey)
        guard let index = view.firstIndex(where: { $0.dbKey == element.dbKey }) else {
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
        _ element: Element, with priority: Int64?,
        in database: RealtimeDatabase, in transaction: Transaction? = nil
        ) throws -> Transaction {
        let transaction = transaction ?? Transaction(database: database)
        try _write(element, with: priority ?? view.last.flatMap { $0.priority.map { $0 + 1 } } ?? 0, by: node!, in: transaction)
        return transaction
    }

    internal func _write(_ element: Element, with priority: Int64,
                         by location: Node, in transaction: Transaction) throws {
        let itemNode = location.child(with: element.dbKey)
        var item = RCItem(key: itemNode.key, value: element)
        item.priority = priority

        transaction.addReversion({ [weak self] in
            self?.storage.remove(for: item.dbKey)
        })
        storage.set(value: element, for: item.dbKey)
        try item.write(to: transaction, by: itemNode) // add item element
    }

    private func _remove(_ element: Element, in transaction: Transaction) {
        if let item = view.first(where: { $0.dbKey == element.dbKey }) {
            _remove(for: item, in: transaction)
        } else {
            debugFatalError("Tries to remove not existed value")
        }
    }

    private func _remove(for item: RCItem, in transaction: Transaction) {
        if let linkID = item.linkID {
            let elementLinksNode = spaceNode.child(with: item.dbKey).linksItemsNode.child(with: linkID)
            transaction.removeValue(by: elementLinksNode) /// remove link from element
        }
        transaction.removeValue(by: view.node!.child(with: item.dbKey)) /// remove item
    }
}

// MARK: DistributedReferences

public struct RCRef: WritableRealtimeValue, Comparable {
    public var raw: RealtimeDatabaseValue? { return reference?.payload.raw }
    public var payload: RealtimeDatabaseValue? { return reference?.payload.user }
    public var node: Node?
    public let dbKey: String!
    var reference: ReferenceRepresentation!

    init(mode: ReferenceMode, value: RealtimeValue) {
        self.dbKey = value.dbKey
        let raw = value.raw
        let payload = value.payload
        let ref: String
        switch mode {
        case .fullPath: ref = value.node!.absolutePath
        case .path(from: let n): ref = value.node!.path(from: n)
        }
        self.reference = ReferenceRepresentation(
            ref: ref,
            payload: (raw, payload)
        )
    }

    public init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        guard let key = data.key else { throw RealtimeError(initialization: RCRef.self, data) }

        self.dbKey = key
        self.reference = try ReferenceRepresentation(data: data, event: event)
    }

    public func write(to transaction: Transaction, by node: Node) throws { transaction.addValue(try reference.defaultRepresentation(), by: node) }
    public var hashValue: Int { return dbKey.hashValue }
    public static func ==(lhs: RCRef, rhs: RCRef) -> Bool { return lhs.dbKey == rhs.dbKey }
    public static func < (lhs: RCRef, rhs: RCRef) -> Bool { return lhs.dbKey < rhs.dbKey }
}

public class RepresentableCollection<Element: RealtimeValue, Ref: WritableRealtimeValue & Comparable>: __RepresentableCollection<Element, Ref> {
    public typealias Builder = RCElementBuilder<Ref, Element>
    internal let builder: Builder

    public struct Options {
        let base: RealtimeValueOptions
        let builder: Builder

        public init(database: RealtimeDatabase?, builder: @escaping Builder) {
            self.base = RealtimeValueOptions(database: database)
            self.builder = builder
        }
    }

    /// Creates new instance associated with database node
    ///
    /// Available options:
    /// - database: Database reference
    /// - representableBuilder: Closure that calls to build elements lazily.
    ///
    /// - Parameter node: Node location for value
    /// - Parameter options: Dictionary of options
    public init(in node: Node?, options: Options) {
        self.builder = options.builder
        super.init(view: SortedCollectionView(node: node, options: options.base), options: options.base)
    }

    init(view: SortedCollectionView<Ref>, options: Options) {
        self.builder = options.builder
        super.init(view: view, options: options.base)
    }

    /// Currently, no available.
    public required init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        #if DEBUG
        fatalError("DistributedReferences does not supported init(data:event:) yet. Use `init(data:event:options:)` instead")
        #else
        throw RealtimeError(source: .collection, description: "DistributedReferences does not supported init(data:event:) yet.")
        #endif
    }

    override func buildElement(with item: Ref) -> Element {
        return builder(item.node, database, item)
    }
}
public final class DistributedReferences<Element: RealtimeValue>: __RepresentableCollection<Element, RCRef> {
    let anchorNode: Node
    let builder: RCElementBuilder<RealtimeValueOptions, Element>

    public struct Options {
        let base: RealtimeValueOptions
        let mode: ReferenceMode
        let builder: RCElementBuilder<RealtimeValueOptions, Element>

        public init(database: RealtimeDatabase?, mode: ReferenceMode, builder: @escaping RCElementBuilder<RealtimeValueOptions, Element>) {
            self.base = RealtimeValueOptions(database: database)
            self.mode = mode
            self.builder = builder
        }
    }

    /// Creates new instance associated with database node
    ///
    /// Available options:
    /// - reference(**required**): `ReferenceMode` value. (default: `case .fullPath`)
    /// - database: Database reference
    /// - elementBuilder: Closure that calls to build elements lazily.
    ///
    /// - Parameter node: Node location for value
    /// - Parameter options: Dictionary of options
    public required init(in node: Node?, options: Options) {
        let anchorNode: Node
        switch options.mode {
        case .fullPath: anchorNode = .root
        case .path(from: let n): anchorNode = n
        }
        self.anchorNode = anchorNode
        self.builder = options.builder
        super.init(in: node, options: options.base)
    }

    public required init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        fatalError("DistributedReferences does not supported init(data:event:) yet. Use `init(data:event:options:)` instead")
    }

    override func buildElement(with item: RCRef) -> Element {
        return builder(anchorNode.child(with: item.reference.source), database, RealtimeValueOptions(database: database, raw: item.raw, payload: item.payload))
    }
}

// MARK: Relations

public struct RelationsItem: WritableRealtimeValue, Comparable {
    public var raw: RealtimeDatabaseValue?
    public var payload: RealtimeDatabaseValue?
    public var node: Node?

    public let dbKey: String!
    var relation: RelationRepresentation!

    init(value: RealtimeValue) {
        self.dbKey = value.dbKey
        self.raw = value.raw
        self.payload = value.payload
    }

    public init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        self.dbKey = data.key
        self.relation = try RelationRepresentation(data: data, event: event)
    }

    public func write(to transaction: Transaction, by node: Node) throws {
        transaction.addValue(try relation.defaultRepresentation(), by: node)
    }

    public func defaultRepresentation() throws -> RealtimeDatabaseValue {
        return try relation.defaultRepresentation()
    }

    public var hashValue: Int { return dbKey.hashValue }
    public static func < (lhs: RelationsItem, rhs: RelationsItem) -> Bool {
        return lhs.relation.targetPath < rhs.relation.targetPath
    }
    public static func ==(lhs: RelationsItem, rhs: RelationsItem) -> Bool {
        return lhs.dbKey == rhs.dbKey
    }
}

public extension RawRepresentable where RawValue == String {
    func relations<V: Object>(in object: Object, anchor: Relations<V>.Options.Anchor = .root, ownerLevelsUp: UInt = 1, _ property: RelationProperty) -> Relations<V> {
        return Relations(
            in: Node(key: rawValue, parent: object.node),
            options: Relations<V>.Options(
                database: object.database,
                anchor: anchor,
                ownerLevelsUp: ownerLevelsUp,
                property: property,
                builder: { node, db, options in
                    return V(in: node, options: options)
                }
            )
        )
    }
}
public extension Relations where Element: Object {
    convenience init(in node: Node?, database: RealtimeDatabase?, anchor: Options.Anchor = .root, ownerLevelsUp: UInt = 1, _ property: RelationProperty) {
        self.init(
            in: node,
            options: Options(
                database: database,
                anchor: anchor,
                ownerLevelsUp: ownerLevelsUp,
                property: property,
                builder: { node, db, options in
                    return Element(in: node, options: options)
                }
            )
        )
    }
}

public class Relations<Element>: __RepresentableCollection<Element, RelationsItem>, WritableRealtimeCollection where Element: RealtimeValue {
    override var _hasChanges: Bool { return view._hasChanges }
    let options: Options

    public required init(in node: Node?, options: Options) {
        if let error = options.validate() {
            fatalError("Options invalid. Reason: \(error)")
        }

        self.options = options
        super.init(view: SortedCollectionView(node: node, options: options.base), options: options.base)
    }

    public required init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        #if DEBUG
        fatalError("Relations does not supported init(data:event:) yet. Use `init(data:event:options:)` instead")
        #else
        throw RealtimeError(source: .collection, description: "Relations does not supported init(data:event:) yet.")
        #endif
    }

    public struct Options {
        let base: RealtimeValueOptions
        /// Anchor behavior to get target path to relation owner
        let anchor: Anchor
        /// Levels up by hierarchy to relation owner of this property
        let ownerLevelsUp: UInt
        /// String path from related object to his relation property
        let property: RelationProperty
        let builder: RCElementBuilder<RealtimeValueOptions, Element>

        // TODO: Don`t control element node, because crash
        public enum Anchor {
            case root
            case branch(collection: Node, backward: Node)
            case levelsUp(UInt)
        }

        public init(database: RealtimeDatabase?, anchor: Anchor, ownerLevelsUp: UInt, property: RelationProperty, builder: @escaping RCElementBuilder<RealtimeValueOptions, Element>) {
            self.base = RealtimeValueOptions(database: database)
            self.anchor = anchor
            self.ownerLevelsUp = ownerLevelsUp
            self.property = property
            self.builder = builder
        }

        fileprivate func anchorNode(forOwner node: Node) -> Node? {
            switch anchor {
            case .root: return .root
            case .branch(let coll, _): return node.branch == coll ? coll : nil
            case .levelsUp(let up): return node.ancestor(onLevelUp: up)
            }
        }

        fileprivate func anchorNode(forCollection node: Node) -> Node? {
            switch anchor {
            case .root: return .root
            case .branch(let coll, _): return node.branch == coll ? coll : nil
            case .levelsUp(let up): return node.ancestor(onLevelUp: ownerLevelsUp)?.ancestor(onLevelUp: up)
            }
        }

        fileprivate func elementPath(with node: Node, anchorNode: Node) -> String {
            switch anchor {
            case .root: return node.absolutePath
            case .branch: return node.path
            case .levelsUp: return node.path(from: anchorNode)
            }
        }

        fileprivate func anchor(forElement element: Node, collection: Node) -> (owner: Node, element: Node)? {
            switch anchor {
            case .root: return (.root, .root)
            case .branch(let coll, let elem):
                if collection.hasAncestor(node: coll) {
                    return (coll, elem)
                } else {
                    return nil
                }
            case .levelsUp(let up):
                return collection.ancestor(onLevelUp: ownerLevelsUp).flatMap { owner -> (Node, Node)? in
                    return owner.ancestor(onLevelUp: up).flatMap { anchor in
                        return element.hasAncestor(node: anchor) ? (anchor, anchor) : nil
                    }
                }
            }
        }

        fileprivate func validate() -> String? {
            guard ownerLevelsUp > 0 else {
                return "`ownerLevelUp` must be more than 0"
            }
            switch anchor {
            case .branch(let coll, let elem):
                if !coll.isAnchor || !elem.isAnchor {
                    return "current `branch` node cannot be used, use specially defined `BranchNode`"
                } else {
                    return nil
                }
            case .levelsUp(0): return "`levelsUp` must be more than 0"
            default: return nil
            }
        }
    }

    override func _write(to transaction: Transaction, by node: Node) throws {
        /// skip the call of super
        guard let ownerNode = node.ancestor(onLevelUp: options.ownerLevelsUp) else {
            throw RealtimeError(source: .collection, description: "Cannot get owner node from levels up: \(options.ownerLevelsUp)")
        }
        guard let anchorNode = options.anchorNode(forOwner: ownerNode) else {
            throw RealtimeError(source: .collection, description: "Couldn`t get anchor node for node \(ownerNode)")
        }
        let view = storage.map { (keyValue) -> RelationsItem in
            let elementNode = keyValue.value.node!
            let relation = RelationRepresentation(
                path: elementNode.path(from: anchorNode),
                property: options.property.path(for: ownerNode),
                payload: (keyValue.value.raw, keyValue.value.payload)
            )
            var item = RelationsItem(value: keyValue.value)
            item.relation = relation
            return item
        }
        self.view.elements = SortedArray(view)
        try self.view._write(to: transaction, by: node)
    }

    override func buildElement(with item: RelationsItem) -> Element {
        guard let ownerNode = self.node?.ancestor(onLevelUp: options.ownerLevelsUp) else { fatalError("Collection must be rooted") }
        guard let anchorNode = options.anchorNode(forOwner: ownerNode) else { fatalError("Couldn`t get anchor node for node \(ownerNode)") }
        let elementNode = anchorNode.child(with: item.relation.targetPath)
        return options.builder(elementNode, database, RealtimeValueOptions(database: database, raw: item.raw, payload: item.payload))
    }

    public override func didSave(in database: RealtimeDatabase, in parent: Node, by key: String) {
        debugFatalError(
            condition: options.anchorNode(forCollection: Node(key: key, parent: parent)) == nil,
            "Collection did save in node that is not have ancestor with defined anchor type \(options.anchor)"
        )
        super.didSave(in: database, in: parent, by: key)
    }
}

extension Relations: MutableRealtimeCollection, ChangeableRealtimeValue {
    public func write(_ element: Element, in transaction: Transaction) throws {
        try write(element: element, in: transaction)
    }
    public func write(_ element: Element) throws -> Transaction {
        return try write(element: element, in: nil)
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
    func write(element: Element, in transaction: Transaction? = nil) throws -> Transaction {
        guard let node = self.node, node.isRooted, let database = self.database
        else { fatalError("This method is available only for rooted objects. Use method insert(element:at:)") }
        guard element.isRooted else { fatalError("Element must be rooted") }
        guard let anchorNode = options.anchor(forElement: element.node!, collection: node)
        else { fatalError("Couldn`t get anchor node") }
        guard isSynced else {
            let transaction = transaction ?? Transaction(database: database)
            transaction.addPrecondition { [unowned transaction] promise in
                self.view._contains(with: element.dbKey) { contains, err in
                    if let e = err {
                        promise.reject(RealtimeError(external: e, in: .collection))
                    } else if contains {
                        promise.reject(RealtimeError(
                            source: .collection,
                            description: "Element cannot be inserted, because already exists"
                        ))
                    } else {
                        do {
                            try self._write(element, in: anchorNode, in: database, in: transaction)
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
        return try _write(element, in: anchorNode, in: database, in: transaction)
    }

    /// Adds element with default sorting priority index or if `nil` to end of collection
    ///
    /// This method is available only if collection is **standalone**,
    /// otherwise use **func write(element:with:in:)**
    ///
    /// - Parameters:
    ///   - element: The element to write
    ///   - index: Priority value or `nil` if you want to add to end of collection.
    public func insert(element: Element) {
        guard isStandalone else { fatalError("This method is available only for standalone objects. Use method write(element:at:in:)") }
        let contains = element.node.map { n in storage[n.key] != nil } ?? false
        guard !contains else {
            fatalError("Element with such key already exists")
        }
        let item = RelationsItem(value: element)
        storage.set(value: element, for: item.dbKey)
        view.insert(item)
    }

    public func delete(element: Element) {
        guard isStandalone else { fatalError("This method is available only for standalone objects. Use method write(element:at:in:)") }
        let contains = element.node.map { n in storage[n.key] != nil } ?? false
        guard contains else {
            fatalError("Element with such key does not exist")
        }

        storage.remove(for: element.dbKey)
        guard let index = view.firstIndex(where: { $0.dbKey == element.dbKey }) else {
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
    public func remove(element: Element, in transaction: Transaction? = nil) -> Transaction {
        guard isRooted, let database = self.database else { fatalError("This method is available only for rooted objects") }

        let transaction = transaction ?? Transaction(database: database)
        guard isSynced else {
            transaction.addPrecondition { [unowned transaction] promise in
                self.view._item(for: element.dbKey) { item, err in
                    if let e = err {
                        promise.reject(RealtimeError(external: e, in: .collection))
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
        _ element: Element,
        in anchor: (element: Node, owner: Node),
        in database: RealtimeDatabase,
        in transaction: Transaction? = nil
        ) throws -> Transaction {
        let transaction = transaction ?? Transaction(database: database)
        try _write(element, by: node!, in: anchor, in: transaction)
        return transaction
    }

    internal func _write(_ element: Element, by location: Node, in anchorNode: (element: Node, owner: Node), in transaction: Transaction) throws {
        let owner = location.ancestor(onLevelUp: options.ownerLevelsUp)!
        let itemNode = location.child(with: element.dbKey)
        let elementNode = element.node!
        let elementRelation = RelationRepresentation(
            path: options.elementPath(with: elementNode, anchorNode: anchorNode.element),
            property: options.property.path(for: owner),
            payload: (element.raw, element.payload)
        )
        var item = RelationsItem(value: element)
        item.relation = elementRelation

        transaction.addReversion({ [weak self] in
            self?.storage.remove(for: item.dbKey)
        })
        storage.set(value: element, for: item.dbKey)
        transaction.addValue(try item.defaultRepresentation(), by: itemNode) /// add item element
    }

    private func _remove(_ element: Element, in transaction: Transaction) {
        if let item = view.first(where: { $0.dbKey == element.dbKey }) {
            _remove(for: item, in: transaction)
        } else {
            debugFatalError("Tries to remove not existed value")
        }
    }

    private func _remove(for item: RelationsItem, in transaction: Transaction) {
        let element = storage.remove(for: item.dbKey) ?? buildElement(with: item)
        transaction.addReversion { [weak self] in
            self?.storage[item.dbKey] = element
        }
        transaction.removeValue(by: view.node!.child(with: item.dbKey)) /// remove item
    }
}
