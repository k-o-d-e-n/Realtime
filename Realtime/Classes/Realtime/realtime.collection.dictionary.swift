//
//  RealtimeDictionary.swift
//  Realtime
//
//  Created by Denis Koryttsev on 16/03/2018.
//

import Foundation
import FirebaseDatabase

public extension RawRepresentable where RawValue == String {
    func dictionary<Key, Value>(from node: Node?, keys: Node) -> RealtimeDictionary<Key, Value> {
        return RealtimeDictionary(in: Node(key: rawValue, parent: node), options: [.keysNode: keys])
    }
    func dictionary<Key, Value>(from node: Node?, keys: Node, elementOptions: [RealtimeValueOption: Any]) -> RealtimeDictionary<Key, Value> {
        return dictionary(from: node, keys: keys, builder: { (node, options) in
            let compoundOptions = options.merging(elementOptions, uniquingKeysWith: { remote, local in remote })
            return Value(in: node, options: compoundOptions)
        })
    }
    func dictionary<Key, Value>(from node: Node?, keys: Node, builder: @escaping RCElementBuilder<Value>) -> RealtimeDictionary<Key, Value> {
        return RealtimeDictionary(in: Node(key: rawValue, parent: node), options: [.keysNode: keys, .elementBuilder: builder])
    }
}

public struct RCDictionaryStorage<K, V>: MutableRCStorage where K: RealtimeDictionaryKey {
    public typealias Value = V
    var sourceNode: Node!
    let keysNode: Node
    let elementBuilder: (Node, [RealtimeValueOption: Any]) -> Value
    var elements: [K: Value] = [:]
    var localElements: [K: Value] = [:]

    func buildElement(with key: K) -> V {
        return elementBuilder(sourceNode.child(with: key.dbKey), key.payload.map { [.payload: $0] } ?? [:])
    }

    mutating func store(value: Value, by key: K) { elements[for: key] = value }
    func storedValue(by key: K) -> Value? { return elements[for: key] }

    internal mutating func element(by key: String) -> (Key, Value) {
        guard let element = storedElement(by: key) else {
            let storeKey = Key(in: keysNode.child(with: key))
            let value = buildElement(with: storeKey)
            store(value: value, by: storeKey)

            return (storeKey, value)
        }

        return element
    }
    fileprivate func storedElement(by key: String) -> (Key, Value)? {
        return elements.first(where: { $0.key.dbKey == key })
    }
}

extension RealtimeValueOption {
    static let keysNode = RealtimeValueOption("realtime.dictionary.keys")
}

