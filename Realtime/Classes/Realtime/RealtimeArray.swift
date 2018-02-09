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
    func array<Element>(from parent: DatabaseReference) -> RealtimeArray<Element> {
        return RealtimeArray(dbRef: parent.child(rawValue))
    }
    func linkedArray<Element>(from parent: DatabaseReference, elements: DatabaseReference) -> LinkedRealtimeArray<Element> {
        return LinkedRealtimeArray(dbRef: parent.child(rawValue), elementsRef: elements)
    }
    func dictionary<Key, Element>(from parent: DatabaseReference, keys: DatabaseReference) -> RealtimeDictionary<Key, Element> {
        return RealtimeDictionary(dbRef: parent.child(rawValue), keysRef: keys)
    }
}

struct RealtimeArrayError: Error {
    enum Kind {
        case alreadyInserted
    }
    let type: Kind
}

/// -----------------------------------------

public protocol RealtimeCollectionStorage {
    associatedtype Value
    func placeholder(with key: String?) -> Value
}
protocol RCStorage: RealtimeCollectionStorage {
    associatedtype Key: StringRepresentableRealtimeArrayKey
    func storedValue(by key: Key) -> Value?
    func valueBy(ref reference: DatabaseReference) -> Value
    func valueRefBy(key: String) -> DatabaseReference
    func newValueRef() -> DatabaseReference
}
extension RCStorage {
    public func placeholder(with key: String? = nil) -> Value {
        return valueBy(ref: key.map(valueRefBy) ?? newValueRef())
    }
}
protocol MutableRCStorage: RCStorage {
    mutating func store(value: Value, by key: Key)
}
extension MutableRCStorage {
    internal mutating func object(for key: Key) -> Value {
        guard let element = storedValue(by: key) else {
            let value = placeholder(with: key.dbKey)
            store(value: value, by: key)

            return value
        }

        return element
    }
}
public struct RCDictionaryStorage<K, V>: MutableRCStorage where K: RealtimeDictionaryKey, K.UniqueKey == K.Key {
    public typealias Value = V
    let elementsRef: DatabaseReference
    let keysRef: DatabaseReference
    let elementBuilder: (DatabaseReference) -> Value
    var elements: [K: Value] = [:]

    mutating func store(value: Value, by key: K) { elements[for: key] = value }
    func storedValue(by key: K) -> Value? { return elements[for: key] }

    func valueBy(ref reference: DatabaseReference) -> Value { return elementBuilder(reference) }
    func valueRefBy(key: String) -> DatabaseReference { return elementsRef.child(key) }
    func newValueRef() -> DatabaseReference { return elementsRef.childByAutoId() }
    internal mutating func element(by key: Key.Key) -> (Key, Value) {
        guard let element = storedElement(by: key) else {
            let keyString = String(describing: key)
            let value = placeholder(with: keyString)
            let storeKey = Key(dbRef: keysRef.child(keyString))
            store(value: value, by: storeKey)

            return (storeKey, value)
        }

        return element
    }
    fileprivate func storedElement(by key: Key.Key) -> (Key, Value)? {
        return elements.first(where: { $0.key.key == key })
    }
}
public struct RCArrayStorage<V>: MutableRCStorage where V: KeyedRealtimeValue {
    public typealias Value = V
    let elementsRef: DatabaseReference
    var elementBuilder: (DatabaseReference) -> Value // TODO: let
    var elements: [_PrototypeValue<V.UniqueKey>.Key: Value] = [:]

    mutating func store(value: Value, by key: _PrototypeValue<V.UniqueKey>) { elements[for: key.key] = value }
    func storedValue(by key: _PrototypeValue<V.UniqueKey>) -> Value? { return elements[for: key.key] }

    func valueBy(ref reference: DatabaseReference) -> Value { return elementBuilder(reference) }
    func valueRefBy(key: String) -> DatabaseReference { return elementsRef.child(key) }
    func newValueRef() -> DatabaseReference { return elementsRef.childByAutoId() }
}
public struct KeyedCollectionStorage<V>: MutableRCStorage {
    public typealias Value = V
    let key: String
    let elementBuilder: (DatabaseReference) -> Value
    var elements: [String: Value] = [:]

    let valueRefByKey: (String) -> DatabaseReference
    let newValueReference: () -> DatabaseReference

    init<Source: RCStorage>(_ base: Source, key: String, builder: @escaping (DatabaseReference) -> Value) {
        self.valueRefByKey = base.valueRefBy
        self.newValueReference = base.newValueRef
        self.key = key
        self.elementBuilder = builder
    }

    mutating func store(value: Value, by key: String) { elements[for: key] = value }
    func storedValue(by key: String) -> Value? { return elements[for: key] }

    func valueBy(ref reference: DatabaseReference) -> Value { return elementBuilder(reference) }
    func valueRefBy(key: String) -> DatabaseReference { return valueRefByKey(key).child(self.key) }
    func newValueRef() -> DatabaseReference { return newValueReference().child(key) }
}
final class AnyCollectionStorage<K, V>: RCStorage where K: StringRepresentableRealtimeArrayKey {
    func storedValue(by key: K) -> V? {
        return _storedValue(key)
    }

    func valueBy(ref reference: DatabaseReference) -> V {
        return _valueBy(reference)
    }

    func valueRefBy(key: String) -> DatabaseReference {
        return _valueRefBy(key)
    }

    func newValueRef() -> DatabaseReference {
        return _newValueRef()
    }

    typealias Key = K
    typealias Value = V

    let _storedValue: (Key) -> Value?
    let _valueBy: (DatabaseReference) -> Value
    let _valueRefBy: (String) -> DatabaseReference
    let _newValueRef: () -> DatabaseReference

