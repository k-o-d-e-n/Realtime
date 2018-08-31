//
//  References.swift
//  Realtime
//
//  Created by Denis Koryttsev on 16/03/2018.
//

import Foundation

public extension RawRepresentable where RawValue == String {
    func linkedArray<Element>(from node: Node?, elements: Node) -> References<Element> {
        return References(in: Node(key: rawValue, parent: node), options: [.elementsNode: elements])
    }
    func linkedArray<Element>(from node: Node?, elements: Node, elementOptions: [ValueOption: Any]) -> References<Element> {
        return linkedArray(from: node, elements: elements, builder: { (node, options) in
            let compoundOptions = options.merging(elementOptions, uniquingKeysWith: { remote, local in remote })
            return Element(in: node, options: compoundOptions)
        })
    }
    func linkedArray<Element>(from node: Node?, elements: Node, builder: @escaping RCElementBuilder<Element>) -> References<Element> {
        return References(in: node, options: [.elementsNode: elements, .elementBuilder: builder])
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
    public var isPrepared: Bool { return _view.isPrepared }

    let _view: AnyRealtimeCollectionView<[RCItem], References>

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
        self._view = AnyRealtimeCollectionView(Property(in: node, representer: Representer<[RCItem]>(collection: Representer.realtimeData)).defaultOnEmpty())
        super.init(in: node, options: options)
        self._view.collection = self
    }

    // MARK: Realtime

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
    public func listening(changes handler: @escaping () -> Void) -> ListeningItem { return _view.source.listeningItem(.just { _ in handler() }) }
    @discardableResult
    override public func runObserving(_ event: DatabaseDataEvent = .value) -> Bool { return _view.source.runObserving(event) }
    override public func stopObserving(_ event: DatabaseDataEvent) { _view.source.stopObserving(event) }
    public func prepare(forUse completion: Assign<(Error?)>) { _view.prepare(forUse: completion) }

    override public var debugDescription: String {
        return """
        {
            ref: \(node?.rootPath ?? "not referred"),
            prepared: \(isPrepared),
            elements: \(_view.value.map { (key: $0.dbKey, index: $0.index) })
        }
        """
    }

    override public func apply(_ data: RealtimeDataProtocol, exactly: Bool) throws {
        try super.apply(data, exactly: exactly)
        try _view.source.apply(data, exactly: exactly)
        _view.isPrepared = exactly
    }

    /// Collection does not respond for versions and raw value, and also payload.
    /// To change value version/raw can use enum, but use modified representer.
    override func _write(to transaction: Transaction, by node: Node) throws {
        /// skip the call of super
        for (index, element) in storage.elements.enumerated() {
            _ = _view.remove(at: index)
            try _write(element.value, at: index, by: node, in: transaction)
        }
    }

    public func didPrepare() {}

    public override func didSave(in database: RealtimeDatabase, in parent: Node, by key: String) {
        super.didSave(in: database, in: parent, by: key)
        _view.source.didSave(in: database, in: parent)
    }

    public override func willRemove(in transaction: Transaction, from ancestor: Node) {
        super.willRemove(in: transaction, from: ancestor)
        _view.source.willRemove(in: transaction, from: ancestor)
    }
    override public func didRemove(from node: Node) {
        super.didRemove(from: node)
        _view.source.didRemove()
    }
}

// MARK: Mutating

public extension References {
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
    func write(element: Element, at index: Int? = nil,
                in transaction: Transaction? = nil) throws -> Transaction {
        guard isRooted, let database = self.database else { fatalError("This method is available only for rooted objects. Use method insert(element:at:)") }
        guard element.node?.parent == storage.sourceNode else { fatalError("Element must be located in elements node") }
        guard isPrepared else {
            let transaction = transaction ?? Transaction(database: database)
            transaction.addPrecondition { [unowned transaction] promise in
                self.prepare(forUse: .just { collection, err in
                    if let e = err {
                        promise.reject(e)
                    } else {
                        do {
                            try collection._write(element, at: index, in: database, in: transaction)
                            promise.fulfill()
                        } catch let e {
                            promise.reject(e)
                        }
                    }
                })
            }
            return transaction
        }

        return try _write(element, at: index, in: database, in: transaction)
    }

    /// Adds element at passed index or if `nil` to end of collection
    ///
    /// This method is available only if collection is **standalone**,
    /// otherwise use **func write(element:at:in:)**
    ///
    /// - Parameters:
    ///   - element: The element to write
    ///   - index: Index value or `nil` if you want to add to end of collection.
    func insert(element: Element, at index: Int? = nil) {
        guard isStandalone else { fatalError("This method is available only for standalone objects. Use method write(element:at:in:)") }
        guard element.node?.parent == storage.sourceNode else { fatalError("Element must be located in elements node") }
        let contains = element.node.map { n in storage.elements[n.key] != nil } ?? false
        guard !contains else {
            fatalError("Element with such key already exists")
        }

        let index = index ?? _view.count
        storage.elements[element.dbKey] = element
        _view.insert(RCItem(element: element, linkID: "", index: index), at: index)
    }

    @discardableResult
    internal func _write(_ element: Element, at index: Int? = nil, in database: RealtimeDatabase, in transaction: Transaction? = nil) throws -> Transaction {
        guard !contains(element) else { throw RealtimeError(source: .collection, description: "Element already contains. Element: \(element)") }

        let transaction = transaction ?? Transaction(database: database)
        try _write(element, at: index ?? count, by: node!, in: transaction)
        return transaction
    }

    internal func _write(_ element: Element, at index: Int,
                by location: Node, in transaction: Transaction) throws {
        let itemNode = location.child(with: element.dbKey)
        let link = element.node!.generate(linkTo: itemNode)
        let item = RCItem(element: element, linkID: link.link.id, index: index)

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
    func remove(at index: Int, in transaction: Transaction? = nil) -> Transaction {
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

    private func _remove(_ element: Element, in transaction: Transaction) {
        if let index = _view.index(where: { $0.dbKey == element.dbKey }) {
            _remove(at: index, in: transaction)
        } else {
            debugFatalError("Tries to remove not existed value")
        }
    }

    private func _remove(at index: Int, in transaction: Transaction) {
        if !_view.source.hasChanges {
            transaction.addReversion(_view.source.currentReversion())
        }
        let item = _view.remove(at: index)
        let element = storage.elements.removeValue(forKey: item.dbKey)
        transaction.addReversion { [weak self] in
            self?.storage.elements[item.dbKey] = element
        }
        transaction.removeValue(by: _view.source.node!.child(with: item.dbKey))
        let elementLinksNode = storage.sourceNode.linksNode.child(
            with: item.dbKey.subpath(with: item.linkID)
        )
        transaction.removeValue(by: elementLinksNode)
    }
}

