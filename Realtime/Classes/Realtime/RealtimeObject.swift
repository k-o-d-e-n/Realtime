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

    public func remove(completion: ((Error?, DatabaseReference) -> ())?) -> Self {
        return remove(with: [], completion: completion)
    }
    
    @discardableResult
    public func remove(with linkedRefs: [DatabaseReference], completion: Database.TransactionCompletion? = nil) -> Self {
        willRemove { (err, removeRefs) in
            guard err == nil else { completion?(err, self.dbRef); return }
            let removes = removeRefs.map { $0 + linkedRefs } ?? linkedRefs
            if !removes.isEmpty {
                RemoteManager.remove(entity: self, with: removes, completion: completion)
            } else {
                RemoteManager.remove(entity: self, completion: completion)
            }
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
    public func didRemove() { dbRef.removeAllObservers() }
    public func didSave() { }
    
    // MARK: Changeable
    
    public var hasChanges: Bool { return false }

    // MARK: Realtime Value

    public required init(snapshot: DataSnapshot) {
        dbRef = snapshot.ref
        apply(snapshot: snapshot)
    }
    
    open func apply(snapshot: DataSnapshot, strongly: Bool) {}

    public func insertChanges(to values: inout [String: Any?], keyed from: DatabaseReference) {
        if hasChanges {
            values[dbRef.path(from: from)] = localValue
        }
    }
    public func insertChanges(to values: inout [Database.UpdateItem]) {
        if hasChanges {
            values.append((dbRef, localValue))
        }
    }
    public func insertChanges(to transaction: RealtimeTransaction) {
        if hasChanges {
            transaction.addNode(item: (dbRef, .value(localValue)))
        }
    }
    
    public var debugDescription: String { return "\n{\n\tref: \(dbRef.pathFromRoot);\n\tvalue: \(String(describing: localValue));\n}" }
}

open class _RealtimeEntity: _RealtimeValue, RealtimeEntityActions {
    /// Warning! Values should be only on first level in hierarchy, else other data is lost.
    @discardableResult
    public func update(completion: ((Error?, DatabaseReference) -> ())? = nil) -> Self {
        //        guard hasChanges else { completion?(RemoteManager.RealtimeEntityError(type: .hasNotChanges), dbRef); return self }

        RemoteManager.update(entity: self, completion: completion)
        return self
    }

    @discardableResult
    public func merge(completion: Database.TransactionCompletion?) -> Self {
        RemoteManager.merge(entity: self, completion: completion)

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
    override public var debugDescription: String { return "\n{\n\tref: \(dbRef.pathFromRoot);\n\tvalue: \(String(describing: localValue));\n\tchanges: \(String(describing: localChanges));\n}" }
}

// TODO: https://github.com/firebase/FirebaseUI-iOS
// TODO: Need learning NSManagedObject as example, and apply him patterns
// TODO: Try to create `parent` typed property.
// TODO: Make RealtimeObject (RealtimeValue) conformed Listenable for listening
open class RealtimeObject: _RealtimeEntity {//, Codable {
    override public var hasChanges: Bool { return containChild(where: { (_, val: ChangeableRealtimeValue) in return val.hasChanges }) }
//    var localChanges: Any? { return keyedValues { return $0.localChanges } }
    override public var localValue: Any? { return keyedValues { return $0.localValue } }

    private lazy var __mv: StandartProperty<Int?> = Nodes.modelVersion.property(from: self.dbRef)
    public typealias Links = RealtimeProperty<[RealtimeLink], RealtimeLinkArraySerializer>
    public lazy var __links: Links = Nodes.links.property(from: self.dbRef) // TODO: Requires downloading before using

//    lazy var parent: RealtimeObject? = self.dbRef.parent.map(RealtimeObject.init) // should be typed

//    enum CodingKeys: String, CodingKey {
//        case __mv, __links
//    }
//
//    public required init(from decoder: Decoder) throws {
//        super.init(dbRef: decoder.userInfo[CodingUserInfoKey(rawValue: "ref")!] as! DatabaseReference)
//        let container = try decoder.container(keyedBy: CodingKeys.self)
//        if let mv = try container.decodeIfPresent(Int?.self, forKey: .__mv) {
//            __mv <= mv
//        }
//        if let links = try container.decodeIfPresent([RealtimeLink].self, forKey: .__links) {
//            __links <= links
//        }
//    }
//
//    required public init(snapshot: DataSnapshot) {
////        try! self.init(from: snapshot)
//        super.init(snapshot: snapshot)
////        let container = try! snapshot.container(keyedBy: CodingKeys.self)
////        if let mv = try? container.decode(Int?.self, forKey: .__mv) {
////            __mv <= mv
////        }
////        if let links = try? container.decode([RealtimeLink].self, forKey: .__links) {
////            __links <= links
////        }
//    }
//
//    required public init(dbRef: DatabaseReference) {
//        super.init(dbRef: dbRef)
//    }
//
//    public func encode(to encoder: Encoder) throws {
//        var container = encoder.container(keyedBy: CodingKeys.self)
//        try container.encode(__mv.value, forKey: .__mv)
//        try container.encode(__links.value, forKey: .__links)
//    }

    override public func didSave() {
        super.didSave()
        enumerateChilds { (_, value: RealtimeValueEvents) in
            value.didSave()
        }
    }
    
    override public func willRemove(completion: @escaping (Error?, [DatabaseReference]?) -> Void) {
        __links.load(completion: { err, _ in completion(err, err.map { _ in self.__links.value.map { $0.dbRef } }) })
    }
    
    override public func didRemove() {
        super.didRemove()
        enumerateChilds { (_, value: RealtimeValueEvents) in
            value.didRemove()
        }
    }
    
    override open func apply(snapshot: DataSnapshot, strongly: Bool) {
        if strongly || Nodes.modelVersion.has(in: snapshot) { __mv.apply(snapshot: Nodes.modelVersion.snapshot(from: snapshot)) }
        if strongly || Nodes.links.has(in: snapshot) { __links.apply(snapshot: Nodes.links.snapshot(from: snapshot)) }

        reflect { (mirror) in
            apply(snapshot: snapshot, strongly: strongly, to: mirror)
        }
    }
    private func apply(snapshot: DataSnapshot, strongly: Bool, to mirror: Mirror) {
        let lazyStorage = ".storage"
        mirror.children.forEach { (child) in
            guard var label = child.label else { return }

            if label.hasSuffix(lazyStorage) {
                label = String(label.prefix(upTo: label.index(label.endIndex, offsetBy: -lazyStorage.count)))
            }

            if let keyPath = (mirror.subjectType as! RealtimeObject.Type).keyPath(for: label) {
                if let value = self[keyPath: keyPath] as? (DataSnapshotRepresented & RealtimeValue) {
                    value.apply(parentSnapshotIfNeeded: snapshot, strongly: strongly)
                }
            }
        }
    }

    open class func keyPath(for label: String) -> AnyKeyPath? {
        fatalError("You should implement class func keyPath(for:)")//("Not found keyPath for label: \(label). Add to 'exclusiveLabels' to skip this label.")
    }

    override public func insertChanges(to values: inout [String : Any?], keyed from: DatabaseReference) {
        reflect(to: _RealtimeEntity.self) { (mirror) in
            mirror.children.forEach({ (child) in
                if let value = child.value as? _RealtimeEntity {
                    value.insertChanges(to: &values, keyed: from)
                }
                if let value = child.value as? _RealtimeValue {
                    value.insertChanges(to: &values, keyed: from)
                }
            })
        }
    }
    override public func insertChanges(to values: inout [Database.UpdateItem]) {
        reflect(to: _RealtimeEntity.self) { (mirror) in
            mirror.children.forEach({ (child) in
                if let value = child.value as? _RealtimeEntity {
                    value.insertChanges(to: &values)
                }
                if let value = child.value as? _RealtimeValue {
                    value.insertChanges(to: &values)
                }
            })
        }
    }
    override public func insertChanges(to transaction: RealtimeTransaction) {
        reflect(to: _RealtimeEntity.self) { (mirror) in
            mirror.children.forEach({ (child) in
                if let value = child.value as? _RealtimeEntity {
                    value.insertChanges(to: transaction)
                }
                if let value = child.value as? _RealtimeValue {
                    value.insertChanges(to: transaction)
                }
            })
        }
    }

    // MARK: RealtimeObject
    
    // TODO: Link as callback for modelVersion property
    open func performMigration(from version: Int?) {
        // implement migration
    }

    private func keyedValues(use maping: (_RealtimeValue) -> Any?) -> [String: Any]? {
        var keyedValues: [String: Any]? = nil
        enumerateChilds { (_, value: _RealtimeValue) in
            guard let mappedValue = maping(value) else { return }

            if keyedValues == nil { keyedValues = [String: Any]() }
            keyedValues![value.dbKey] = mappedValue
        }
        return keyedValues
    }
    fileprivate func enumerateChilds<As>(from type: Any.Type = _RealtimeEntity.self, _ block: (String?, As) -> Void) {
        reflect(to: type) { (mirror) in
            mirror.children.forEach({ (child) in
                guard let value = child.value as? As else { return }

                block(child.label, value)
            })
        }
    }
    private func containChild<As>(from type: Any.Type = _RealtimeEntity.self, where block: (String?, As) -> Bool) -> Bool {
        var contains = false
        reflect(to: type) { (mirror) in
            guard !contains else { return }
            contains = mirror.children.contains(where: { (child) -> Bool in
                guard let value = child.value as? As else { return false }

                return block(child.label, value)
            })
        }
        return contains
    }
    private func reflect(to type: Any.Type = RealtimeObject.self, _ block: (Mirror) -> Void) {
        var mirror = Mirror(reflecting: self)
        block(mirror)
        while let _mirror = mirror.superclassMirror, _mirror.subjectType != type {
            block(_mirror)
            mirror = _mirror
        }
    }
    
//    override public var debugDescription: String { return "\n{\n\tref: \(dbRef.pathFromRoot);" }//_allProps.reduce("\n{\n\tref: \(dbRef.pathFromRoot);") { $0 + "\n\"\($1.dbKey)\":" + $1.debugDescription } + "\n}" }
}

extension RealtimeObject: Reverting {
    public func revert() {
        enumerateChilds { (_, value: Reverting) in
            value.revert()
        }
    }
    public func currentReversion() -> () -> Void {
        var revertions: [() -> Void] = []
        enumerateChilds { (_, value: Reverting) in
            revertions.insert(value.currentReversion(), at: 0)
        }
        return { revertions.forEach { $0() } }
    }
}

extension RealtimeObject {
    public func save(in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        let transaction = transaction ?? RealtimeTransaction()
        transaction.set(self)
        return transaction
    }
    public func update(in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        let transaction = transaction ?? RealtimeTransaction()
        transaction.update(self)
        return transaction
    }
    public func delete(in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        let transaction = transaction ?? RealtimeTransaction()
        transaction.delete(self)
        return transaction
    }
}

extension RealtimeObject: Linkable {
    public var linksRef: DatabaseReference { return __links.dbRef }
    @discardableResult
    public func add(link: RealtimeLink) -> Self {
        guard !__links.value.contains(where: { $0 == link }) else { return self }
            
        __links.value.append(link)
        return self
    }
    @discardableResult
    public func remove(linkBy id: String) -> Self {
        guard let index = __links.value.index(where: { $0.id == id }) else { return self }

        __links.value.remove(at: index)
        return self
    }
}
public extension Linkable {
    func addLink(_ link: RealtimeLink, in transaction: RealtimeTransaction) {
        add(link: link)
        transaction.addNode(ref: linksRef.child(link.id), value: link.dbValue)
    }
    func removeLink(by id: String, in transaction: RealtimeTransaction) {
        remove(linkBy: id)
        transaction.addNode(ref: linksRef.child(id), value: nil)
    }
}
