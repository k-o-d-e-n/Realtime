//
//  RealtimeProperty.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 18/02/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation
import FirebaseDatabase

public extension RawRepresentable where Self.RawValue == String {
    func property<T: HasDefaultLiteral>(from node: Node?, options: [RealtimeValueOption: Any] = [.representer: AnyRVRepresenter<T>.default]) -> RealtimeProperty<T> {
        return RealtimeProperty(in: Node(key: rawValue, parent: node), options: options)
    }

    func primitive<V: FireDataValue>(from node: Node?) -> RealtimeProperty<V> {
        return RealtimeProperty(in: Node(key: rawValue, parent: node))
    }
    func relation<V: RealtimeObject>(from node: Node?, ownerLevelsUp: Int = 1, _ property: String) -> RealtimeRelation<V> {
        return RealtimeRelation(in: Node(key: rawValue, parent: node),
                                options: [.relation: RealtimeRelation<V>.Options(ownerLevelsUp: ownerLevelsUp, property: property)])
    }
    func `enum`<V: RawRepresentable & HasDefaultLiteral>(from node: Node?) -> RealtimeProperty<V> {
        return RealtimeProperty(in: Node(key: rawValue, parent: node),
                                options: [.representer: AnyRVRepresenter<V>(serializer: EnumSerializer.self)])
    }
    func optionalEnum<V: RawRepresentable>(from node: Node?) -> RealtimeProperty<V?> {
        return RealtimeProperty(in: Node(key: rawValue, parent: node),
                                options: [.representer: AnyRVRepresenter<V?>(serializer: OptionalEnumSerializer.self)])
    }
    func optionalDate(from node: Node?) -> RealtimeProperty<Date?> {
        return RealtimeProperty(in: Node(key: rawValue, parent: node),
                                options: [.representer: AnyRVRepresenter(serializer: DateSerializer.self)])
    }
    func optionalUrl(from node: Node?) -> RealtimeProperty<URL?> {
        return RealtimeProperty(in: Node(key: rawValue, parent: node),
                                options: [.representer: AnyRVRepresenter(serializer: URLSerializer.self)])
    }

    func linked<V: RealtimeValue>(from node: Node?) -> RealtimeProperty<V?> {
        return RealtimeProperty(in: Node(key: rawValue, parent: node),
                                options: [.representer: AnyRVRepresenter(serializer: LinkableValueSerializer<V>.self)])
    }
    func codable<V: Codable & HasDefaultLiteral>(from node: Node?) -> RealtimeProperty<V> {
        return RealtimeProperty(in: Node(key: rawValue, parent: node),
                                options: [.representer: AnyRVRepresenter<V>(serializer: CodableSerializer.self)])
    }

    func nested<Type: RealtimeObject>(in object: RealtimeObject) -> Type {
        let property = Type(in: Node(key: rawValue, parent: object.node))
        property.parent = object
        return property
    }
}

extension RealtimeProperty: FilteringEntity {}

public extension RealtimeValueOption {
    static var relation = RealtimeValueOption("realtime.relation")
}

// TODO: May be need create real relation to property in linked entity, but not simple register external link
// TODO: Remove id from value
public final class RealtimeRelation<Related: RealtimeObject>: RealtimeProperty<Related> {
    let options: Options

    public required init(in node: Node?, options: [RealtimeValueOption: Any]) {
        guard let node = node else { fatalError() }
        guard case let relation as Options = options[.relation] else { fatalError("Skipped required options")}

        self.options = relation
        super.init(in: node, options: [.representer: AnyRVRepresenter<Related>.relation(relation.property)])
    }

    public override func willRemove(in transaction: RealtimeTransaction, from ancestor: Node) {
        super.willRemove(in: transaction, from: ancestor)
        transaction.addPrecondition { [unowned transaction] (promise) in
            self.loadValue(completion: .just({ (err, val) in
                if let node = val?.node?.child(with: self.options.property) {
                    transaction.addValue(nil, by: node)
                }
                promise.fulfill(err)
            }))
        }
    }

