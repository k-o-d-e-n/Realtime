//
//  RealTimeObject.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 14/01/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation
import FirebaseDatabase

// TODO: Add caching mechanism, for reuse entities

public protocol DataSnapshotRepresented {
    init?(snapshot: DataSnapshot)
    func apply(snapshot: DataSnapshot, strongly: Bool)
}
public extension DataSnapshotRepresented {
    func apply(snapshot: DataSnapshot) {
        apply(snapshot: snapshot, strongly: true)
    }
}

// MARK: RealtimeValue

public protocol KeyedRealtimeValue: RealtimeValue, Hashable {
    associatedtype UniqueKey: Hashable, LosslessStringConvertible
    var uniqueKey: UniqueKey { get }
}
extension KeyedRealtimeValue {
    var uniqueKey: String { return dbKey }
}

public protocol RealtimeValue: RealtimeValueEvents, DataSnapshotRepresented, CustomDebugStringConvertible {
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
    var hashValue: Int { return dbKey.count }
    static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.dbRef.url == rhs.dbRef.url
    }
}
public protocol RealtimeValueEvents {
    func didSave()
    func didRemove()
}

// MARK: Extended Realtime Value

public protocol ChangeableRealtimeValue: RealtimeValue {
    var hasChanges: Bool { get }
}

public protocol ChangeableRealtimeEntity: ChangeableRealtimeValue {
    func insertChanges(to values: inout [String: Any?], keyed from: DatabaseReference)
    func insertChanges(to values: inout [Database.UpdateItem])
    func insertChanges(to transaction: RealtimeTransaction)
}
public extension ChangeableRealtimeEntity {
    func insertChanges(to values: inout [String: Any?]) { insertChanges(to: &values, keyed: dbRef) }
}
fileprivate extension ChangeableRealtimeEntity {
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
    @discardableResult func updateThoroughly(completion: Database.TransactionCompletion?) -> Self
    @discardableResult func update(with values: [Database.UpdateItem], completion: ((Error?, DatabaseReference) -> ())?) -> Self
    @discardableResult func update(with values: [String: Any?], completion: ((Error?, DatabaseReference) -> ())?) -> Self
//    @discardableResult func fetch(completion: ((Self) -> ())?) -> Self // ? completion ?
//    @discardableResult func unlink(_ link: RealtimeLink, completion: ((Error?, DatabaseReference) -> Void)?) -> Self
//    @discardableResult func link(_ link: RealtimeLink, completion: ((Error?, DatabaseReference) -> Void)?) -> Self
}

