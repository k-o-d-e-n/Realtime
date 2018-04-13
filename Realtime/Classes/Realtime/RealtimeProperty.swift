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
//    func property<Type: RealtimeValue>(from parent: DatabaseReference) -> Type {
//        return Type(in: Node.root.child(with: parent.rootPath))
//    }
    func property<Type: RealtimeValue>(from node: Node?) -> Type {
        return Type(in: Node(key: rawValue, parent: node))
    }
    func property<Type: RealtimeValue>() -> Type {
        return Type(in: Node(key: rawValue))
    }
}

public extension Node {
    func property<Type: RealtimeValue>() -> Type! {
        return Type(in: self)
    }
}

extension RealtimeProperty: FilteringEntity {}

// TODO: May be need create real relation to property in linked entity, but not simple register external link
// TODO: Remove id from value
public final class RealtimeRelation<Related: RealtimeObject>: RealtimeProperty<(String, Related)?, RelationableValueSerializer<Related>> {
    public override func revert() {
        if let old = oldValue.flatMap({ $0 }) { old.1.add(link: old.1.node!.generate(linkTo: node!).link) }
        if let new = value { new.1.remove(linkBy: new.0) }
        super.revert()
    }
    public var related: Related? { return value?.1 }

    public required init(in node: Node?, value: T) {
        if node.map({ !$0.isRooted }) ?? true {
            debugFatalError("Relation should be initialized with rooted node");
        }
        super.init(in: node, value: value)
    }

    public override func setValue(_ value: (String, Related)?, in transaction: RealtimeTransaction?) -> RealtimeTransaction {
        fatalError("Use setValue(_: Related?, in:) function instead")
    }

    @discardableResult
    public func setValue(_ value: Related?, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        let transaction = transaction ?? RealtimeTransaction()
        if let (id, related) = self.value {
            related.removeLink(by: id, in: transaction)
        }
        if let v = value {
            let link = v.node!.generate(linkTo: node!).link
            v.addLink(link, in: transaction)
            self.value = (link.id, v)
            transaction.set(self)
        } else {
            transaction.delete(self)
        }

        return transaction
    }
}

// MARK: Listenable realtime property

public typealias StandartProperty<StandartType: HasDefaultLiteral & Codable> = RealtimeProperty<StandartType, Serializer<StandartType>>
public typealias OptionalEnumProperty<EnumType: RawRepresentable> = RealtimeProperty<EnumType?, EnumSerializer<EnumType>>
public extension URL {
    typealias OptionalProperty = RealtimeProperty<URL?, URLSerializer>
}

public extension Date {
    typealias OptionalProperty = RealtimeProperty<Date?, DateSerializer>
}

public extension RawRepresentable where Self: HasDefaultLiteral {
    typealias OptionalProperty = RealtimeProperty<Self?, EnumSerializer<Self>>
}

public typealias LinkedRealtimeProperty<V: RealtimeValue> = RealtimeProperty<V?, LinkableValueSerializer<V>>

// TODO: Add possible update value at subpath
// TODO: Create property for storage data
// TODO: Research how can use ExpressibleByNilLiteral pattern in RP
public class RealtimeProperty<T, Serializer: _Serializer>: _RealtimeValue, ValueWrapper, InsiderOwner, Reverting where T == Serializer.Entity {
    public func revert() {
        oldValue.map {
            localPropertyValue.set($0)
            resetHasChanges()
            insider.dataDidChange()
        }
//        (value as? Reverting & ChangeableRealtimeValue)?.revertIfChanged()
    }
    public func currentReversion() -> () -> Void {
        return { [weak self] in
            guard let this = self else { return }
            this.oldValue.map {
                this.localPropertyValue.set($0)
                this.resetHasChanges()
                this.insider.dataDidChange()
            }
        }
    }

    private var _hasChanges = false
    override public private(set) var hasChanges: Bool {
        set { _hasChanges = newValue }
        get { return _hasChanges }//(value as? ChangeableRealtimeValue).map { $0.hasChanges || _hasChanges } ?? _hasChanges }
    }
    override public var localValue: Any? { return Serializer.serialize(entity: localPropertyValue.get()) }
    
    private var localPropertyValue: PropertyValue<T>
    fileprivate var oldValue: T?
    public var value: T {
        get { return localPropertyValue.get() }
        set {
            oldValue = localPropertyValue.get()
            registerHasChanges()
            setValue(newValue)
        }
    }
    public var insider: Insider<T>
    public var lastError: Property<Error?>
    
    // MARK: Initializers, deinitializer
    
