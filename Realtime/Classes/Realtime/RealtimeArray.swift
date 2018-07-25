//
//  RealtimeArray.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 18/02/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation
import FirebaseDatabase

public extension RawRepresentable where RawValue == String {
    func array<Element>(from node: Node?) -> RealtimeArray<Element> {
        return RealtimeArray(in: Node(key: rawValue, parent: node))
    }
    func array<Element>(from node: Node?, elementOptions: [RealtimeValueOption: Any]) -> RealtimeArray<Element> {
        return array(from: node, builder: { (node, options) in
            let compoundOptions = options.merging(elementOptions, uniquingKeysWith: { remote, local in remote })
            return Element(in: node, options: compoundOptions)
        })
    }
    func array<Element>(from node: Node?, builder: @escaping RCElementBuilder<Element>) -> RealtimeArray<Element> {
        return RealtimeArray(in: Node(key: rawValue, parent: node), options: [.elementBuilder: builder])
    }
}
public extension Node {
    func array<Element>() -> RealtimeArray<Element> {
        return RealtimeArray(in: self)
    }
}

// MARK: Implementation RealtimeCollection`s

public extension RealtimeArray {
    convenience init<E>(in node: Node?, elements: LinkedRealtimeArray<E>) {
        self.init(in: node,
                  options: [.elementBuilder: elements.storage.elementBuilder],
                  viewSource: elements._view.source)
    }
}

/// # Realtime Array
/// ## https://stackoverflow.com/questions/24047991/does-swift-have-documentation-comments-or-tools/28633899#28633899
/// Comment writing guide
public final class RealtimeArray<Element>: _RealtimeValue, RC where Element: RealtimeValue & RealtimeValueEvents {
    public override var version: Int? { return nil }
    public override var raw: FireDataValue? { return nil }
    public override var payload: [String : FireDataValue]? { return nil }
    override public var hasChanges: Bool { return !storage.localElements.isEmpty }
    public internal(set) var storage: RCArrayStorage<Element>
    public var view: RealtimeCollectionView { return _view }
    public var isPrepared: Bool { return _view.isPrepared }

    let _view: AnyRealtimeCollectionView<RealtimeProperty<[RCItem]>>

    public convenience required init(in node: Node?, options: [RealtimeValueOption: Any]) {
        let viewParentNode = node.flatMap { $0.isRooted ? $0.linksNode : nil }
        self.init(
            in: node,
            options: options,
            viewSource: RealtimeProperty(in: Node(key: InternalKeys.items, parent: viewParentNode))
        )
    }