    public override func write(to transaction: RealtimeTransaction, by node: Node) {
        super.write(to: transaction, by: node)
        if let backwardNode = value?.node?.child(with: options.property) {
            let ownerNode = node.ancestor(on: options.ownerLevelsUp)!
            let thisProperty = node.path(from: ownerNode)
            let backwardRelation = Relation(path: ownerNode.rootPath, property: thisProperty)
            transaction.addValue(backwardRelation.fireValue, by: backwardNode)
        }
        if let previousNode = oldValue.value?.node?.child(with: options.property) {
            transaction.addValue(nil, by: previousNode)
        }
    }

    public struct Options {
        /// Levels up by hierarchy to relation owner of this property
        let ownerLevelsUp: Int
        /// String path from related object to his relation property
        let property: String
    }
}

// MARK: Listenable realtime property

public extension RealtimeValueOption {
    static var representer: RealtimeValueOption = RealtimeValueOption("realtime.property.representer")
    static var initialValue: RealtimeValueOption = RealtimeValueOption("realtime.property.initialValue")
}

public enum ListenValue<T> {
    case none // none(reverted: Bool)
    case local(T)
    case remote(T) // remote(T, reverted: Bool)
    indirect case error(Error, last: ListenValue<T>)
//    case reverted(T)

    public var value: T? {
        switch self {
        case .none: return nil
        case .local(let v): return v
        case .remote(let v): return v
        case .error(_, let v): return v.value
        }
    }
}

infix operator =?
public extension ListenValue {
    static func =?(_ value: inout T, _ prop: ListenValue) {
        if let v = prop.value {
            value = v
        }
    }
    static func =?(_ value: inout T?, _ prop: ListenValue) {
        if let v = prop.value {
            value = v
        }
    }
    static func <=(_ value: inout T?, _ prop: ListenValue) {
        value = prop.value
    }
}

// TODO: Add possible update value at subpath
// TODO: Create property for storage data
// TODO: Research how can use ExpressibleByNilLiteral pattern in RP
public class RealtimeProperty<T>: _RealtimeValue, ValueWrapper, InsiderOwner, Reverting {
    public func revert() {
        guard hasChanges else { return }

        localPropertyValue.set(oldValue)
        insider.dataDidChange()
    }
    public func currentReversion() -> () -> Void {
        return { [weak self] in
            self?.revert()
        }
    }

    override public var hasChanges: Bool {
        guard case .local = localPropertyValue.get() else {
            return false
        }

        return true
    }

    private var localPropertyValue: PropertyValue<ListenValue<T>>
    fileprivate var oldValue: ListenValue<T> = .none
    public var value: T? {
        get { return localPropertyValue.get().value }
        set {
            if !hasChanges {
                oldValue = localPropertyValue.get()
            }
            setValue(newValue.map { .local($0) } ?? .none)
        }
    }
    let representer: AnyRVRepresenter<T>
    public var insider: Insider<ListenValue<T>>
    
    // MARK: Initializers, deinitializer
    
    public required init(in node: Node?, options: [RealtimeValueOption: Any] = [.representer: AnyRVRepresenter<T>.default]) {
        guard case let representer as AnyRVRepresenter<T> = options[.representer] else { fatalError("Bad options") }

        self.localPropertyValue = PropertyValue((options[.initialValue] as? T).map { .local($0) } ?? .none)
        self.insider = Insider(source: localPropertyValue.get)
        self.representer = representer
        super.init(in: node, options: options)
    }

    @discardableResult
    public func setValue(_ value: T?, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        self.value = value
        let transaction = transaction ?? RealtimeTransaction()
        transaction.set(self)
        return transaction
    }

    @discardableResult
    public func changeValue(use changing: (inout T?) -> (), in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        changing(&value)
        let transaction = transaction ?? RealtimeTransaction()
        transaction.set(self)
        return transaction
    }
    
    public override func load(completion: Assign<(error: Error?, ref: DatabaseReference)>?) {
        super.load(completion: completion?.with(work: { (val) in
            val.error.map(self.setError)
        }))
    }
    @discardableResult
    public func loadValue(completion: Assign<(error: Error?, value: T?)>) -> Self {
        super.load(completion: .just { (err, _) in
            err.map(self.setError)
            completion.assign((err, self.value))
        })

        return self
    }

