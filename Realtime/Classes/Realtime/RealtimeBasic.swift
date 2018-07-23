//
//  RealtimeBasic.swift
//  Realtime
//
//  Created by Denis Koryttsev on 31/01/2018.
//

import Foundation
import FirebaseDatabase

struct RealtimeError: Error {
    let localizedDescription: String

    init(_ descr: String) {
        self.localizedDescription = descr
    }
}

internal let lazyStoragePath = ".storage"

public protocol FireDataProtocol {
    var value: Any? { get }
    var priority: Any? { get }
    var children: NSEnumerator { get }
    var dataKey: String? { get }
    var dataRef: DatabaseReference? { get }
    var childrenCount: UInt { get }
    func exists() -> Bool
    func hasChildren() -> Bool
    func hasChild(_ childPathString: String) -> Bool
    func child(forPath path: String) -> FireDataProtocol
}

extension DataSnapshot: FireDataProtocol {
    public var dataKey: String? {
        return key
    }

    public var dataRef: DatabaseReference? {
        return ref
    }

    public func child(forPath path: String) -> FireDataProtocol {
        return childSnapshot(forPath: path)
    }
}
extension MutableData: FireDataProtocol {
    public var dataKey: String? {
        return key
    }

    public var dataRef: DatabaseReference? {
        return nil
    }

    public func exists() -> Bool {
        return value != nil && !(value is NSNull)
    }

    public func child(forPath path: String) -> FireDataProtocol {
        return childData(byAppendingPath: path)
    }
    
    public func hasChild(_ childPathString: String) -> Bool {
        return hasChild(atPath: childPathString)
    }
}

// TODO: Avoid using three separated protocols

public protocol DataSnapshotRepresented {
    var payload: [String: Any]? { get }
    init?(snapshot: DataSnapshot)
}
extension DataSnapshotRepresented {
    public var payload: [String : Any]? { return nil }
}

public protocol MutableDataRepresented {
    var localValue: Any? { get }
    init(data: MutableData) throws
}

// TODO: I can make data wrapper struct, without create protocol or conformed protocol (avoid conformation DataSnapshot and MutableData)
public protocol FireDataRepresented {
    var localValue: Any? { get }
    init(fireData: FireDataProtocol) throws
}

public protocol DatabaseKeyRepresentable {
    var dbKey: String! { get }
}

// MARK: RealtimeValue

public struct RealtimeValueOption: Hashable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}
extension RealtimeValueOption {
    static var payload: RealtimeValueOption = RealtimeValueOption("realtime.value.payload")
}

/// Base protocol for all database entities
public protocol RealtimeValue: DatabaseKeyRepresentable, DataSnapshotRepresented {
    /// Node location in database
    var node: Node? { get }

    /// Designed initializer
    ///
    /// - Parameter node: Node location for value
    init(in node: Node?, options: [RealtimeValueOption: Any])
    /// Applies value of data snapshot
    ///
    /// - Parameters:
    ///   - snapshot: Snapshot value
    ///   - strongly: Indicates that snapshot should be applied as is (for example, empty values will be set to `nil`).
    ///               Pass `false` if snapshot represents part of data (for example filtered list).
    func apply(snapshot: DataSnapshot, strongly: Bool)

    /// Writes all local stored data to transaction as is. You shouldn't call it directly.
    ///
    /// - Parameters:
    ///   - transaction: Current transaction
    ///   - node: Database node where data will be store
    func write(to transaction: RealtimeTransaction, by node: Node)
}
public extension RealtimeValue {
    var dbRef: DatabaseReference? {
        return node.flatMap { $0.isRooted ? $0.reference : nil }
    }
    init(in node: Node?) { self.init(in: node, options: [:]) }
    init() { self.init(in: nil) }
}
extension HasDefaultLiteral where Self: RealtimeValue {}

public extension RealtimeValue {
    func apply(snapshot: DataSnapshot) {
        apply(snapshot: snapshot, strongly: true)
    }
    func apply(parentSnapshotIfNeeded parent: DataSnapshot, strongly: Bool) {
        guard strongly || dbKey.has(in: parent) else { return }

        apply(snapshot: dbKey.snapshot(from: parent), strongly: strongly)
    }
}
public extension RealtimeValue {
    var isInserted: Bool { return isRooted }
    var isStandalone: Bool { return !isRooted }
    var isReferred: Bool { return node?.parent != nil }
    var isRooted: Bool { return node?.isRooted ?? false }
}
public extension RealtimeValue {
    var dbKey: String! { return node!.key }

