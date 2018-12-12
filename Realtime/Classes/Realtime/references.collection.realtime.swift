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
public class __RepresentableCollection<Element, Ref: RCViewItem>: _RealtimeValue, RealtimeCollection where Element: RealtimeValue {
    internal var storage: RCKeyValueStorage<Element>

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
    /// - database: Database reference
    ///
    /// - Parameter node: Node location for value
    /// - Parameter options: Dictionary of options
    public required convenience init(in node: Node?, options: [ValueOption : Any]) {
        self.init(view: SortedCollectionView(in: node, options: options), options: options)
    }

    init(view: SortedCollectionView<Ref>, options: [ValueOption: Any]) {
        self.storage = RCKeyValueStorage()
        self.view = view
        super.init(in: view.node, options: options)
    }

    public convenience init(data: RealtimeDataProtocol, exactly: Bool, elementsNode: Node) throws {
        self.init(in: data.node, options: [.elementsNode: elementsNode,
                                               .database: data.database as Any])
        try apply(data, exactly: exactly)
    }

    public required init(data: RealtimeDataProtocol, exactly: Bool) throws {
        self.storage = RCKeyValueStorage()
        self.view = SortedCollectionView(in: data.node, options: [.database: data.database as Any])
        try super.init(data: data, exactly: exactly)
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

    internal func buildElement(with item: Ref) -> Element {
        fatalError("Override")
    }
}

public class References<Element: RealtimeValue>: __RepresentableCollection<Element, RCItem>, WritableRealtimeCollection {
    internal let builder: RealtimeValueBuilder<Element>

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
        self.builder = RealtimeValueBuilder(spaceNode: elements, impl: builder)
        super.init(view: SortedCollectionView(in: node, options: options),
                   options: options)
    }

    override func buildElement(with item: RCItem) -> Element {
        return builder.build(with: item)
    }

    /// Currently, no available.
    public required init(data: RealtimeDataProtocol, exactly: Bool) throws {
        #if DEBUG
        fatalError("References does not supported init(data:exactly:) yet.")
        #else
        throw RealtimeError(source: .collection, description: "References does not supported init(data:exactly:) yet.")
        #endif
    }
}

// MARK: Mutating

public final class MutableReferences<Element: RealtimeValue>: References<Element>, MutableRealtimeCollection {
    override var _hasChanges: Bool { return view._hasChanges }

    private var shouldLinking = true // TODO: Fix it
    public func unlinked() -> MutableReferences<Element> { shouldLinking = false; return self }

    public func write(_ element: Element, in transaction: Transaction) throws {
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
        guard element.node?.parent == builder.spaceNode else { fatalError("Element must be located in elements node") }
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
        guard element.node?.parent == builder.spaceNode else { fatalError("Element must be located in elements node") }
        let contains = element.node.map { n in storage[n.key] != nil } ?? false
        guard !contains else {
            fatalError("Element with such key already exists")
        }

        let index = priority ?? view.count
        let item = RCItem(element: element, priority: index, linkID: nil)
        storage.set(value: element, for: item.dbKey)
        view.insert(item)
    }

    public func delete(element: Element) {
        guard isStandalone else { fatalError("This method is available only for standalone objects. Use method write(element:at:in:)") }
        guard element.node?.parent == builder.spaceNode else { fatalError("Element must be located in elements node") }
        let contains = element.node.map { n in storage[n.key] != nil } ?? false
        guard contains else {
            fatalError("Element with such key does not exist")
        }

        storage.remove(for: element.dbKey)
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
            self?.storage.remove(for: item.dbKey)
        })
        storage.set(value: element, for: item.dbKey)
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
        let element = storage.remove(for: item.dbKey)
        transaction.addReversion { [weak self] in
            self?.storage[item.dbKey] = element
        }
        if let linkID = item.linkID {
            let elementLinksNode = builder.spaceNode.child(with: item.dbKey).linksItemsNode.child(with: linkID)
            transaction.removeValue(by: elementLinksNode) /// remove link from element
        }
        transaction.removeValue(by: view.node!.child(with: item.dbKey)) /// remove item
    }
}

// MARK: Relations

public struct RelationsItem: RCViewItem, Comparable {
    public let dbKey: String!
    let relation: RelationRepresentation!
    public var payload: RealtimeValuePayload {
        return RealtimeValuePayload(system: (nil, nil), user: nil)
    }

    public init(_ element: (key: String, relation: RelationRepresentation?)) {
        self.relation = element.relation
        self.dbKey = element.key
    }

    public init(data: RealtimeDataProtocol, exactly: Bool) throws {
        self.dbKey = data.key
        self.relation = try RelationRepresentation(data: data, exactly: exactly)
    }

    public var rdbValue: RealtimeDataValue {
        return relation.rdbValue
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
    func relations<V: Object>(in object: Object, anchor: Relations<V>.Options.Anchor = .root, ownerLevelsUp: UInt = 1, _ property: RelationMode) -> Relations<V> {
        return Relations(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .relation: Relations<V>.Options(
                    anchor: anchor,
                    ownerLevelsUp: ownerLevelsUp,
                    property: property
                )
            ]
        )
    }
}

public class Relations<Element>: __RepresentableCollection<Element, RelationsItem>, WritableRealtimeCollection where Element: RealtimeValue {
    override var _hasChanges: Bool { return view._hasChanges }
    let options: Options

