//
//  RealtimeCollection.swift
//  Realtime
//
//  Created by Denis Koryttsev on 16/03/2018.
//

import Foundation
import FirebaseDatabase

extension ValueOption {
    static let elementBuilder = ValueOption("realtime.collection.builder")
    static let keyBuilder = ValueOption("realtime.collection.keyBuilder")
}

public typealias Changes = (deleted: [Int], inserted: [Int], modified: [Int], moved: [(from: Int, to: Int)])
public enum RCEvent {
    case initial
    case updated(Changes)
}

/// -----------------------------------------

typealias RealtimeValuePayload = (system: SystemPayload, user: [String: RealtimeDataValue]?)
internal func databaseValue(of payload: RealtimeValuePayload) -> [String: RealtimeDataValue] {
    var val: [String: RealtimeDataValue] = [:]
    if let mv = payload.system.version {
        val[InternalKeys.modelVersion.rawValue] = mv
    }
    if let raw = payload.system.raw {
        val[InternalKeys.raw.rawValue] = raw
    }
    if let p = payload.user {
        val[InternalKeys.payload.rawValue] = p
    }
    return val
}

struct RCItem: Hashable, Comparable, DatabaseKeyRepresentable, RealtimeDataRepresented, RealtimeDataValueRepresented {
    let dbKey: String!
    var priority: Int
    var linkID: String?
    let payload: RealtimeValuePayload

    init<T: RealtimeValue>(element: T, key: String, priority: Int, linkID: String?) {
        self.dbKey = key
        self.priority = priority
        self.linkID = linkID
        self.payload = RealtimeValuePayload((element.version, element.raw), element.payload)
    }

    init<T: RealtimeValue>(element: T, priority: Int, linkID: String?) {
        self.dbKey = element.dbKey
        self.priority = priority
        self.linkID = linkID
        self.payload = RealtimeValuePayload((element.version, element.raw), element.payload)
    }

    init(data: RealtimeDataProtocol, exactly: Bool) throws {
        guard let key = data.key else {
            throw RealtimeError(initialization: RCItem.self, data)
        }
        guard let index: Int = try InternalKeys.index.map(from: data) else {
            throw RealtimeError(initialization: RCItem.self, data)
        }

        self.dbKey = key
        self.priority = index
        self.linkID = try InternalKeys.link.map(from: data)
        let valueData = InternalKeys.value.child(from: data)
        self.payload = RealtimeValuePayload(
            try (InternalKeys.modelVersion.map(from: valueData), InternalKeys.raw.map(from: valueData)),
            try InternalKeys.payload.map(from: valueData)
        )
    }

    var rdbValue: RealtimeDataValue {
        var value: [String: RealtimeDataValue] = [:]
        value[InternalKeys.value.rawValue] = databaseValue(of: payload)
        value[InternalKeys.link.rawValue] = linkID
        value[InternalKeys.index.rawValue] = priority

        return value
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(dbKey)
    }

    static func ==(lhs: RCItem, rhs: RCItem) -> Bool {
        return lhs.dbKey == rhs.dbKey
    }

    static func < (lhs: RCItem, rhs: RCItem) -> Bool {
        if lhs.priority < rhs.priority {
            return true
        } else if lhs.priority > rhs.priority {
            return false
        } else {
            return lhs.dbKey < rhs.dbKey
        }
    }
}

/// A type that stores collection values and responsible for lazy initialization elements
public protocol RealtimeCollectionStorage {
    associatedtype Value
}
protocol RCStorage: RealtimeCollectionStorage {
    associatedtype Key: Hashable, DatabaseKeyRepresentable
    var sourceNode: Node! { get }
    func storedValue(by key: Key) -> Value?
}
protocol MutableRCStorage: RCStorage {
    mutating func store(value: Value, by key: Key)
}

/// A type that stores an abstract elements, receives the notify about a change of collection
public protocol RealtimeCollectionView {}
protocol RCView: RealtimeCollectionView, BidirectionalCollection {}

/// A type that makes possible to do someone actions related with collection
public protocol RealtimeCollectionActions {
    /// Single loading of value. Returns error if object hasn't rooted node.
    ///
    /// - Parameter completion: Closure that called on end loading or error
    func load(timeout: DispatchTimeInterval, completion: Assign<Error?>?)
    /// Indicates that value can observe. It is true when object has rooted node, otherwise false.
    var canObserve: Bool { get }
    /// Enables/disables auto downloading of the data and keeping in sync
    var keepSynced: Bool { get set }
    /// Indicates that value already observed.
    var isObserved: Bool { get }
    /// Runs or keeps observing value.
    ///
    /// If observing already run, value remembers each next call of function
    /// as requirement to keep observing while is not called `stopObserving()`.
    /// The call of function must be balanced with `stopObserving()` function.
    ///
    /// - Returns: True if running was successful or observing already run, otherwise false
    @discardableResult func runObserving() -> Bool
    /// Stops observing, if observers no more, else decreases the observers counter.
    func stopObserving()
}

