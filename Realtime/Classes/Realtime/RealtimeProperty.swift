//
//  RealtimeProperty.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 18/02/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation
import FirebaseDatabase

public extension RTNode where Self.RawValue == String {
    func property<Type: RealtimeValue>(from parent: DatabaseReference) -> Type {
        return Type(dbRef: reference(from: parent))
    }
}

extension RealtimeProperty: FilteringEntity {}

// TODO: Rewrite
public class _Linked<Linked: KeyedRealtimeValue & Linkable & ChangeableRealtimeEntity>: _RealtimeValue, ValueWrapper, InsiderOwner {
    fileprivate lazy var _link: RealtimeLink.OptionalProperty = RealtimeLink.OptionalProperty(dbRef: self.dbRef)
    //    var insider: Insider<RealtimeLink?> { set { _link.insider = newValue } get { return _link.insider } }
    public lazy var insider: Insider<Linked?> = self._link.insider.mapped { [unowned self] _ in self.linked }
    public override var hasChanges: Bool { return _link.hasChanges }
    public override var localValue: Any? { return _link.localValue }
    public var value: Linked? {
        set {
            let oldValue = _link.value
            _link.value = newValue.map { dbRef.link(to: $0.dbRef) }
            if oldValue != _link.value {
                reloadLinked()
            }
        }
        get { return linked }
    }

    fileprivate var linked: Linked?

    public required init(dbRef: DatabaseReference) {
        super.init(dbRef: dbRef)
//        self.depends(on: self._link)
        _ = self._link.distinctUntilChanged(comparer: { $0 == $1 }).listening(.guarded(self) { _, _self in
            _self.reloadLinked()
            _self.insider.dataDidChange()
        })
    }

    override public func didRemove() {
        _link.didRemove()
    }

    override public func didSave() {
        _link.didSave()
    }

    public convenience required init(snapshot: DataSnapshot) {
        self.init(dbRef: snapshot.ref)
        apply(snapshot: snapshot)
    }

    override public func apply(snapshot: DataSnapshot, strongly: Bool) {
        _link.apply(snapshot: snapshot, strongly: strongly)
    }

    fileprivate func reloadLinked() { linked = self._link.value?.entity(Linked.self) }
}

// TODO: Use simple RealtimeProperty with value typed by Reference (like as DocumentReference in Firestore)
public final class LinkedRealtimeProperty<Linked: KeyedRealtimeValue & Linkable & ChangeableRealtimeEntity>: _Linked<Linked> {
//    var link: RealtimeLink.OptionalProperty { return _link }
    public func link(withoutUpdate value: Linked) {
        self._link.value = dbRef.link(to: value.dbRef)
    }
    public func link(_ entity: Linked, to transaction: RealtimeTransaction) {
        link(withoutUpdate: entity)
        transaction.addUpdate(item: (dbRef, localValue))
    }
}

// TODO: May be need create real relation to property in linked entity, but not simple register external link
public final class RealtimeRelation<Linked: KeyedRealtimeValue & Linkable & ChangeableRealtimeEntity>: _Linked<Linked> {
    public func link(withoutUpdate value: Linked) {
        if let oldLink = self._link.value { linked?.remove(linkBy: oldLink.id) }
        self._link.value = dbRef.link(to: value.dbRef)
        value.add(link: value.generate(linkTo: dbRef).link)
    }
    public func link(_ entity: Linked, to transaction: RealtimeTransaction) {
        if let oldLink = self._link.value, let linked = self.linked {
            linked.removeLink(by: oldLink.id, in: transaction)
            _link.value = nil
        }
        link(withoutUpdate: entity)
        if self.value != nil { linked?.insertChanges(to: transaction) }
        transaction.addUpdate(item: (dbRef, localValue))
        entity.insertChanges(to: transaction)
    }
}

// MARK: Listenable realtime property

public typealias StandartProperty<StandartType: Initializable> = RealtimeProperty<StandartType, Serializer<StandartType>>
public typealias OptionalEnumProperty<EnumType: RawRepresentable> = RealtimeProperty<EnumType?, EnumSerializer<EnumType>>
public extension URL {
    typealias OptionalProperty = RealtimeProperty<URL?, URLSerializer>
}

public extension Date {
    typealias OptionalProperty = RealtimeProperty<Date?, DateSerializer>
}

public extension RawRepresentable where Self: Initializable {
    typealias OptionalProperty = RealtimeProperty<Self?, EnumSerializer<Self>>
}

// TODO: Add possible update value at subpath
// TODO: Create property for storage data
// TODO: Research how can use ExpressibleByNilLiteral pattern in RP
public final class RealtimeProperty<T, Serializer: _Serializer>: _RealtimeValue, ValueWrapper, InsiderOwner where T == Serializer.Entity {
    private var _hasChanges = false
    override public private(set) var hasChanges: Bool {
        set { _hasChanges = newValue }
        get { return _hasChanges }
    }
    override public var localValue: Any? { return Serializer.serialize(entity: localPropertyValue.get()) }
    
    private var localPropertyValue: PropertyValue<T>
    public var value: T {
        get { return localPropertyValue.get() }
        set {
            localPropertyValue.set(newValue)
            registerHasChanges()
            insider.dataDidChange()
        }
    }
    public var insider: Insider<T>
    public var lastError: Property<Error?>
    
    // MARK: Initializers, deinitializer
    
    public init<Prop: RealtimeProperty>(dbRef: DatabaseReference, value: T, onFetch: ((Prop, Error?) -> ())? = nil) {
        self.localPropertyValue = PropertyValue(value)
        self.insider = Insider(source: localPropertyValue.get)
        self.lastError = Property<Error?>(value: nil)
        super.init(dbRef: dbRef)
        
        _ = onFetch.map { on in
            load { err, _ in
                on(self as! Prop, err)
            }
        }
    }
    
    public convenience required init(dbRef: DatabaseReference) {
        self.init(dbRef: dbRef, value: T.defValue)
    }

    }
    }
    
    
    @discardableResult
    override public func load(completion: Database.TransactionCompletion? = nil) -> Self {
        super.load { (err, ref) in
            err.map { self.lastError.value = $0 }
            completion?(err, ref)
        }
        
        return self
    }
    @discardableResult
    public func loadValue(completion: @escaping (Error?, T) -> Void) -> Self {
        super.load { (err, _) in
            err.map { self.lastError.value = $0 }
            completion(err, self.value)
        }

        return self
    }
    
    // MARK: Events
    
    override public func didSave() {
        super.didSave()
        resetHasChanges()
    }
    
    override public func didRemove() {
        super.didRemove()
        resetHasChanges()
        value = T.defValue
    }
    
    // MARK: Changeable
    
    public convenience required init(snapshot: DataSnapshot) {
        self.init(dbRef: snapshot.ref)
        apply(snapshot: snapshot)
    }
    
    override public func apply(snapshot: DataSnapshot, strongly: Bool) {
        super.apply(snapshot: snapshot, strongly: strongly)
        resetHasChanges()
        value = Serializer.deserialize(entity: snapshot)
    }

    private func registerHasChanges() {
        if !hasChanges { hasChanges = true }
    }
    private func resetHasChanges() {
        if hasChanges { hasChanges = false }
    }
}
extension RealtimeProperty {
    // MARK: Setters

    public func setValue(_ value: T, completion: @escaping (Error?, DatabaseReference) -> ()) {
        self.value = value
        save(completion: completion)
    }

    public func changeValue(use changing: (inout T) -> (), completion: ((Error?, DatabaseReference) -> ())?) {
        changing(&value)
        save(completion: completion)
    }
}

// TODO: Implement new SharedRealtimeProperty
