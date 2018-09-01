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
    func array<Element>(from node: Node?) -> Values<Element> {
        return Values(in: Node(key: rawValue, parent: node))
    }
    func array<Element>(from node: Node?, elementOptions: [ValueOption: Any]) -> Values<Element> {
        return array(from: node, builder: { (node, options) in
            let compoundOptions = options.merging(elementOptions, uniquingKeysWith: { remote, local in remote })
            return Element(in: node, options: compoundOptions)
        })
    }
    func array<Element>(from node: Node?, builder: @escaping RCElementBuilder<Element>) -> Values<Element> {
        return Values(in: Node(key: rawValue, parent: node), options: [.elementBuilder: builder])
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
    public var isPrepared: Bool { return _view.isPrepared }

    let _view: AnyRealtimeCollectionView<[RCItem], Values>

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
            viewSource: InternalKeys.items.property(
                from: viewParentNode,
                representer: Representer<[RCItem]>.collectionView()
            ).defaultOnEmpty()
        )
    }

    init(in node: Node?,
         options: [ValueOption: Any],
         viewSource: Property<[RCItem]>) {
        let builder = options[.elementBuilder] as? RCElementBuilder<Element> ?? Element.init
        self.storage = RCArrayStorage(sourceNode: node, elementBuilder: builder, elements: [:])
        self._view = AnyRealtimeCollectionView(viewSource)
        super.init(in: node, options: options)
        self._view.collection = self
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
    override public func runObserving(_ event: DatabaseDataEvent = .value) -> Bool { return _view.source.runObserving(event) }
    override public func stopObserving(_ event: DatabaseDataEvent) { _view.source.stopObserving(event) }
    public func prepare(forUse completion: Assign<(Error?)>) { _view.prepare(forUse: completion) }

    public lazy var changes: AnyListenable<RCEvent> = {
        guard _view.source.isRooted else {
            fatalError("Can`t get reference")
        }

        return Accumulator(repeater: .unsafe(), _view.source.dataObserver.map { [unowned self] (value) -> RCEvent in
            switch value.1 {
            case .value:
                return .initial
            case .childAdded:
                let item = try RCItem(data: value.0)
                self._view.insertRemote(item, at: item.index)
                return .updated((deleted: [], inserted: [item.index], modified: [], moved: []))
            case .childRemoved:
                let item = try RCItem(data: value.0)
                let index = self._view.removeRemote(item)
                return .updated((deleted: index.map { [$0] } ?? [], inserted: [], modified: [], moved: []))
            case .childChanged:
                let item = try RCItem(data: value.0)
                let index = self._view.moveRemote(item)
                return .updated((deleted: [], inserted: [], modified: [], moved: index.map { [($0, item.index)] } ?? []))
            case .childMoved:
                return .updated((deleted: [], inserted: [], modified: [], moved: []))
            }
        }).asAny()
    }()

    override public var debugDescription: String {
        return """
        {
            ref: \(node?.rootPath ?? "not referred"),
            prepared: \(isPrepared),
            elements: \(_view.value.map { (key: $0.dbKey, index: $0.index) })
        }
        """
    }
    
    // MARK: Mutating

    /// Adds element to collection at passed index,
    /// and writes a changes to transaction.
    ///
    /// If collection is standalone, use **func insert(element:at:)** instead.
    ///
    /// - Parameters:
    ///   - element: The element to write
    ///   - index: Index value or `nil` if you want to add to end of collection.
    ///   - transaction: Write transaction to keep the changes
    /// - Returns: A passed transaction or created inside transaction.
    @discardableResult
    public func write(element: Element, at index: Int? = nil, in transaction: Transaction? = nil) throws -> Transaction {
        guard isRooted, let database = self.database else { fatalError("This method is available only for rooted objects. Use method insert(element:at:)") }
        guard !element.isReferred || element.node!.parent == storage.sourceNode
            else { fatalError("Element must not be referred in other location") }
        guard isPrepared else {
            let transaction = transaction ?? Transaction(database: database)
            transaction.addPrecondition { [unowned transaction] promise in
                self.prepare(forUse: .just { collection, err in
                    if let e = err {
                        promise.reject(e)
                    } else {
                        do {
                            try collection._insert(element, at: index, in: database, in: transaction)
                            promise.fulfill()
                        } catch let e {
                            promise.reject(e)
                        }
                    }
                })
            }
            return transaction
        }

        return try _insert(element, at: index, in: database, in: transaction)
    }

    /// Adds element at passed index or if `nil` to end of collection
    ///
    /// This method is available only if collection is **standalone**,
    /// otherwise use **func write(element:at:in:)**
    ///
    /// - Parameters:
    ///   - element: The element to write
    ///   - index: Index value or `nil` if you want to add to end of collection.
    public func insert(element: Element, at index: Int? = nil) {
        guard isStandalone else { fatalError("This method is available only for standalone objects. Use method write(element:at:in:)") }
        guard !element.isReferred || element.node!.parent == storage.sourceNode
            else { fatalError("Element must not be referred in other location") }
        let contains = element.node.map { n in storage.elements[n.key] != nil } ?? false
        guard !contains else {
            fatalError("Element with such key already exists")
        }

        let index = index ?? _view.count
        let key = element.node.map { $0.key } ?? String(index)
        storage.elements[key] = element
        _view.insert(RCItem(element: element, key: key, linkID: "", index: index), at: index)
    }

    @discardableResult
    func _insert(_ element: Element, at index: Int? = nil, in database: RealtimeDatabase, in transaction: Transaction? = nil) throws -> Transaction {
        guard element.node.map({ _ in !contains(element) }) ?? true
            else { fatalError("Element with such key already exists") }

        let transaction = transaction ?? Transaction(database: database)
        try _write(element, at: index ?? count, by: (storage: node!, itms: _view.source.node!), in: transaction)
        return transaction
    }

    func _write(_ element: Element, at index: Int,
                by location: (storage: Node, itms: Node), in transaction: Transaction) throws {
        let elementNode = element.node.map { $0.moveTo(location.storage); return $0 } ?? location.storage.childByAutoId()
        let itemNode = location.itms.child(with: elementNode.key)
        let link = elementNode.generate(linkTo: itemNode)
        let item = RCItem(element: element, key: elementNode.key, linkID: link.link.id, index: index)

        var reversion: () -> Void {
            let sourceRevers = _view.source.hasChanges ?
                nil : _view.source.currentReversion()

            return { [weak self] in
                sourceRevers?()
                self?.storage.elements.removeValue(forKey: item.dbKey)
            }
        }
        transaction.addReversion(reversion)
        _view.insert(item, at: item.index)
        storage.store(value: element, by: item)
        transaction.addValue(item.rdbValue, by: itemNode)
        transaction.addValue(link.link.rdbValue, by: link.node)
        try transaction.set(element, by: elementNode)
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
        guard isPrepared else {
            transaction.addPrecondition { [unowned transaction] promise in
                self.prepare(forUse: .just { collection, err in
                    if let e = err {
                        promise.reject(e)
                    } else {
                        collection._remove(element, in: transaction)
                        promise.fulfill()
                    }
                })
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

        let transaction = transaction ?? Transaction(database: database)
        guard isPrepared else {
            transaction.addPrecondition { [unowned transaction] promise in
                self.prepare(forUse: .just { collection, err in
                    if let e = err {
                        promise.reject(e)
                    } else {
                        collection._remove(at: index, in: transaction)
                        promise.fulfill()
                    }
                })
            }
            return transaction
        }

        _remove(at: index, in: transaction)
        return transaction
    }

    func _remove(_ element: Element, in transaction: Transaction) {
        if let index = _view.index(where: { $0.dbKey == element.dbKey }) {
            return _remove(at: index, in: transaction)
        } else {
            debugFatalError("Tries to remove not existed value")
        }
    }

    func _remove(at index: Int, in transaction: Transaction) {
        if !_view.source.hasChanges {
            transaction.addReversion(_view.source.currentReversion())
        }
        let item = _view.remove(at: index)
        let element = storage.elements.removeValue(forKey: item.dbKey) ?? storage.object(for: item)
        element.willRemove(in: transaction, from: storage.sourceNode)
        transaction.addReversion { [weak self] in
            self?.storage.elements[item.dbKey] = element
        }
        transaction.removeValue(by: _view.source.node!.child(with: item.dbKey)) // remove item element
        transaction.removeValue(by: storage.sourceNode.child(with: item.dbKey)) // remove element
        transaction.addCompletion { result in
            if result {
                element.didRemove()
            }
        }
    }
    
    // MARK: Realtime

    public required init(data: RealtimeDataProtocol, exactly: Bool) throws {
        let node = data.node
        let viewParentNode = node.flatMap { $0.isRooted ? $0.linksNode : nil }
        self.storage = RCArrayStorage(sourceNode: node, elementBuilder: Element.init, elements: [:])
        self._view = AnyRealtimeCollectionView(InternalKeys.items.property(from: viewParentNode, representer: Representer<[RCItem]>(collection: Representer.realtimeData).defaultOnEmpty()))
        try super.init(data: data, exactly: exactly)
        self._view.collection = self
    }

    var _snapshot: (RealtimeDataProtocol, Bool)?
    override public func apply(_ data: RealtimeDataProtocol, exactly: Bool) throws {
        guard _view.isPrepared else {
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
        for (index, element) in elems.enumerated() {
            _ = _view.remove(at: index)
            try _write(element.value,
                       at: index,
                       by: (storage: node,
                            itms: Node(key: InternalKeys.items, parent: node.linksNode)),
                       in: transaction)
        }
    }

    public func didPrepare() {
        try? _snapshot.map(apply)
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
    override public func didRemove(from node: Node) {
        super.didRemove(from: node)
        _view.source.didRemove()
        storage.elements.values.forEach { $0.didRemove(from: storage.sourceNode) }
    }
}
