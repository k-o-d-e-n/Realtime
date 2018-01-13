//
//  RealtimeArray.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 18/02/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation
import FirebaseDatabase

// TODO: Need implement Swift standart sequence protocol such as LazySequenceProtocol and others

//struct LazyScanIterator<Base : IteratorProtocol, ResultElement>
//: IteratorProtocol {
//    mutating func next() -> ResultElement? {
//        return nextElement.map { result in
//            nextElement = base.next().map { nextPartialResult(result, $0) }
//            return result
//        }
//    }
//    private var nextElement: ResultElement? // The next result of next().
//    private var base: Base                  // The underlying iterator.
//    private let nextPartialResult: (ResultElement, Base.Element) -> ResultElement
//}

//internal protocol MutableRealtimeCollection: RealtimeCollection
//protocol RealtimeAssociatedCollection: MutableRealtimeCollection

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
    enum ErrorKind {
        case notActivated
        case arrayNotCreated
        case alreadyCreated
        case alreadyInserted
    }
    let type: ErrorKind
}

/// MARK: RealtimeArray separated, new version

public protocol StringRepresentableRealtimeArrayKey {
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

public protocol KeyValueAccessableCollection {
    associatedtype Key
    associatedtype Value
    subscript(for key: Key) -> Value? { get set }
}

extension Array: KeyValueAccessableCollection {
    public subscript(for key: Int) -> Element? {
        get { return self[key] }
        set(newValue) { self[key] = newValue! }
    }
}
extension Dictionary: KeyValueAccessableCollection {
    public subscript(for key: Key) -> Value? {
        get { return self[key] }
        set(newValue) { self[key] = newValue }
    }
}

public typealias ElementContainer = Collection & KeyValueAccessableCollection

public protocol RequiresPreparation: _Prepared {
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
public protocol _Prepared: class {
    var isPrepared: Bool { set get }
}

public protocol _RC: class, Collection, RealtimeValue {}
public protocol _RCPrototype {
    associatedtype KeysIterator: IteratorProtocol
    func makeKeysIterator() -> KeysIterator
    func key(by index: Int) -> KeysIterator.Element
}
public protocol _RCElementProvider: Collection {
    associatedtype StoreKey: StringRepresentableRealtimeArrayKey
    associatedtype StoreValue
    func valueRefBy(key: String) -> DatabaseReference
    func newValueRef() -> DatabaseReference
    func valueBy(ref reference: DatabaseReference) -> StoreValue
    func store(value: StoreValue, by key: StoreKey)
    func storedValue(by key: StoreKey) -> StoreValue?
}
extension _RCElementProvider {
    internal func object(for key: StoreKey) -> StoreValue {
        guard let element = storedValue(by: key) else {
            let value = valueBy(ref: valueRefBy(key: key.dbKey))
            store(value: value, by: key)

            return value
        }

        return element
    }
}
extension _RC where Self: _RCElementProvider, Self.Iterator.Element == Self.StoreValue, Self: _RCPrototype, Self.KeysIterator.Element == Self.StoreKey, Index == Int {
    public func makeIterator() -> RCValueIterator<Self> { return RCValueIterator(self) }
    public subscript(position: Index) -> StoreValue {
        return object(for: key(by: position))
    }
}
public struct RCValueIterator<C: _RC & _RCPrototype & _RCElementProvider>: IteratorProtocol where C.KeysIterator.Element == C.StoreKey {
    private weak var collection: C!
    private var keysIterator: C.KeysIterator

    init(_ base: C) {
        self.collection = base
        self.keysIterator = collection.makeKeysIterator()
    }

    public mutating func next() -> C.StoreValue? {
        return keysIterator.next().map(collection.object)
    }
}

public protocol _RCArrayPrototype {
    associatedtype Prototype: ArrayPrototype
    var prototype: Prototype { get }
}
extension _RCArrayPrototype where Self: RealtimeCollection {
    public var debugDescription: String { return prototype.debugDescription }
}
extension _RCArrayPrototype where Self: RealtimeCollection {
    public func prepare(forUse completion: @escaping (Error?) -> Void) {
        guard !isPrepared else { completion(nil); return }

        prototype.load { (err, _) in
            self.isPrepared = err == nil

            completion(err)
        }
    }
}
extension _RCArrayPrototype where Self: RealtimeCollection, Prototype.T: Collection {
    public var startIndex: Prototype.T.Index { return prototype.value.startIndex }
    public var endIndex: Prototype.T.Index { return prototype.value.endIndex }

    public func index(after i: Prototype.T.Index) -> Prototype.T.Index {
        return prototype.value.index(after: i)
    }
}
extension _RCArrayPrototype where Self: RealtimeCollection, Prototype.T: Collection, Prototype.T.Iterator.Element == Self.KeysIterator.Element {
    public func makeKeysIterator() -> Prototype.T.Iterator {
        return prototype.value.makeIterator()
    }
    public func key(by index: Prototype.T.Index) -> Prototype.T.Iterator.Element {
        return prototype.value[index]
    }
}

public protocol _RCArrayContainer: class {
    var elementsRef: DatabaseReference { get }