    override public func writeChanges(to transaction: RealtimeTransaction, by node: Node) {
        if hasChanges {
            transaction.addReversion(currentReversion())
            super.writeChanges(to: transaction, by: node)
        }
    }

    public override func write(to transaction: RealtimeTransaction, by node: Node) {
        if let val = localPropertyValue.get().value {
            do {
                transaction.addValue(try representer.encode(val), by: node)
            } catch let e {
                fatalError(e.localizedDescription)
            }
        }
    }
    
    // MARK: Events
    
    override public func didSave(in parent: Node, by key: String) {
        super.didSave(in: parent, by: key)
        if case .local(let v) = localPropertyValue.get() {
            setValue(.remote(v))
        }
    }
    
    override public func didRemove(from node: Node) {
        super.didRemove(from: node)
        setValue(.none)
    }
    
    // MARK: Changeable

    public convenience required init(fireData: FireDataProtocol) throws {
        self.init(in: fireData.dataRef.map(Node.from))
        apply(fireData)
    }

    override public func apply(_ data: FireDataProtocol, strongly: Bool) {
        super.apply(data, strongly: strongly)
        do {
            setValue(.remote(try representer.decode(data)))
        } catch let e {
            setError(e)
        }
    }

    private func setValue(_ value: ListenValue<T>) {
        localPropertyValue.set(value)
        insider.dataDidChange()
    }

    private func setError(_ error: Error) {
        localPropertyValue.set(.error(error, last: localPropertyValue.get()))
        insider.dataDidChange()
    }
}

// TODO: Reconsider usage it. Some RealtimeValue things are not need here.
public final class SharedProperty<T>: _RealtimeValue, InsiderOwner where T: FireDataValue, T: HasDefaultLiteral {
    private var localPropertyValue: PropertyValue<T>
    public var value: T { return localPropertyValue.get() }
    public var insider: Insider<T>
    let representer: AnyRVRepresenter<T> = .default

    // MARK: Initializers, deinitializer

    public required init(in node: Node?, options: [RealtimeValueOption: Any]) {
        self.localPropertyValue = PropertyValue(T())
        self.insider = Insider(source: localPropertyValue.get)
        super.init(in: node, options: options)
    }

    public override func write(to transaction: RealtimeTransaction, by node: Node) {
        /// shared property cannot change in transaction
    }

    // MARK: Events

    override public func didSave(in parent: Node, by key: String) {
        super.didSave(in: parent, by: key)
    }

    override public func didRemove(from node: Node) {
        super.didRemove(from: node)
        setValue(T())
    }

    // MARK: Changeable

    public convenience required init(fireData: FireDataProtocol) throws {
        self.init(in: fireData.dataRef.map(Node.from))
        apply(fireData)
    }

    override public func apply(_ data: FireDataProtocol, strongly: Bool) {
        super.apply(data, strongly: strongly)
        do {
            setValue(try representer.decode(data))
        } catch let e {
            debugFatalError(e.localizedDescription)
        }
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
                    let dataValue = data.exists() ? try T.init(fireData: data) : T()
                    data.value = try changing(dataValue)
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
                    self.setValue(Serializer.deserialize(s))
                    completion?(true, self.value)
                } else {
                    debugFatalError("Transaction completed without error, but snapshot does not exist")

                    completion?(false, self.value)
                }
            })
        }
    }
}

public final class MutationPoint<T> where T: FireDataValue {
    public let node: Node
    public required init(in node: Node) throws {
        guard node.isRooted else { throw RealtimeError("Node should be rooted") }
        self.node = node
    }
}
public extension MutationPoint {
    func set(value: T, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        let transaction = transaction ?? RealtimeTransaction()
        transaction.addValue(value, by: node)

        return transaction
    }
    func mutate(by key: String? = nil, use value: T, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        let transaction = transaction ?? RealtimeTransaction()
        transaction.addValue(value, by: key.map { node.child(with: $0) } ?? node.childByAutoId())

        return transaction
    }
    func removeValue(for key: String, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        let transaction = transaction ?? RealtimeTransaction()
        transaction.addValue(nil, by: node.child(with: key))

        return transaction
    }
}
