//
//  RealtimeArray.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 18/02/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation
import FirebaseDatabase

// TODO: Add RealtimeValueActions implementation

public extension RTNode where RawValue == String {
    func array<Element>(from node: Node?) -> RealtimeArray<Element> {
        return RealtimeArray(in: Node(key: rawValue, parent: node))
    }
}
public extension Node {
    func array<Element>() -> RealtimeArray<Element> {
        return RealtimeArray(in: self)
    }
}

// MARK: Implementation RealtimeCollection`s

/// # Realtime Array
/// ## https://stackoverflow.com/questions/24047991/does-swift-have-documentation-comments-or-tools/28633899#28633899
/// Comment writing guide
public final class RealtimeArray<Element>: RC where Element: RealtimeValue & RealtimeValueEvents & Linkable {
//    public let dbRef: DatabaseReference
    public var node: Node?
    public var storage: RCArrayStorage<Element>
    public var view: RealtimeCollectionView { return _view }
    public var isPrepared: Bool { return _view.isPrepared }

    let _view: AnyRealtimeCollectionView<RealtimeProperty<[_PrototypeValue], _PrototypeValueSerializer>>

    public init(in node: Node?) {
        precondition(node != nil)
        self.node = node
        self.storage = RCArrayStorage(sourceNode: node!, elementBuilder: Element.init, elements: [:])
        self._view = AnyRealtimeCollectionView(RealtimeProperty(in: node?.child(with: Nodes.items.rawValue)))
    }

    // Implementation

    public func contains(_ element: Element) -> Bool {
        return _view.source.value.contains { $0.dbKey == element.dbKey }
    }
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
    
    // TODO: Create Realtime wrapper for DatabaseQuery
    // TODO: Check filter with difficult values aka dictionary
    public func filtered(by value: Any, for node: RealtimeNode, completion: @escaping ([Element], Error?) -> ()) {
        filtered(with: { $0.queryOrdered(byChild: node.rawValue).queryEqual(toValue: value) }, completion: completion)
    }
    
    public func filtered(with query: (DatabaseReference) -> DatabaseQuery, completion: @escaping ([Element], Error?) -> ()) {
        checkPreparation()

        query(dbRef!).observeSingleEvent(of: .value, with: { (snapshot) in
            self.apply(snapshot: snapshot, strongly: false)
            
            completion(self.filter { snapshot.hasChild($0.dbKey) }, nil)
        }) { (error) in
            completion([], error)
        }
    }
    
    // MARK: Mutating

    // TODO: Add parameter for sending local event (after write to db, or immediately)
    @discardableResult
    public func insert(element: Element, at index: Int? = nil, in transaction: RealtimeTransaction? = nil) throws -> RealtimeTransaction {
        guard !element.isReferred else { fatalError("Element must not be referred in other location") }

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

        let elementNode = element.node.map { $0.moveTo(storage.sourceNode); return $0 }
            ?? storage.sourceNode.child(with: DatabaseReference.root().childByAutoId().key)
        let transaction = transaction ?? RealtimeTransaction()
        let link = elementNode.generate(linkTo: _view.source.node!.child(with: elementNode.key))
        let key = _PrototypeValue(dbKey: elementNode.key, linkId: link.link.id, index: index ?? count)

        let oldValue = _view.source.value
        _view.source.value.insert(key, at: key.index)
        storage.store(value: element, by: key)
        transaction.addReversion { [weak self] in
            self?._view.source.value = oldValue
            self?.storage.elements.removeValue(forKey: key)
            element.remove(linkBy: link.link.id)
        }
        transaction.addNode(_view.source.node!, value: _view.source.localValue)
        if let elem = element as? RealtimeObject { // TODO: Fix it
            transaction.addNode(link.sourceNode, value: link.link.localValue)
            transaction.update(elem, by: elementNode) // TODO:
        } else {
            element.add(link: link.link)
            transaction.set(element, by: elementNode)
        }
        transaction.addCompletion { [weak self] (result) in
            if result {
                self?.didSave()
            }
        }
        return transaction
    }

    @discardableResult
    public func remove(element: Element, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction? {
        if let index = _view.source.value.index(where: { $0.dbKey == element.dbKey }) {
            return remove(at: index, in: transaction)
        }
        return transaction
    }

    @discardableResult
    public func remove(at index: Int, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
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

        let element = self[index]
        element.willRemove(in: transaction)

        let oldValue = _view.source.value
        let key = _view.source.value.remove(at: index)
        transaction.addReversion { [weak _view] in
            _view?.source.value = oldValue
        }
        transaction.addNode(_view.source.node!, value: _view.source.localValue)
        transaction.addNode(storage.sourceNode.child(with: key.dbKey), value: nil)
        transaction.addCompletion { [weak self] result in
            if result {
                self?.storage.elements.removeValue(forKey: key)
                element.didRemove()
                self?.didSave()
            }
        }
        return transaction
    }
    
    // MARK: Realtime
    
    public var localValue: Any? {
        let split = storage.elements.reduce((exists: [], removed: [])) { (res, keyValue) -> (exists: [(_PrototypeValue, Element)], removed: [(_PrototypeValue, Element)]) in
            guard _view.source.value.contains(keyValue.key) else {
                return (res.exists, res.removed + [keyValue])
            }
            
            return (res.exists + [keyValue], res.removed)
        }
        var value = Dictionary<String, Any?>(keyValues: split.exists, mapKey: { $0.dbKey }, mapValue: { $0.localValue })
        value[_view.source.dbKey] = _view.source.localValue
        split.removed.forEach { value[$0.0.dbKey] = nil }
        
        return value
    }

    public required convenience init(snapshot: DataSnapshot) {
        self.init(in: Node.root.child(with: snapshot.ref.rootPath))
        apply(snapshot: snapshot)
    }
    
    public func apply(snapshot: DataSnapshot, strongly: Bool) {
        if strongly || Nodes.items.has(in: snapshot) {
            _view.source.apply(snapshot: Nodes.items.snapshot(from: snapshot))
            _view.isPrepared = true
        }
        _view.source.value.forEach { key in
            guard snapshot.hasChild(key.dbKey) else {
                if strongly { storage.elements.removeValue(forKey: key) }
                return
            }
            let childSnapshot = snapshot.childSnapshot(forPath: key.dbKey)
            if let element = storage.elements[key] {
                element.apply(snapshot: childSnapshot, strongly: strongly)
            } else {
                storage.elements[key] = Element(snapshot: childSnapshot, strongly: strongly)
            }
        }
    }
    
    public func didSave(in node: Node) {
        _view.source.didSave()
    }

    public func willRemove(in transaction: RealtimeTransaction) { _view.source.willRemove(in: transaction) }
    public func didRemove(from node: Node) {
        _view.source.didRemove()
    }
}