/// A type that represents Realtime database collection
public protocol RealtimeCollection: BidirectionalCollection, RealtimeValue, RealtimeCollectionActions {
    associatedtype Storage: RealtimeCollectionStorage
    /// Lazy local storage for elements
    var storage: Storage { get }
    /// Object that stores data of the view collection
    var view: RealtimeCollectionView { get }
    /// Listenable that receives changes events
    var changes: AnyListenable<RCEvent> { get }
    /// Indicates that collection has actual collection view data
    var isSynced: Bool { get }
}
protocol RC: RealtimeCollection, RealtimeValueEvents where Storage: RCStorage {
    associatedtype View: RCView
    var _view: View { get }
}

/// MARK: Values separated, new version

protocol KeyValueAccessableCollection {
    associatedtype Key
    associatedtype Value
    subscript(for key: Key) -> Value? { get set }
}

extension Array: KeyValueAccessableCollection {
    subscript(for key: Int) -> Element? {
        get { return self[key] }
        set { self[key] = newValue! }
    }
}
extension Dictionary: KeyValueAccessableCollection {
    subscript(for key: Key) -> Value? {
        get { return self[key] }
        set { self[key] = newValue }
    }
}

public extension RealtimeCollection {
    /// RealtimeCollection actions

    func filtered<ValueGetter: Listenable & RealtimeValueActions>(
        map values: @escaping (Iterator.Element) -> ValueGetter,
        predicate: @escaping (ValueGetter.Out) -> Bool,
        onCompleted: @escaping ([Iterator.Element]) -> ()
    ) {
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
            let listening = value.once().listening(onValue: <-{ (val) in
                released = current.index(after: released)
                guard predicate(val) else {
                    completeIfNeeded(released)
                    return
                }

                filteredElements.append(element)
                completeIfNeeded(released)
            })

            value.load(timeout: .seconds(10), completion: .just { err in
                listening.dispose()
            })
        }
    }
}
extension RealtimeCollection where Self: AnyObject, Element: RealtimeValue {
    public mutating func filtered<Node: RawRepresentable>(by value: Any, for node: Node, completion: @escaping ([Element], Error?) -> ()) where Node.RawValue == String {
        filtered(with: { $0.queryOrdered(byChild: node.rawValue).queryEqual(toValue: value) }, completion: completion)
    }

    public mutating func filtered(with query: (DatabaseReference) -> DatabaseQuery, completion: @escaping ([Element], Error?) -> ()) {
        guard let ref = node?.reference() else  {
            fatalError("Can`t get database reference")
        }

        var collection = self
        query(ref).observeSingleEvent(of: .value, with: { (data) in
            do {
                try collection.apply(data, exactly: false)
                completion(collection.filter { data.hasChild($0.dbKey) }, nil)
            } catch let e {
                completion(collection.filter { data.hasChild($0.dbKey) }, e)
            }
        }) { (error) in
            completion([], error)
        }
    }
}

public typealias RCElementBuilder<Element> = (Node, [ValueOption: Any]) -> Element
public struct RCArrayStorage<V>: MutableRCStorage where V: RealtimeValue {
    public typealias Value = V
    var sourceNode: Node!
    let elementBuilder: RCElementBuilder<V>
    var elements: [String: Value] = [:]

    mutating func store(value: Value, by key: RCItem) { elements[for: key.dbKey] = value }
    func storedValue(by key: RCItem) -> Value? { return elements[for: key.dbKey] }

    func buildElement(with key: RCItem) -> V {
        return elementBuilder(sourceNode.child(with: key.dbKey), [.systemPayload: key.payload.system,
                                                                  .userPayload: key.payload.user as Any])
    }

    internal mutating func object(for key: Key) -> Value {
        guard let element = storedValue(by: key) else {
            let value = buildElement(with: key)
            store(value: value, by: key)

            return value
        }

        return element
    }
}

/// Type-erased Realtime collection storage
public struct AnyRCStorage: RealtimeCollectionStorage {
    public typealias Value = Any
}

final class AnyRealtimeCollectionView<Source, Viewed: RealtimeCollection & AnyObject>: RCView where Source: BidirectionalCollection, Source: HasDefaultLiteral {
    let source: Property<Source>
    var value: Source {
        return source.wrapped ?? Source()
    }

    internal(set) var isSynced: Bool = false

    init(_ source: Property<Source>) {
        self.source = source
    }

    func load(_ completion: Assign<(Error?)>) {
        guard !isSynced else { completion.assign(nil); return }

        source.load(completion: completion)
    }

    func _contains(with key: String, completion: @escaping (Bool, Error?) -> Void) {
        guard let db = source.database, let node = source.node else {
            fatalError("Unexpected behavior")
        }
        db.load(
            for: node.child(with: key),
            timeout: .seconds(10),
            completion: { (data) in
                completion(data.exists(), nil)
        },
            onCancel: { completion(false, $0) }
        )
    }