    init(in node: Node?,
         options: [RealtimeValueOption: Any],
         viewSource: RealtimeProperty<[RCItem]>) {
        let builder = options[.elementBuilder] as? RCElementBuilder<Element> ?? Element.init
        self.storage = RCArrayStorage(sourceNode: node, elementBuilder: builder, elements: [:], localElements: [])
        self._view = AnyRealtimeCollectionView(viewSource)
        super.init(in: node, options: options)
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
    public func listening(changes handler: @escaping () -> Void) -> ListeningItem {
        return _view.source.listeningItem(.guarded(self) { _, this in
            this._view.isPrepared = true
            handler()
        })
    }
    @discardableResult
    override public func runObserving() -> Bool { return _view.source.runObserving() }
    override public func stopObserving() { _view.source.stopObserving() }
    override public var debugDescription: String { return _view.source.debugDescription }
    public func prepare(forUse completion: Assign<(Error?)>) {
        _view.prepare(forUse: completion.with(work: .weak(self) { err, `self` in
            if err == nil {
                self.map { $0._snapshot.map($0.apply) }
            }
        }))
    }
    
    // TODO: Create Realtime wrapper for DatabaseQuery
    // TODO: Check filter with difficult values aka dictionary
    public func filtered<Node: RawRepresentable>(by value: Any, for node: Node, completion: @escaping ([Element], Error?) -> ()) where Node.RawValue == String {
        filtered(with: { $0.queryOrdered(byChild: node.rawValue).queryEqual(toValue: value) }, completion: completion)
    }
    
    public func filtered(with query: (DatabaseReference) -> DatabaseQuery, completion: @escaping ([Element], Error?) -> ()) {
        checkPreparation()

        query(dbRef!).observeSingleEvent(of: .value, with: { (data) in
            self.apply(data, strongly: false)
            
            completion(self.filter { data.hasChild($0.dbKey) }, nil)
        }) { (error) in
            completion([], error)
        }
    }
    
    // MARK: Mutating

    @discardableResult
    public func write(element: Element, at index: Int? = nil, in transaction: RealtimeTransaction? = nil) throws -> RealtimeTransaction {
        guard isRooted else { fatalError("This method is available only for rooted objects. Use method insert(element:at:)") }
        guard !element.isReferred || element.node!.parent == storage.sourceNode
            else { fatalError("Element must not be referred in other location") }
        guard isPrepared else {
            let transaction = transaction ?? RealtimeTransaction()
            transaction.addPrecondition { [unowned transaction] promise in
                self.prepare(forUse: .just { collection, err in
                    try! collection._insert(element, at: index, in: transaction)
                    promise.fulfill(err)
                })
            }
            return transaction
        }

        return try _insert(element, at: index, in: transaction)
    }

    public func insert(element: Element, at index: Int? = nil) throws {
        guard isStandalone else { fatalError("This method is available only for standalone objects. Use method write(element:at:in:)") }
        guard !element.isReferred || element.node!.parent == storage.sourceNode
            else { fatalError("Element must not be referred in other location") }
        let contains = element.node.map { n in storage.localElements.contains(where: { $0.dbKey == n.key }) } ?? false
        guard !contains else {
            fatalError("Element with such key already exists")
        }

        storage.localElements.insert(element, at: index ?? storage.localElements.count)
    }

    @discardableResult
    func _insert(_ element: Element, at index: Int? = nil, in transaction: RealtimeTransaction? = nil) throws -> RealtimeTransaction {
        guard element.node.map({ _ in !contains(element) }) ?? true
            else { fatalError("Element with such key already exists") }

        let transaction = transaction ?? RealtimeTransaction()
        _write(element, at: index ?? count, by: (storage: node!, itms: _view.source.node!), in: transaction)
        transaction.addCompletion { [weak self] (result) in
            if result {
                self?.didSave()
            }
        }
        return transaction
    }

    func _write(_ element: Element, at index: Int,
                by location: (storage: Node, itms: Node), in transaction: RealtimeTransaction) {
        let elementNode = element.node.map { $0.moveTo(location.storage); return $0 } ?? location.storage.childByAutoId()
        let itemNode = location.itms.child(with: elementNode.key)
        let link = elementNode.generate(linkTo: itemNode)
        let item = RCItem(element: element, key: elementNode.key, linkID: link.link.id, index: index)

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
        transaction.addValue(item.fireValue, by: itemNode)
        transaction.addValue(link.link.fireValue, by: link.node)
        transaction._set(element, by: elementNode)
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
        let element = storage.elements.removeValue(forKey: item) ?? storage.object(for: item)
        element.willRemove(in: transaction, from: storage.sourceNode)
        transaction.addReversion { [weak self] in
            self?.storage.elements[item] = element
        }
        transaction.addValue(nil, by: _view.source.node!.child(with: item.dbKey)) // remove item element
        transaction.addValue(nil, by: storage.sourceNode.child(with: item.dbKey)) // remove element
        transaction.addCompletion { [weak self] result in
            if result {
                element.didRemove()
                self?.didSave()
            }
        }
        return transaction
    }
    
    // MARK: Realtime

    public required convenience init(fireData: FireDataProtocol) throws {
        self.init(in: fireData.dataRef.map(Node.from))
        apply(fireData)
    }

    var _snapshot: (FireDataProtocol, Bool)?
    override public func apply(_ data: FireDataProtocol, strongly: Bool) {
        guard _view.isPrepared else {
            _snapshot = (data, strongly)
            return
        }
        _snapshot = nil
        _view.source.value.forEach { key in
            guard data.hasChild(key.dbKey) else {
                if strongly { storage.elements.removeValue(forKey: key) }
                return
            }
            let childData = data.child(forPath: key.dbKey)
            if let element = storage.elements[key] {
                element.apply(childData, strongly: strongly)
            } else {
                storage.elements[key] = try! Element(fireData: childData, strongly: strongly)
            }
        }
    }

    override public func writeChanges(to transaction: RealtimeTransaction, by node: Node) {
        if hasChanges {
            for (index, element) in storage.localElements.enumerated() {
                _write(element,
                       at: index,
                       by: (storage: node,
                            itms: Node(key: InternalKeys.items, parent: node.linksNode)),
                       in: transaction)
            }
        }
    }

    /// Collection does not respond for versions and raw value, and also payload.
    /// To change value version/raw can use enum, but use modified representer.
    public override func write(to transaction: RealtimeTransaction, by node: Node) {
//        super.write(to: transaction, by: node)
        // writes changes because after save collection can use only transaction mutations
        writeChanges(to: transaction, by: node)
    }

//    override public func willSave(in transaction: RealtimeTransaction, in parent: Node, by key: String) {

//    }
    override public func didSave(in parent: Node, by key: String) {
        super.didSave(in: parent, by: key)
        if let node = self.node {
            _view.source.didSave(in: node.linksNode)
            storage.sourceNode = node
        }
        storage.localElements.removeAll()
        storage.elements.forEach { $1.didSave(in: storage.sourceNode, by: $0.dbKey) }
    }

    public override func willRemove(in transaction: RealtimeTransaction, from ancestor: Node) {  // TODO: Elements don't receive willRemove event
        super.willRemove(in: transaction, from: ancestor)
        if ancestor == node?.parent {
            transaction.addValue(nil, by: node!.linksNode)
        }
    }
    override public func didRemove(from node: Node) {
        super.didRemove(from: node)
        _view.source.didRemove()
        storage.elements.values.forEach { $0.didRemove(from: storage.sourceNode) }
    }
}