    associatedtype Container: ElementContainer
    var elements: Container { get set }
}
extension _RCArrayContainer {
    var countAvailable: Container.IndexDistance { return elements.count }
    func forEachAvailable(_ body: (Container.Iterator.Element) throws -> Void) rethrows {
        try elements.forEach(body)
    }
}
public extension _RCArrayContainer where Self: RealtimeCollection {
    func valueRefBy(key: String) -> DatabaseReference { return elementsRef.child(key) }
    func newValueRef() -> DatabaseReference { return elementsRef.childByAutoId() }
}
public extension _RCArrayContainer where Self: RealtimeCollection, Self.StoreValue: RealtimeValue {
    func valueBy(ref reference: DatabaseReference) -> StoreValue { return StoreValue(dbRef: reference) }
}
public extension _RCArrayContainer where Self: RealtimeCollection, Self.Container.Value == Self.StoreValue, Self.Container.Key == Self.StoreKey {
    func store(value: StoreValue, by key: StoreKey) { elements[for: key] = value }
    func storedValue(by key: StoreKey) -> StoreValue? { return elements[for: key] }
}

public typealias ArrayPrototype = RealtimeValue & InsiderOwner & ValueWrapper & RealtimeValueActions
public protocol RealtimeCollection: _RC, _RCElementProvider, _RCPrototype, RequiresPreparation {
    func changesListening(completion: @escaping () -> Void) -> ListeningItem
    func runObserving() -> Void
    func stopObserving() -> Void
}
extension RealtimeCollection {
    /// RealtimeCollection actions

