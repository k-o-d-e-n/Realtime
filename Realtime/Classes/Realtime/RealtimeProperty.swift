//
//  RealtimeProperty.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 18/02/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation
import FirebaseDatabase

extension RealtimeNode {
    func property<Type: RealtimeValue>(from parent: DatabaseReference) -> Type {
        return Type(dbRef: reference(from: parent))
    }
}

extension RealtimeProperty: FilteringEntity {}

// TODO: Rewrite
fileprivate class _Linked<Linked: KeyedRealtimeValue & Linkable & ChangeableRealtimeEntity>: _RealtimeValue, ValueWrapper, InsiderOwner {
    fileprivate lazy var _link: RealtimeLink.OptionalProperty = RealtimeLink.OptionalProperty(dbRef: self.dbRef)
    //    var insider: Insider<RealtimeLink?> { set { _link.insider = newValue } get { return _link.insider } }
    lazy var insider: Insider<Linked?> = self._link.insider.mapped { [unowned self] _ in self.linked }
    override var hasChanges: Bool { return _link.hasChanges }
    override var localValue: Any? { return _link.localValue }
    var value: Linked? {
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

    required init(dbRef: DatabaseReference) {
        super.init(dbRef: dbRef)
//        self.depends(on: self._link)
        _ = self._link.distinctUntilChanged(comparer: { $0 == $1 }).listening({ [weak self] _ in
            guard let _self = self else { return }
            _self.reloadLinked()
            _self.insider.dataDidChange()
        })
    }

    override func didRemove() {
        _link.didRemove()
    }

    override func didSave() {
        _link.didSave()
    }

    convenience required init(snapshot: DataSnapshot) {
        self.init(dbRef: snapshot.ref)
        apply(snapshot: snapshot)
    }

    override func apply(snapshot: DataSnapshot, strongly: Bool) {
        _link.apply(snapshot: snapshot, strongly: strongly)
    }

    fileprivate func reloadLinked() { linked = self._link.value?.entity(Linked.self) }
}

class LinkedRealtimeProperty<Linked: KeyedRealtimeValue & Linkable & ChangeableRealtimeEntity>: _Linked<Linked> {
//    var link: RealtimeLink.OptionalProperty { return _link }
    func link(withoutUpdate value: Linked) {
        self._link.setLocalValue(dbRef.link(to: value.dbRef))
    }
    func link(_ entity: Linked, to transaction: RealtimeTransaction) {
        link(withoutUpdate: entity)
        transaction.addUpdate(item: (dbRef, localValue))
    }
}

// TODO: May be need create real relation to property in linked entity, but not simple register external link
class RealtimeRelation<Linked: KeyedRealtimeValue & Linkable & ChangeableRealtimeEntity>: _Linked<Linked> {
    func link(withoutUpdate value: Linked) {
        if let oldLink = self._link.value { linked?.remove(linkBy: oldLink.id) }
        self._link.setLocalValue(dbRef.link(to: value.dbRef))
        value.add(link: value.generate(linkTo: dbRef).link)
    }
    func link(_ entity: Linked, to transaction: RealtimeTransaction) {
        if let oldLink = self._link.value, let linked = self.linked {
            linked.removeLink(by: oldLink.id, in: transaction)
            _link.setLocalValue(nil)
        }
        link(withoutUpdate: entity)
        if self.value != nil { linked?.insertChanges(to: transaction) }
        transaction.addUpdate(item: (dbRef, localValue))
        entity.insertChanges(to: transaction)
    }
}

typealias StandartProperty<StandartType: Initializable> = RealtimeProperty<StandartType, Serializer<StandartType>>
typealias OptionalEnumProperty<EnumType: RawRepresentable> = RealtimeProperty<EnumType?, EnumSerializer<EnumType>>
extension URL {
    typealias OptionalProperty = RealtimeProperty<URL?, URLSerializer>
}

extension Date {
    typealias OptionalProperty = RealtimeProperty<Date?, DateSerializer>
}

// MARK: Listenable realtime property

typealias SimpleProperty<PrimitiveType: Initializable> = RealtimeProperty<PrimitiveType, Serializer<PrimitiveType>>
extension RawRepresentable where Self: Initializable {
    typealias OptionalProperty = RealtimeProperty<Self?, EnumSerializer<Self>>
}

// TODO: Add possible update value at subpath
// TODO: Create property for storage data
// TODO: Research how can use ExpressibleByNilLiteral pattern in RP
final class RealtimeProperty<T, Serializer: _Serializer>: _RealtimeValue, ValueWrapper, InsiderOwner where T == Serializer.Entity {
    private var _hasChanges = false
    override private(set) var hasChanges: Bool {
        set { _hasChanges = newValue }
        get { return _hasChanges }
    }
    override var localValue: Any? { return Serializer.serialize(entity: localPropertyValue.get()) }
    
    private var localPropertyValue: PropertyValue<T>
    private var localProperty: T {
        get { return localPropertyValue.get() }
        set { localPropertyValue.set(newValue); insider.dataDidChange() }
    }
    var value: T {
        get { return localProperty }
        set { localProperty = newValue; save(completion: { err, _ in if err != nil { self.lastError.value = err } }) }
    }
    var insider: Insider<T>
    var lastError: Property<Error?>
    
    // MARK: Initializers, deinitializer
    
    init<Prop: RealtimeProperty>(dbRef: DatabaseReference, value: T, onFetch: ((Prop, Error?) -> ())? = nil) {
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
    
    convenience required init(dbRef: DatabaseReference) {
        self.init(dbRef: dbRef, value: T.defValue)
    }
    
    deinit {
    }
    
    // MARK: Setters
    
    func setLocalValue(_ value: T) {
        localProperty = value
        if !hasChanges { hasChanges = true }
    }
    
    func changeLocalValue(use: (inout T) -> ()) {
        use(&localProperty)
        if !hasChanges { hasChanges = true }
    }
    
    func setValue(_ value: T, completion: @escaping (Error?, DatabaseReference) -> ()) {
        setLocalValue(value)
        save(completion: completion)
    }
    
    func changeValue(use changing: (inout T) -> (), completion: ((Error?, DatabaseReference) -> ())?) {
        changeLocalValue(use: changing)
        save(completion: completion)
    }
    
    @discardableResult
    override func load(completion: Database.TransactionCompletion? = nil) -> Self {
        super.load { (err, ref) in
            err.map { self.lastError.value = $0 }
            completion?(err, ref)
        }
        
        return self
    }
    @discardableResult
    func loadValue(completion: @escaping (Error?, T) -> Void) -> Self {
        super.load { (err, _) in
            err.map { self.lastError.value = $0 }
            completion(err, self.value)
        }

        return self
    }
    
//    func runObserving() {
//        guard observingToken == nil else { return }
//        
//        observingToken = super.observe() { (err, ref) in
//            err.map { self.lastError.value = $0 }
//        }
//    }
//
//    func stopObserving() {
//        guard let token = observingToken else { return }
//
//        endObserve(for: token)
//    }
    
    // MARK: Events
    
    override func didSave() {
        if hasChanges { hasChanges = false }
    }
    
    override func didRemove() {
        if hasChanges { hasChanges = false }
        localProperty = T.defValue
    }
    
    // MARK: Changeable
    
    convenience required init(snapshot: DataSnapshot) {
        self.init(dbRef: snapshot.ref)
        apply(snapshot: snapshot)
    }
    
    override func apply(snapshot: DataSnapshot, strongly: Bool) {
        if hasChanges { hasChanges = false }
        localProperty = Serializer.deserialize(entity: snapshot)
    }
}

// TODO: Implement new SharedRealtimeProperty
