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
}

/// -----------------------------------------

// TODO: For Value of AssociatedValues is not defined payloads
struct RCItem: Hashable, DatabaseKeyRepresentable, RealtimeDataRepresented, RealtimeDataValueRepresented {
    let dbKey: String!
    let linkID: String
    let index: Int
    let internalPayload: (mv: Int?, raw: RealtimeDataValue?)
    let payload: [String: RealtimeDataValue]?

    init<T: RealtimeValue>(element: T, key: String, linkID: String, index: Int) {
        self.dbKey = key
        self.linkID = linkID
        self.index = index
        self.payload = element.payload
        self.internalPayload = (element.version, element.raw)
    }

    init<T: RealtimeValue>(element: T, linkID: String, index: Int) {
        self.dbKey = element.dbKey
        self.linkID = linkID
        self.index = index
        self.payload = element.payload
        self.internalPayload = (element.version, element.raw)
    }

    init(data: RealtimeDataProtocol, exactly: Bool) throws {
        guard let key = data.node?.key else {
            throw RealtimeError(initialization: RCItem.self, data)
        }
        guard data.hasChildren() else { // TODO: For test, remove!
            guard let val = data.value as? [String: RealtimeDataValue],
                let value = val.first,
                let linkValue = value.value as? [String: Any],
                let index = linkValue[InternalKeys.index.rawValue] as? Int
            else {
                throw RealtimeError(initialization: RCItem.self, data)
            }

            self.dbKey = key
            self.linkID = value.key
            self.index = index
            self.payload = linkValue[InternalKeys.payload.rawValue] as? [String: RealtimeDataValue]
            self.internalPayload = (linkValue[InternalKeys.modelVersion.rawValue] as? Int, linkValue[InternalKeys.raw.rawValue] as? RealtimeDataValue)
            return
        }
        guard let value = data.makeIterator().next() else {
            throw RealtimeError(initialization: RCItem.self, data)
        }
        guard let linkID = value.node?.key else {
            throw RealtimeError(initialization: RCItem.self, data)
        }
        guard let index: Int = InternalKeys.index.map(from: value) else {
            throw RealtimeError(initialization: RCItem.self, data)
        }

        self.dbKey = key
        self.linkID = linkID
        self.index = index
        self.payload = InternalKeys.payload.map(from: value)
        self.internalPayload = (InternalKeys.modelVersion.map(from: data), InternalKeys.raw.map(from: data))
    }

    var rdbValue: RealtimeDataValue {
        var value: [String: RealtimeDataValue] = [:]
        let link: [String: RealtimeDataValue] = [InternalKeys.index.rawValue: index]
        value[linkID] = link
        if let mv = internalPayload.mv {
            value[InternalKeys.modelVersion.rawValue] = mv
        }
        if let raw = internalPayload.raw {
            value[InternalKeys.raw.rawValue] = raw
        }
        if let p = payload {
            value[InternalKeys.payload.rawValue] = p
        }

        return value
    }

    var hashValue: Int {
        return dbKey.hashValue &- linkID.hashValue
    }

    static func ==(lhs: RCItem, rhs: RCItem) -> Bool {
        return lhs.dbKey == rhs.dbKey
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
    func buildElement(with key: Key) -> Value
    mutating func store(value: Value, by key: Key)
}
extension MutableRCStorage {
    internal mutating func object(for key: Key) -> Value {
        guard let element = storedValue(by: key) else {
            let value = buildElement(with: key)
            store(value: value, by: key)

            return value
        }

        return element
    }
}

/// A type that stores an abstract elements, receives the notify about a change of collection
public protocol RealtimeCollectionView {}
protocol RCView: RealtimeCollectionView, BidirectionalCollection, RequiresPreparation {}

/// A type that makes possible to do someone actions related with collection
public protocol RealtimeCollectionActions {
    /// Single loading of value. Returns error if object hasn't rooted node.
    ///
    /// - Parameter completion: Closure that called on end loading or error
    func load(completion: Assign<Error?>?)
    /// Indicates that value can observe. It is true when object has rooted node, otherwise false.
    var canObserve: Bool { get }
    /// Runs observing value, if
    ///
    /// - Returns: True if running was successful or observing already run, otherwise false
    @discardableResult func runObserving() -> Bool
    /// Stops observing, if observers no more.
    func stopObserving()
}

public protocol RealtimeCollection: BidirectionalCollection, RealtimeValue, RealtimeCollectionActions, RequiresPreparation {
    associatedtype Storage: RealtimeCollectionStorage
    var storage: Storage { get }
    //    associatedtype View: RealtimeCollectionView
    var view: RealtimeCollectionView { get }