    init?(snapshot: DataSnapshot, strongly: Bool) {
        if strongly { self.init(snapshot: snapshot) }
        else {
            self.init(in: .from(snapshot))
            apply(snapshot: snapshot, strongly: false)
        }
    }
}
public extension Hashable where Self: RealtimeValue {
    var hashValue: Int { return dbKey.hashValue }
    static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.node == rhs.node
    }
}
public protocol RealtimeValueEvents {
    /// Must call always before save(update) action
    ///
    /// - Parameters:
    ///   - transaction: Save transaction
    ///   - parent: Parent node to save
    ///   - key: Location in parent node
    func willSave(in transaction: RealtimeTransaction, in parent: Node, by key: String)
    /// Notifies object that it has been saved in specified parent node
    ///
    /// - Parameter parent: Parent node
    /// - Parameter key: Location in parent node
    func didSave(in parent: Node, by key: String)
    /// Must call always before removing action
    ///
    /// - Parameters:
    ///   - transaction: Remove transaction
    ///   - ancestor: Ancestor where remove action called
    func willRemove(in transaction: RealtimeTransaction, from ancestor: Node)
    /// Notifies object that it has been removed from specified ancestor node
    ///
    /// - Parameter ancestor: Ancestor node
    func didRemove(from ancestor: Node)
}
extension RealtimeValueEvents where Self: RealtimeValue {
    func willSave(in transaction: RealtimeTransaction, in parent: Node) {
        guard let node = self.node else {
            return debugFatalError("Unkeyed value will be saved to undefined location in parent node: \(parent.rootPath)")
        }
        willSave(in: transaction, in: parent, by: node.key)
    }
    func didSave(in parent: Node) {
        if let node = self.node {
            didSave(in: parent, by: node.key)
        } else {
            debugFatalError("Unkeyed value has been saved to undefined location in parent node: \(parent.rootPath)")
        }
    }
    func didSave() {
        if let parent = node?.parent, let node = self.node {
            didSave(in: parent, by: node.key)
        } else {
            debugFatalError("Rootless value has been saved to undefined location")
        }
    }
    func willRemove(in transaction: RealtimeTransaction) {
        if let parent = node?.parent {
            willRemove(in: transaction, from: parent)
        } else {
            debugFatalError("Rootless value will be removed from itself location")
        }
    }
    func didRemove() {
        if let parent = node?.parent {
            didRemove(from: parent)
        } else {
            debugFatalError("Rootless value has been removed from itself location")
        }
    }
}

// MARK: Extended Realtime Value

public protocol ChangeableRealtimeValue: RealtimeValue {
    /// Indicates that value was changed
    var hasChanges: Bool { get }

    /// Writes all changes of value to passed transaction
    ///
    /// - Parameters:
    ///   - transaction: Current transaction
    ///   - node: Node for this value
    func writeChanges(to transaction: RealtimeTransaction, by node: Node)
}

public protocol RealtimeValueActions: RealtimeValueEvents {
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

// ------------------------------------------------------------------------

struct RemoteManager {
    static func loadData<Entity: RealtimeValue & RealtimeValueEvents>(to entity: Entity, completion: Assign<(error: Error?, ref: DatabaseReference)>? = nil) {
        guard let ref = entity.dbRef else {
            debugFatalError(condition: true, "Couldn`t get reference")
            completion?.assign((RealtimeError("Couldn`t get reference"), .root()))
            return
        }

        ref.observeSingleEvent(of: .value, with: { entity.apply(snapshot: $0); completion?.assign((nil, ref)) }, withCancel: { completion?.assign(($0, ref)) })
    }

    static func observe<T: RealtimeValue & RealtimeValueEvents>(type: DataEventType = .value, entity: T, onUpdate: Database.TransactionCompletion? = nil) -> UInt? {
        guard let ref = entity.dbRef else {
            debugFatalError(condition: true, "Couldn`t get reference")
            onUpdate?(RealtimeError("Couldn`t get reference"), .root())
            return nil
        }
        return ref.observe(type, with: { entity.apply(snapshot: $0); onUpdate?(nil, $0.ref) }, withCancel: { onUpdate?($0, ref) })
    }
}