    init<Base: RCStorage>(_ base: Base) where Base.Key == K, Base.Value == V {
        self._storedValue = base.storedValue
        self._newValueRef = base.newValueRef
        self._valueBy = base.valueBy
        self._valueRefBy = base.valueRefBy
    }
}

public protocol RealtimeCollectionView {}
protocol RCView: RealtimeCollectionView, BidirectionalCollection, RequiresPreparation {}

struct AnyCollectionKey: RealtimeCollectionContainerKey {
    let key: String

    init<Base: RealtimeCollectionContainerKey>(_ key: Base) where Base.Key: CustomStringConvertible {
        self.key = key.key.description
    }
//    init<Base: RealtimeCollectionContainerKey>(_ key: Base) where Base.Key == String {
//        self.key = key.key
//    }
}

public final class AnyRealtimeCollectionView<Source>: RCView where Source: ValueWrapper & RealtimeValueActions, Source.T: BidirectionalCollection {
    let source: Source
    public internal(set) var isPrepared: Bool = false

    init(_ source: Source) {
        self.source = source
    }

    public func prepare(forUse completion: @escaping (Error?) -> Void) {
        guard !isPrepared else { completion(nil); return }

        source.load { (err, _) in
            self.isPrepared = err == nil

            completion(err)
        }
    }
    public func prepareRecursive(forUse completion: @escaping (Error?) -> Void) {
        // TODO:
    }

    public var startIndex: Source.T.Index { return source.value.startIndex }
    public var endIndex: Source.T.Index { return source.value.endIndex }
    public func index(after i: Source.T.Index) -> Source.T.Index { return source.value.index(after: i) }
    public func index(before i: Source.T.Index) -> Source.T.Index { return source.value.index(before: i) }
    public subscript(position: Source.T.Index) -> Source.T.Element { return source.value[position] }
}

public protocol RealtimeCollection: BidirectionalCollection, RealtimeValue, RequiresPreparation {
    associatedtype Storage: RealtimeCollectionStorage
    var storage: Storage { get }
//    associatedtype View: RealtimeCollectionView
    var view: RealtimeCollectionView { get }

    func listening(changes handler: @escaping () -> Void) -> ListeningItem // TODO: Add current changes as parameter to handler
    func runObserving() -> Void
    func stopObserving() -> Void
}
protocol RC: RealtimeCollection, RealtimeValueEvents {
    associatedtype View: RCView
    var _view: View { get }
}

/// MARK: RealtimeArray separated, new version

public protocol StringRepresentableRealtimeArrayKey { // TODO: See LosslessStringConvertible, ExpressibleByStringLiteral
    var dbKey: String { get }
}
extension String: StringRepresentableRealtimeArrayKey {
    public var dbKey: String { return self }
}
extension Int: StringRepresentableRealtimeArrayKey {
    public var dbKey: String { return String(self) }
}
extension Double: StringRepresentableRealtimeArrayKey {
    public var dbKey: String { return String(Int(self)) }
}
extension StringRepresentableRealtimeArrayKey where Self: CustomStringConvertible {
    public var dbKey: String { return String(describing: self) }
}

public protocol RealtimeCollectionKey: Hashable, StringRepresentableRealtimeArrayKey {
    associatedtype EntityId: Hashable, LosslessStringConvertible
    associatedtype LinkId: Hashable
    var entityId: EntityId { get }
    var linkId: LinkId { get }
}

public protocol RealtimeCollectionContainerKey {
    associatedtype Key: Equatable
    var key: Key { get }
}

extension RealtimeCollectionContainerKey where Self: RealtimeCollectionKey {
    public var key: EntityId { return entityId }
}

protocol KeyValueAccessableCollection {
    associatedtype Key
    associatedtype Value
    subscript(for key: Key) -> Value? { get set }
}

extension Array: KeyValueAccessableCollection {
    subscript(for key: Int) -> Element? {
        get { return self[key] }
        set(newValue) { self[key] = newValue! }
    }
}
extension Dictionary: KeyValueAccessableCollection {
    subscript(for key: Key) -> Value? {
        get { return self[key] }
        set(newValue) { self[key] = newValue }
    }
}

public protocol RequiresPreparation {
    var isPrepared: Bool { get }
    func prepare(forUse completion: @escaping (Error?) -> Void)
    func prepareRecursive(forUse completion: @escaping (Error?) -> Void)
}

public extension RequiresPreparation {
    func prepare(forUse completion: @escaping (Self, Error?) -> Void) {
        prepare(forUse: { completion(self, $0) })
    }
}
public extension RequiresPreparation where Self: RealtimeCollection {
    func prepareRecursive(forUse completion: @escaping (Error?) -> Void) {
        prepare { (err) in
            guard err == nil else { completion(err); return }
            prepareElementsRecursive(self, completion: { completion($0) })
        }
    }
}
extension RequiresPreparation {
    fileprivate func checkPreparation() {
        guard isPrepared else { fatalError("Instance should be activated before performing this action.") }
    }
}

//extension _RCArrayContainer {
//    var countAvailable: Container.IndexDistance { return elements.count }
//    func forEachAvailable(_ body: (Container.Iterator.Element) throws -> Void) rethrows {
//        try elements.forEach(body)
//    }
//}
public extension RealtimeCollection {
    /// RealtimeCollection actions

