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
    var localValue: Any? { get }
    init?(snapshot: DataSnapshot)
}

public protocol MutableDataRepresented {
    var localValue: Any? { get }
    init(data: MutableData) throws
}

// TODO: I can make data wrapper struct, without create protocol or conformed protocol (avoid conformation DataSnapshot and MutableData)
public protocol FireDataRepresented {
    var localValue: Any? { get }
    init(firData: FireDataProtocol) throws
}

// MARK: RealtimeValue

public protocol DatabaseKeyRepresentable {
    var dbKey: String! { get }
}

/// Base protocol for all database entities
public protocol RealtimeValue: DatabaseKeyRepresentable, DataSnapshotRepresented {
//    var dbRef: DatabaseReference { get } // TODO: Use abstract protocol which has methods for observing and reference. Need for use DatabaseQuery
    var node: Node? { get }

    init(in node: Node?)
    /// Applies value of data snapshot
    ///
    /// - Parameters:
    ///   - snapshot: Snapshot value
    ///   - strongly: Indicates that snapshot should be applied as is (for example, empty values will be set to `nil`).
    ///               Pass `false` if snapshot represents part of data (for example filtered list).
    func apply(snapshot: DataSnapshot, strongly: Bool)
}
public extension RealtimeValue {
    var dbRef: DatabaseReference? {
        return node.flatMap { $0.isRooted ? $0.reference : nil }
    }
    init() { self.init(in: nil) }
}

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
    /// Notifies object that it has been saved in specified parent node
    ///
    /// - Parameter parent: Parent node
    /// - Parameter key: Location in parent node
    func didSave(in parent: Node, by key: String)
    /// Must call always before removing action
    ///
    /// - Parameter transaction: Current transaction
    func willRemove(in transaction: RealtimeTransaction)
    /// Notifies object that it has been removed from specified ancestor node
    ///
    /// - Parameter ancestor: Ancestor node
    func didRemove(from ancestor: Node)
}
extension RealtimeValueEvents where Self: RealtimeValue {
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
    var hasChanges: Bool { get }

    func insertChanges(to transaction: RealtimeTransaction, by node: Node)
}

public protocol RealtimeValueActions: RealtimeValueEvents {
    func load(completion: Assign<(error: Error?, ref: DatabaseReference)>?)
    @discardableResult func runObserving() -> Bool
    func stopObserving()
}

public protocol Linkable {
    @discardableResult func add(link: SourceLink) -> Self
    @discardableResult func remove(linkBy id: String) -> Self
    var linksNode: Node! { get }
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
