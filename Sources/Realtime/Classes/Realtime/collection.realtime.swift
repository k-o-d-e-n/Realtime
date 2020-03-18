//
//  RealtimeCollection.swift
//  Realtime
//
//  Created by Denis Koryttsev on 16/03/2018.
//

import Foundation

/// Post processing data event for any `RealtimeCollection`.
///
/// - initial: Event for start data
/// - updated: Any update event
public enum RCEvent {
    case initial // TODO: Rename to `value` or `full` or `reload`
    case updated(deleted: [Int], inserted: [Int], modified: [Int], moved: [(from: Int, to: Int)]) // may be [Int] replace to IndexSet?
}

/// -----------------------------------------

/// A type that makes possible to do someone actions related with collection
public protocol RealtimeCollectionActions {
    /// Single loading of value. Returns error if object hasn't rooted node.
    ///
    /// - Parameter completion: Closure that called on end loading or error
    func load(timeout: DispatchTimeInterval) -> RealtimeTask
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
public protocol RealtimeCollectionView: BidirectionalCollection, RealtimeCollectionActions {
    func contains(elementWith key: String, completion: @escaping (Bool, Error?) -> Void)
}
extension RealtimeCollectionView where Self: RealtimeCollection {
    public func contains(elementWith key: String, completion: @escaping (Bool, Error?) -> Void) {
        view.contains(elementWith: key, completion: completion)
    }
}

/// Defines way to explore data in collection
///
/// - view: Gets data through loading collection's view as single value
/// - viewByPages: Gets data through loading collection's view by pages.
/// **Warning**: Currently this option is not support live synchronization
public enum RCDataExplorer {
    case view(ascending: Bool)
    case viewByPages(control: PagingControl, size: UInt, ascending: Bool)
}

/// A type that represents Realtime database collection
public protocol RealtimeCollection: RandomAccessCollection, RealtimeValue, RealtimeCollectionActions {
    associatedtype View: RealtimeCollectionView
    /// Object that stores data of the view collection
    var view: View { get }
    /// Listenable that receives changes events
    var changes: AnyListenable<RCEvent> { get }
    /// Indicates that collection has actual collection view data
    var isSynced: Bool { get }
    /// Defines way to explore data of collection.
    ///
    /// **Warning**: Almost each change this property will be reset current view elements
    var dataExplorer: RCDataExplorer { get set }
}
extension RealtimeCollection {
    public var isObserved: Bool { return view.isObserved }
    public var canObserve: Bool { return view.canObserve }
    public var isAscending: Bool {
        switch dataExplorer {
        case .view(let ascending), .viewByPages(_, _, let ascending): return ascending
        }
    }

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
extension RealtimeCollection where Index == Int {
    public func mapCommitedUpdate(_ event: RCEvent) -> (deleted: [Int], inserted: [Element], modified: [Element], moved: [Element]) {
        switch event {
        case .initial: return ([], Array(self), [], [])
        case .updated(let deleted, let inserted, let modified, let moved):
            return (
                deleted,
                inserted.map({ self[$0] }),
                modified.map({ self[$0] }),
                moved.map({ self[$1] })
            )
        }
    }
}

public protocol WritableRealtimeCollection: RealtimeCollection, WritableRealtimeValue {
    func write(to transaction: Transaction, by node: Node) throws
}

public protocol MutableRealtimeCollection: RealtimeCollection {
    func write(_ element: Element, in transaction: Transaction) throws
    func write(_ element: Element) throws -> Transaction
    func erase(at index: Int, in transaction: Transaction)
    func erase(at index: Int) -> Transaction
}
