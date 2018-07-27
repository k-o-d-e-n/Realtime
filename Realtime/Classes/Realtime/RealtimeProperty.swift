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
    func readonlyProperty<T>(from node: Node?, representer: Representer<T> = .any) -> ReadonlyRealtimeProperty<T> {
        return ReadonlyRealtimeProperty(in: Node(key: rawValue, parent: node), options: [.representer: representer])
    }
    func readonlyProperty<T>(from node: Node?, representer: Representer<T> = .any) -> ReadonlyRealtimeProperty<T?> {
        return readonlyProperty(from: node, representer: representer.optional())
    }
    func property<T>(from node: Node?, representer: Representer<T> = .any) -> RealtimeProperty<T> {
        return RealtimeProperty(in: Node(key: rawValue, parent: node), options: [.representer: representer])
    }
    func property<T: _Optional>(from node: Node?, representer: Representer<T> = .any) -> RealtimeProperty<T?> {
        return property(from: node, representer: representer.optional())
    }

    func `enum`<V: RawRepresentable>(from node: Node?) -> RealtimeProperty<V> {
        return property(from: node, representer: Representer<V>.default(Representer<V.RawValue>.any))
    }
    func `enum`<V: RawRepresentable>(from node: Node?) -> RealtimeProperty<V?> {
        return property(from: node, representer: Representer<V>.default(Representer<V.RawValue>.any).optional())
    }
    func date(from node: Node?, strategy: DateCodingStrategy = .secondsSince1970) -> RealtimeProperty<Date> {
        return property(from: node, representer: Representer<Date>.date(strategy))
    }
    func date(from node: Node?, strategy: DateCodingStrategy = .secondsSince1970) -> RealtimeProperty<Date?> {
        return property(from: node, representer: Representer<Date>.date(strategy).optional())
    }
    func url(from node: Node?) -> RealtimeProperty<URL> {
        return property(from: node, representer: Representer<URL>.default)
    }
    func url(from node: Node?) -> RealtimeProperty<URL?> {
        return property(from: node, representer: Representer<URL>.default.optional())
    }
    func codable<V: Codable>(from node: Node?) -> RealtimeProperty<V> {
        return property(from: node, representer: Representer<V>.json)
    }
    func codable<V: Codable>(from node: Node?) -> RealtimeProperty<V?> {
        return property(from: node, representer: Representer<V>.json.optional())
    }

    func reference<V: RealtimeValue>(from node: Node?, mode: RealtimeReference<V>.Mode) -> RealtimeReference<V> {
        return RealtimeReference(in: Node(key: rawValue, parent: node), options: [.reference: mode])
    }
    func optionalReference<V: RealtimeValue>(from node: Node?, mode: RealtimeReference<V>.Mode) -> RealtimeReference<V> {
        return RealtimeReference(in: Node(key: rawValue, parent: node), options: [.reference: mode])
    }
    func relation<V: RealtimeObject, Property: RawRepresentable>(from node: Node?, ownerLevelsUp: Int = 1, _ property: Property) -> RealtimeRelation<V> where Property.RawValue == String {
        return RealtimeRelation(in: Node(key: rawValue, parent: node),
                                options: [.relation: RealtimeRelation<V>.Options(ownerLevelsUp: ownerLevelsUp, property: property.rawValue)])
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
        super.init(in: node, options: [.representer: Representer.reference(mode).optional()])
    }

    override func _write(to transaction: RealtimeTransaction, by node: Node) {
        _write_RealtimeValue(to: transaction, by: node)
        super.write(to: transaction, by: node)
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
        super.init(in: node, options: [.representer: Representer<Related>.relation(relation.property).optional()])
    }

    public override func willRemove(in transaction: RealtimeTransaction, from ancestor: Node) {
        super.willRemove(in: transaction, from: ancestor)
        transaction.addPrecondition { [unowned transaction] (promise) in
            self.loadValue(
                completion: .just({ (val) in
                    if let node = val?.node?.child(with: self.options.property) {
                        transaction.removeValue(by: node)
                    }
                    promise.fulfill(nil)
                }),
                fail: .just(promise.fulfill)
            )
        }
    }

    override func _write(to transaction: RealtimeTransaction, by node: Node) {
        _write_RealtimeValue(to: transaction, by: node)
        super._write(to: transaction, by: node)
        if let backwardNode = unwrapped?.node?.child(with: options.property) {
            let ownerNode = node.ancestor(on: options.ownerLevelsUp)!
            let thisProperty = node.path(from: ownerNode)
            let backwardRelation = Relation(path: ownerNode.rootPath, property: thisProperty)
            transaction.addValue(backwardRelation.fireValue, by: backwardNode)
        }
        if let previousNode = oldValue.unwrapped?.node?.child(with: options.property) {
            transaction.removeValue(by: previousNode)
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

public enum ListenValue<T> {
    case initial // none(reverted: Bool)
    case removed
    case local(T)
    case remote(T, strong: Bool) // remote(T, reverted: Bool)
    indirect case error(Error, last: ListenValue<T>)
//    case reverted(T)

    public var value: T? {
        switch self {
        case .removed, .initial: return nil
        case .local(let v): return v
        case .remote(let v, _): return v
        case .error(_, let v): return v.value
        }
    }
}
extension ListenValue: _Optional {
    public func map<U>(_ f: (T) throws -> U) rethrows -> U? {
        return try value.map(f)
    }

    public func flatMap<U>(_ f: (T) throws -> U?) rethrows -> U? {
        return try value.flatMap(f)
    }

    public var isNone: Bool {
        fatalError()
    }

    public var isSome: Bool {
        fatalError()
    }

    public var unsafelyUnwrapped: T {
        return value!
    }

    public typealias Wrapped = T

    public init(nilLiteral: ()) {
        self = .initial
    }
}

extension ListenValue where T: _Optional {
    public var unwrapped: T.Wrapped? {
        switch self {
        case .removed, .initial: return nil
        case .local(let v): return v.unsafelyUnwrapped
        case .remote(let v, _): return v.unsafelyUnwrapped
        case .error(_, let v): return v.unwrapped
        }
    }
}

infix operator =?
infix operator =!
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
    static func =!(_ value: inout T, _ prop: ListenValue) {
        value = prop.value!
    }
}

public class RealtimeProperty<T>: ReadonlyRealtimeProperty<T>, ChangeableRealtimeValue, WritableRealtimeValue, Reverting {
    internal var _changedValue: T? {
        switch localPropertyValue.get() {
        case .local(let v): return v
        case .remote, .error, .initial, .removed: return nil
        }
    }
    override var _hasChanges: Bool { return _changedValue != nil }

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

    @discardableResult
    public func setValue(_ value: T, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        guard let node = self.node, node.isRooted else { fatalError("Mutation cannot be do. Value is not rooted") }

        _setValue(value)
        let transaction = transaction ?? RealtimeTransaction()
        _writeChanges(to: transaction, by: node)
        return transaction
    }

    override func _writeChanges(to transaction: RealtimeTransaction, by node: Node) {
        if let changed = _changedValue {
//            super._writeChanges(to: transaction, by: node)
            transaction.addReversion(currentReversion())
            do { transaction._addValue(try representer.encode(changed), by: node) }
            catch let e { fatalError(e.localizedDescription) }
        }
    }

    /// Property does not respond for versions and raw value, and also payload.
    /// To change value version/raw can use enum, but use modified representer.
    override func _write(to transaction: RealtimeTransaction, by node: Node) {
//        super._write(to: transaction, by: node)
        do {
            switch localPropertyValue.get() {
            case .initial: break
//                if  {
//                    throw RealtimeError("Required property has not been set")
//                }
            case .error, .removed: break
            case .local(let v): transaction._addValue(try representer.encode(v), by: node)
            case .remote(let v, _): transaction._addValue(try representer.encode(v), by: node)
            }
        } catch let e {
            fatalError(e.localizedDescription)
        }
    }

    internal func _setValue(_ value: T) {
        if !hasChanges {
            oldValue = localPropertyValue.get()
        }
        _setListenValue(.local(value))
    }
}
public extension RealtimeProperty {
    static func <=(_ prop: inout RealtimeProperty, _ value: T) {
        prop._setValue(value)
    }
}

// TODO: Need to make as wrapper
@available(*, introduced: 0.4.3)
public class ReadonlyRealtimeProperty<T>: _RealtimeValue, InsiderOwner {
    fileprivate var localPropertyValue: PropertyValue<ListenValue<T>>
    fileprivate var oldValue: ListenValue<T> = .initial
    let representer: Representer<T>
    public var insider: Insider<ListenValue<T>>

    public override var version: Int? { return nil }
    public override var raw: FireDataValue? { return nil }
    public override var payload: [String : FireDataValue]? { return nil }

    internal var _version: Int? { return super.version }
    internal var _raw: FireDataValue? { return super.raw }
    internal var _payload: [String : FireDataValue]? { return super.payload }
    
    // MARK: Initializers, deinitializer

    convenience init(in node: Node?, representer: Representer<T>) {
        self.init(in: node, options: [.representer: representer])
    }
    
    public required init(in node: Node?, options: [RealtimeValueOption: Any] = [.representer: Representer<T>.any]) {
        guard case let representer as Representer<T> = options[.representer] else { fatalError("Bad options") }

        self.localPropertyValue = PropertyValue((options[.initialValue] as? T).map { .local($0) } ?? .initial)
        self.insider = Insider(source: localPropertyValue.get)
        self.representer = representer
        super.init(in: node, options: options)
    }
    
    public override func load(completion: Assign<(error: Error?, ref: DatabaseReference)>?) {
        super.load(completion: completion?.with(work: { (val) in
            val.error.map(self.setError)
        }))
    }

    @discardableResult
    public func loadValue(completion: Assign<T>, fail: Assign<Error>) -> Self {
        let failing = fail.with(work: setError)
        super.load(completion: .just { (err, _) in
            if let e = err {
                failing.assign(e)
            } else if let v = self._value {
                completion.assign(v)
            } else {
                failing.assign(RealtimeError("Fail"))
            }
        })

        return self
    }

    override func _writeChanges(to transaction: RealtimeTransaction, by node: Node) {
        /// readonly property cannot have changes
    }

    override func _write(to transaction: RealtimeTransaction, by node: Node) {
        /// readonly property cannot write something
    }
    
    // MARK: Events
    
    override public func didSave(in parent: Node, by key: String) {
        super.didSave(in: parent, by: key)
        if case .local(let v) = localPropertyValue.get() {
            _setListenValue(.remote(v, strong: true))
        }
    }
    
    override public func didRemove(from node: Node) {
        super.didRemove(from: node)
        _setListenValue(.removed)
    }
    
    // MARK: Changeable

    public convenience required init(fireData: FireDataProtocol) throws {
        self.init(in: fireData.dataRef.map(Node.from))
        apply(fireData)
    }

    override public func apply(_ data: FireDataProtocol, strongly: Bool) {
        super.apply(data, strongly: strongly)
        do {
            _setListenValue(.remote(try representer.decode(data), strong: strongly))
        } catch let e {
            setError(e)
        }
    }

    fileprivate func _setListenValue(_ value: ListenValue<T>) {
        localPropertyValue.set(value)
        insider.dataDidChange()
    }

    private func setError(_ error: Error) {
        localPropertyValue.set(.error(error, last: localPropertyValue.get()))
        insider.dataDidChange()
    }
}

public extension ReadonlyRealtimeProperty {
    var lastEvent: ListenValue<T> {
        return localPropertyValue.get()
    }

    func value() throws -> T {
        switch localPropertyValue.get() {
        case .initial: throw RealtimeError("Value has not been recevied yet")
        case .local(let v): return v
        case .remote(let v, _): return v
        case .error(let e, _): throw e
        case .removed: throw RealtimeError("Value has been removed")
        }
    }

    internal var _value: T? {
        return localPropertyValue.get().value
    }
}
extension ReadonlyRealtimeProperty {
    public func then(_ f: (T) -> Void) {
        if let v = localPropertyValue.get().value {
            f(v)
        }
    }
}
public extension ReadonlyRealtimeProperty {
    static func =?(_ value: inout T, _ prop: ReadonlyRealtimeProperty) {
        if let v = prop._value {
            value = v
        }
    }
    static func <=(_ value: inout T?, _ prop: ReadonlyRealtimeProperty) {
        value = prop._value
    }
}
public extension ReadonlyRealtimeProperty {
    func mapValue<U>(_ transform: (T) throws -> U) rethrows -> U? {
        return try _value.map(transform)
    }
    func flatMapValue<U>(_ transform: (T) throws -> U?) rethrows -> U? {
        return try _value.flatMap(transform)
    }
}
public extension ReadonlyRealtimeProperty where T: _Optional {
    var unwrapped: T.Wrapped? {
        return lastEvent.unwrapped
    }
    static func <=(_ value: inout T.Wrapped?, _ prop: ReadonlyRealtimeProperty) {
        value = prop.unwrapped
    }
}

// TODO: Reconsider usage it. Some RealtimeValue things are not need here.
public final class SharedProperty<T>: _RealtimeValue, InsiderOwner where T: FireDataValue & HasDefaultLiteral {
    private var localPropertyValue: PropertyValue<T>
    public var value: T { return localPropertyValue.get() }
    public var insider: Insider<T>
    let representer: Representer<T> = .any

    // MARK: Initializers, deinitializer

    public required init(in node: Node?, options: [RealtimeValueOption: Any]) {
        self.localPropertyValue = PropertyValue(T())
        self.insider = Insider(source: localPropertyValue.get)
        super.init(in: node, options: options)
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
        transaction.removeValue(by: node.child(with: key))

        return transaction
    }
}
