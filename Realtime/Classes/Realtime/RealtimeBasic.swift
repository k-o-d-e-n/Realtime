//
//  RealtimeBasic.swift
//  Realtime
//
//  Created by Denis Koryttsev on 31/01/2018.
//

import Foundation
import FirebaseDatabase

public protocol DataSnapshotRepresented {
    init?(snapshot: DataSnapshot)
    /// Applies value of data snapshot
    ///
    /// - Parameters:
    ///   - snapshot: Snapshot value
    ///   - strongly: Indicates that snapshot should be applied as is
    func apply(snapshot: DataSnapshot, strongly: Bool) // TODO: `strongly` has bad defined target
}
public extension DataSnapshotRepresented {
    func apply(snapshot: DataSnapshot) {
        apply(snapshot: snapshot, strongly: true)
    }
}
public extension DataSnapshotRepresented where Self: RealtimeValue {
    func apply(parentSnapshotIfNeeded parent: DataSnapshot, strongly: Bool) {
        guard strongly || dbKey.has(in: parent) else { return }

        apply(snapshot: dbKey.snapshot(from: parent), strongly: strongly)
    }
}

// MARK: RealtimeValue

/// Database value that has unique key in itself space
public protocol KeyedRealtimeValue: RealtimeValue, Hashable {
    associatedtype UniqueKey: Hashable, LosslessStringConvertible
    var uniqueKey: UniqueKey { get }
}
extension KeyedRealtimeValue {
    var uniqueKey: String { return dbKey }
}

/// Base protocol for all database entities
public protocol RealtimeValue: DataSnapshotRepresented, CustomDebugStringConvertible {
    var dbRef: DatabaseReference { get } // TODO: Use abstract protocol which has methods for observing and reference. Need for use DatabaseQuery
    var localValue: Any? { get }

    init(dbRef: DatabaseReference)
}
public extension RealtimeValue {
    var dbKey: String { return dbRef.key }
    //    var prototype: [AnyHashable : Any]? { return !localValue == nil ? [dbKey: localValue!] : nil }

    init?(snapshot: DataSnapshot, strongly: Bool) {
        if strongly { self.init(snapshot: snapshot) }
        else {
            self.init(dbRef: snapshot.ref)
            apply(snapshot: snapshot, strongly: false)
        }
    }
}
public extension Hashable where Self: RealtimeValue {
    var hashValue: Int { return dbKey.hashValue }
    static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.dbRef.url == rhs.dbRef.url
    }
}
public protocol RealtimeValueEvents: class {
    func didSave()
    func willRemove(completion: @escaping (Error?, [DatabaseReference]?) -> Void)
    func didRemove()
}

// MARK: Extended Realtime Value

public protocol ChangeableRealtimeValue: RealtimeValue {
    var hasChanges: Bool { get }

    func insertChanges(to values: inout [String: Any?], keyed from: DatabaseReference)
    func insertChanges(to values: inout [Database.UpdateItem])
    func insertChanges(to transaction: RealtimeTransaction)
}
public extension ChangeableRealtimeValue {
    func insertChanges(to values: inout [String: Any?]) { insertChanges(to: &values, keyed: dbRef) }
}
extension ChangeableRealtimeValue {
    var localChanges: [String: Any?] { var changes: [String: Any?] = [:]; insertChanges(to: &changes); return changes }
}

//protocol RealtimeEntityStates {
//    var isInserted: Bool { get }
//    var isDeleted: Bool { get }
//    var isFault: Bool { get }
//}

public protocol RealtimeEntityActions: RealtimeValueActions {
    @discardableResult func update(completion: ((Error?, DatabaseReference) -> ())?) -> Self
    /// Updated only values, which changed on any level down in hierarchy.
    @discardableResult func merge(completion: Database.TransactionCompletion?) -> Self
    @discardableResult func update(with values: [Database.UpdateItem], completion: ((Error?, DatabaseReference) -> ())?) -> Self
    @discardableResult func update(with values: [String: Any?], completion: ((Error?, DatabaseReference) -> ())?) -> Self
    //    @discardableResult func fetch(completion: ((Self) -> ())?) -> Self // ? completion ?
    //    @discardableResult func unlink(_ link: RealtimeLink, completion: ((Error?, DatabaseReference) -> Void)?) -> Self
    //    @discardableResult func link(_ link: RealtimeLink, completion: ((Error?, DatabaseReference) -> Void)?) -> Self
}