    public required init(in node: Node?, value: T) {
        self.localPropertyValue = PropertyValue(value)
        self.insider = Insider(source: localPropertyValue.get)
        self.lastError = Property<Error?>(value: nil)
        super.init(in: node)
    }

    public convenience required init(in node: Node?) {
        self.init(in: node, value: T())
    }

//    public convenience init(from decoder: Decoder) throws {
////        self.init(snapshot: decoder as! DataSnapshot)
//        let container = try decoder.singleValueContainer()
//        self.init(dbRef: decoder.userInfo[CodingUserInfoKey(rawValue: "ref")!] as! DatabaseReference,
//                  value: try container.decode(T.self))
//    }
//
//    public func encode(to encoder: Encoder) throws {
//        var container = encoder.singleValueContainer()
//        try container.encode(value)
//    }

//    deinit {
//    }

    @discardableResult
    public func setValue(_ value: T, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        self.value = value
        let transaction = transaction ?? RealtimeTransaction()
        transaction.set(self)
        return transaction
    }

    @discardableResult
    public func changeValue(use changing: (inout T) -> (), in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        changing(&value)
        let transaction = transaction ?? RealtimeTransaction()
        transaction.set(self)
        return transaction
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
    
    override public func didSave(in node: Node) {
        super.didSave(in: node)
        resetHasChanges()
    }
    
    override public func didRemove(from node: Node) {
        super.didRemove(from: node)
        resetHasChanges()
        setValue(T())
    }
    
    // MARK: Changeable
    
    public convenience required init(snapshot: DataSnapshot) {
        self.init(in: Node(key: snapshot.key, parent: nil))
        apply(snapshot: snapshot)
    }

    override public func apply(snapshot: DataSnapshot, strongly: Bool) {
        super.apply(snapshot: snapshot, strongly: strongly)
        resetHasChanges()
        setValue(Serializer.deserialize(entity: snapshot))
    }

    private func registerHasChanges() {
        if !hasChanges { hasChanges = true }
    }
    private func resetHasChanges() {
        oldValue = nil
        if hasChanges { hasChanges = false }
    }
    private func setValue(_ value: T) {
        localPropertyValue.set(value)
        insider.dataDidChange()
    }
}

public class SharedProperty<T, Serializer: _Serializer>: _RealtimeValue, ValueWrapper, InsiderOwner where T == Serializer.Entity, T: MutableDataRepresented {
    override public var localValue: Any? { return Serializer.serialize(entity: localPropertyValue.get()) }

    private var localPropertyValue: PropertyValue<T>
    public var value: T {
        get { return localPropertyValue.get() }
        set { setValue(newValue) }
    }
    public var insider: Insider<T>

    // MARK: Initializers, deinitializer

    public required init(in node: Node?, value: T) {
        self.localPropertyValue = PropertyValue(value)
        self.insider = Insider(source: localPropertyValue.get)
        super.init(in: node)
    }

    public convenience required init(in node: Node?) {
        self.init(in: node, value: T())
    }

    // MARK: Events

    override public func didSave(in node: Node) {
        super.didSave(in: node)
    }

    override public func didRemove(from node: Node) {
        super.didRemove(from: node)
        setValue(T())
    }

    // MARK: Changeable

    public convenience required init(snapshot: DataSnapshot) {
        self.init(in: Node(key: snapshot.key, parent: nil))
        apply(snapshot: snapshot)
    }

    override public func apply(snapshot: DataSnapshot, strongly: Bool) {
        super.apply(snapshot: snapshot, strongly: strongly)
        setValue(Serializer.deserialize(entity: snapshot))
    }

    fileprivate func setValue(_ value: T) {
        localPropertyValue.set(value)
        insider.dataDidChange()
    }
}

public extension SharedProperty {
    public func changeValue(use changing: @escaping (T) throws -> T, completion: ((Bool, T) -> Void)? = nil) {
        debugFatalError(condition: dbRef == nil, "")
        
        if let ref = dbRef {
            ref.runTransactionBlock({ data in
                do {
                    let dataValue = data.exists() ? try T.init(data: data) : T()
                    data.value = try changing(dataValue).localValue
                } catch let e {
                    debugFatalError(e.localizedDescription)

                    return .abort()
                }
                return .success(withValue: data)
            }, andCompletionBlock: { [unowned self] error, commited, snapshot in
                guard error == nil else {
                    completion?(false, self.value)
                    return
                }

                if let s = snapshot {
                    self.setValue(Serializer.deserialize(entity: s))
                    completion?(true, self.value)
                } else {
                    debugFatalError("Transaction completed without error, but snapshot does not exist")

                    completion?(false, self.value)
                }
            })
        }
    }
}

