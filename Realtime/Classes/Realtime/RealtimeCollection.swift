//
//  RealtimeCollection.swift
//  Realtime
//
//  Created by Denis Koryttsev on 16/03/2018.
//

import Foundation

struct RCError: Error {
    enum Kind {
        case alreadyInserted
        case failedServerData
    }
    let type: Kind
}

/// -----------------------------------------

// TODO: May be need use format as: [__linkID: linkID, __i: index, __pl: [...]]
struct RCItem: Hashable, DatabaseKeyRepresentable, FireDataRepresented, FireDataValueRepresented {
    let dbKey: String!
    let linkID: String
    let index: Int
    let payload: [String: FireDataValue]?

    init(dbKey: String, linkID: String, index: Int, payload: [String: FireDataValue]? = nil) {
        self.dbKey = dbKey
        self.linkID = linkID
        self.index = index
        self.payload = payload
    }

    init(fireData: FireDataProtocol) throws {
        guard case let value as FireDataProtocol = fireData.children.nextObject() else {
            throw RCError(type: .failedServerData)
        }
        guard let index: Int = value.flatMap() ?? Nodes.index.map(from: value) else {
            throw RCError(type: .failedServerData)
        }

        self.dbKey = fireData.dataKey
        self.linkID = value.dataKey!
        self.index = index
        self.payload = Nodes.payload.map(from: value)
    }

    var fireValue: FireDataValue {
        var value: [String: FireDataValue] = [:]
        let link: [String: FireDataValue] = [Nodes.index.rawValue: index]
        value[linkID] = link
        if let p = payload {
            value[Nodes.payload.rawValue] = p
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

public protocol RealtimeCollectionView {}
protocol RCView: RealtimeCollectionView, BidirectionalCollection, RequiresPreparation {}

public protocol RealtimeCollectionActions {
    /// Single loading of value. Returns error if object hasn't rooted node.
    ///
    /// - Parameter completion: Closure that called on end loading or error
    func load(completion: Assign<(error: Error?, ref: DatabaseReference)>?)
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

/// MARK: RealtimeArray separated, new version

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

public protocol RequiresPreparation {
    var isPrepared: Bool { get }
    func prepare(forUse completion: Assign<(Error?)>)
    func prepareRecursive(forUse completion: @escaping (Error?) -> Void)
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

    func filtered<ValueGetter: InsiderOwner & ValueWrapper & RealtimeValueActions>(map values: @escaping (Iterator.Element) -> ValueGetter,
                                                                                   fetchIf: ((ValueGetter.V) -> Bool)? = nil,
                                                                                   predicate: @escaping (ValueGetter.V) -> Bool,
                                                                                   onCompleted: @escaping ([Iterator.Element]) -> ()) where ValueGetter.OutData == ValueGetter.V {
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

public struct RCArrayStorage<V>: MutableRCStorage where V: RealtimeValue {
    public typealias Value = V
    var sourceNode: Node!
    let elementBuilder: (Node, [String: Any]?) -> Value
    var elements: [String: Value] = [:]
    var localElements: [V] = []

    mutating func store(value: Value, by key: RCItem) { elements[for: key.dbKey] = value }
    func storedValue(by key: RCItem) -> Value? { return elements[for: key.dbKey] }

    func buildElement(with key: RCItem) -> V {
        return elementBuilder(sourceNode.child(with: key.dbKey), key.payload)
    }
}

public struct AnyArrayStorage: RealtimeCollectionStorage {
    public typealias Value = Any
}

public final class AnyRealtimeCollectionView<Source>: RCView where Source: BidirectionalCollection, Source: HasDefaultLiteral {
    let source: RealtimeProperty<Source>

    var value: Source {
        return source.value ?? Source()
    }

    public internal(set) var isPrepared: Bool = false

    init(_ source: RealtimeProperty<Source>) {
        self.source = source
    }

    public func prepare(forUse completion: Assign<(Error?)>) {
        guard !isPrepared else { completion.assign(nil); return }

        source.load(completion:
            completion
                .with(work: { (err) in
                    self.isPrepared = err == nil
                })
                .map({ $0.error })
        )
    }
    public func prepareRecursive(forUse completion: @escaping (Error?) -> Void) {
        // TODO:
    }

    public var startIndex: Source.Index { return value.startIndex }
    public var endIndex: Source.Index { return value.endIndex }
    public func index(after i: Source.Index) -> Source.Index { return value.index(after: i) }
    public func index(before i: Source.Index) -> Source.Index { return value.index(before: i) }
    public subscript(position: Source.Index) -> Source.Element { return value[position] }
}

extension AnyRealtimeCollectionView where Source == Array<RCItem> {
    func append(_ element: RCItem) {
        insert(element, at: count)
    }
    func insert(_ element: RCItem, at index: Int) {
        var value = self.value
        value.insert(element, at: index)
        source.value = value
    }
    func remove(at index: Int) -> RCItem {
        var value = self.value
        let removed = value.remove(at: index)
        source.value = value
        return removed
    }
}