    public required init(in node: Node?, options: [ValueOption: Any]) {
        guard case let relation as Options = options[.relation] else { fatalError("Skipped required options") }
        if let error = relation.validate() {
            fatalError("Options invalid. Reason: \(error)")
        }
//        guard let n = node, n.ancestor(onLevelUp: relation.ownerLevelsUp) != nil else {
//            fatalError("Collection node is not have ancestor on \(relation.ownerLevelsUp) level up")
//        }

        self.options = relation
        super.init(view: SortedCollectionView(in: node, options: options),
                   options: options)
    }

    public required init(data: RealtimeDataProtocol, exactly: Bool) throws {
        #if DEBUG
        fatalError("References does not supported init(data:exactly:) yet.")
        #else
        throw RealtimeError(source: .collection, description: "References does not supported init(data:exactly:) yet.")
        #endif
    }

    public struct Options {
        /// Anchor behavior to get target path to relation owner
        let anchor: Anchor
        /// Levels up by hierarchy to relation owner of this property
        let ownerLevelsUp: UInt
        /// String path from related object to his relation property
        let property: RelationMode

        // TODO: Don`t control element node, because crash
        public enum Anchor {
            case root
            case branch(collection: Node, backward: Node)
            case levelsUp(UInt)
        }

        public init(anchor: Anchor, ownerLevelsUp: UInt, property: RelationMode) {
            self.anchor = anchor
            self.ownerLevelsUp = ownerLevelsUp
            self.property = property
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

        fileprivate func anchorNode(forElement node: Node) -> Node? {
            switch anchor {
            case .root: return .root
            case .branch(_, let elem): return node.branch == elem ? elem : nil
            case .levelsUp(let up): return node.ancestor(onLevelUp: up)
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
            let relation = RelationRepresentation(path: elementNode.path(from: anchorNode), property: options.property.path(for: ownerNode))
            /// a backward write
            if shouldWriteBackward {
                let ownerRelation = RelationRepresentation(path: ownerNode.path(from: anchorNode), property: node.child(with: keyValue.key).path(from: ownerNode))
                transaction.addValue(ownerRelation.rdbValue, by: elementNode.child(with: options.property.propertyPath))
            }
            return RelationsItem((keyValue.key, relation))
        }
        self.view.elements = SortedArray(view)
        try self.view._write(to: transaction, by: node)
    }

    override func buildElement(with item: RelationsItem) -> Element {
        guard let ownerNode = self.node?.ancestor(onLevelUp: options.ownerLevelsUp) else { fatalError("Collection must be rooted") }
        guard let anchorNode = options.anchorNode(forOwner: ownerNode) else { fatalError("Couldn`t get anchor node for node \(ownerNode)") }
        let elementNode = anchorNode.child(with: item.relation.targetPath)
        return Element(in: elementNode, options: [:])
    }

    public override func didSave(in database: RealtimeDatabase, in parent: Node, by key: String) {
        debugFatalError(
            condition: options.anchorNode(forCollection: Node(key: key, parent: parent)) == nil,
            "Collection did save in node that is not have ancestor with defined anchor type \(options.anchor)"
        )
        super.didSave(in: database, in: parent, by: key)
    }

    // TODO: Reconsider after remove backward writing
    public override func willRemove(in transaction: Transaction, from ancestor: Node) {
        super.willRemove(in: transaction, from: ancestor)
        transaction.addPrecondition { [unowned transaction] (promise) in
            self.view.load(completion: .just { [unowned self] e in
                self.view.forEach({ (item) in
                    self._removeBackward(for: item, element: nil, in: transaction)
                })
            })
        }
    }

    fileprivate var shouldWriteBackward: Bool = true
    public func unWrittenBackward() -> Relations<Element> {
        self.shouldWriteBackward = false
        return self
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
        let item = RelationsItem((element.dbKey, nil))
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
            property: options.property.path(for: owner)
        )
        let item = RelationsItem((elementNode.key, elementRelation))

        transaction.addReversion({ [weak self] in
            self?.storage.remove(for: item.dbKey)
        })
        storage.set(value: element, for: item.dbKey)
        transaction.addValue(item.rdbValue, by: itemNode) /// add item element

        /// a backward write
        if shouldWriteBackward {
            let ownerRelation = RelationRepresentation(path: owner.path(from: anchorNode.owner), property: itemNode.path(from: owner))
            transaction.addValue(
                ownerRelation.rdbValue,
                by: elementNode.copy(to: anchorNode.element).child(with: options.property.propertyPath).child(with: owner.key)
            )
        }
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
        /// a backward remove
        if shouldWriteBackward {
            _removeBackward(for: item, element: element, in: transaction)
        }
    }

    private func _removeBackward(for item: RelationsItem, element: Element?, in transaction: Transaction) {
        let anchorNode = options.anchor(forElement: (element ?? buildElement(with: item)).node!, collection: self.node!)!.element
        let ownerNode = self.node!.ancestor(onLevelUp: options.ownerLevelsUp)!
        transaction.removeValue(
            by: anchorNode.child(with: item.relation.targetPath).child(with: item.relation.relatedProperty).child(with: ownerNode.key)
        )
    }
}
