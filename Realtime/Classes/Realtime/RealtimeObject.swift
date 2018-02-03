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

    public func _remove(completion: ((Error?, DatabaseReference) -> ())? = nil) -> Self {
        RemoteManager.remove(entity: self, completion: completion)

        return self
    }
    
    @discardableResult
    public func remove(completion: ((Error?, DatabaseReference) -> ())? = nil) -> Self {
        willRemove { (err, linked) in
            guard err == nil else { completion?(err, self.dbRef); return }
            if let links = linked {
                RemoteManager.remove(entity: self, with: links, completion: completion)
            } else {
                RemoteManager.remove(entity: self, completion: completion)
            }
        }
        
        return self
    }
    
    @discardableResult
    public func remove(with linkedRefs: [DatabaseReference], completion: Database.TransactionCompletion? = nil) -> Self {
        willRemove { (err, linked) in
            guard err == nil else { completion?(err, self.dbRef); return }
            RemoteManager.remove(entity: self, with: linked.map { $0 + linkedRefs } ?? linkedRefs, completion: completion)
        }
        
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

    public func willRemove(completion: @escaping (Error?, [DatabaseReference]?) -> Void) { completion(nil, nil) }
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
    public typealias ChangeableEntity = ChangeableRealtimeEntity & RealtimeValueEvents
    public typealias ChangeableProperty = ChangeableRealtimeValue & RealtimeValueEvents
    public typealias Property = RealtimeValue & RealtimeValueEvents
    fileprivate var _props = [Property]() // TODO: May be use Dictionary with RealtimeNode as key. `allKeys` -> childNodes
    fileprivate var _changeProps = [ChangeableProperty]()
    fileprivate var _changeEntities = [ChangeableEntity]()
    fileprivate var _allProps: [Property] {
        let props: [Property] = _props + _changeProps
        return props + _changeEntities
    }
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
        _allProps.forEach { $0.didSave() }
    }
    
    override public func willRemove(completion: @escaping (Error?, [DatabaseReference]?) -> Void) {
        links.load(completion: { err, _ in completion(err, err.map { _ in self.links.value.map { $0.dbRef } }) })
    }
    
    override public func didRemove() {
        super.didRemove()
        _props.forEach { $0.didRemove() }
        _changeProps.forEach { $0.didRemove() }
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
        _changeEntities.forEach { prop in
            prop.insertChanges(to: &values, keyed: from)
        }
    }
    override public func insertChanges(to values: inout [Database.UpdateItem]) {
        _changeProps.forEach { $0.insertChanges(to: &values) }
        _changeEntities.forEach { $0.insertChanges(to: &values) }
    }
    override public func insertChanges(to transaction: RealtimeTransaction) {
        _changeProps.forEach { $0.insertChanges(to: transaction) }
        _changeEntities.forEach { $0.insertChanges(to: transaction) }
    }

    // MARK: RealtimeObject
    
    // TODO: Link as callback for modelVersion property
    open func performMigration(from version: Int?) {
        // implement migration
    }

    public func register<T: ChangeableEntity>(prop: T, completion: ((T) -> Void)? = nil) -> T {
        _changeEntities.append(prop)
        completion?(prop)

        return prop
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
