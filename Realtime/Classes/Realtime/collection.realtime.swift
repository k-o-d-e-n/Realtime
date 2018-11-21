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

public typealias RealtimeValuePayload = (system: SystemPayload, user: [String: RealtimeDataValue]?)
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

public protocol RCViewElementProtocol: DatabaseKeyRepresentable, RealtimeDataRepresented, RealtimeDataValueRepresented {}

public protocol RCViewItem: Hashable, Comparable, RCViewElementProtocol {
    var payload: RealtimeValuePayload { get }
    associatedtype Element
    init(_ element: Element)
}

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

/// A type that stores an abstract elements, receives the notify about a change of collection
public protocol RealtimeCollectionView: BidirectionalCollection, RealtimeCollectionActions {}

/// A type that represents Realtime database collection
public protocol RealtimeCollection: BidirectionalCollection, RealtimeValue, RealtimeCollectionActions {
    associatedtype View: RealtimeCollectionView
    /// Object that stores data of the view collection
    var view: View { get }
    /// Listenable that receives changes events
    var changes: AnyListenable<RCEvent> { get }
    /// Indicates that collection has actual collection view data
    var isSynced: Bool { get }
}
extension RealtimeCollection {
    public var isObserved: Bool { return view.isObserved }
    public var canObserve: Bool { return view.canObserve }

    @discardableResult
    public func runObserving() -> Bool { return view.runObserving() }
    public func stopObserving() { view.stopObserving() }

    public var startIndex: View.Index { return view.startIndex }
    public var endIndex: View.Index { return view.endIndex }
    public func index(after i: View.Index) -> View.Index { return view.index(after: i) }
    public func index(before i: View.Index) -> View.Index { return view.index(before: i) }
}
extension RealtimeCollection where Element: DatabaseKeyRepresentable, View.Element: DatabaseKeyRepresentable {
    /// Returns a Boolean value indicating whether the sequence contains an
    /// element that has the same key.
    ///
    /// - Parameter element: The element to check for containment.
    /// - Returns: `true` if `element` is contained in the range; otherwise,
    ///   `false`.
    public func contains(_ element: Element) -> Bool {
        return view.contains { $0.dbKey == element.dbKey }
    }
}

public protocol WritableRealtimeCollection: RealtimeCollection, WritableRealtimeValue {
    func write(to transaction: Transaction, by node: Node) throws
}

public protocol MutableRealtimeCollection: RealtimeCollection {
    func write(_ element: Element, to transaction: Transaction) throws
    func write(_ element: Element) throws -> Transaction
    func erase(at index: Int, in transaction: Transaction)
    func erase(at index: Int) -> Transaction
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

