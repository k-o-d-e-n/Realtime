//
//  LinkedRealtimeArray.swift
//  Realtime
//
//  Created by Denis Koryttsev on 16/03/2018.
//

import Foundation

public extension RTNode where RawValue == String {
    func linkedArray<Element>(from node: Node?, elements: Node) -> LinkedRealtimeArray<Element> {
        return LinkedRealtimeArray(in: Node(key: rawValue, parent: node), elementsNode: elements)
    }
}

public final class LinkedRealtimeArray<Element>: _RealtimeValue, RC where Element: RealtimeValue {
    public internal(set) var storage: RCArrayStorage<Element>
    public var view: RealtimeCollectionView { return _view }
    override public var localValue: Any? { return _view.source.localValue }
    public var isPrepared: Bool { return _view.isPrepared }

    let _view: AnyRealtimeCollectionView<RealtimeProperty<[RCItem], RCItemArraySerializer>>

    public required init(in node: Node?, elementsNode: Node) {
        self.storage = RCArrayStorage(sourceNode: elementsNode,
                                      elementBuilder: { n, _ in Element(in: n) },
                                      elements: [:],
                                      localElements: [])
        self._view = AnyRealtimeCollectionView(RealtimeProperty(in: node))
        super.init(in: node)
    }

    public required init(in node: Node?) {
        fatalError("Linked array cannot be initialized with init(node:) initializer")
    }

    // MARK: Realtime

    public required init(dbRef: DatabaseReference) {
        fatalError("Linked array cannot be initialized with init(dbRef:) initializer")
    }
    // TODO: For resolve error can be store link to objects in private key
    public required init(snapshot: DataSnapshot) {
        fatalError("Linked array cannot be initialized with init(snapshot:) initializer")
    }

    public convenience required init(snapshot: DataSnapshot, elementsNode: Node) {
        self.init(in: Node.root.child(with: snapshot.ref.rootPath), elementsNode: elementsNode)
        apply(snapshot: snapshot)
    }

    // Implementation

    public func contains(_ element: Element) -> Bool { return _view.source.value.contains { $0.dbKey == element.dbKey } }

    public subscript(position: Int) -> Element { return storage.object(for: _view.source.value[position]) }
    public var startIndex: Int { return _view.startIndex }
    public var endIndex: Int { return _view.endIndex }
    public func index(after i: Int) -> Int { return _view.index(after: i) }
    public func index(before i: Int) -> Int { return _view.index(before: i) }
    public func listening(changes handler: @escaping () -> Void) -> ListeningItem { return _view.source.listeningItem(.just { _ in handler() }) }
    override public func runObserving() -> Bool { return _view.source.runObserving() }
    override public func stopObserving() { _view.source.stopObserving() }
    override public var debugDescription: String { return _view.source.debugDescription }
    public func prepare(forUse completion: Assign<(Error?)>) { _view.prepare(forUse: completion) }

    override public func apply(snapshot: DataSnapshot, strongly: Bool) {
        super.apply(snapshot: snapshot, strongly: strongly)
        _view.source.apply(snapshot: snapshot, strongly: strongly)
        _view.isPrepared = true
    }

    override public func insertChanges(to transaction: RealtimeTransaction, by node: Node) {
        if hasChanges {
            for (index, element) in storage.localElements.enumerated() {
                _write(element, at: index, by: node, in: transaction)
            }
        }
    }

//    public func willSave(in transaction: RealtimeTransaction, in parent: Node, by key: String) {

//    }
    override public func didSave(in parent: Node, by key: String) {
        super.didSave(in: parent, by: key)
        _view.source.didSave(in: parent)
    }

    override public func willRemove(in transaction: RealtimeTransaction) {
        super.willRemove(in: transaction)
        _view.source.willRemove(in: transaction)
    }
    override public func didRemove(from node: Node) {
        super.didRemove(from: node)
        _view.source.didRemove()
    }
}

// MARK: Mutating

public extension LinkedRealtimeArray {
    @discardableResult
    func write(element: Element, at index: Int? = nil,
                in transaction: RealtimeTransaction? = nil) throws -> RealtimeTransaction {
        guard isRooted else { fatalError("This method is available only for rooted objects. Use method insert(element:at:)") }
        guard element.node?.parent == storage.sourceNode else { fatalError("Element must be located in elements node") }
        guard isPrepared else {
            let transaction = transaction ?? RealtimeTransaction()
            transaction.addPrecondition { [unowned transaction] promise in
                self.prepare(forUse: .just { collection, err in
                    try! collection.write(element: element, at: index, in: transaction)
                    promise.fulfill(err)
                })
            }
            return transaction
        }
        guard !contains(element) else { throw RCError(type: .alreadyInserted) }

        let transaction = transaction ?? RealtimeTransaction()
        _write(element, at: index ?? count, by: node!, in: transaction)
        transaction.addCompletion { [weak self] (result) in
            if result {
                self?.didSave()
            }
        }
        return transaction
    }

    func insert(element: Element, at index: Int? = nil) {
        guard isStandalone else { fatalError("This method is available only for standalone objects. Use method write(element:at:in:)") }
        guard element.node?.parent == storage.sourceNode else { fatalError("Element must be located in elements node") }
        let contains = element.node.map { n in storage.localElements.contains(where: { $0.dbKey == n.key }) } ?? false
        guard !contains else {
            fatalError("Element with such key already exists")
        }

        storage.localElements.insert(element, at: index ?? storage.localElements.count)
    }

    func _write(_ element: Element, at index: Int,
                by location: Node, in transaction: RealtimeTransaction) {
        let itemNode = location.child(with: element.dbKey)
        let link = element.node!.generate(linkTo: itemNode)
        let item = RCItem(dbKey: element.dbKey,
                          linkID: link.link.id,
                          index: index)

        var reversion: () -> Void {
            let sourceRevers = _view.source.hasChanges ?
                nil : _view.source.currentReversion()

            return { [weak self] in
                sourceRevers?()
                self?.storage.elements.removeValue(forKey: item)
            }
        }
        transaction.addReversion(reversion)
        _view.source.value.insert(item, at: item.index)
        storage.store(value: element, by: item)
        transaction.addValue(RCItemSerializer.serialize(item), by: itemNode)
        transaction.addValue(link.link.localValue, by: link.node)
    }

    @discardableResult
    func remove(element: Element, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction? {
        if let index = _view.source.value.index(where: { $0.dbKey == element.dbKey }) {
            return remove(at: index, in: transaction)
        }
        return transaction
    }

    @discardableResult
    func remove(at index: Int, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        guard isRooted else { fatalError("This method is available only for rooted objects") }

        let transaction = transaction ?? RealtimeTransaction()
        guard isPrepared else {
            transaction.addPrecondition { [unowned transaction] promise in
                self.prepare(forUse: .just { collection, err in
                    collection.remove(at: index, in: transaction)
                    promise.fulfill(err)
                })
            }
            return transaction
        }

        if !_view.source.hasChanges {
            transaction.addReversion(_view.source.currentReversion())
        }
        let item = _view.source.value.remove(at: index)
        let element = storage.elements.removeValue(forKey: item)
        transaction.addReversion { [weak self] in
            self?.storage.elements[item] = element
        }
        transaction.addValue(nil, by: _view.source.node!.child(with: item.dbKey))
        let elementLinksNode = storage.sourceNode.linksNode.child(
            with: item.dbKey.subpath(with: item.linkID)
        )
        transaction.addValue(nil, by: elementLinksNode)
        transaction.addCompletion { [weak self] (result) in
            if result {
                self?.didSave()
            }
        }
        return transaction
    }
}

