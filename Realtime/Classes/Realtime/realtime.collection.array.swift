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

/// # Realtime Array
/// ## https://stackoverflow.com/questions/24047991/does-swift-have-documentation-comments-or-tools/28633899#28633899
/// Comment writing guide
public final class Values<Element>: _RealtimeValue, ChangeableRealtimeValue, RC where Element: WritableRealtimeValue & RealtimeValueEvents {
    public override var version: Int? { return nil }
    public override var raw: FireDataValue? { return nil }
    public override var payload: [String : FireDataValue]? { return nil }
    override var _hasChanges: Bool { return isStandalone && storage.elements.count > 0 }
    public internal(set) var storage: RCArrayStorage<Element>
    public var view: RealtimeCollectionView { return _view }
    public var isPrepared: Bool { return _view.isPrepared }

    let _view: AnyRealtimeCollectionView<[RCItem], Values>

    public convenience required init(in node: Node?) {
        self.init(in: node, options: [:])
    }

    public convenience required init(in node: Node?, options: [ValueOption: Any]) {
        let viewParentNode = node.flatMap { $0.isRooted ? $0.linksNode : nil }
        self.init(
            in: node,
            options: options,
            viewSource: InternalKeys.items.property(
                from: viewParentNode,
                representer: Representer<[RCItem]>(collection: Representer.fireData)
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

    public func contains(_ element: Element) -> Bool {
        return _view.contains { $0.dbKey == element.dbKey }
    }
    public subscript(position: Int) -> Element { return storage.object(for: _view[position]) }
    public var startIndex: Int { return _view.startIndex }
    public var endIndex: Int { return _view.endIndex }
    public func index(after i: Int) -> Int { return _view.index(after: i) }
    public func index(before i: Int) -> Int { return _view.index(before: i) }
    public func listening(changes handler: @escaping () -> Void) -> ListeningItem {
        return _view.source.map { _ in }.listeningItem(onValue: handler)
    }
    @discardableResult
    override public func runObserving() -> Bool { return _view.source.runObserving() }
    override public func stopObserving() { _view.source.stopObserving() }
    override public var debugDescription: String { return _view.source.debugDescription }
    public func prepare(forUse completion: Assign<(Error?)>) { _view.prepare(forUse: completion) }
    
    // TODO: Create Realtime wrapper for DatabaseQuery
    // TODO: Check filter with difficult values aka dictionary
    public func filtered<Node: RawRepresentable>(by value: Any, for node: Node, completion: @escaping ([Element], Error?) -> ()) where Node.RawValue == String {
        filtered(with: { $0.queryOrdered(byChild: node.rawValue).queryEqual(toValue: value) }, completion: completion)
    }
    
    public func filtered(with query: (DatabaseReference) -> DatabaseQuery, completion: @escaping ([Element], Error?) -> ()) {
        guard let ref = node?.reference() else  {
            fatalError("Can`t get database reference")
        }
        checkPreparation()

        query(ref).observeSingleEvent(of: .value, with: { (data) in
            do {
                try self.apply(data, exactly: false)
                completion(self.filter { data.hasChild($0.dbKey) }, nil)
            } catch let e {
                completion(self.filter { data.hasChild($0.dbKey) }, e)
            }
        }) { (error) in
            completion([], error)
        }
    }
    
    // MARK: Mutating

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
        transaction.addValue(item.fireValue, by: itemNode)
        transaction.addValue(link.link.fireValue, by: link.node)
        try transaction.set(element, by: elementNode)
    }

    @discardableResult
    public func remove(element: Element, in transaction: Transaction? = nil) -> Transaction? {
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

    public required init(fireData: FireDataProtocol, exactly: Bool) throws {
        let node = fireData.node
        let viewParentNode = node.flatMap { $0.isRooted ? $0.linksNode : nil }
        self.storage = RCArrayStorage(sourceNode: node, elementBuilder: Element.init, elements: [:])
        self._view = AnyRealtimeCollectionView(InternalKeys.items.property(from: viewParentNode, representer: Representer<[RCItem]>(collection: Representer.fireData).defaultOnEmpty()))
        try super.init(fireData: fireData, exactly: exactly)
        self._view.collection = self
    }

    var _snapshot: (FireDataProtocol, Bool)?
    override public func apply(_ data: FireDataProtocol, exactly: Bool) throws {
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
                storage.elements[key.dbKey] = try Element(fireData: childData, exactly: exactly)
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
            _view.remove(at: index)
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
