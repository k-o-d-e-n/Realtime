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
    public internal(set) var node: Node?
    public internal(set) var storage: RCArrayStorage<Element>
    public var view: RealtimeCollectionView { return _view }
    public var localValue: Any? { return _view.source.localValue }
    public var isPrepared: Bool { return _view.isPrepared }

    let _view: AnyRealtimeCollectionView<RealtimeProperty<[_PrototypeValue], _PrototypeValuesSerializer>>

    public required init(in node: Node, elementsNode: Node) {
        self.node = node
        self.storage = RCArrayStorage(sourceNode: elementsNode, elementBuilder: Element.init, elements: [:])
        self._view = AnyRealtimeCollectionView(RealtimeProperty(in: node.linksNode))
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

    public func didSave(in parent: Node, by key: String) {
        debugFatalError(condition: self.node.map { $0.key != key } ?? false, "Value has been saved to node: \(parent) by key: \(key), but current node has key: \(node!.key).")
        debugFatalError(condition: !parent.isRooted, "Value has been saved non rooted node: \(parent)")

        if let node = self.node {
            node.parent = parent
        } else {
            self.node = Node(key: key, parent: parent)
        }

        _view.source.didSave(in: parent)
    }

    public func willRemove(in transaction: RealtimeTransaction) { _view.source.willRemove(in: transaction) }
    public func didRemove(from node: Node) { _view.source.didRemove() }
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
        let key = _PrototypeValue(dbKey: element.dbKey, linkID: link.link.id, index: index ?? self.count)

        let oldValue = _view.source.value
        _view.source.value.insert(key, at: key.index)
        transaction.addReversion { [weak _view] in
            _view?.source.value = oldValue
        }
        transaction.addValue(_ProtoValueSerializer.serialize(entity: key), by: _view.source.node!.child(with: key.dbKey))
        transaction.addValue(link.link.localValue, by: link.sourceNode)
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
        transaction.addValue(nil, by: _view.source.node!.child(with: key.dbKey))
        let linksNode = storage.sourceNode.child(with: key.dbKey.subpath(with: key.linkID)).linksNode
        transaction.addValue(nil, by: linksNode)
        transaction.addCompletion { [weak self] (result) in
            if result {
                self?.storage.elements.removeValue(forKey: key)?.remove(linkBy: key.linkID)
                self?.didSave()
            }
        }
        return transaction
    }
}

//public extension LinkedRealtimeArray where Element: MutableDataRepresented {
//    public func changeValue(use changing: @escaping (T) throws -> T, completion: @escaping (Bool, T) -> Void) {
//        debugFatalError(condition: dbRef != nil, "")
//        if let ref = dbRef {
//            ref.runTransactionBlock({ data in
//                do {
//                    let dataValue = try T.init(data: data)
//                    data.value = try changing(dataValue).localValue
//                } catch let e {
//                    debugFatalError(e.localizedDescription)
//                    return .abort()
//                }
//                return .success(withValue: data)
//            }, andCompletionBlock: { [unowned self] error, commited, snapshot in
//                guard error == nil else {
//                    return completion(false, self.value)
//                }
//
//                if let s = snapshot {
//                    self.setValue(Serializer.deserialize(entity: s))
//                    completion(true, self.value)
//                } else {
//                    debugFatalError("Transaction completed without error, but snapshot does not exist")
//                    completion(false, self.value)
//                }
//            })
//        }
//    }
//}