    var startIndex: Source.Index { return value.startIndex }
    var endIndex: Source.Index { return value.endIndex }
    func index(after i: Source.Index) -> Source.Index { return value.index(after: i) }
    func index(before i: Source.Index) -> Source.Index { return value.index(before: i) }
    subscript(position: Source.Index) -> Source.Element { return value[position] }
}

extension AnyRealtimeCollectionView where Source == SortedArray<RCItem> {
    func insertRemote(_ element: RCItem) -> Int {
        var value = self.value
        let i = value.insert(element)
        source._setValue(.remote(value))
        return i
    }
    func removeRemote(_ element: RCItem) -> Int? {
        var value = self.value
        guard let i = value.index(where: { $0.dbKey == element.dbKey }) else { return nil }
        value.remove(at: i)
        source._setValue(.remote(value))
        return i
    }
    func moveRemote(_ element: RCItem) -> (from: Int, to: Int)? {
        if let from = value.index(where: { $0.dbKey == element.dbKey }) {
            var value = self.value
            value.remove(at: from)
            let to = value.insert(element)
            source._setValue(.remote(value))
            return (from, to)
        } else {
            debugFatalError("Cannot move element \(element), because it is not found")
            return nil
        }
    }

    func insertionIndex(for newElement: RCItem) -> Int {
        return value.insertionIndex(for: newElement)
    }
    
    func insert(_ element: RCItem) -> Int {
        var value = self.value
        let i = value.insert(element)
        source._setLocalValue(value)
        return i
    }
    func remove(at index: Int) -> RCItem {
        var value = self.value
        let removed = value.remove(at: index)
        source._setLocalValue(value)
        return removed
    }
    func removeAll() {
        source._setLocalValue([])
    }
}
extension AnyRealtimeCollectionView where Source.Element: RealtimeDataRepresented {
    func _item(for key: String, completion: @escaping (Source.Element?, Error?) -> Void) {
        guard let db = source.database, let node = source.node else {
            fatalError("Unexpected behavior")
        }
        db.load(
            for: node.child(with: key),
            timeout: .seconds(10),
            completion: { (data) in
                if data.exists() {
                    do {
                        completion(try Source.Element(data: data), nil)
                    } catch let e {
                        completion(nil, e)
                    }
                } else {
                    completion(nil, nil)
                }
        },
            onCancel: { completion(nil, $0) }
        )
    }
}

extension AnyRealtimeCollectionView where Source == SortedArray<RDItem> {
    func insertRemote(_ element: RDItem) -> Int {
        var value = self.value
        let i = value.insert(element)
        source._setValue(.remote(value))
        return i
    }
    func removeRemote(_ element: RDItem) -> Int? {
        var value = self.value
        guard let i = value.index(where: { $0.dbKey == element.dbKey }) else { return nil }
        value.remove(at: i)
        source._setValue(.remote(value))
        return i
    }
    func moveRemote(_ element: RDItem) -> (from: Int, to: Int)? {
        if let from = value.index(where: { $0.dbKey == element.dbKey }) {
            var value = self.value
            value.remove(at: from)
            let to = value.insert(element)
            source._setValue(.remote(value))
            return (from, to)
        } else {
            debugFatalError("Cannot move element \(element), because it is not found")
            return nil
        }
    }

    func insertionIndex(for newElement: RDItem) -> Int {
        return value.insertionIndex(for: newElement)
    }

    func insert(_ element: RDItem) -> Int {
        var value = self.value
        let i = value.insert(element)
        source._setLocalValue(value)
        return i
    }
    func remove(at index: Int) -> RDItem {
        var value = self.value
        let removed = value.remove(at: index)
        source._setLocalValue(value)
        return removed
    }
    func removeAll() {
        source._setLocalValue([])
    }
}

extension AnyRealtimeCollectionView where Source == Array<RCItem> {
    func append(_ element: RCItem) {
        insert(element, at: count)
    }
    func insert(_ element: RCItem, at index: Int) {
        var value = self.value
        value.insert(element, at: index)
        source._setLocalValue(value)
    }
    func insertRemote(_ element: RCItem, at index: Int) {
        var value = self.value
        value.insert(element, at: index)
        source._setValue(.remote(value))
    }
    func moveRemote(_ element: RCItem) -> Int? {
        if let index = value.index(where: { $0.dbKey == element.dbKey }) {
            var value = self.value
            value.remove(at: index)
            value.insert(element, at: element.priority)
            source._setValue(.remote(value))
            return index
        } else {
            debugFatalError("Cannot move element \(element), because it is not found")
            return nil
        }
    }
    func remove(at index: Int) -> RCItem {
        var value = self.value
        let removed = value.remove(at: index)
        source._setLocalValue(value)
        return removed
    }
    func removeRemote(_ item: RCItem) -> Int? {
        var value = self.value
        guard let i = value.index(of: item) else { return nil }
        value.remove(at: i)
        source._setValue(.remote(value))
        return i
    }
    func removeAll() {
        source._setLocalValue([])
    }
}