public typealias RealtimeDictionaryKey = Hashable & RealtimeValue
public final class RealtimeDictionary<Key, Value>: _RealtimeValue, ChangeableRealtimeValue, RC
where Value: WritableRealtimeValue & RealtimeValueEvents, Key: RealtimeDictionaryKey {
    public override var version: Int? { return nil }
    public override var raw: FireDataValue? { return nil }
    public override var payload: [String : FireDataValue]? { return nil }
    override var _hasChanges: Bool { return storage.localElements.count > 0 }
    public var view: RealtimeCollectionView { return _view }
    public internal(set) var storage: RCDictionaryStorage<Key, Value>
    public var isPrepared: Bool { return _view.isPrepared }

    let _view: AnyRealtimeCollectionView<[RCItem], RealtimeDictionary>

    public required init(in node: Node?, options: [RealtimeValueOption: Any]) {
        guard case let keysNode as Node = options[.keysNode] else { fatalError("Skipped required options") }
        guard keysNode.isRooted else { fatalError("Keys must has rooted location") }

        let viewParentNode = node.flatMap { $0.isRooted ? $0.linksNode : nil }
        let builder = options[.elementBuilder] as? RCElementBuilder<Value> ?? Value.init
        self.storage = RCDictionaryStorage(sourceNode: node, keysNode: keysNode, elementBuilder: builder, elements: [:], localElements: [:])
        self._view = AnyRealtimeCollectionView(InternalKeys.items.property(from: viewParentNode, representer: Representer<[RCItem]>(collection: Representer.fireData).defaultOnEmpty()))
        super.init(in: node, options: options)
        self._view.collection = self
    }

    // MARK: Implementation

    private var shouldLinking = true // TODO: Create class family for such cases
    public func unlinked() -> RealtimeDictionary<Key, Value> { shouldLinking = false; return self }

    public var startIndex: Int { return _view.startIndex }
    public var endIndex: Int { return _view.endIndex }
    public func index(after i: Int) -> Int { return _view.index(after: i) }
    public func index(before i: Int) -> Int { return _view.index(before: i) }

    public func listening(changes handler: @escaping () -> Void) -> ListeningItem { return _view.source.listeningItem(.just { _ in handler() }) }
    public func listeningEvents() -> Accumulator<RCEvent> {
        guard let ref = _view.source.dbRef else {
            fatalError("Can`t get reference")
        }

        let repeater = Repeater<RCEvent>.unsafe()
        return Accumulator(
            repeater: repeater,
            ref.snapshot(.childAdded).map({ (data) -> RCEvent in
                let item = try RCItem(fireData: data)
                self._view.insert(item, at: item.index)
                return .updated((deleted: [], inserted: [item.index], modified: [], moved: []))
            }),
            ref.snapshot(.childRemoved).map { (data) -> RCEvent in
                let item = try RCItem(fireData: data)
                let index = self._view.removeRemote(item)
                return .updated((deleted: index.map { [$0] } ?? [], inserted: [], modified: [], moved: []))
            },
            ref.snapshot(.childChanged).map { (data) -> RCEvent in
                let item = try RCItem(fireData: data)
                let index = self._view.first(where: { $0.dbKey == item.dbKey })?.index
                return .updated((deleted: [], inserted: [], modified: [], moved: index.map { [($0, item.index)] } ?? []))
            }
        )
    }
    @discardableResult
    override public func runObserving() -> Bool { return _view.source.runObserving() }
    override public func stopObserving() { _view.source.stopObserving() }
    override public var debugDescription: String { return _view.source.debugDescription }
    public func prepare(forUse completion: Assign<(Error?)>) { _view.prepare(forUse: completion) }

    public typealias Element = (key: Key, value: Value)

    public func makeIterator() -> IndexingIterator<RealtimeDictionary> { return IndexingIterator(_elements: self) }
    public subscript(position: Int) -> Element { return storage.element(by: _view[position].dbKey) }
    public subscript(key: Key) -> Value? { return contains(valueBy: key) ? storage.object(for: key) : nil }

    public func contains(valueBy key: Key) -> Bool {
        if isStandalone {
            return storage.localElements[key] != nil
        } else {
            _view.checkPreparation()
            return _view.contains(where: { $0.dbKey == key.dbKey })
        }
    }

    public func filtered<Node: RawRepresentable>(by value: Any, for node: Node, completion: @escaping ([Element], Error?) -> ()) where Node.RawValue == String {
        filtered(with: { $0.queryOrdered(byChild: node.rawValue).queryEqual(toValue: value) }, completion: completion)
    }

    public func filtered(with query: (DatabaseReference) -> DatabaseQuery, completion: @escaping ([Element], Error?) -> ()) {
        checkPreparation()

        query(dbRef!).observeSingleEvent(of: .value, with: { (data) in
            do {
                try self.apply(data, exactly: false)
                completion(self.filter { data.hasChild($0.key.dbKey) }, nil)
            } catch let e {
                completion(self.filter { data.hasChild($0.key.dbKey) }, e)
            }
        }) { (error) in
            completion([], error)
        }
    }

    // MARK: Mutating

    public func set(element: Value, for key: Key) {
        guard isStandalone else { fatalError("This method is available only for standalone objects. Use method write(element:for:in:)") }
        guard storage.keysNode == key.node?.parent else { fatalError("Key is not contained in keys node") }
        guard element.node.map({ $0.parent == nil && $0.key == key.dbKey }) ?? true
            else { fatalError("Element is referred to incorrect location") }

        storage.localElements[key] = element
    }

    @discardableResult
    public func write(element: Value, for key: Key, in transaction: RealtimeTransaction? = nil) throws -> RealtimeTransaction {
        guard isRooted else { fatalError("This method is available only for rooted objects. Use method set(element:for:)") }
        guard storage.keysNode == key.node?.parent else { fatalError("Key is not contained in keys node") }
        guard element.node.map({ $0.parent == nil && $0.key == key.dbKey }) ?? true
            else { fatalError("Element is referred to incorrect location") }

        let transaction = transaction ?? RealtimeTransaction()
        guard isPrepared else {
            transaction.addPrecondition { [unowned transaction] promise in
                self.prepare(forUse: .just { collection, err in
                    guard err == nil else { return promise.reject(err!) }
                    do {
                        try collection._write(element, for: key, in: transaction)
                        promise.fulfill()
                    } catch let e {
                        promise.reject(e)
                    }
                })
            }
            return transaction
        }

        try _write(element, for: key, in: transaction)
        return transaction
    }

    func _write(_ element: Value, for key: Key, in transaction: RealtimeTransaction) throws {
        if contains(valueBy: key) {
            throw RealtimeError(source: .collection, description: "Value by key \(key) already exists. Replacing is not supported yet.")
        }

        try _write(element, for: key,
                   by: (storage: node!, itms: _view.source.node!), in: transaction)
        transaction.addCompletion { [weak self] result in
            if result {
                self?.didSave()
            }
        }
    }

    func _write(_ element: Value, for key: Key,
                by location: (storage: Node, itms: Node), in transaction: RealtimeTransaction) throws {
        let needLink = shouldLinking
        let itemNode = location.itms.child(with: key.dbKey)
        let elementNode = location.storage.child(with: key.dbKey)
        let link = key.node!.generate(linkTo: [itemNode, elementNode, elementNode.linksNode])
        let item = RCItem(element: key, linkID: link.link.id, index: count)

        var reversion: () -> Void {
            let sourceRevers = _view.source.hasChanges ?
                nil : _view.source.currentReversion()

            return { [weak self] in
                sourceRevers?()
                self?.storage.elements.removeValue(forKey: key)
            }
        }
        transaction.addReversion(reversion)
        _view.append(item)
        storage.store(value: element, by: key)

        if needLink {
            transaction.addValue(link.link.fireValue, by: link.node)
            let valueLink = elementNode.generate(linkKeyedBy: link.link.id,
                                                 to: [itemNode, link.node])
            transaction.addValue(valueLink.link.fireValue, by: valueLink.node)
        }
        transaction.addValue(item.fireValue, by: itemNode)
        try transaction._set(element, by: elementNode)
    }

    @discardableResult
    public func remove(for key: Key, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction? {
        guard isRooted else { fatalError("This method is available only for rooted objects") }
        guard storage.keysNode == key.node?.parent else { fatalError("Key is not contained in keys node") }
        guard isPrepared else {
            let transaction = transaction ?? RealtimeTransaction()
            transaction.addPrecondition { [unowned transaction] promise in
                self.prepare(forUse: .just { collection, err in
                    if let e = err {
                        promise.reject(e)
                    } else {
                        collection.remove(for: key, in: transaction)
                        promise.fulfill()
                    }
                })
            }
            return transaction
        }

        guard let index = _view.index(where: { $0.dbKey == key.dbKey }) else { return transaction }

        let transaction = transaction ?? RealtimeTransaction()

        let element = storage.elements.removeValue(forKey: key) ?? storage.object(for: key)
        element.willRemove(in: transaction, from: storage.sourceNode)

        if !_view.source.hasChanges {
            transaction.addReversion(_view.source.currentReversion())
        }
        let item = _view.remove(at: index)
        transaction.addReversion { [weak self] in
            self?.storage.elements[key] = element
        }
        transaction.removeValue(by: _view.source.node!.child(with: key.dbKey)) // remove item element
        transaction.removeValue(by: storage.sourceNode.child(with: key.dbKey)) // remove element
        transaction.removeValue(by: key.node!.linksNode.child(with: item.linkID)) // remove link from key object
        transaction.addCompletion { [weak self] result in
            if result {
                element.didRemove()
                self?.didSave()
            }
        }
        return transaction
    }

    // MARK: Realtime


    public required init(in node: Node?) {
        fatalError("Realtime dictionary cannot be initialized with init(in:) initializer")
    }

    public required convenience init(fireData: FireDataProtocol) throws {
        #if DEBUG
        fatalError("RealtimeDictionary does not supported init(fireData:) yet.")
        #else
        throw RealtimeError(source: .collection, description: "RealtimeDictionary does not supported init(fireData:) yet.")
        #endif
    }

    public convenience init(fireData: FireDataProtocol, keysNode: Node) throws {
        self.init(in: fireData.dataRef.map(Node.from), options: [.keysNode: keysNode])
        try apply(fireData, exactly: true)
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
                if exactly, let contained = storage.elements.first(where: { $0.0.dbKey == key.dbKey }) { storage.elements.removeValue(forKey: contained.key) }
                return
            }
            let childData = data.child(forPath: key.dbKey)
            if var element = storage.elements.first(where: { $0.0.dbKey == key.dbKey })?.value {
                try element.apply(childData, exactly: exactly)
            } else {
                let keyEntity = Key(in: storage.keysNode.child(with: key.dbKey))
                storage.elements[keyEntity] = try Value(fireData: childData, exactly: exactly)
            }
        }
    }

    override func _writeChanges(to transaction: RealtimeTransaction, by node: Node) throws {
        try storage.localElements.forEach { (key, value) in
            try _write(value,
                       for: key,
                       by: (storage: node,
                            itms: Node(key: InternalKeys.items, parent: node.linksNode)),
                       in: transaction)
        }
    }

    /// Collection does not respond for versions and raw value, and also payload.
    /// To change value version/raw can use enum, but use modified representer.
    override func _write(to transaction: RealtimeTransaction, by node: Node) throws {
//        super._write(to: transaction, by: node)
        // writes changes because after save collection can use only transaction mutations
        try _writeChanges(to: transaction, by: node)
    }

    public func didPrepare() {
        try? _snapshot.map(apply)
    }

//    public func willSave(in transaction: RealtimeTransaction, in parent: Node, by key: String) {
//
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
            transaction.removeValue(by: node!.linksNode)
        }
    }
    override public func didRemove(from node: Node) {
        super.didRemove(from: node)
        _view.source.didRemove()
        storage.elements.values.forEach { $0.didRemove(from: storage.sourceNode) }
    }
}
