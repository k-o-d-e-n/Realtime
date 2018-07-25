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
    func `enum`<V: RawRepresentable>(from node: Node?) -> RealtimeProperty<V> {
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

    func reference<V: RealtimeValue>(from node: Node?, mode: RealtimeReference<V>.Mode) -> RealtimeReference<V> {
        return RealtimeReference(in: Node(key: rawValue, parent: node), options: [.reference: mode])
    }
    func relation<V: RealtimeObject, Property: RawRepresentable>(from node: Node?, ownerLevelsUp: Int = 1, _ property: Property) -> RealtimeRelation<V> where Property.RawValue == String {
        return RealtimeRelation(in: Node(key: rawValue, parent: node),
                                options: [.relation: RealtimeRelation<V>.Options(ownerLevelsUp: ownerLevelsUp, property: property.rawValue)])
    }
    
    func codable<V: Codable>(from node: Node?) -> RealtimeProperty<V> {
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
    static let relation = RealtimeValueOption("realtime.relation")
    static let reference = RealtimeValueOption("realtime.reference")
}

public final class RealtimeReference<Referenced: RealtimeValue>: RealtimeProperty<Referenced?> {
    public override var version: Int? { return _version }
    public override var raw: FireDataValue? { return _raw }
    public override var payload: [String : FireDataValue]? { return _payload }

    public required init(in node: Node?, options: [RealtimeValueOption : Any]) {
        let mode: Mode = options[.reference] as? Mode ?? .fullPath
        super.init(in: node, options: [.representer: AnyRVRepresenter.reference(mode)])
    }

    public enum Mode {
        case fullPath
        case key(from: Node)
    }
}

public final class RealtimeRelation<Related: RealtimeObject>: RealtimeProperty<Related?> {
    let options: Options
    public override var version: Int? { return _version }
    public override var raw: FireDataValue? { return _raw }
    public override var payload: [String : FireDataValue]? { return _payload }

    public required init(in node: Node?, options: [RealtimeValueOption: Any]) {
        guard let node = node else { fatalError() }
        guard case let relation as Options = options[.relation] else { fatalError("Skipped required options") }

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
        if let previousNode = oldValue??.node?.child(with: options.property) {
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
    static let representer: RealtimeValueOption = RealtimeValueOption("realtime.property.representer")
    static let initialValue: RealtimeValueOption = RealtimeValueOption("realtime.property.initialValue")
}

// TODO: Add possible update value at subpath
// TODO: Create property for storage data
// TODO: Research how can use ExpressibleByNilLiteral pattern in RP
public class RealtimeProperty<T>: _RealtimeValue, ValueWrapper, InsiderOwner, Reverting where T: HasDefaultLiteral {
    public func revert() {
        oldValue.map {
            localPropertyValue.set($0)
            resetHasChanges()
            insider.dataDidChange()
        }
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
        get { return _hasChanges }
    }

    private var localPropertyValue: PropertyValue<T>
    fileprivate var oldValue: T?
    public var value: T {
        get { return localPropertyValue.get() }
        set {
            if !hasChanges {
                oldValue = localPropertyValue.get()
                registerHasChanges()
            }
            setValue(newValue)
        }
    }
    let representer: AnyRVRepresenter<T>
    public var insider: Insider<T>
    public var lastError: Property<Error?>

    public override var version: Int? { return nil }
    public override var raw: FireDataValue? { return nil }
    public override var payload: [String : FireDataValue]? { return nil }

    internal var _version: Int? { return super.version }
    internal var _raw: FireDataValue? { return super.raw }
    internal var _payload: [String : FireDataValue]? { return super.payload }
    
    // MARK: Initializers, deinitializer
    
    public required init(in node: Node?, options: [RealtimeValueOption: Any] = [.representer: AnyRVRepresenter<T>.default]) {
        guard case let representer as AnyRVRepresenter<T> = options[.representer] else { fatalError("Bad options") }

        self.localPropertyValue = PropertyValue(options[.initialValue] as? T ?? T())
        self.insider = Insider(source: localPropertyValue.get)
        self.representer = representer
        self.lastError = Property<Error?>(value: nil)
        super.init(in: node, options: options)
    }

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
    
    public override func load(completion: Assign<(error: Error?, ref: DatabaseReference)>?) {
        super.load(completion: completion?.with(work: { (val) in
            val.error.map { self.lastError.value = $0 }
        }))
    }
    @discardableResult
    public func loadValue(completion: Assign<(error: Error?, value: T)>) -> Self {
        super.load(completion: .just { (err, _) in
            err.map { self.lastError.value = $0 }
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

    /// Property does not respond for versions and raw value, and also payload.
    /// To change value version/raw can use enum, but use modified representer.
    public override func write(to transaction: RealtimeTransaction, by node: Node) {
        super.write(to: transaction, by: node)
        do {
            transaction.addValue(try representer.encode(localPropertyValue.get()), by: node)
        } catch let e {
            fatalError(e.localizedDescription)
        }
    }
    
    // MARK: Events
    
    override public func didSave(in parent: Node, by key: String) {
        super.didSave(in: parent, by: key)
        resetHasChanges()
    }
    
    override public func didRemove(from node: Node) {
        super.didRemove(from: node)
        resetHasChanges()
        setValue(T())
    }
    
    // MARK: Changeable

    public convenience required init(fireData: FireDataProtocol) throws {
        self.init(in: fireData.dataRef.map(Node.from))
        apply(fireData)
    }

    override public func apply(_ data: FireDataProtocol, strongly: Bool) {
        super.apply(data, strongly: strongly)
        resetHasChanges()
        do {
            setValue(try representer.decode(data))
        } catch let e {
            lastError <= e
        }
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

public final class SharedProperty<T>: _RealtimeValue, ValueWrapper, InsiderOwner where T: FireDataValue, T: HasDefaultLiteral {
    private var localPropertyValue: PropertyValue<T>
    public var value: T {
        get { return localPropertyValue.get() }
        set { setValue(newValue) }
    }
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

public final class MutationPoint<T> {
    public let node: Node
    public required init(in node: Node) throws {
        guard node.isRooted else { throw RealtimeError("Node should be rooted") }
        self.node = node
    }
}
public extension MutationPoint where T: FireDataRepresented & FireDataValueRepresented {
    func set(value: T, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        let transaction = transaction ?? RealtimeTransaction()
        transaction.addValue(value.fireValue, by: node)

        return transaction
    }
    func mutate(by key: String? = nil, use value: T, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        let transaction = transaction ?? RealtimeTransaction()
        transaction.addValue(value.fireValue, by: key.map { node.child(with: $0) } ?? node.childByAutoId())

        return transaction
    }
}
public extension MutationPoint where T: FireDataValue {
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
}
extension MutationPoint {
    func removeValue(for key: String, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        let transaction = transaction ?? RealtimeTransaction()
        transaction.addValue(nil, by: node.child(with: key))

        return transaction
    }
}
