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

public final class LinkedRealtimeArray<Element>: RC where Element: RealtimeValue & Linkable {
    public var node: Node?
    public var storage: RCArrayStorage<Element>
    public var view: RealtimeCollectionView { return _view }
    public var localValue: Any? { return _view.source.localValue }
    public var isPrepared: Bool { return _view.isPrepared }

    let _view: AnyRealtimeCollectionView<RealtimeProperty<[_PrototypeValue], _PrototypeValueSerializer>>

    public required init(in node: Node, elementsNode: Node) {
        self.node = node
        self.storage = RCArrayStorage(sourceNode: elementsNode, elementBuilder: Element.init, elements: [:])
        self._view = AnyRealtimeCollectionView(RealtimeProperty(in: node))
    }

    public init(in node: Node?) {
        fatalError()
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
    public func runObserving() { _view.source.runObserving() }
    public func stopObserving() { _view.source.stopObserving() }
    public var debugDescription: String { return _view.source.debugDescription }
    public func prepare(forUse completion: @escaping (Error?) -> Void) { _view.prepare(forUse: completion) }

    public func apply(snapshot: DataSnapshot, strongly: Bool) {
        _view.source.apply(snapshot: snapshot, strongly: strongly)
        _view.isPrepared = true
    }

    public func didSave(in node: Node) {
        _view.source.didSave()
    }

    public func willRemove(in transaction: RealtimeTransaction) { _view.source.willRemove(in: transaction) }
    public func didRemove(from node: Node) {
        _view.source.didRemove()
    }
}

// MARK: Mutating

public extension LinkedRealtimeArray {
    @discardableResult
    func insert(element: Element, at index: Int? = nil, in transaction: RealtimeTransaction? = nil) throws -> RealtimeTransaction {
        //        _view.checkPreparation()
        guard isPrepared else {
            let transaction = transaction ?? RealtimeTransaction()
            transaction.addPrecondition { [unowned transaction] promise in
                self.prepare(forUse: { collection, err in
                    try! collection.insert(element: element, at: index, in: transaction)
                    promise.fulfill(err)
                })
            }
            return transaction
        }
        guard !contains(element) else { throw RealtimeArrayError(type: .alreadyInserted) }

        let transaction = transaction ?? RealtimeTransaction()
        let link = element.node!.generate(linkTo: _view.source.node!)
        let key = _PrototypeValue(dbKey: element.dbKey, linkId: link.link.id, index: index ?? self.count)

        let oldValue = _view.source.value
        _view.source.value.insert(key, at: key.index)
        transaction.addReversion { [weak _view] in
            _view?.source.value = oldValue
        }
        transaction.addNode(_view.source.node!, value: _view.source.localValue)
        transaction.addNode(link.sourceNode, value: link.link.localValue)
        transaction.addCompletion { [weak self] (result) in
            if result {
                self?.storage.elements[key] = element
                self?.didSave()
            }
        }
        return transaction
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
        //        _view.checkPreparation()
        let transaction = transaction ?? RealtimeTransaction()
        guard isPrepared else {
            transaction.addPrecondition { [unowned transaction] promise in
                self.prepare(forUse: { collection, err in
                    collection.remove(at: index, in: transaction)
                    promise.fulfill(err)
                })
            }
            return transaction
        }

        let oldValue = _view.source.value
        let key = _view.source.value.remove(at: index)
        transaction.addReversion { [weak _view] in
            _view?.source.value = oldValue
        }
        transaction.addNode(_view.source.node!, value: _view.source.localValue)
        let linksRef = Nodes.links.rawValue.appending(storage.sourceNode.child(with: key.dbKey.subpath(with: key.linkId)).rootPath).reference()
        transaction.addNode(item: (linksRef, .value(nil)))
        transaction.addCompletion { [weak self] (result) in
            if result {
                self?.storage.elements.removeValue(forKey: key)?.remove(linkBy: key.linkId)
                self?.didSave()
            }
        }
        return transaction
    }
}
