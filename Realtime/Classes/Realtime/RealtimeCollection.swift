//
//  RealtimeCollection.swift
//  Realtime
//
//  Created by Denis Koryttsev on 16/03/2018.
//

import Foundation

struct RealtimeArrayError: Error {
    enum Kind {
        case alreadyInserted
    }
    let type: Kind
}

/// -----------------------------------------

struct _PrototypeValue: Hashable, DatabaseKeyRepresentable {
    let dbKey: String!
    let linkId: String
    let index: Int

    var hashValue: Int {
        return dbKey.hashValue &- linkId.hashValue
    }

    static func ==(lhs: _PrototypeValue, rhs: _PrototypeValue) -> Bool {
        return lhs.dbKey == rhs.dbKey
    }
}
final class _PrototypeValueSerializer: _Serializer {
    class func deserialize(entity: DataSnapshot) -> [_PrototypeValue] {
        guard let keyes = entity.value as? [String: [String: Int]] else { return Entity() }

        return keyes
            .map { _PrototypeValue(dbKey: $0.key, linkId: $0.value.first!.key, index: $0.value.first!.value) }
            .sorted(by: { $0.index < $1.index })
    }

    class func serialize(entity: [_PrototypeValue]) -> Any? {
        return entity.reduce(Dictionary<String, Any>(), { (result, key) -> [String: Any] in
            var result = result
            result[key.dbKey] = [key.linkId: result.count]
            return result
        })
    }
}

public protocol RealtimeCollectionStorage {
    associatedtype Value
}
protocol RCStorage: RealtimeCollectionStorage {
    associatedtype Key: Hashable, DatabaseKeyRepresentable
    var sourceNode: Node { get }
    func storedValue(by key: Key) -> Value?
}
protocol MutableRCStorage: RCStorage {
    func buildElement(with key: String) -> Value
    mutating func store(value: Value, by key: Key)
}
extension MutableRCStorage {
    internal mutating func object(for key: Key) -> Value {
        guard let element = storedValue(by: key) else {
            let value = buildElement(with: key.dbKey)
            store(value: value, by: key)

            return value
        }

        return element
    }
}

public protocol RealtimeCollectionView {}
protocol RCView: RealtimeCollectionView, BidirectionalCollection, RequiresPreparation {}

public protocol RealtimeCollection: BidirectionalCollection, RealtimeValue, RequiresPreparation {
    associatedtype Storage: RealtimeCollectionStorage
    var storage: Storage { get }
    //    associatedtype View: RealtimeCollectionView
    var view: RealtimeCollectionView { get }

    func listening(changes handler: @escaping () -> Void) -> ListeningItem // TODO: Add current changes as parameter to handler
    func runObserving() -> Void
    func stopObserving() -> Void
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
    func checkPreparation() {
        guard isPrepared else { fatalError("Instance should be activated before performing this action.") }
    }
}

public extension RealtimeCollection where Iterator.Element: RequiresPreparation {
    func prepareRecursive(_ completion: @escaping (Error?) -> Void) {
        let current = self
        current.prepare { (err) in
            print(current.count, Iterator.Element.self)
            guard err == nil else { completion(err); return }

            var lastErr: Error?
            let group = DispatchGroup()

            current.indices.forEach { _ in group.enter() }
            current.forEach { element in
                element.prepareRecursive { (e) in
                    lastErr = e
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                completion(lastErr)
            }
        }
    }
}

func prepareElementsRecursive<RC: Collection>(_ collection: RC, completion: @escaping (Error?) -> Void) {
    var lastErr: Error? = nil
    let group = DispatchGroup()

    collection.indices.forEach { _ in group.enter() }
    collection.forEach { element in
        if let prepared = (element as? RequiresPreparation) {
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

public struct RCArrayStorage<V>: MutableRCStorage where V: RealtimeValue {
    public typealias Value = V
    let sourceNode: Node
    let elementBuilder: (Node) -> Value
    var elements: [_PrototypeValue: Value] = [:]

    mutating func store(value: Value, by key: _PrototypeValue) { elements[for: key] = value }
    func storedValue(by key: _PrototypeValue) -> Value? { return elements[for: key] }

    func buildElement(with key: String) -> V {
        return elementBuilder(sourceNode.child(with: key))
    }
}

public struct AnyArrayStorage: RealtimeCollectionStorage {
    public typealias Value = Any
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