public protocol RealtimeValueActions {
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

struct RemoteManager {
    static func save<T: RealtimeValue>(entity: T, completion: ((Error?, DatabaseReference) -> ())? = nil) {
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
    static func update<T: ChangeableRealtimeEntity>(entity: T, completion: ((Error?, DatabaseReference) -> ())? = nil) {
        var changes: [String: Any?] = [:]
        entity.insertChanges(to: &changes)
        entity.dbRef.update(use: changes) { (error, ref) in
            if error == nil { entity.didSave() }
            
            completion?(error, ref)
        }
    }
    
    static func update<T: ChangeableRealtimeEntity>(entity: T, with values: [String: Any?], completion: ((Error?, DatabaseReference) -> ())?) {
        let root = entity.dbRef.root
        var keyValuePairs = values
        entity.insertChanges(to: &keyValuePairs, keyed: root)
        root.update(use: keyValuePairs) { (err, ref) in
            if err == nil { entity.didSave() }
            
            completion?(err, ref)
        }
    }

    static func update<T: ChangeableRealtimeEntity>(entity: T, with values: [Database.UpdateItem], completion: ((Error?, DatabaseReference) -> ())?) {
        var refValuePairs = values
        entity.insertChanges(to: &refValuePairs)
        Database.database().update(use: refValuePairs) { (err, ref) in
            if err == nil { entity.didSave() }

            completion?(err, ref)
        }
    }

    static func updateThoroughly<T: ChangeableRealtimeEntity>(entity: T, completion: ((Error?, DatabaseReference) -> ())? = nil) {
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

    static func remove<T: RealtimeValue>(entity: T, completion: ((Error?, DatabaseReference) -> ())? = nil) {
        entity.dbRef.removeValue { (error, ref) in
            if error == nil { entity.didRemove() }
            
            completion?(error, ref)
        }
    }
    
    static func remove<T: RealtimeValue>(entity: T, with linkedRefs: [DatabaseReference], completion: Database.TransactionCompletion? = nil) {
        let references = linkedRefs + [entity.dbRef]
        Database.database().update(use: references.map { ($0, nil) }) { (err, ref) in
            if err == nil { entity.didRemove() }
            
            completion?(err, ref)
        }
    }
    
    static func loadData<Entity: RealtimeValue>(to entity: Entity, completion: Database.TransactionCompletion? = nil) {
        entity.dbRef.observeSingleEvent(of: .value, with: { entity.apply(snapshot: $0); completion?(nil, entity.dbRef) }, withCancel: { completion?($0, entity.dbRef) })
    }
    
    static func observe<T: RealtimeValue>(type: DataEventType = .value, entity: T, onUpdate: Database.TransactionCompletion? = nil) -> UInt {
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

// TODO: Create reset local changes method. Need save old value ??
open class _RealtimeValue: ChangeableRealtimeValue, RealtimeValueActions, KeyedRealtimeValue {
    open var uniqueKey: String { return dbKey }
    public let dbRef: DatabaseReference
    private var observingToken: UInt?
    public var localValue: Any? { return nil }
    public required init(dbRef: DatabaseReference) {
        self.dbRef = dbRef
    }

    deinit {
        observingToken.map(endObserve)
    }

    /// Warning! Save only local value, which it may be empty, that to make removing object, or him parts.
    @discardableResult
    public func save(completion: ((Error?, DatabaseReference) -> ())? = nil) -> Self {
        RemoteManager.save(entity: self, completion: completion)
        return self
    }

    @discardableResult
    public func save(with values: [Database.UpdateItem], completion: ((Error?, DatabaseReference) -> ())? = nil) -> Self {
        Database.database().update(use: values + [(dbRef, localValue)], completion: { err, ref in
            if err == nil { self.didSave() }

            completion?(err, ref)
        })
        return self
    }
    
    @discardableResult
    public func remove(completion: ((Error?, DatabaseReference) -> ())? = nil) -> Self {
        RemoteManager.remove(entity: self, completion: completion)
        
        return self
    }
    
    @discardableResult
    public func remove(with linkedRefs: [DatabaseReference], completion: Database.TransactionCompletion? = nil) -> Self {
        RemoteManager.remove(entity: self, with: linkedRefs, completion: completion)
        
        return self
    }
    
    @discardableResult
    public func load(completion: Database.TransactionCompletion?) -> Self {
        RemoteManager.loadData(to: self, completion: completion); return self
    }

    @discardableResult
    public func runObserving() -> Self {
        guard observingToken == nil else { return self }
        observingToken = observe(type: .value, onUpdate: nil); return self
    }

    @discardableResult
    public func stopObserving() -> Self {
        guard let token = observingToken else { return self }
        endObserve(for: token); return self
    }
    
    func observe(type: DataEventType = .value, onUpdate: Database.TransactionCompletion? = nil) -> UInt {
        return RemoteManager.observe(type: type, entity: self, onUpdate: onUpdate)
    }

    func endObserve(for token: UInt) {
        dbRef.removeObserver(withHandle: token);
    }

    public func didRemove() { }
    public func didSave() { }
    
    // MARK: Changeable
    
    public var hasChanges: Bool { return false }

    // MARK: Realtime Value

    public required init(snapshot: DataSnapshot) {
        dbRef = snapshot.ref
        apply(snapshot: snapshot)
    }
    
    open func apply(snapshot: DataSnapshot, strongly: Bool) {}
    
    public var debugDescription: String { return "\n{\n\tref: \(dbRef.pathFromRoot);\n\tvalue: \(String(describing: localValue));\n}" }
}

open class _RealtimeEntity: _RealtimeValue, ChangeableRealtimeEntity, RealtimeEntityActions {
    /// Warning! Values should be only on first level in hierarchy, else other data is lost.
    @discardableResult
    public func update(completion: ((Error?, DatabaseReference) -> ())? = nil) -> Self {
        //        guard hasChanges else { completion?(RemoteManager.RealtimeEntityError(type: .hasNotChanges), dbRef); return self }

        RemoteManager.update(entity: self, completion: completion)
        return self
    }

    @discardableResult
    public func updateThoroughly(completion: Database.TransactionCompletion?) -> Self {
        RemoteManager.updateThoroughly(entity: self, completion: completion)

        return self
    }

    @discardableResult
    public func update(with values: [Database.UpdateItem], completion: ((Error?, DatabaseReference) -> ())?) -> Self {
        RemoteManager.update(entity: self, with: values, completion: completion)

        return self
    }

    @discardableResult
    public func update(with values: [String : Any?], completion: ((Error?, DatabaseReference) -> ())?) -> Self {
        RemoteManager.update(entity: self, with: values, completion: completion)

        return self
    }
    public func insertChanges(to values: inout [String : Any?], keyed from: DatabaseReference) { fatalError("You should override this method " + #function) }
    public func insertChanges(to values: inout [Database.UpdateItem]) { fatalError("You should override this method " + #function) }
    public func insertChanges(to transaction: RealtimeTransaction) { fatalError("You should override this method " + #function) }
    override public var debugDescription: String { return "\n{\n\tref: \(dbRef.pathFromRoot);\n\tvalue: \(String(describing: localValue));\n\tchanges: \(String(describing: localChanges));\n}" }
}

// TODO: https://github.com/firebase/FirebaseUI-iOS
// TODO: Need learning NSManagedObject as example, and apply him patterns
// TODO: Try to create `parent` typed property.
// TODO: Make RealtimeObject (RealtimeValue) conformed Listenable for listening
open class RealtimeObject: _RealtimeEntity {
    public typealias ChangeableProperty = ChangeableRealtimeEntity
    public typealias Property = RealtimeValue
    fileprivate var _props = [Property]() // TODO: May be use Dictionary with RealtimeNode as key. `allKeys` -> childNodes
    fileprivate var _changeProps = [ChangeableProperty]()
    fileprivate var _allProps: [Property] { return _props + _changeProps }
    override public var hasChanges: Bool { return _changeProps.first { $0.hasChanges } != nil }
//    var localChanges: Any? { return keyedValues { return $0.localChanges } }
    override public var localValue: Any? { return keyedValues { return $0.localValue } }

    private lazy var modelVersion: StandartProperty<Int?> = self.register(prop: Nodes.modelVersion.property(from: self.dbRef))
    public typealias Links = RealtimeProperty<[RealtimeLink], RealtimeLinkArraySerializer>
    public lazy var links: Links = self.register(prop: Links(dbRef: Nodes.links.reference(from: self.dbRef))) // TODO: Requires downloading before using

//    lazy var parent: RealtimeObject? = self.dbRef.parent.map(RealtimeObject.init) // should be typed

    @discardableResult
    override public func updateThoroughly(completion: ((Error?, DatabaseReference) -> ())? = nil) -> Self {
        var changes = [String: Any?]()
        insertChanges(to: &changes, keyed: dbRef)
        if changes.count > 0 {
            dbRef.updateChildValues(changes as Any as! [String: Any]) { (error, ref) in
                if error == nil { self.didSave() }
                
                completion?(error, ref)
            }
        } else {
            completion?(RemoteManager.RealtimeEntityError(type: .hasNotChanges), dbRef)
        }
        
        return self
    }
    
    override public func didSave() {
        super.didSave()
        _props.forEach { $0.didSave() }
        _changeProps.forEach { $0.didSave() }
    }
    
    func willRemove(completion: @escaping (Error?, DatabaseReference) -> Void) {
        links.load(completion: completion)
    }
    
    override public func didRemove() {
        super.didRemove()
        _props.forEach { $0.didRemove() }
        _changeProps.forEach { $0.didRemove() }
    }
    
    @discardableResult
    override public func remove(completion: ((Error?, DatabaseReference) -> ())?) -> Self {
        willRemove { (error, ref) in
            guard error == nil else { completion?(error, ref); return }
            
            if self.links.value.isEmpty {
                super.remove(completion: completion)
            } else {
                self.remove(with: self.links.value.map { $0.dbRef }, completion: completion)
            }
        }
        
        return self
    }
    
    override open func apply(snapshot: DataSnapshot, strongly: Bool) {
        /// properties is lazy loaded because apply snapshot processed directly
//        properties.forEach { prop in
//            if snapshot.hasChild(prop.dbKey) { prop.apply(snapshot: snapshot.childSnapshot(forPath: prop.dbKey)) }
//        }
        if strongly || Nodes.modelVersion.has(in: snapshot) { modelVersion.apply(snapshot: Nodes.modelVersion.snapshot(from: snapshot)) }
        if strongly || Nodes.links.has(in: snapshot) { links.apply(snapshot: Nodes.links.snapshot(from: snapshot)) }
    }
    
    override public func insertChanges(to values: inout [String : Any?], keyed from: DatabaseReference) {
        _changeProps.forEach { prop in
            prop.insertChanges(to: &values, keyed: from)
        }
    }
    override public func insertChanges(to values: inout [Database.UpdateItem]) {
        _changeProps.forEach { $0.insertChanges(to: &values) }
    }
    override public func insertChanges(to transaction: RealtimeTransaction) {
        _changeProps.forEach { $0.insertChanges(to: transaction) }
    }

    // MARK: RealtimeObject
    
    // TODO: Link as callback for modelVersion property
    open func performMigration(from version: Int?) {
        // implement migration
    }
    
    public func register<T: ChangeableProperty>(prop: T, completion: ((T) -> Void)? = nil) -> T {
        _changeProps.append(prop)
        completion?(prop)
        
        return prop
    }
    public func register<T: Property>(prop: T, completion: ((T) -> Void)? = nil) -> T {
        _props.append(prop)
        completion?(prop)

        return prop
    }

    private func keyedValues(use maping: (RealtimeValue) -> Any?) -> [String: Any]? {
        var keyedValues: [String: Any]? = nil
        _allProps.forEach {
            if let value = maping($0) {
                if keyedValues == nil { keyedValues = [String: Any]() }
                
                keyedValues![$0.dbKey] = value
            }
        }
        
        return keyedValues
    }
    
    override public var debugDescription: String { return _allProps.reduce("\n{\n\tref: \(dbRef.pathFromRoot);") { $0 + "\n\"\($1.dbKey)\":" + $1.debugDescription } + "\n}" }
}

extension RealtimeObject: Linkable {
    public var linksRef: DatabaseReference { return links.dbRef }
    @discardableResult
    public func add(link: RealtimeLink) -> Self {
        links.changeLocalValue { (values) in
            guard !values.contains(where: { $0 == link }) else { return }
            
            values.append(link)
        }
        return self
    }
    @discardableResult
    public func remove(linkBy id: String) -> Self {
        links.changeLocalValue { (values) in
            guard let index = values.index(where: { $0.id == id }) else { return }
            
            values.remove(at: index)
        }
        return self
    }
}
public extension Linkable {
    func addLink(_ link: RealtimeLink, in transaction: RealtimeTransaction) {
        add(link: link)
        transaction.addUpdate(item: (linksRef.child(link.id), link.dbValue))
    }
    func removeLink(by id: String, in transaction: RealtimeTransaction) {
        remove(linkBy: id)
        transaction.addUpdate(item: (linksRef.child(id), nil))
    }
}

protocol RealtimeEntityClass: class, RealtimeValue {}
protocol ChangeableRealtimeEntityClass: RealtimeEntityClass, ChangeableRealtimeEntity {}

// TODO: Use Unmanaged wrapper instead
enum RealtimeRetainer {
    static fileprivate var retainer: [RealtimeEntityClass] = []
}
extension RealtimeEntityClass {
    func retain() {
        RealtimeRetainer.retainer.append(self)
    }
    
    func release() {
        RealtimeRetainer.retainer.remove(at: RealtimeRetainer.retainer.index { self === $0 }!)
    }
}