    public func filtered<ValueGetter: InsiderOwner & ValueWrapper & RealtimeValueActions>(map values: @escaping (Iterator.Element) -> ValueGetter,
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
public extension RealtimeCollection where Self: _RCArrayPrototype {
    func changesListening(completion: @escaping () -> Void) -> ListeningItem {
        return prototype.listeningItem(.just { _ in completion() })
    }
    func runObserving() {
//        var oldValue: Prototype.T? = nil
//        _ = prototype.listening { (newValue) in
//            if newValue != oldValue {
                // make changes
//            }
//        }
        prototype.runObserving()
    }
    func stopObserving() {
        prototype.stopObserving()
    }
}

public extension _RCElementProvider {
    func newPlaceholder() -> StoreValue { return valueBy(ref: newValueRef()) }
    func newPlaceholder(with key: String) -> StoreValue { return valueBy(ref: valueRefBy(key: key)) }
}

// MARK: Implementation RealtimeCollection`s

public typealias RealtimeDictionaryKey = StringRepresentableRealtimeArrayKey & RealtimeCollectionContainerKey & KeyedRealtimeValue & Linkable
public final class RealtimeDictionary<Key, Value>: RealtimeCollection, _RCArrayPrototype, _RCArrayContainer
where Value: KeyedRealtimeValue & ChangeableRealtimeValue & RealtimeValueActions, Key: RealtimeDictionaryKey, Key.UniqueKey == Key.Key {
    public typealias PrototypeKey = _PrototypeValue<Key.Key>
    public typealias PrototypeValueSerializer = _PrototypeValueSerializer<Key.Key>
    public let dbRef: DatabaseReference
    public var elementsRef: DatabaseReference { return dbRef }
    private var prototypeRef: DatabaseReference { return Nodes.items.reference(from: dbRef) }
    private var keysRef: DatabaseReference
    
    public var prototype: RealtimeProperty<[PrototypeKey], PrototypeValueSerializer>
    public var elements: [Key: Value] = [:]

    public var isPrepared: Bool = false

    private var shouldLinking = true // TODO: Create class family for such cases
    func unlinked() -> RealtimeDictionary<Key, Value> { shouldLinking = false; return self }
    
    public required init(dbRef: DatabaseReference, keysRef: DatabaseReference) {
        self.dbRef = dbRef
        self.keysRef = keysRef
        self.prototype = RealtimeProperty(dbRef: Nodes.items.reference(from: dbRef))
    }

    // MARK: Implementation

    public typealias Element = (key: Key, value: Value)

    public func makeIterator() -> IndexingIterator<RealtimeDictionary> {
        return IndexingIterator(_elements: self)
    }
    public subscript(position: Int) -> Element {
        let k = key(by: position)
        guard let element = storedElement(by: k) else {
            let value = valueBy(ref: valueRefBy(key: k.dbKey))
            let storeKey = Container.Key(dbRef: keysRef.child(k.dbKey))
            elements[for: storeKey] = value

            return (storeKey, value)
        }

        return element
    }

    subscript(key: Container.Key) -> StoreValue? {
        guard let prototypeKey = prototype.value.first(where: { $0.key == key.key }) else { return nil }
        return object(for: prototypeKey)
    }

    public func store(value: Value, by key: _PrototypeValue<Key.Key>) {
        let storeKey = Container.Key(dbRef: keysRef.child(key.dbKey))
        elements[for: storeKey] = value
    }
    public func storedValue(by key: _PrototypeValue<Key.Key>) -> Value? {
        return storedElement(by: key)?.value
    }
    private func storedElement(by key: _PrototypeValue<Key.Key>) -> Element? {
        return elements.first(where: { $0.key.key == key.key })
    }

    public func filtered(by value: Any, for node: RealtimeNode, completion: @escaping ([Element], Error?) -> ()) {
        filtered(with: { $0.queryOrdered(byChild: node.rawValue).queryEqual(toValue: value) }, completion: completion)
    }
    
    public func filtered(with query: (DatabaseReference) -> DatabaseQuery, completion: @escaping ([Element], Error?) -> ()) {
        query(dbRef).observeSingleEvent(of: .value, with: { (snapshot) in
            self.apply(snapshot: snapshot, strongly: false)
            
            completion(self.elements.filter { snapshot.hasChild($0.key.dbKey) }, nil) // TODO: why such filter? to see snapshot result
        }) { (error) in
            completion([], error)
        }
    }
    
    // MARK: Mutating

    // TODO: Element must be referenced by key. Avoid this unnecessary pre-action
    // TODO: Use methods from store for save/retrieve
    public func set(element: Value, for key: Key, completion: ((Error?, DatabaseReference) -> ())? = nil) {
        guard element.dbRef.isChild(for: dbRef) else { fatalError("Element has reference to location not inside that dictionary") }
        guard prototype.value.contains(where: { $0.key == key.key }) else {
            let link = key.generate(linkTo: prototypeRef)
            let prototypeValue = PrototypeKey(entityId: key.uniqueKey, linkId: link.link.id, index: count)
            prototype.changeLocalValue { $0.append(prototypeValue) }
            elements[key] = element
            let update = shouldLinking ? [(link.sourceRef, link.link.dbValue), (element.dbRef, element.localValue)] : [(element.dbRef, element.localValue)]
            prototype.save(with: update) { (error, ref) in
                if error == nil {
                    key.add(link: link.link)
                }
                completion?(error, ref)
            }
            return
        }

        self.elements[key] = element
        element.save(completion: completion)
    }

    public func remove(for key: Key, completion: ((Error?, DatabaseReference) -> ())? = nil) {
        guard let index = prototype.value.index(where: { $0.key == key.key }) else { return }

        var p_value: PrototypeKey!
        prototype.changeLocalValue { p_value = $0.remove(at: index) }
        prototype.save(with: [(valueRefBy(key: key.dbKey), nil),
                              (key.dbRef.child(Nodes.links.subpath(with: p_value.linkId)), nil)]) { (err, ref) in
                                if err == nil {
                                    key.remove(linkBy: p_value.linkId)
                                    self.elements.removeValue(forKey: key)
                                }
                                completion?(err, ref)
        }
    }
    
    // MARK: Realtime
    
    public var localValue: Any? {
        let keys = prototype.value.map { $0.key }
        let split = elements.reduce((exists: [], removed: [])) { (res, keyValue) -> (exists: [(Key, Value)], removed: [(Key, Value)]) in
            guard keys.contains(keyValue.key.key) else {
                return (res.exists, res.removed + [keyValue])
            }
            
            return (res.exists + [keyValue], res.removed)
        }
        var value = Dictionary<String, Any?>(keys: keys.map { String($0) }, values: split.exists.map { $0.1.localValue })
        value[prototype.dbKey] = prototype.localValue
        split.removed.forEach { value[String($0.0.key)] = nil }
        
        return value
    }
    
    public required init(dbRef: DatabaseReference) {
        fatalError("Realtime dictionary cannot be initialized with init(dbRef:) initializer")
    }
    
    public required convenience init(snapshot: DataSnapshot) {
        fatalError("Realtime dictionary cannot be initialized with init(snapshot:) initializer")
    }
    
    convenience init(snapshot: DataSnapshot, keysRef: DatabaseReference) {
        self.init(dbRef: snapshot.ref, keysRef: keysRef)
        apply(snapshot: snapshot)
    }
    
    public func apply(snapshot: DataSnapshot, strongly: Bool) {
        if strongly || Nodes.items.has(in: snapshot) {
            prototype.apply(snapshot: Nodes.items.snapshot(from: snapshot))
            isPrepared = true
        }
        prototype.value.forEach { key in
            guard snapshot.hasChild(key.dbKey) else {
                if strongly, let contained = elements.first(where: { $0.0.key == key.key }) { elements.removeValue(forKey: contained.key) }
                return
            }
            let childSnapshot = snapshot.childSnapshot(forPath: key.dbKey)
            if let element = elements.first(where: { $0.0.key == key.key })?.value {
                element.apply(snapshot: childSnapshot, strongly: strongly)
            } else {
                let keyEntity = Key(dbRef: keysRef.child(key.dbKey))
                elements[keyEntity] = Value(snapshot: childSnapshot, strongly: strongly)
            }
        }
    }
    
    public func didSave() {
        prototype.didSave()
    }
    
    public func didRemove() {
        prototype.didRemove()
    }
}

/// # Realtime Array
/// ## https://stackoverflow.com/questions/24047991/does-swift-have-documentation-comments-or-tools/28633899#28633899
/// Comment writing guide
public final class RealtimeArray<Elem>: RealtimeCollection, _RCArrayPrototype, _RCArrayContainer
where Elem: KeyedRealtimeValue & Linkable & RealtimeEntityActions, Elem.UniqueKey: StringRepresentableRealtimeArrayKey {
    public typealias PrototypeKey = _PrototypeValue<Element.UniqueKey>
    public typealias KeySerializer = _PrototypeValueSerializer<Element.UniqueKey>
    public typealias Element = Elem

    public let dbRef: DatabaseReference
    public var elementsRef: DatabaseReference { return dbRef }
    internal var prototypeRef: DatabaseReference { return Nodes.items.reference(from: dbRef) }
    
    public var prototype: RealtimeProperty<[PrototypeKey], KeySerializer>
    public var elements: [PrototypeKey.Key: Element] = [:]

    public var isPrepared: Bool = false
    
    public required init(dbRef: DatabaseReference) {
        self.dbRef = dbRef
        self.prototype = RealtimeProperty(dbRef: Nodes.items.reference(from: dbRef))
    }

    // Implementation

    public func store(value: Element, by key: PrototypeKey) {
        elements[for: key.key] = value
    }
    public func storedValue(by key: PrototypeKey) -> Element? {
        return elements[key.key]
    }
    
    func contains(_ element: Iterator.Element) -> Bool {
        return prototype.value.contains { $0.entityId == element.uniqueKey }
    }
    
    // TODO: Create Realtime wrapper for DatabaseQuery
    // TODO: Check filter with difficult values aka dictionary
    public func filtered(by value: Any, for node: RealtimeNode, completion: @escaping ([Element], Error?) -> ()) {
        filtered(with: { $0.queryOrdered(byChild: node.rawValue).queryEqual(toValue: value) }, completion: completion)
    }
    
    public func filtered(with query: (DatabaseReference) -> DatabaseQuery, completion: @escaping ([Element], Error?) -> ()) {
        query(dbRef).observeSingleEvent(of: .value, with: { (snapshot) in
            self.apply(snapshot: snapshot, strongly: false)
            
            completion(self.elements.filter { snapshot.hasChild($0.value.dbKey) }.map { $0.value }, nil)
        }) { (error) in
            completion([], error)
        }
    }
    
    // MARK: Mutating

    public func write(to transaction: RealtimeTransaction, actions: ((Element, Int?) throws -> Void, (Int) -> Void) -> Void) {
        checkPreparation()

        let insert: (Element, Int?) throws -> Void = { element, index in
            guard !self.contains(element) else { throw RealtimeArrayError(type: .alreadyInserted) }

            let link = element.generate(linkTo: self.prototypeRef)
            let key = PrototypeKey(entityId: element.uniqueKey, linkId: link.link.id, index: index ?? self.count)
            self.prototype.changeLocalValue { $0.insert(key, at: key.index) }
            element.add(link: link.link)
            transaction.addUpdate(item: (element.dbRef, element.localValue))

            transaction.addCompletion { (err) in
                if err == nil {
                    self.elements[key.key] = element
                    self.prototype.didSave()
                }
            }
        }
        var removedKeys: [PrototypeKey] = []
        let remove: (Int) -> Void = { index in
            self.prototype.changeLocalValue { removedKeys.append($0.remove(at: index)) }
            transaction.addCompletion { (err) in
                if err == nil {
                    removedKeys.forEach { key in
                        self.elements.removeValue(forKey: key.key)
                    }
                    self.prototype.didSave()
                }
            }
        }

        actions(insert, remove)
        removedKeys.forEach { transaction.addUpdate(item: (valueRefBy(key: $0.dbKey), nil)) }
        transaction.addUpdate(item: (prototype.dbRef, prototype.localValue))
    }

    public func insert(element: Element, at index: Int? = nil, completion: ((Error?, DatabaseReference) -> ())? = nil) {
        checkPreparation()
        guard !contains(element) else { completion?(RealtimeArrayError(type: .alreadyInserted), elementsRef); return }

        let link = element.generate(linkTo: prototypeRef)
        let key = PrototypeKey(entityId: element.uniqueKey, linkId: link.link.id, index: index ?? count)
        prototype.changeLocalValue { $0.insert(key, at: key.index) }
        element.add(link: link.link)
        elements[key.key] = element
        element.save(with: [(prototype.dbRef, prototype.localValue)]) { (error, ref) in
            if error == nil {
                self.prototype.didSave()
            }
            completion?(error, ref)
        }
    }
    
    public func remove(element: Element, completion: Database.TransactionCompletion?) {
        if let index = prototype.value.index(where: { $0.entityId == element.uniqueKey }) {
            remove(at: index, completion: completion)
        }
    }
    
    public func remove(at index: Int, completion: ((Error?, DatabaseReference) -> ())? = nil) {
        checkPreparation()
        
        var key: PrototypeKey!
        prototype.changeLocalValue { key = $0.remove(at: index) }
        prototype.save(with: [(valueRefBy(key: key.dbKey), nil)]) { (err, ref) in
            if err == nil {
                self.prototype.didSave()
                self.elements.removeValue(forKey: key.key)
            }
            completion?(err, ref)
        }
    }
    
    // MARK: Realtime
    
    public var localValue: Any? {
        let keys = prototype.value.map { $0.key }
        let split = elements.reduce((exists: [], removed: [])) { (res, keyValue) -> (exists: [(PrototypeKey.Key, Element)], removed: [(PrototypeKey.Key, Element)]) in
            guard keys.contains(keyValue.key) else {
                return (res.exists, res.removed + [keyValue])
            }
            
            return (res.exists + [keyValue], res.removed)
        }
        var value = Dictionary<String, Any?>(keys: keys.map { String($0) }, values: split.exists.map { $0.1.localValue })
        value[prototype.dbKey] = prototype.localValue
        split.removed.forEach { value[String($0.0)] = nil }
        
        return value
    }

    public required convenience init(snapshot: DataSnapshot) {
        self.init(dbRef: snapshot.ref)
        apply(snapshot: snapshot)
    }
    
    public func apply(snapshot: DataSnapshot, strongly: Bool) {
        if strongly || Nodes.items.has(in: snapshot) {
            prototype.apply(snapshot: Nodes.items.snapshot(from: snapshot))
            isPrepared = true
        }
        prototype.value.forEach { key in
            guard snapshot.hasChild(key.dbKey) else {
                if strongly { elements.removeValue(forKey: key.key) }
                return
            }
            let childSnapshot = snapshot.childSnapshot(forPath: key.dbKey)
            if let element = elements[key.key] {
                element.apply(snapshot: childSnapshot, strongly: strongly)
            } else {
                elements[key.key] = Element(snapshot: childSnapshot, strongly: strongly)
            }
        }
    }
    
    public func didSave() {
        prototype.didSave()
    }
    
    public func didRemove() {
        prototype.didRemove()
    }
}

public struct _PrototypeValue<Key: Hashable & LosslessStringConvertible>: RealtimeCollectionKey, RealtimeCollectionContainerKey {
    public let entityId: Key
    public let linkId: String
    let index: Int
    public var dbKey: String { return String(entityId) }
    
    public var hashValue: Int {
        return entityId.hashValue &- linkId.hashValue
    }
    
    public static func ==(lhs: _PrototypeValue, rhs: _PrototypeValue) -> Bool {
        return lhs.entityId == rhs.entityId
    }
}
public final class _PrototypeValueSerializer<Key: Hashable & LosslessStringConvertible>: _Serializer {
    public class func deserialize(entity: DataSnapshot) -> [_PrototypeValue<Key>] {
        guard let keyes = entity.value as? [Key: [String: Int]] else { return Entity.defValue }
        
        return keyes
            .map { _PrototypeValue(entityId: $0.key, linkId: $0.value.first!.key, index: $0.value.first!.value) }
            .sorted(by: { $0.index < $1.index })
    }
    
    public class func serialize(entity: [_PrototypeValue<Key>]) -> Any? {
        return entity.reduce(Dictionary<Key, Any>(), { (result, key) -> [Key: Any] in
            var result = result
            result[key.entityId] = [key.linkId: result.count]
            return result
        })
    }
}

// TODO: Listen prototype changes for remove deleted elements in other operations.
// TODO: Add method for activate realtime mode (observing changes).
public final class LinkedRealtimeArray<Elem>: RealtimeCollection, _RC, _RCElementProvider, _RCPrototype, _RCArrayPrototype, _RCArrayContainer
where Elem: KeyedRealtimeValue, Elem.UniqueKey: StringRepresentableRealtimeArrayKey {
    public typealias Key = _PrototypeValue<Element.UniqueKey>
    public typealias KeySerializer = _PrototypeValueSerializer<Element.UniqueKey>
    public typealias Element = Elem
    
    public let dbRef: DatabaseReference
    public var elementsRef: DatabaseReference
    internal var prototypeRef: DatabaseReference { return dbRef }
    public var prototype: RealtimeProperty<[Key], KeySerializer>
    public var elements: [Key.Key: Element] = [:]
    
    // optional
    var elementBuilder: ((Element.Type, DatabaseReference) -> Element)?
    var keyPath: String?
    public var isPrepared: Bool = false
    
    public required init(dbRef: DatabaseReference, elementsRef: DatabaseReference) {
        self.dbRef = dbRef
        self.elementsRef = elementsRef
        self.prototype = RealtimeProperty(dbRef: dbRef)
    }
    
    // MARK: Realtime
    
    public var localValue: Any? { return prototype.localValue }
    
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

    func contains(_ element: Iterator.Element) -> Bool {
        return prototype.value.contains { $0.entityId == element.uniqueKey }
    }

    public typealias StoreKey = _PrototypeValue<Element.UniqueKey>.Key
    public typealias StoreValue = Element
    public func makeKeysIterator() -> AnyIterator<_PrototypeValue<Element.UniqueKey>.Key> {
        var itr = prototype.value.makeIterator()
        return AnyIterator { itr.next()?.key }
    }
    public func key(by index: Int) -> _PrototypeValue<Element.UniqueKey>.Key {
        return prototype.value[index].key
    }
    public func valueRefBy(key: String) -> DatabaseReference {
        return elementsRef.child(keyPath.map { key + "/" + $0 } ?? key)
    }

    public func apply(snapshot: DataSnapshot, strongly: Bool) {
        prototype.apply(snapshot: snapshot, strongly: strongly)
        isPrepared = true
    }

    public func didSave() {
        prototype.didSave()
    }

    public func didRemove() {
        prototype.didRemove()
    }
}
extension LinkedRealtimeArray: KeyedRealtimeValue {
    public var uniqueKey: String { return dbKey }
}
extension LinkedRealtimeArray {
    convenience init(dbRef: DatabaseReference, elementsRef: DatabaseReference, keyPath: String, elementBuilder: ((Element.Type, DatabaseReference) -> Element)?) {
        self.init(dbRef: dbRef, elementsRef: elementsRef)
        self.keyPath = keyPath
        self.elementBuilder = elementBuilder
    }
    func by<KeyPathModel>(keyPath: String) -> LinkedRealtimeArray<KeyPathModel>
        where KeyPathModel: KeyedRealtimeValue, KeyPathModel.UniqueKey: StringRepresentableRealtimeArrayKey, KeyPathModel.UniqueKey == Element.UniqueKey {
        let byPath = LinkedRealtimeArray<KeyPathModel>(dbRef: dbRef, elementsRef: elementsRef, keyPath: keyPath, elementBuilder: nil)
        if isPrepared {
            byPath.isPrepared = true
            byPath.prototype.setLocalValue(prototype.value)
            byPath.prototype.didSave() // reset `hasChanges` to false
        }
        return byPath
    }
    func by<KeyPathModel>(keyPath: String, elements: DatabaseReference, elementBuilder: ((KeyPathModel.Type, DatabaseReference) -> KeyPathModel)?) -> LinkedRealtimeArray<KeyPathModel>
        where KeyPathModel: KeyedRealtimeValue, KeyPathModel.UniqueKey: StringRepresentableRealtimeArrayKey, KeyPathModel.UniqueKey == Element.UniqueKey {
            let byPath = LinkedRealtimeArray<KeyPathModel>(dbRef: dbRef, elementsRef: elements, keyPath: keyPath, elementBuilder: elementBuilder)
            if isPrepared {
                byPath.isPrepared = true
                byPath.prototype.setLocalValue(prototype.value)
                byPath.prototype.didSave() // reset `hasChanges` to false
            }
            return byPath
    }
}
extension LinkedRealtimeArray where Element: Linkable {
    // MARK: Mutating

    func write(to transaction: RealtimeTransaction, actions: ((Element, Int?) throws -> Void, (Int) -> Void) -> Void) {
        checkPreparation()

        let insert: (Element, Int?) throws -> Void = { element, index in
            guard !self.contains(element) else { throw RealtimeArrayError(type: .alreadyInserted) }

            let link = element.generate(linkTo: self.prototypeRef)
            let key = Key(entityId: element.uniqueKey, linkId: link.link.id, index: index ?? self.count)
            self.prototype.changeLocalValue { $0.insert(key, at: key.index) }
            element.add(link: link.link)
            transaction.addUpdate(item: (link.sourceRef, link.link.dbValue))

            transaction.addCompletion { (err) in
                if err == nil {
                    self.elements[key.key] = element
                    self.prototype.didSave()
                }
            }
        }
        var removedKeys: [Key] = []
        let remove: (Int) -> Void = { index in
            self.prototype.changeLocalValue { removedKeys.append($0.remove(at: index)) }
            transaction.addCompletion { (err) in
                if err == nil {
                    removedKeys.forEach { key in
                        self.elements.removeValue(forKey: key.key)?.remove(linkBy: key.linkId)
                    }
                }
            }
        }

        actions(insert, remove)
        removedKeys.forEach { transaction.addUpdate(item: (valueRefBy(key: $0.dbKey).child(Nodes.links.subpath(with: $0.linkId)), nil)) }
        transaction.addUpdate(item: (prototype.dbRef, prototype.localValue))
    }

    func insert(element: Element, at index: Int? = nil, completion: Database.TransactionCompletion?) {
        checkPreparation()
        guard !contains(element) else { completion?(RealtimeArrayError(type: .alreadyInserted), elementsRef); return }

        let link = element.generate(linkTo: prototypeRef)
        let key = Key(entityId: element.uniqueKey, linkId: link.link.id, index: index ?? count)
        prototype.changeLocalValue { $0.insert(key, at: key.index) }
        prototype.save(with: [(link.sourceRef, link.link.dbValue)]) { (err, ref) in
            if err == nil {
                element.add(link: link.link)
                self.elements[key.key] = element
                self.prototype.didSave()
            }
            completion?(err, ref)
        }
    }
    
    func remove(element: Element, completion: Database.TransactionCompletion?) {
        if let index = prototype.value.index(where: { $0.entityId == element.uniqueKey }) {
            remove(at: index, completion: completion)
        }
    }
    
    func remove(at index: Int, completion: Database.TransactionCompletion?) {
        checkPreparation()

        var key: Key!
        prototype.changeLocalValue { key = $0.remove(at: index) }
        prototype.save(with: [(valueRefBy(key: key.dbKey).child(Nodes.links.subpath(with: key.linkId)), nil)]) { (err, ref) in
            if err == nil {
                self.prototype.didSave()
                self.elements.removeValue(forKey: key.key)?.remove(linkBy: key.linkId)
            }
            
            completion?(err, ref)
        }
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

private class _AnyRealtimeCollectionBase<Elem, StoreKey: StringRepresentableRealtimeArrayKey, StoreValue>: Collection {
    typealias Element = Elem
    var dbRef: DatabaseReference { fatalError() }
    var isPrepared: Bool { fatalError() }
    var localValue: Any? { fatalError() }
    func makeIterator() -> AnyIterator<Element> { fatalError() }
    var startIndex: Int { fatalError() }
    var endIndex: Int { fatalError() }
    func index(after i: Int) -> Int { fatalError() }
    subscript(position: Int) -> Element { fatalError() }
    func apply(snapshot: DataSnapshot, strongly: Bool) { fatalError() }
    func didSave() { fatalError() }
    func didRemove() { fatalError() }
    func makeKeysIterator() -> AnyIterator<StoreKey> { fatalError() }
    func key(by index: Int) -> StoreKey { fatalError() }
    func valueRefBy(key: String) -> DatabaseReference { fatalError() }
    func valueBy(ref reference: DatabaseReference) -> StoreValue { fatalError() }
//    func storedValue(by key: StoreKey) -> StoreValue? { fatalError() }
//    func store(value: StoreValue, by key: StoreKey) { fatalError() }
    func newValueRef() -> DatabaseReference { fatalError() }
    func prepare(forUse completion: @escaping (Error?) -> Void) { fatalError() }
    func runObserving() { fatalError() }
    func stopObserving() { fatalError() }
    func changesListening(completion: @escaping () -> Void) -> ListeningItem { fatalError() }
    required init?(snapshot: DataSnapshot) {  }
    required init(dbRef: DatabaseReference) {  }
    var debugDescription: String { return "" }
}

private final class __AnyRealtimeCollection<C: RealtimeCollection>: _AnyRealtimeCollectionBase<C.Iterator.Element, C.StoreKey, C.StoreValue>
where C.KeysIterator.Element == C.StoreKey, C.Index == Int {
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
    override var isPrepared: Bool { return base.isPrepared }
    override var localValue: Any? { return base.localValue }

    override func makeIterator() -> AnyIterator<C.Iterator.Element> { return AnyIterator(base.makeIterator()) }
    override var startIndex: Int { return base.startIndex }
    override var endIndex: Int { return base.endIndex }
    override func index(after i: Int) -> Int { return base.index(after: i) }
    override subscript(position: Int) -> C.Iterator.Element { return base[position] }

    override func apply(snapshot: DataSnapshot, strongly: Bool) { base.apply(snapshot: snapshot, strongly: strongly) }
    override func didSave() { base.didSave() }
    override func didRemove() { base.didRemove() }
    override func makeKeysIterator() -> AnyIterator<C.StoreKey> { return AnyIterator(base.makeKeysIterator()) }
    override func key(by index: Int) -> C.StoreKey { return base.key(by: index) }
    override func valueRefBy(key: String) -> DatabaseReference { return base.valueRefBy(key: key) }
    override func valueBy(ref reference: DatabaseReference) -> C.StoreValue { return base.valueBy(ref: reference) }
//    override func storedValue(by key: C.PrototypeKey) -> C.StoreValue? { return base.storedValue(by: key) }
//    override func store(value: C.StoreValue, by key: C.PrototypeKey) { base.store(value: value, by: key) }
    override func newValueRef() -> DatabaseReference { return base.newValueRef() }
    override func prepare(forUse completion: @escaping (Error?) -> Void) { base.prepare(forUse: completion) }
    override func changesListening(completion: @escaping () -> Void) -> ListeningItem { return base.changesListening(completion: completion) }
    override func runObserving() { base.runObserving() }
    override func stopObserving() { base.stopObserving() }
    override var debugDescription: String { return base.debugDescription }
}

//final class AnyRealtimeCollection<StoreKey: StringRepresentableRealtimeArrayKey, StoreValue>: RealtimeCollection {
//    private let base: _AnyRealtimeCollectionBase<StoreKey, StoreValue>
//    required init(base: C) {
//        self.base = base
//        super.init(dbRef: base.dbRef)
//    }
//
//    convenience required init?(snapshot: DataSnapshot) {
//        //        if let base = C(snapshot: snapshot) {
//        //            self.init(base: base)
//        //        }
//        fatalError()
//    }
//
//    convenience required init(dbRef: DatabaseReference) {
//        self.init(base: C(dbRef: dbRef))
//    }
//
//    override var dbRef: DatabaseReference { return base.dbRef }
//    override var isActive: Bool { return base.isActive }
//    override var localValue: Any? { return base.localValue }
//
//    override func makeIterator() -> C.Iterator { return base.makeIterator() }
//    override var startIndex: Int { return base.startIndex }
//    override var endIndex: Int { return base.endIndex }
//    override func index(after i: Int) -> Int { return base.index(after: i) }
//    override subscript(position: Int) -> C.Iterator.Element { return base[position] }
//
//    override func apply(snapshot: DataSnapshot, strongly: Bool) { base.apply(snapshot: snapshot, strongly: strongly) }
//    override func didSave() { base.didSave() }
//    override func didRemove() { base.didRemove() }
//    override func makeKeysIterator() -> AnyIterator<C.PrototypeKey> { return base.makeKeysIterator() }
//    override func key(by index: Int) -> C.PrototypeKey { return base.key(by: index) }
//    override func valueRefBy(key: String) -> DatabaseReference { return base.valueRefBy(key: key) }
//    override func valueBy(ref reference: DatabaseReference) -> C.StoreValue { return base.valueBy(ref: reference) }
//    override func storedValue(by key: C.PrototypeKey) -> C.StoreValue? { return base.storedValue(by: key) }
//    override func store(value: C.StoreValue, by key: C.PrototypeKey) { base.store(value: value, by: key) }
//    override func newValueRef() -> DatabaseReference { return base.newValueRef() }
//    override func loadPrototype(completion: Database.TransactionCompletion?) { base.loadPrototype(completion: completion) }
//    override func changesListening(completion: @escaping () -> Void) -> ListeningItem { return base.changesListening(completion: completion) }
//    override var debugDescription: String { return base.debugDescription }
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

extension RealtimeCollection where Self.Iterator.Element == Self.StoreValue, Self.Index == Int, Self.KeysIterator.Element == Self.StoreKey {
    func keyed<Element: KeyedRealtimeValue>(by node: RealtimeNode, elementBuilder: @escaping (DatabaseReference) -> Element = { .init(dbRef: $0) })
        -> KeyedRealtimeArray<Element, Self.StoreKey, Self.StoreValue> where Element.UniqueKey: StringRepresentableRealtimeArrayKey {
        return KeyedRealtimeArray(base: self, keyPath: node, elementBuilder: elementBuilder)
    }
}

// TODO: Create lazy flatMap collection with keyPath access

// TODO: Must be easier 
public final class KeyedRealtimeArray<Elem, StoreKey, BaseStoreValue>: RealtimeCollection
where Elem: KeyedRealtimeValue, Elem.UniqueKey: StringRepresentableRealtimeArrayKey, StoreKey: StringRepresentableRealtimeArrayKey {
    public typealias Element = Elem
    public typealias Index = Int
    let keyPath: RealtimeNode
    private let elementBuilder: (DatabaseReference) -> Elem
    private let base: _AnyRealtimeCollectionBase<BaseStoreValue, StoreKey, BaseStoreValue>
    private var elements: [String: Element] = [:]
    init<RC: RealtimeCollection>(base: RC, keyPath: RealtimeNode, elementBuilder: @escaping (DatabaseReference) -> Elem = { .init(dbRef: $0) })
        where RC.Iterator.Element == BaseStoreValue, RC.KeysIterator.Element == KeysIterator.Element, RC.StoreValue == BaseStoreValue, RC.StoreKey == StoreKey, RC.Index == Int {
        self.keyPath = keyPath
        self.base = __AnyRealtimeCollection(base: base)
        self.elementBuilder = elementBuilder
    }

    public var dbRef: DatabaseReference { return base.dbRef }
    public var isPrepared: Bool { get { return base.isPrepared } set {} }
    public var localValue: Any? { return base.localValue }

    public var startIndex: Index { return base.startIndex }
    public var endIndex: Index { return base.endIndex }
    public func index(after i: Index) -> Index { return base.index(after: i) }

    public func prepare(forUse completion: @escaping (Error?) -> Void) {
        base.prepare(forUse: completion)
    }
    public func changesListening(completion: @escaping () -> Void) -> ListeningItem {
        return base.changesListening(completion: completion)
    }
    public func runObserving() {
        base.runObserving()
    }
    public func stopObserving() {
        base.stopObserving()
    }

    public typealias StoreValue = Element
    public func makeKeysIterator() -> AnyIterator<StoreKey> {
        return base.makeKeysIterator()
    }
    public func key(by index: Int) -> StoreKey {
        return base.key(by: index)
    }
    public func newValueRef() -> DatabaseReference {
        return base.newValueRef()
    }
    public func valueRefBy(key: String) -> DatabaseReference {
        return base.valueRefBy(key: keyPath.path(from: key))
    }
    public func valueBy(ref reference: DatabaseReference) -> Element {
        return elementBuilder(reference)
    }

    public func storedValue(by key: StoreKey) -> Element? {
        return elements[key.dbKey]
    }
    public func store(value: Element, by key: StoreKey) {
        elements[key.dbKey] = value
    }
    public var debugDescription: String { return base.debugDescription }

    public convenience required init?(snapshot: DataSnapshot) {
        fatalError()
    }

    public required init(dbRef: DatabaseReference) {
        fatalError()
    }

    public func apply(snapshot: DataSnapshot, strongly: Bool) {
        base.apply(snapshot: snapshot, strongly: strongly)
    }

    public func didSave() {
        base.didSave()
    }

    public func didRemove() {
        base.didRemove()
    }
}

extension RealtimeCollection where Iterator.Element: RequiresPreparation {
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