    func listening(changes handler: @escaping () -> Void) -> ListeningItem // TODO: Add current changes as parameter to handler
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

/// A type that does not ready to use after instance initialization,
/// or has limited using, because requires remote data.
public protocol RequiresPreparation {
    /// Indicates that instance is ready to use
    var isPrepared: Bool { get }
    /// Calls loading required data
    ///
    /// - Parameter completion: Callback on result of loading
    func prepare(forUse completion: Assign<(Error?)>)
    /// Calls loading required data recursivly
    ///
    /// If current type encapsulates some type conforms this protocol,
    /// call his preparation in this method.
    ///
    /// - Parameter completion: Callback on result of loading
    func prepareRecursive(forUse completion: @escaping (Error?) -> Void)
    /// Method that should call after successful preparation.
    func didPrepare()
}

public extension RequiresPreparation {
    func prepare(forUse completion: Assign<(collection: Self, error: Error?)>) {
        prepare(forUse: completion.map { (self, $0) })
    }
}
public extension RequiresPreparation where Self: RealtimeCollection {
    func prepareRecursive(forUse completion: @escaping (Error?) -> Void) {
        prepare(forUse: Assign<(Error?)>.just { (err) in
            guard err == nil else { completion(err); return }
            prepareElementsRecursive(self, completion: { completion($0) })
        })
    }
}
extension RequiresPreparation {
    func checkPreparation() {
        guard isPrepared else { fatalError("Instance should be prepared before performing this action.") }
    }
}

public extension RealtimeCollection where Iterator.Element: RequiresPreparation {
    func prepareRecursive(_ completion: @escaping (Error?) -> Void) {
        prepare(forUse: .just { (collection, err) in
            guard err == nil else { completion(err); return }

            var lastErr: Error?
            let group = DispatchGroup()

            collection.indices.forEach { _ in group.enter() }
            collection.forEach { element in
                element.prepareRecursive { (e) in
                    lastErr = e
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                completion(lastErr)
            }
        })
    }
}

func prepareElementsRecursive<RC: Collection>(_ collection: RC, completion: @escaping (Error?) -> Void) {
    var lastErr: Error? = nil
    let group = DispatchGroup()

    collection.indices.forEach { _ in group.enter() }
    collection.forEach { element in
        if case let prepared as RequiresPreparation = element {
            prepared.prepareRecursive { (err) in
                lastErr = err
                group.leave()
            }
        } else {
            group.leave()
        }
    }

    group.notify(queue: .main) {
        completion(lastErr)
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
            _ = value.once().listeningItem(onValue: <-{ (val) in
                released = current.index(after: released)
                guard predicate(val) else {
                    completeIfNeeded(released)
                    return
                }

                filteredElements.append(element)
                completeIfNeeded(released)
            })

            value.load(completion: nil)
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
        checkPreparation()

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
        return elementBuilder(sourceNode.child(with: key.dbKey), key.payload.map { [.payload: $0] } ?? [:])
    }
}

/// Type-erased Realtime collection storage
public struct AnyRCStorage: RealtimeCollectionStorage {
    public typealias Value = Any
}

final class AnyRealtimeCollectionView<Source, Viewed: RealtimeCollection & AnyObject>: RCView where Source: BidirectionalCollection, Source: HasDefaultLiteral {
    let source: Property<Source>
    weak var collection: Viewed?
    var listening: Disposable!

    var value: Source {
        return source.wrapped ?? Source()
    }

    internal(set) var isPrepared: Bool = false {
        didSet {
            if isPrepared, oldValue == false {
                didPrepare()
            }
        }
    }

    init(_ source: Property<Source>) {
        self.source = source
        self.listening = source
            .livetime(self)
            .filter { [unowned self] _ in !self.isPrepared }
            .listening(onValue: .guarded(self) { event, view in
                switch event {
                case .remote(_, exact: let s): view.isPrepared = s
                default: break
                }
            })
    }

    deinit {
        listening.dispose()
    }

    func prepare(forUse completion: Assign<(Error?)>) {
        guard !isPrepared else { completion.assign(nil); return }

        source.load(completion:
            completion.with(work: { err in
                self.isPrepared = err == nil
            })
        )
    }
    func prepareRecursive(forUse completion: @escaping (Error?) -> Void) {
        // TODO:
    }

    func didPrepare() {
        collection?.didPrepare()
    }

    var startIndex: Source.Index { return value.startIndex }
    var endIndex: Source.Index { return value.endIndex }
    func index(after i: Source.Index) -> Source.Index { return value.index(after: i) }
    func index(before i: Source.Index) -> Source.Index { return value.index(before: i) }
    subscript(position: Source.Index) -> Source.Element { return value[position] }
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
    @discardableResult
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