    func filtered<ValueGetter: InsiderOwner & ValueWrapper & RealtimeValueActions>(map values: @escaping (Iterator.Element) -> ValueGetter,
                  fetchIf: ((ValueGetter.T) -> Bool)? = nil,
                  predicate: @escaping (ValueGetter.T) -> Bool,
                  onCompleted: @escaping ([Iterator.Element]) -> ()) where ValueGetter.OutData == ValueGetter.T {
        var filteredElements: [Iterator.Element] = []
        let count = endIndex
        let completeIfNeeded = { (releasedCount: Index) in
            if count == releasedCount {
                onCompleted(filteredElements)
            }
        }

        var released = startIndex
        let current = self
        current.forEach { element in
            let value = values(element)
            let listeningItem = value.listeningItem(as: { $0.once() }, .just { (val) in
                released = current.index(after: released)
                guard predicate(val) else {
                    completeIfNeeded(released)
                    return
                }

                filteredElements.append(element)
                completeIfNeeded(released)
            })

            if fetchIf == nil || fetchIf!(value.value) {
                value.load(completion: nil)
            } else {
                listeningItem.notify()
            }
        }
    }
}

// MARK: Implementation RealtimeCollection`s

public typealias RealtimeDictionaryKey = StringRepresentableRealtimeArrayKey & RealtimeCollectionContainerKey & KeyedRealtimeValue & Linkable
public final class RealtimeDictionary<Key, Value>: RC
where Value: KeyedRealtimeValue & ChangeableRealtimeValue & RealtimeValueActions, Key: RealtimeDictionaryKey, Key.UniqueKey == Key.Key {
    public let dbRef: DatabaseReference
    public var view: RealtimeCollectionView { return _view }
    public var storage: RCDictionaryStorage<Key, Value>
    public var isPrepared: Bool { return _view.isPrepared }

    let _view: AnyRealtimeCollectionView<RealtimeProperty<[PrototypeKey], PrototypeValueSerializer>>

    public required init(dbRef: DatabaseReference, keysRef: DatabaseReference) {
        self.dbRef = dbRef
        self.storage = RCDictionaryStorage(elementsRef: dbRef, keysRef: keysRef, elementBuilder: Value.init, elements: [:])
        self._view = AnyRealtimeCollectionView(RealtimeProperty(dbRef: Nodes.items.reference(from: dbRef)))
    }

    // MARK: Implementation

    private var shouldLinking = true // TODO: Create class family for such cases
    public func unlinked() -> RealtimeDictionary<Key, Value> { shouldLinking = false; return self }

    public var startIndex: Int { return _view.startIndex }
    public var endIndex: Int { return _view.endIndex }
    public func index(after i: Int) -> Int { return _view.index(after: i) }
    public func index(before i: Int) -> Int { return _view.index(before: i) }
    public func listening(changes handler: @escaping () -> Void) -> ListeningItem { return _view.source.listeningItem(.just { _ in handler() }) }
    public func runObserving() {
        //        var oldValue: Prototype.T? = nil
        //        _ = prototype.listening { (newValue) in
        //            if newValue != oldValue {
        // make changes
        //            }
        //        }
        _view.source.runObserving()
    }
    public func stopObserving() { _view.source.stopObserving() }
    public var debugDescription: String { return _view.source.debugDescription }
    public func prepare(forUse completion: @escaping (Error?) -> Void) { _view.prepare(forUse: completion) }


    public typealias Element = (key: Key, value: Value)

    public func makeIterator() -> IndexingIterator<RealtimeDictionary> { return IndexingIterator(_elements: self) }
    public subscript(position: Int) -> Element { return storage.element(by: _view[position].key) }
    public subscript(key: Key) -> Value? { return storage.object(for: key) }

    public func containsValue(byKey key: Key) -> Bool { _view.checkPreparation(); return _view.source.value.contains(where: { $0.key == key.key }) }

    typealias PrototypeKey = _PrototypeValue<Key.Key>
    typealias PrototypeValueSerializer = _PrototypeValueSerializer<Key.Key>

    public func filtered(by value: Any, for node: RealtimeNode, completion: @escaping ([Element], Error?) -> ()) {
        filtered(with: { $0.queryOrdered(byChild: node.rawValue).queryEqual(toValue: value) }, completion: completion)
    }
    
    public func filtered(with query: (DatabaseReference) -> DatabaseQuery, completion: @escaping ([Element], Error?) -> ()) {
        query(dbRef).observeSingleEvent(of: .value, with: { (snapshot) in
            self.apply(snapshot: snapshot, strongly: false)
            
            completion(self.storage.elements.filter { snapshot.hasChild($0.key.dbKey) }, nil) // TODO: why such filter? to see snapshot result
        }) { (error) in
            completion([], error)
        }
    }
    
    // MARK: Mutating

    // TODO: element.dbRef should be equal key.dbRef. Avoid this misleading predicate
    public func set(element: Value, for key: Key, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        guard element.dbRef.isChild(for: dbRef) else { fatalError("Element has reference to location not inside that dictionary") }
        guard element.dbKey == key.dbKey else { fatalError("Element should have reference equal to key reference") }

        let transaction = transaction ?? RealtimeTransaction()
        if !isPrepared {
            transaction.addPrecondition { promise in
                self.prepare(forUse: promise.fulfill)
            }
        }
        
        let oldElement = storage.storedValue(by: key)
        guard containsValue(byKey: key) else {
            let link = key.generate(linkTo: _view.source.dbRef)
            let prototypeValue = PrototypeKey(entityId: key.uniqueKey, linkId: link.link.id, index: count)
            let oldValue = _view.source.value
            _view.source.value.append(prototypeValue)
            storage.store(value: element, by: key)
            transaction.addReversion { [weak self] in
                self?._view.source.value = oldValue
                if let old = oldElement {
                    self?.storage.store(value: old, by: key)
                } else {
                    self?.storage.elements.removeValue(forKey: key)
                }
            }
            if shouldLinking {
                transaction.addNode(item: (link.sourceRef, .value(link.link.dbValue)))
            }
            transaction.set(element)
            transaction.addNode(item: (_view.source.dbRef, .value(_view.source.localValue)))
            transaction.addCompletion { [weak self] result in
                if result {
                    key.add(link: link.link)
                    self?.didSave()
                }
            }
            return transaction
        }

        storage.store(value: element, by: key)
        transaction.addReversion { [weak self] in
            if let old = oldElement {
                self?.storage.store(value: old, by: key)
            } else {
                self?.storage.elements.removeValue(forKey: key)
            }
        }

        transaction.set(element)
        transaction.addCompletion { [weak self] result in
            if result {
                self?.didSave()
            }
        }
        return transaction
    }

    public func remove(for key: Key, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction? {
        guard let index = _view.source.value.index(where: { $0.key == key.key }) else { return transaction }

        let transaction = transaction ?? RealtimeTransaction()
        if !isPrepared {
            transaction.addPrecondition { promise in
                self.prepare(forUse: promise.fulfill)
            }
        }

        let oldValue = _view.source.value
        let p_value: PrototypeKey = _view.source.value.remove(at: index)
        transaction.addReversion { [weak _view] in
            _view?.source.value = oldValue
        }
        transaction.addNode(item: (_view.source.dbRef, .value(_view.source.localValue)))
        transaction.addNode(item: (storage.valueRefBy(key: key.dbKey), .value(nil)))
        transaction.addNode(item: (key.dbRef.child(Nodes.links.subpath(with: p_value.linkId)), .value(nil)))
        transaction.addCompletion { [weak self] result in
            if result {
                key.remove(linkBy: p_value.linkId)
                self?.storage.elements.removeValue(forKey: key)
                self?.didSave()
            }
        }
        return transaction
    }
    
    // MARK: Realtime
    
    public var localValue: Any? {
        let keys = _view.source.value.map { $0.key }
        let split = storage.elements.reduce((exists: [], removed: [])) { (res, keyValue) -> (exists: [(Key, Value)], removed: [(Key, Value)]) in
            guard keys.contains(keyValue.key.key) else {
                return (res.exists, res.removed + [keyValue])
            }
            
            return (res.exists + [keyValue], res.removed)
        }
        var value = Dictionary<String, Any?>(keys: keys.map { String($0) }, values: split.exists.map { $0.1.localValue })
        value[_view.source.dbKey] = _view.source.localValue
        split.removed.forEach { value[String($0.0.key)] = nil }
        
        return value
    }
    
    public required init(dbRef: DatabaseReference) {
        fatalError("Realtime dictionary cannot be initialized with init(dbRef:) initializer")
    }
    
    public required convenience init(snapshot: DataSnapshot) {
        fatalError("Realtime dictionary cannot be initialized with init(snapshot:) initializer")
    }
    
    public convenience init(snapshot: DataSnapshot, keysRef: DatabaseReference) {
        self.init(dbRef: snapshot.ref, keysRef: keysRef)
        apply(snapshot: snapshot)
    }
    
    public func apply(snapshot: DataSnapshot, strongly: Bool) {
        if strongly || Nodes.items.has(in: snapshot) {
            _view.source.apply(snapshot: Nodes.items.snapshot(from: snapshot))
            _view.isPrepared = true
        }
        _view.source.value.forEach { key in
            guard snapshot.hasChild(key.dbKey) else {
                if strongly, let contained = storage.elements.first(where: { $0.0.key == key.key }) { storage.elements.removeValue(forKey: contained.key) }
                return
            }
            let childSnapshot = snapshot.childSnapshot(forPath: key.dbKey)
            if let element = storage.elements.first(where: { $0.0.key == key.key })?.value {
                element.apply(snapshot: childSnapshot, strongly: strongly)
            } else {
                let keyEntity = Key(dbRef: storage.keysRef.child(key.dbKey))
                storage.elements[keyEntity] = Value(snapshot: childSnapshot, strongly: strongly)
            }
        }
    }
    
    public func didSave() {
        _view.source.didSave()
    }

    public func willRemove(completion: @escaping (Error?, [DatabaseReference]?) -> Void) { _view.source.willRemove(completion: completion) }
    public func didRemove() {
        _view.source.didRemove()
    }
}

/// # Realtime Array
/// ## https://stackoverflow.com/questions/24047991/does-swift-have-documentation-comments-or-tools/28633899#28633899
/// Comment writing guide
public final class RealtimeArray<Element>: RC
where Element: KeyedRealtimeValue & Linkable & RealtimeEntityActions, Element.UniqueKey: StringRepresentableRealtimeArrayKey {
    public let dbRef: DatabaseReference
    public var storage: RCArrayStorage<Element>
    public var view: RealtimeCollectionView { return _view }
    public var isPrepared: Bool { return _view.isPrepared }

    let _view: AnyRealtimeCollectionView<RealtimeProperty<[PrototypeKey], KeySerializer>>

    public required init(dbRef: DatabaseReference) {
        self.dbRef = dbRef
        self.storage = RCArrayStorage(elementsRef: dbRef, elementBuilder: Element.init, elements: [:])
        self._view = AnyRealtimeCollectionView(RealtimeProperty(dbRef: Nodes.items.reference(from: dbRef)))
    }

    // Implementation

    public func contains(_ element: Element) -> Bool {
        return _view.source.value.contains { $0.entityId == element.uniqueKey }
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

    typealias PrototypeKey = _PrototypeValue<Element.UniqueKey>
    typealias KeySerializer = _PrototypeValueSerializer<Element.UniqueKey>
    
    // TODO: Create Realtime wrapper for DatabaseQuery
    // TODO: Check filter with difficult values aka dictionary
    public func filtered(by value: Any, for node: RealtimeNode, completion: @escaping ([Element], Error?) -> ()) {
        filtered(with: { $0.queryOrdered(byChild: node.rawValue).queryEqual(toValue: value) }, completion: completion)
    }
    
    public func filtered(with query: (DatabaseReference) -> DatabaseQuery, completion: @escaping ([Element], Error?) -> ()) {
        query(dbRef).observeSingleEvent(of: .value, with: { (snapshot) in
            self.apply(snapshot: snapshot, strongly: false)
            
            completion(self.storage.elements.filter { snapshot.hasChild($0.value.dbKey) }.map { $0.value }, nil)
        }) { (error) in
            completion([], error)
        }
    }
    
    // MARK: Mutating

    @discardableResult
    public func insert(element: Element, at index: Int? = nil, in transaction: RealtimeTransaction? = nil) throws -> RealtimeTransaction {
//        _view.checkPreparation()
        guard element.dbRef.isChild(for: dbRef) else { fatalError("Element has reference to location not inside that dictionary") }
        guard !contains(element) else { throw RealtimeArrayError(type: .alreadyInserted) }

        let transaction = transaction ?? RealtimeTransaction()
        if !isPrepared {
            transaction.addPrecondition { promise in
                self.prepare(forUse: promise.fulfill)
            }
        }

        let link = element.generate(linkTo: _view.source.dbRef)
        let key = PrototypeKey(entityId: element.uniqueKey, linkId: link.link.id, index: index ?? count)

        let oldValue = _view.source.value
        _view.source.value.insert(key, at: key.index)
        element.add(link: link.link)
        storage.store(value: element, by: key)
        transaction.addReversion { [weak self] in
            self?._view.source.value = oldValue
            self?.storage.elements.removeValue(forKey: key.key)
            element.remove(linkBy: link.link.id)
        }
        transaction.addNode(item: (_view.source.dbRef, .value(_view.source.localValue)))
        if let elem = element as? RealtimeObject { // TODO: Fix it
            transaction.update(elem)
        } else {
            transaction.set(element)
        }
        transaction.addCompletion { [weak self] (result) in
            if result {
                self?.didSave()
            }
        }
        return transaction
    }

    @discardableResult
    func remove(element: Element, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction? {
        if let index = _view.source.value.index(where: { $0.entityId == element.uniqueKey }) {
            return remove(at: index, in: transaction)
        }
        return transaction
    }

    @discardableResult
    public func remove(at index: Int, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
//        _view.checkPreparation()

        let transaction = transaction ?? RealtimeTransaction()
        if !isPrepared {
            transaction.addPrecondition { promise in
                self.prepare(forUse: promise.fulfill)
            }
        }

        let oldValue = _view.source.value
        let key: PrototypeKey = _view.source.value.remove(at: index)
        transaction.addReversion { [weak _view] in
            _view?.source.value = oldValue
        }
        transaction.addNode(item: (_view.source.dbRef, .value(_view.source.localValue)))
        transaction.addNode(item: (storage.valueRefBy(key: key.dbKey), .value(nil)))
        transaction.addCompletion { [weak self] result in
            if result {
                self?.storage.elements.removeValue(forKey: key.key)
                self?.didSave()
            }
        }
        return transaction
    }
    
    // MARK: Realtime
    
    public var localValue: Any? {
        let keys = _view.source.value.map { $0.key }
        let split = storage.elements.reduce((exists: [], removed: [])) { (res, keyValue) -> (exists: [(_PrototypeValue<Element.UniqueKey>.Key, Element)], removed: [(_PrototypeValue<Element.UniqueKey>.Key, Element)]) in
            guard keys.contains(keyValue.key) else {
                return (res.exists, res.removed + [keyValue])
            }
            
            return (res.exists + [keyValue], res.removed)
        }
        var value = Dictionary<String, Any?>(keys: keys.map { String($0) }, values: split.exists.map { $0.1.localValue })
        value[_view.source.dbKey] = _view.source.localValue
        split.removed.forEach { value[$0.0.dbKey] = nil }
        
        return value
    }

    public required convenience init(snapshot: DataSnapshot) {
        self.init(dbRef: snapshot.ref)
        apply(snapshot: snapshot)
    }
    
    public func apply(snapshot: DataSnapshot, strongly: Bool) {
        if strongly || Nodes.items.has(in: snapshot) {
            _view.source.apply(snapshot: Nodes.items.snapshot(from: snapshot))
            _view.isPrepared = true
        }
        _view.source.value.forEach { key in
            guard snapshot.hasChild(key.dbKey) else {
                if strongly { storage.elements.removeValue(forKey: key.key) }
                return
            }
            let childSnapshot = snapshot.childSnapshot(forPath: key.dbKey)
            if let element = storage.elements[key.key] {
                element.apply(snapshot: childSnapshot, strongly: strongly)
            } else {
                storage.elements[key.key] = Element(snapshot: childSnapshot, strongly: strongly)
            }
        }
    }
    
    public func didSave() {
        _view.source.didSave()
    }

    public func willRemove(completion: @escaping (Error?, [DatabaseReference]?) -> Void) { _view.source.willRemove(completion: completion) }
    public func didRemove() {
        _view.source.didRemove()
    }
}

struct _PrototypeValue<Key: Hashable & LosslessStringConvertible>: RealtimeCollectionKey, RealtimeCollectionContainerKey, CustomStringConvertible {
    let entityId: Key
    let linkId: String
    let index: Int
    var description: String { return String(entityId) }
    
    var hashValue: Int {
        return entityId.hashValue &- linkId.hashValue
    }
    
    static func ==(lhs: _PrototypeValue, rhs: _PrototypeValue) -> Bool {
        return lhs.entityId == rhs.entityId
    }
}
final class _PrototypeValueSerializer<Key: Hashable & LosslessStringConvertible>: _Serializer {
    class func deserialize(entity: DataSnapshot) -> [_PrototypeValue<Key>] {
        guard let keyes = entity.value as? [Key: [String: Int]] else { return Entity.defValue }
        
        return keyes
            .map { _PrototypeValue(entityId: $0.key, linkId: $0.value.first!.key, index: $0.value.first!.value) }
            .sorted(by: { $0.index < $1.index })
    }
    
    class func serialize(entity: [_PrototypeValue<Key>]) -> Any? {
        return entity.reduce(Dictionary<Key, Any>(), { (result, key) -> [Key: Any] in
            var result = result
            result[key.entityId] = [key.linkId: result.count]
            return result
        })
    }
}

public final class LinkedRealtimeArray<Element>: RC
where Element: KeyedRealtimeValue & Linkable, Element.UniqueKey: StringRepresentableRealtimeArrayKey {
    public let dbRef: DatabaseReference
    public var storage: RCArrayStorage<Element>
    public var view: RealtimeCollectionView { return _view }
    public var localValue: Any? { return _view.source.localValue }
    public var isPrepared: Bool { return _view.isPrepared }

    let _view: AnyRealtimeCollectionView<RealtimeProperty<[Key], KeySerializer>>

    public required init(dbRef: DatabaseReference, elementsRef: DatabaseReference) {
        self.dbRef = dbRef
        self.storage = RCArrayStorage(elementsRef: elementsRef, elementBuilder: Element.init, elements: [:])
        self._view = AnyRealtimeCollectionView(RealtimeProperty(dbRef: dbRef))
    }
    
    // MARK: Realtime

    public required init(dbRef: DatabaseReference) {
        fatalError("Linked array cannot be initialized with init(dbRef:) initializer")
    }
    // TODO: For resolve error can be store link to objects in private key
    public required init(snapshot: DataSnapshot) {
        fatalError("Linked array cannot be initialized with init(snapshot:) initializer")
    }
    
    public convenience required init(snapshot: DataSnapshot, elementsRef: DatabaseReference) {
        self.init(dbRef: snapshot.ref, elementsRef: elementsRef)
        apply(snapshot: snapshot)
    }

    // Implementation

    public func contains(_ element: Element) -> Bool { return _view.source.value.contains { $0.entityId == element.uniqueKey } }

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

    typealias Key = _PrototypeValue<Element.UniqueKey>
    typealias KeySerializer = _PrototypeValueSerializer<Element.UniqueKey>

    public func apply(snapshot: DataSnapshot, strongly: Bool) {
        _view.source.apply(snapshot: snapshot, strongly: strongly)
        _view.isPrepared = true
    }

    public func didSave() {
        _view.source.didSave()
    }

    public func willRemove(completion: @escaping (Error?, [DatabaseReference]?) -> Void) { _view.source.willRemove(completion: completion) }
    public func didRemove() {
        _view.source.didRemove()
    }
}
extension LinkedRealtimeArray: KeyedRealtimeValue {
    public var uniqueKey: String { return dbKey }
}
public extension LinkedRealtimeArray {
    // MARK: Mutating

    @discardableResult
    func insert(element: Element, at index: Int? = nil, in transaction: RealtimeTransaction? = nil) throws -> RealtimeTransaction {
//        _view.checkPreparation()
        guard !contains(element) else { throw RealtimeArrayError(type: .alreadyInserted) }

        let transaction = transaction ?? RealtimeTransaction()
        if !isPrepared {
            transaction.addPrecondition { promise in
                self.prepare(forUse: promise.fulfill)
            }
        }

        let link = element.generate(linkTo: self._view.source.dbRef)
        let key = Key(entityId: element.uniqueKey, linkId: link.link.id, index: index ?? self.count)

        let oldValue = _view.source.value
        _view.source.value.insert(key, at: key.index)
        transaction.addReversion { [weak _view] in
            _view?.source.value = oldValue
        }
        transaction.addNode(item: (_view.source.dbRef, .value(_view.source.localValue)))
        transaction.addNode(item: (link.sourceRef, .value(link.link.dbValue)))
        transaction.addCompletion { [weak self] (result) in
            if result {
                self?.storage.elements[key.key] = element
                self?.didSave()
            }
        }
        return transaction
    }

    @discardableResult
    func remove(element: Element, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction? {
        if let index = _view.source.value.index(where: { $0.entityId == element.uniqueKey }) {
            return remove(at: index, in: transaction)
        }
        return transaction
    }

    @discardableResult
    func remove(at index: Int, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
//        _view.checkPreparation()

        let transaction = transaction ?? RealtimeTransaction()
        if !isPrepared {
            transaction.addPrecondition { promise in
                self.prepare(forUse: promise.fulfill)
            }
        }
        
        let oldValue = _view.source.value
        let key: Key = _view.source.value.remove(at: index)
        transaction.addReversion { [weak _view] in
            _view?.source.value = oldValue
        }
        transaction.addNode(item: (_view.source.dbRef, .value(_view.source.localValue)))
        transaction.addNode(item: (storage.valueRefBy(key: key.dbKey).child(Nodes.links.subpath(with: key.linkId)), .value(nil)))
        transaction.addCompletion { [weak self] (result) in
            if result {
                self?.storage.elements.removeValue(forKey: key.key)?.remove(linkBy: key.linkId)
                self?.didSave()
            }
        }
        return transaction
    }
}

extension DatabaseReference {
    func link(to targetRef: DatabaseReference) -> RealtimeLink {
        return RealtimeLink(id: key, path: targetRef.pathFromRoot)
    }
}
extension KeyedRealtimeValue {
    func generate(linkTo targetRef: DatabaseReference) -> (sourceRef: DatabaseReference, link: RealtimeLink) {
        let linkRef = Nodes.links.reference(from: dbRef).childByAutoId()
        return (linkRef, RealtimeLink(id: linkRef.key, path: targetRef.pathFromRoot))
    }
}

// MARK: Type erased realtime collection

private class _AnyRealtimeCollectionBase<Element>: Collection {
    var dbRef: DatabaseReference { fatalError() }
    var view: RealtimeCollectionView { fatalError() }
    var isPrepared: Bool { fatalError() }
    var localValue: Any? { fatalError() }
    func makeIterator() -> AnyIterator<Element> { fatalError() }
    var startIndex: Int { fatalError() }
    var endIndex: Int { fatalError() }
    func index(after i: Int) -> Int { fatalError() }
    func index(before i: Int) -> Int { fatalError() }
    subscript(position: Int) -> Element { fatalError() }
    func apply(snapshot: DataSnapshot, strongly: Bool) { fatalError() }
    func runObserving() { fatalError() }
    func stopObserving() { fatalError() }
    func listening(changes handler: @escaping () -> Void) -> ListeningItem { fatalError() }
    public func prepare(forUse completion: @escaping (Error?) -> Void) { fatalError() }
    required init?(snapshot: DataSnapshot) {  }
    required init(dbRef: DatabaseReference) {  }
    var debugDescription: String { return "" }
}

private final class __AnyRealtimeCollection<C: RealtimeCollection>: _AnyRealtimeCollectionBase<C.Iterator.Element>
where C.Index == Int {
    let base: C
    required init(base: C) {
        self.base = base
        super.init(dbRef: base.dbRef)
    }
    
    convenience required init?(snapshot: DataSnapshot) {
        guard let base = C(snapshot: snapshot) else { return nil }
        self.init(base: base)
    }
    
    convenience required init(dbRef: DatabaseReference) {
        self.init(base: C(dbRef: dbRef))
    }

    override var dbRef: DatabaseReference { return base.dbRef }
    override var view: RealtimeCollectionView { return base.view }
    override var localValue: Any? { return base.localValue }
    override var isPrepared: Bool { return base.isPrepared }

    override func makeIterator() -> AnyIterator<C.Iterator.Element> { return AnyIterator(base.makeIterator()) }
    override var startIndex: Int { return base.startIndex }
    override var endIndex: Int { return base.endIndex }
    override func index(after i: Int) -> Int { return base.index(after: i) }
    override func index(before i: Int) -> Int { return base.index(before: i) }
    override subscript(position: Int) -> C.Iterator.Element { return base[position] }

    override func apply(snapshot: DataSnapshot, strongly: Bool) { base.apply(snapshot: snapshot, strongly: strongly) }
    override func prepare(forUse completion: @escaping (Error?) -> Void) { base.prepare(forUse: completion) }
    override func listening(changes handler: @escaping () -> Void) -> ListeningItem { return base.listening(changes: handler) }
    override func runObserving() { base.runObserving() }
    override func stopObserving() { base.stopObserving() }
    override var debugDescription: String { return base.debugDescription }
}

//class AnyRealtimeCollection<Element>: RealtimeCollection {
//    private let base: _AnyRealtimeCollectionBase<Element>
//
//    public var dbRef: DatabaseReference { return base.dbRef }
//    public var view: RealtimeCollectionView { return base.view }
//    public var storage: AnyCollectionStorage<>
//    public var localValue: Any? { return base.localValue }
//    public var isPrepared: Bool { return base.isPrepared }
//    public var startIndex: Int { return base.startIndex }
//    public var endIndex: Int { return base.endIndex }
//    public func index(after i: Index) -> Index { return base.index(after: i) }
//    public subscript(position: Int) -> Element { return base[position] }
//    public var debugDescription: String { return base.debugDescription }
//    public func prepare(forUse completion: @escaping (Error?) -> Void) { base.prepare(forUse: completion) }
//    public func listening(changes handler: @escaping () -> Void) -> ListeningItem { return base.listening(changes: handler) }
//    public func runObserving() { base.runObserving() }
//    public func stopObserving() { base.stopObserving() }
//    public convenience required init?(snapshot: DataSnapshot) { fatalError() }
//    public required init(dbRef: DatabaseReference) { fatalError() }
//    public func apply(snapshot: DataSnapshot, strongly: Bool) { base.apply(snapshot: snapshot, strongly: strongly) }
//    public func didSave() { base.didSave() }
//    public func didRemove() { base.didRemove() }
//}

// TODO: Create wrapper that would sort array (sorting by default) (example array from tournament table)
// 1) Sorting performs before save prototype (storing sorted array)
// 2) Sorting performs after load prototype (runtime sorting)

extension RealtimeArray: KeyedRealtimeValue {
    public var uniqueKey: String { return dbKey }
}
extension KeyedRealtimeArray: KeyedRealtimeValue {
    public var uniqueKey: String { return dbKey }
}

public extension RealtimeArray {
    func keyed<Keyed: KeyedRealtimeValue, Node: RTNode>(by node: Node, elementBuilder: @escaping (DatabaseReference) -> Keyed = { .init(dbRef: $0) })
        -> KeyedRealtimeArray<Keyed, Element> where Keyed.UniqueKey: StringRepresentableRealtimeArrayKey, Node.RawValue == String {
        return KeyedRealtimeArray(base: self, key: node, elementBuilder: elementBuilder)
    }
}
public extension LinkedRealtimeArray {
    func keyed<Keyed: KeyedRealtimeValue, Node: RTNode>(by node: Node, elementBuilder: @escaping (DatabaseReference) -> Keyed = { .init(dbRef: $0) })
        -> KeyedRealtimeArray<Keyed, Element> where Keyed.UniqueKey: StringRepresentableRealtimeArrayKey, Node.RawValue == String {
            return KeyedRealtimeArray(base: self, key: node, elementBuilder: elementBuilder)
    }
}
public extension RealtimeDictionary {
    func keyed<Keyed: KeyedRealtimeValue, Node: RTNode>(by node: Node, elementBuilder: @escaping (DatabaseReference) -> Keyed = { .init(dbRef: $0) })
        -> KeyedRealtimeArray<Keyed, Element> where Keyed.UniqueKey: StringRepresentableRealtimeArrayKey, Node.RawValue == String {
            return KeyedRealtimeArray(base: self, key: node, elementBuilder: elementBuilder)
    }
}

// TODO: Create lazy flatMap collection with keyPath access

struct AnySharedCollection<Element>: Collection {
    let _startIndex: () -> Int
    let _endIndex: () -> Int
    let _indexAfter: (Int) -> Int
    let _subscript: (Int) -> Element

    init<Base: Collection>(_ base: Base) where Base.Iterator.Element == Element, Base.Index: SignedInteger {
        self._startIndex = { return base.startIndex.toOther() }
        self._endIndex = { return base.endIndex.toOther() }
        self._indexAfter = { return base.index(after: $0.toOther()).toOther() }
        self._subscript = { return base[$0.toOther()] }
    }

    public var startIndex: Int { return _startIndex() }
    public var endIndex: Int { return _endIndex() }
    public func index(after i: Int) -> Int { return _indexAfter(i) }
    public subscript(position: Int) -> Element { return _subscript(position) }
}

// TODO: Need update keyed storage when to parent view changed to operate actual data
public final class KeyedRealtimeArray<Element, BaseElement>: RealtimeCollection
where Element: KeyedRealtimeValue, Element.UniqueKey: StringRepresentableRealtimeArrayKey {
    public typealias Index = Int
    private let base: _AnyRealtimeCollectionBase<BaseElement>
    private let baseView: AnySharedCollection<AnyCollectionKey>

    init<B: RC, Node: RTNode>(base: B, key: Node, elementBuilder: @escaping (DatabaseReference) -> Element = { .init(dbRef: $0) })
    where B.Storage: RCStorage, B.View.Iterator.Element: RealtimeCollectionContainerKey, B.View.Iterator.Element.Key: CustomStringConvertible,
        B.View.Index: SignedInteger, B.Iterator.Element == BaseElement, B.Index == Int, Node.RawValue == String {
        self.base = __AnyRealtimeCollection(base: base)
        self.storage = KeyedCollectionStorage(base.storage, key: key.rawValue, builder: elementBuilder)
        self.baseView = AnySharedCollection(base._view.lazy.map(AnyCollectionKey.init))
    }

    public var dbRef: DatabaseReference { return base.dbRef }
    public var view: RealtimeCollectionView { return base.view }
    public var storage: KeyedCollectionStorage<Element>
    public var localValue: Any? { return base.localValue }
    public var isPrepared: Bool { return base.isPrepared }

    public var startIndex: Index { return base.startIndex }
    public var endIndex: Index { return base.endIndex }
    public func index(after i: Index) -> Index { return base.index(after: i) }
    public func index(before i: Int) -> Int { return base.index(before: i) }
    public subscript(position: Int) -> Element { return storage.object(for: baseView[position].key) }
    public var debugDescription: String { return base.debugDescription }
    public func prepare(forUse completion: @escaping (Error?) -> Void) { base.prepare(forUse: completion) }

    public func listening(changes handler: @escaping () -> Void) -> ListeningItem {
        return base.listening(changes: handler)
    }
    public func runObserving() {
        base.runObserving()
    }
    public func stopObserving() {
        base.stopObserving()
    }

    public convenience required init?(snapshot: DataSnapshot) {
        fatalError()
    }

    public required init(dbRef: DatabaseReference) {
        fatalError()
    }

    public func apply(snapshot: DataSnapshot, strongly: Bool) {
        base.apply(snapshot: snapshot, strongly: strongly)
    }
}

public extension RealtimeCollection where Iterator.Element: RequiresPreparation {
    func prepareRecursive(_ completion: @escaping (Error?) -> Void) {
        let current = self
        current.prepare { (err) in
            let count = current.endIndex
            let completeIfNeeded = { (releasedCount: Index) in
                if count == releasedCount {
                    completion(err)
                }
            }

            var released = current.startIndex
            current.forEach { element in
                element.prepareRecursive { (_) in
                    released = current.index(after: released)
                    completeIfNeeded(released)
                }
            }
        }
    }
}

func prepareElementsRecursive<RC: Collection>(_ collection: RC, completion: @escaping (Error?) -> Void) {
    let count = collection.endIndex
    var lastErr: Error? = nil
    let completeIfNeeded = { (releasedCount: RC.Index) in
        if count == releasedCount {
            completion(lastErr)
        }
    }

    var released = collection.startIndex
    collection.forEach { element in
        if let prepared = (element as? RequiresPreparation) {
            prepared.prepareRecursive { (err) in
                lastErr = err
                released = collection.index(after: released)
                completeIfNeeded(released)
            }
        } else {
            released = collection.index(after: released)
            completeIfNeeded(released)
        }
    }
}