public protocol RealtimeValueActions: RealtimeValueEvents {
    @discardableResult func save(completion: ((Error?, DatabaseReference) -> ())?) -> Self
    @discardableResult func save(with values: [Database.UpdateItem], completion: ((Error?, DatabaseReference) -> ())?) -> Self
    @discardableResult func remove(completion: ((Error?, DatabaseReference) -> ())?) -> Self
    @discardableResult func remove(with linkedRefs: [DatabaseReference], completion: Database.TransactionCompletion?) -> Self
    @discardableResult func load(completion: Database.TransactionCompletion?) -> Self
    @discardableResult func runObserving() -> Self
    @discardableResult func stopObserving() -> Self
}

public protocol Linkable {
    @discardableResult func add(link: RealtimeLink) -> Self
    @discardableResult func remove(linkBy id: String) -> Self
    var linksRef: DatabaseReference { get }
}

// ------------------------------------------------------------------------

struct RemoteManager {
    static func save<T: RealtimeValue & RealtimeValueEvents>(entity: T, completion: ((Error?, DatabaseReference) -> ())? = nil) {
        guard let value = entity.localValue else {
            completion?(RealtimeEntityError(type: .valueDoesNotExists), entity.dbRef)
            return
        }

        entity.dbRef.setValue(value) { (error, ref) in
            if error == nil { entity.didSave() }

            completion?(error, ref)
        }
    }

    /// Warning! Values should be only on first level in hierarchy, else other data is lost.
    static func update<T: ChangeableRealtimeValue & RealtimeValueEvents>(entity: T, completion: ((Error?, DatabaseReference) -> ())? = nil) {
        var changes: [String: Any?] = [:]
        entity.insertChanges(to: &changes)
        entity.dbRef.update(use: changes) { (error, ref) in
            if error == nil { entity.didSave() }

            completion?(error, ref)
        }
    }

    static func update<T: ChangeableRealtimeValue & RealtimeValueEvents>(entity: T, with values: [String: Any?], completion: ((Error?, DatabaseReference) -> ())?) {
        let root = entity.dbRef.root
        var keyValuePairs = values
        entity.insertChanges(to: &keyValuePairs, keyed: root)
        root.update(use: keyValuePairs) { (err, ref) in
            if err == nil { entity.didSave() }

            completion?(err, ref)
        }
    }

    static func update<T: ChangeableRealtimeValue & RealtimeValueEvents>(entity: T, with values: [Database.UpdateItem], completion: ((Error?, DatabaseReference) -> ())?) {
        var refValuePairs = values
        entity.insertChanges(to: &refValuePairs)
        Database.database().update(use: refValuePairs) { (err, ref) in
            if err == nil { entity.didSave() }

            completion?(err, ref)
        }
    }

    static func merge<T: ChangeableRealtimeValue & RealtimeValueEvents>(entity: T, completion: ((Error?, DatabaseReference) -> ())? = nil) {
        var changes = [String: Any?]()
        entity.insertChanges(to: &changes, keyed: entity.dbRef)
        if changes.count > 0 {
            entity.dbRef.updateChildValues(changes as Any as! [String: Any]) { (error, ref) in
                if error == nil { entity.didSave() }

                completion?(error, ref)
            }
        } else {
            completion?(RemoteManager.RealtimeEntityError(type: .hasNotChanges), entity.dbRef)
        }
    }

    static func remove<T: RealtimeValue & RealtimeValueEvents>(entity: T, completion: ((Error?, DatabaseReference) -> ())? = nil) {
        entity.dbRef.removeValue { (error, ref) in
            if error == nil { entity.didRemove() }

            completion?(error, ref)
        }
    }

    static func remove<T: RealtimeValue & RealtimeValueEvents>(entity: T, with linkedRefs: [DatabaseReference], completion: Database.TransactionCompletion? = nil) {
        let references = linkedRefs + [entity.dbRef]
        Database.database().update(use: references.map { ($0, nil) }) { (err, ref) in
            if err == nil { entity.didRemove() }

            completion?(err, ref)
        }
    }

    static func loadData<Entity: RealtimeValue & RealtimeValueEvents>(to entity: Entity, completion: Database.TransactionCompletion? = nil) {
        entity.dbRef.observeSingleEvent(of: .value, with: { entity.apply(snapshot: $0); completion?(nil, entity.dbRef) }, withCancel: { completion?($0, entity.dbRef) })
    }

    static func observe<T: RealtimeValue & RealtimeValueEvents>(type: DataEventType = .value, entity: T, onUpdate: Database.TransactionCompletion? = nil) -> UInt {
        return entity.dbRef.observe(type, with: { entity.apply(snapshot: $0); onUpdate?(nil, $0.ref) }, withCancel: { onUpdate?($0, entity.dbRef) })
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
