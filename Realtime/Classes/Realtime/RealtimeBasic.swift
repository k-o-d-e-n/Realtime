//
//  RealtimeBasic.swift
//  Realtime
//
//  Created by Denis Koryttsev on 31/01/2018.
//

import Foundation
import FirebaseDatabase

internal let lazyStoragePath = ".storage"

public protocol DataSnapshotProtocol {
    var value: Any? { get }
    var priority: Any? { get }
    var children: NSEnumerator { get }
//    var key: String? { get }
//    var ref: DatabaseReference? { get }
    var childrenCount: UInt { get }
    func exists() -> Bool
    func hasChildren() -> Bool
    func hasChild(_ childPathString: String) -> Bool
    func child(forPath path: String) -> DataSnapshotProtocol
}

extension DataSnapshot: DataSnapshotProtocol {
    public func child(forPath path: String) -> DataSnapshotProtocol {
        return childSnapshot(forPath: path)
    }
}
extension MutableData: DataSnapshotProtocol {
    public func exists() -> Bool {
        return value != nil && !(value is NSNull)
    }

    public func child(forPath path: String) -> DataSnapshotProtocol {
        return childData(byAppendingPath: path)
    }
    
    public func hasChild(_ childPathString: String) -> Bool {
        return hasChild(atPath: childPathString)
    }
}

public protocol DataSnapshotRepresented {
    var localValue: Any? { get }
    init?(snapshot: DataSnapshot)
}

public protocol MutableDataRepresented {
    var localValue: Any? { get }
    init(data: MutableData) throws
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
            self.init(in: Node.root.child(with: snapshot.ref.rootPath))
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
    func didSave(in parent: Node)
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
    func didSave() {
        if let parent = node?.parent {
            didSave(in: parent)
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

    func insertChanges(to transaction: RealtimeTransaction, to parentNode: Node?)
}

public protocol RealtimeValueActions: RealtimeValueEvents {
    @discardableResult func save(completion: ((Error?, DatabaseReference) -> ())?) -> Self
    @discardableResult func save(with values: [Database.UpdateItem], completion: ((Error?, DatabaseReference) -> ())?) -> Self
    @discardableResult func remove(completion: ((Error?, DatabaseReference) -> ())?) -> Self
    @discardableResult func remove(with linkedRefs: [DatabaseReference], completion: Database.TransactionCompletion?) -> Self
    @discardableResult func load(completion: Database.TransactionCompletion?) -> Self
    @discardableResult func runObserving() -> Bool
    func stopObserving()
}

public protocol RealtimeEntityActions: RealtimeValueActions {
    @discardableResult func update(completion: ((Error?, DatabaseReference) -> ())?) -> Self
    /// Updated only values, which changed on any level down in hierarchy.
    @discardableResult func merge(completion: Database.TransactionCompletion?) -> Self
    @discardableResult func update(with values: [Database.UpdateItem], completion: ((Error?, DatabaseReference) -> ())?) -> Self
    @discardableResult func update(with values: [String: Any?], completion: ((Error?, DatabaseReference) -> ())?) -> Self
}

public protocol Linkable {
    @discardableResult func add(link: SourceLink) -> Self
    @discardableResult func remove(linkBy id: String) -> Self
    var linksRef: DatabaseReference! { get }
}

// ------------------------------------------------------------------------

struct RemoteManager {
    static func save<T: RealtimeValue & RealtimeValueEvents>(entity: T, completion: ((Error?, DatabaseReference) -> ())? = nil) {
        guard let value = entity.localValue else {
            completion?(RealtimeEntityError(type: .valueDoesNotExists), entity.dbRef!)
            return
        }

        entity.dbRef!.setValue(value) { (error, ref) in
            if error == nil { entity.didSave(in: entity.node!) }

            completion?(error, ref)
        }
    }

    /// Warning! Values should be only on first level in hierarchy, else other data is lost.
    static func update<T: ChangeableRealtimeValue & RealtimeValueEvents>(entity: T, completion: ((Error?, DatabaseReference) -> ())? = nil) {
        fatalError()
//        var changes: [String: Any?] = [:]
//        entity.insertChanges(to: &changes)
//        entity.dbRef!.update(use: changes) { (error, ref) in
//            if error == nil { entity.didSave() }
//
//            completion?(error, ref)
//        }
    }

    static func update<T: ChangeableRealtimeValue & RealtimeValueEvents>(entity: T, with values: [String: Any?], completion: ((Error?, DatabaseReference) -> ())?) {
//        let root = entity.dbRef!.root
//        var keyValuePairs = values
        fatalError()
//        entity.insertChanges(to: &keyValuePairs, keyed: root)
//        root.update(use: keyValuePairs) { (err, ref) in
//            if err == nil { entity.didSave() }
//
//            completion?(err, ref)
//        }
    }

    static func update<T: ChangeableRealtimeValue & RealtimeValueEvents>(entity: T, with values: [Database.UpdateItem], completion: ((Error?, DatabaseReference) -> ())?) {
//        var refValuePairs = values
        fatalError()
//        entity.insertChanges(to: &refValuePairs)
//        Database.database().update(use: refValuePairs) { (err, ref) in
//            if err == nil { entity.didSave() }
//
//            completion?(err, ref)
//        }
    }

    static func merge<T: ChangeableRealtimeValue & RealtimeValueEvents>(entity: T, completion: ((Error?, DatabaseReference) -> ())? = nil) {
//        var changes = [String: Any?]()
        fatalError()
//        entity.insertChanges(to: &changes, keyed: entity.dbRef)
//        if changes.count > 0 {
//            entity.dbRef.updateChildValues(changes as Any as! [String: Any]) { (error, ref) in
//                if error == nil { entity.didSave() }
//
//                completion?(error, ref)
//            }
//        } else {
//            completion?(RemoteManager.RealtimeEntityError(type: .hasNotChanges), entity.dbRef)
//        }
    }

    static func remove<T: RealtimeValue & RealtimeValueEvents>(entity: T, completion: ((Error?, DatabaseReference) -> ())? = nil) {
        entity.dbRef!.removeValue { (error, ref) in
            if error == nil { entity.didRemove(from: entity.node!) }

            completion?(error, ref)
        }
    }

    static func remove<T: RealtimeValue & RealtimeValueEvents>(entity: T, with linkedRefs: [DatabaseReference], completion: Database.TransactionCompletion? = nil) {
        let references = linkedRefs + [entity.dbRef!]
        Database.database().update(use: references.map { ($0, nil) }) { (err, ref) in
            if err == nil { entity.didRemove(from: entity.node!) }

            completion?(err, ref)
        }
    }

    static func loadData<Entity: RealtimeValue & RealtimeValueEvents>(to entity: Entity, completion: Database.TransactionCompletion? = nil) {
        entity.dbRef!.observeSingleEvent(of: .value, with: { entity.apply(snapshot: $0); completion?(nil, entity.dbRef!) }, withCancel: { completion?($0, entity.dbRef!) })
    }

    static func observe<T: RealtimeValue & RealtimeValueEvents>(type: DataEventType = .value, entity: T, onUpdate: Database.TransactionCompletion? = nil) -> UInt {
        return entity.dbRef!.observe(type, with: { entity.apply(snapshot: $0); onUpdate?(nil, $0.ref) }, withCancel: { onUpdate?($0, entity.dbRef!) })
    }

    // TODO: Create warning type together with error.
    /// Warning like as signal about specials events happened on execute operation, but it is not failed.
    struct RealtimeEntityError: Error {
        enum ErrorKind {
            case hasNotChanges
            case valueDoesNotExists
        }
        let type: ErrorKind
    }
}
