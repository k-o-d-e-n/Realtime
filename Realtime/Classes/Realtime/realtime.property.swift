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
    internal func _property<T>(from node: Node?, representer: Representer<T>) -> RealtimeProperty<T> {
        return RealtimeProperty(in: Node(key: rawValue, parent: node), options: [.representer: representer])
    }

    func readonlyProperty<T>(from node: Node?, representer: Representer<T> = .any) -> ReadonlyRealtimeProperty<T> {
        return ReadonlyRealtimeProperty(in: Node(key: rawValue, parent: node), options: [.representer: representer])
    }
    func readonlyProperty<T>(from node: Node?, representer: Representer<T> = .any) -> ReadonlyRealtimeProperty<T?> {
        return readonlyProperty(from: node, representer: representer.optional())
    }
    func property<T: FireDataValue>(from node: Node?) -> RealtimeProperty<T> {
        return _property(from: node, representer: .any)
    }
    func property<T: FireDataValue>(from node: Node?) -> RealtimeProperty<T?> {
        return RealtimeProperty(in: Node(key: rawValue, parent: node), options: [.representer: Representer<T>.any.optional()])
    }

    func `enum`<V: RawRepresentable>(from node: Node?) -> RealtimeProperty<V> {
        return _property(from: node, representer: Representer<V>.default(Representer<V.RawValue>.any))
    }
    func `enum`<V: RawRepresentable>(from node: Node?) -> RealtimeProperty<V?> {
        return _property(from: node, representer: Representer<V>.default(Representer<V.RawValue>.any).optional())
    }
    func date(from node: Node?, strategy: DateCodingStrategy = .secondsSince1970) -> RealtimeProperty<Date> {
        return _property(from: node, representer: Representer<Date>.date(strategy))
    }
    func date(from node: Node?, strategy: DateCodingStrategy = .secondsSince1970) -> RealtimeProperty<Date?> {
        return _property(from: node, representer: Representer<Date>.date(strategy).optional())
    }
    func url(from node: Node?) -> RealtimeProperty<URL> {
        return _property(from: node, representer: Representer<URL>.default)
    }
    func url(from node: Node?) -> RealtimeProperty<URL?> {
        return _property(from: node, representer: Representer<URL>.default.optional())
    }
    func codable<V: Codable>(from node: Node?) -> RealtimeProperty<V> {
        return _property(from: node, representer: Representer<V>.json)
    }
    func optionalCodable<V: Codable>(from node: Node?) -> RealtimeProperty<V?> {
        return _property(from: node, representer: Representer<V>.json.optional())
    }

    func reference<V: RealtimeObject>(from node: Node?, mode: ReferenceMode) -> RealtimeReference<V> {
        return RealtimeReference(in: Node(key: rawValue, parent: node), options: [.reference: RealtimeReference<V>.Options(mode: mode)])
    }
    func reference<V: RealtimeObject>(from node: Node?, mode: ReferenceMode) -> RealtimeReference<V?> {
        return RealtimeReference(in: Node(key: rawValue, parent: node), options: [.reference: RealtimeReference<V?>.Options(V?.self, mode: mode)])
    }
    func relation<V: RealtimeObject>(from node: Node?, rootLevelsUp: Int? = nil, ownerLevelsUp: Int = 1, _ property: RelationMode) -> RealtimeRelation<V> {
        return RealtimeRelation(in: Node(key: rawValue, parent: node),
                                options: [.relation: RealtimeRelation<V>.Options(rootLevelsUp: rootLevelsUp, ownerLevelsUp: ownerLevelsUp, property: property)])
    }
    func relation<V: RealtimeObject>(from node: Node?, rootLevelsUp: Int? = nil, ownerLevelsUp: Int = 1, _ property: RelationMode) -> RealtimeRelation<V?> {
        return RealtimeRelation(in: Node(key: rawValue, parent: node),
                                options: [.relation: RealtimeRelation.Options(V?.self, rootLevelsUp: rootLevelsUp, ownerLevelsUp: ownerLevelsUp, property: property)])
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

public final class RealtimeReference<Referenced: RealtimeValue>: RealtimeProperty<Referenced> {
    public override var version: Int? { return super._version }
    public override var raw: FireDataValue? { return super._raw }
    public override var payload: [String : FireDataValue]? { return super._payload }

    public required init(in node: Node?, options: [RealtimeValueOption : Any]) {
        guard case let o as Options = options[.reference] else { fatalError("Skipped required options") }
        super.init(in: node, options: [.representer: o.representer])
    }

    @discardableResult
    public override func setValue(_ value: Referenced, in transaction: RealtimeTransaction? = nil) throws -> RealtimeTransaction {
        guard value.isRooted else { fatalError("Value must with rooted node") }

        return try super.setValue(value, in: transaction)
    }

    override func _write(to transaction: RealtimeTransaction, by node: Node) throws {
        _write_RealtimeValue(to: transaction, by: node)
        try super._write(to: transaction, by: node)
    }

    public struct Options {
        let representer: Representer<Referenced>

        public init(mode: ReferenceMode) {
            self.representer = Representer<Referenced>.reference(mode)
        }

        public init<U: _Optional>(_: U.Type = U.self, mode: ReferenceMode) where Referenced == Optional<U.Wrapped> {
            let base = Representer<U.Wrapped>.reference(mode)
            self.representer = Representer(optional: base)
        }
    }
}

public final class RealtimeRelation<Related: RealtimeValue>: RealtimeProperty<Related> {
    var options: Options
    public override var version: Int? { return super._version }
    public override var raw: FireDataValue? { return super._raw }
    public override var payload: [String : FireDataValue]? { return super._payload }

    public required init(in node: Node?, options: [RealtimeValueOption: Any]) {
        guard let node = node else { fatalError() }
        guard case let relation as RealtimeRelation<Related>.Options = options[.relation] else { fatalError("Skipped required options") }

        self.options = relation
        super.init(in: node, options: [.representer: relation.representer])
    }

    @discardableResult
    public override func setValue(_ value: Related, in transaction: RealtimeTransaction? = nil) throws -> RealtimeTransaction {
        guard value.isRooted else { fatalError("Value must with rooted node") }

        return try super.setValue(value, in: transaction)
    }

    public override func willRemove(in transaction: RealtimeTransaction, from ancestor: Node) {
        super.willRemove(in: transaction, from: ancestor)
        guard let node = self.node, node.isRooted else {
            fatalError("Cannot get node")
        }
        removeOldValueIfExists(in: transaction, by: node)
    }

    override func _write(to transaction: RealtimeTransaction, by node: Node) throws {
        _write_RealtimeValue(to: transaction, by: node)
        try super._write(to: transaction, by: node)
        if let backwardValueNode = wrapped?.node {
            if let ownerNode = node.ancestor(onLevelUp: options.ownerLevelsUp) {
                let backwardPropertyNode = backwardValueNode.child(with: options.property.path(for: backwardValueNode))
                let thisProperty = node.path(from: ownerNode)
                let backwardRelation = Relation(path: options.rootLevelsUp.map(ownerNode.path) ?? ownerNode.rootPath, property: thisProperty)
                transaction.addValue(backwardRelation.fireValue, by: backwardPropertyNode)
            } else {
                throw RealtimeError(source: .value, description: "Cannot get owner node from levels up: \(options.ownerLevelsUp)")
            }
        }
    }

    override func _writeChanges(to transaction: RealtimeTransaction, by node: Node) throws {
        if hasChanges {
            try _write(to: transaction, by: node)
            removeOldValueIfExists(in: transaction, by: node)
        }
    }

    public override func apply(_ data: FireDataProtocol, strongly: Bool) throws {
        _apply_RealtimeValue(data, strongly: strongly)
        try super.apply(data, strongly: strongly)
    }

    private func removeOldValueIfExists(in transaction: RealtimeTransaction, by node: Node) {
        transaction.addPrecondition { [unowned transaction] (promise) in
            node.reference().observeSingleEvent(of: .value, with: { (data) in
                guard data.exists() else { return promise.fulfill(nil) }
                do {
                    let relation = try Relation(fireData: data)
                    transaction.removeValue(by: Node.root.child(with: relation.targetPath).child(with: relation.relatedProperty))
                    promise.fulfill(nil)
                } catch let e {
                    promise.fulfill(e)
                }
            }, withCancel: promise.fulfill)
        }
    }

    struct Options {
        /// Levels up by hierarchy to relation owner of this property
        let ownerLevelsUp: Int
        /// String path from related object to his relation property
        let property: RelationMode
        /// Levels up by hierarchy to the same node for both related values. Default nil, that means root node
        let rootLevelsUp: Int?
        let representer: Representer<Related>

        public init(rootLevelsUp: Int?, ownerLevelsUp: Int, property: RelationMode) {
            self.rootLevelsUp = rootLevelsUp
            self.ownerLevelsUp = ownerLevelsUp
            self.property = property
            self.representer = Representer<Related>.relation(property, rootLevelsUp: rootLevelsUp)
        }

        public init<U: _Optional>(_: U.Type = U.self, rootLevelsUp: Int?, ownerLevelsUp: Int, property: RelationMode) where Related == Optional<U.Wrapped> {
            self.rootLevelsUp = rootLevelsUp
            self.ownerLevelsUp = ownerLevelsUp
            self.property = property
            self.representer = Representer(optional: Representer<U.Wrapped>.relation(property, rootLevelsUp: rootLevelsUp))
        }
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
}
extension ListenValue: _Optional {
    public func map<U>(_ f: (T) throws -> U) rethrows -> U? {
        return try wrapped.map(f)
    }

    public func flatMap<U>(_ f: (T) throws -> U?) rethrows -> U? {
        return try wrapped.flatMap(f)
    }

    public var unsafelyUnwrapped: T {
        return wrapped!
    }

    public var wrapped: T? {
        switch self {
        case .removed, .initial: return nil
        case .local(let v): return v
        case .remote(let v, _): return v
        case .error(_, let v): return v.wrapped
        }
    }

    public typealias Wrapped = T

    public init(nilLiteral: ()) {
        self = .initial
    }
}

public extension ListenValue where T: _Optional {
    var wrapped: T.Wrapped? {
        switch self {
        case .removed, .initial: return nil
        case .local(let v): return v.wrapped
        case .remote(let v, _): return v.wrapped
        case .error(_, let v): return v.wrapped
        }
    }
    static func <==(_ value: inout T.Wrapped?, _ prop: ListenValue) {
        value = prop.wrapped
    }
}

infix operator =?
infix operator =!
public extension ListenValue {
    static func ?? (optional: ListenValue, defaultValue: @autoclosure () throws -> T) rethrows -> T {
        return try optional.wrapped ?? defaultValue()
    }
    static func ?? (optional: ListenValue, defaultValue: @autoclosure () throws -> T?) rethrows -> T? {
        return try optional.wrapped ?? defaultValue()
    }
    static func =?(_ value: inout T, _ prop: ListenValue) {
        if let v = prop.wrapped {
            value = v
        }
    }
    static func =?(_ value: inout T?, _ prop: ListenValue) {
        if let v = prop.wrapped {
            value = v
        }
    }
    static func <==(_ value: inout T?, _ prop: ListenValue) {
        value = prop.wrapped
    }
    static func =!(_ value: inout T, _ prop: ListenValue) {
        value = prop.wrapped!
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
    public func setValue(_ value: T, in transaction: RealtimeTransaction? = nil) throws -> RealtimeTransaction {
        guard let node = self.node, node.isRooted else { fatalError("Mutation cannot be do. Value is not rooted") }

        _setValue(value)
        let transaction = transaction ?? RealtimeTransaction()
        try _writeChanges(to: transaction, by: node)
        return transaction
    }

    override func _writeChanges(to transaction: RealtimeTransaction, by node: Node) throws {
        if let changed = _changedValue {
//            super._writeChanges(to: transaction, by: node)
            transaction.addReversion(currentReversion())
            transaction._addValue(updateType, try representer.encode(changed), by: node)
        }
    }

    /// Property does not respond for versions and raw value, and also payload.
    /// To change value version/raw can use enum, but use modified representer.
    override func _write(to transaction: RealtimeTransaction, by node: Node) throws {
//        super._write(to: transaction, by: node)
        switch localPropertyValue.get() {
        case .initial: break
//                if  {
//                    throw RealtimeError("Required property has not been set")
//                }
        case .error, .removed: break
        case .local(let v): transaction._addValue(updateType, try representer.encode(v), by: node)
        case .remote(let v, _): transaction._addValue(updateType, try representer.encode(v), by: node)
        }
    }

    internal func _setValue(_ value: T) {
        if !hasChanges {
            oldValue = localPropertyValue.get()
        }
        _setListenValue(.local(value))
    }
}

infix operator <==: AssignmentPrecedence
public extension RealtimeProperty {
    static func <== (_ prop: RealtimeProperty, _ value: @autoclosure () throws -> T) rethrows {
        prop._setValue(try value())
    }
}

// TODO: Need to make as wrapper
@available(*, introduced: 0.4.3)
public class ReadonlyRealtimeProperty<T>: _RealtimeValue, InsiderOwner {
    fileprivate var localPropertyValue: PropertyValue<ListenValue<T>>
    fileprivate var oldValue: ListenValue<T> = .initial
    fileprivate(set) var representer: Representer<T>
    public var insider: Insider<ListenValue<T>>

    public override var version: Int? { return nil }
    public override var raw: FireDataValue? { return nil }
    public override var payload: [String : FireDataValue]? { return nil }

    internal var _version: Int? { return super.version }
    internal var _raw: FireDataValue? { return super.raw }
    internal var _payload: [String : FireDataValue]? { return super.payload }
    
    // MARK: Initializers, deinitializer

    public convenience init(in node: Node?, representer: Representer<T>) {
        self.init(in: node, options: [.representer: representer])
    }
    
    public required init(in node: Node?, options: [RealtimeValueOption: Any] = [.representer: Representer<T>.any]) {
        guard case let representer as Representer<T> = options[.representer] else { fatalError("Bad options") }

        self.localPropertyValue = PropertyValue((options[.initialValue] as? T).map { .local($0) } ?? .initial)
        self.insider = Insider(source: localPropertyValue.get)
        self.representer = representer
        super.init(in: node, options: options)
    }
    
    public override func load(completion: Assign<Error?>?) {
        super.load(completion: completion?.with(work: { (val) in
            val.map(self.setError)
        }))
    }

    @discardableResult
    public func loadValue(completion: Assign<T>, fail: Assign<Error>) -> Self {
        let failing = fail.with(work: setError)
        super.load(completion: .just { err in
            if let e = err {
                failing.assign(e)
            } else if case .remote(let v, _) = self.lastEvent {
                completion.assign(v)
            } else if case .error(let e, _) = self.lastEvent {
                failing.assign(e)
            } else {
                failing.assign(RealtimeError(source: .value, description: "Undefined error in \(self)"))
            }
        })

        return self
    }

    internal var updateType: ValueNode.Type { return ValueNode.self }

    override func _writeChanges(to transaction: RealtimeTransaction, by node: Node) throws {
        /// readonly property cannot have changes
    }

    override func _write(to transaction: RealtimeTransaction, by node: Node) throws {
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
        try apply(fireData, strongly: true)
    }

    override public func apply(_ data: FireDataProtocol, strongly: Bool) throws {
//        super.apply(data, strongly: strongly)
        do {
            _setListenValue(.remote(try representer.decode(data), strong: strongly))
        } catch let e {
            setError(e)
            throw e
        }
    }

    internal func _setListenValue(_ value: ListenValue<T>) {
        localPropertyValue.set(value)
        insider.dataDidChange()
    }

    internal func setError(_ error: Error) {
        localPropertyValue.set(.error(error, last: localPropertyValue.get()))
        insider.dataDidChange()
    }
}
public extension ReadonlyRealtimeProperty {
    var lastEvent: ListenValue<T> {
        return localPropertyValue.get()
    }

    var wrapped: T? {
        return localPropertyValue.get().wrapped
    }
}
public extension ReadonlyRealtimeProperty {
    public func then(_ f: (T) -> Void, else e: (() -> Void)? = nil) -> ReadonlyRealtimeProperty {
        if let v = wrapped {
            f(v)
        } else {
            e?()
        }
        return self
    }
    public func `else`(_ f: () -> Void) {
        if nil == wrapped {
            f()
        }
    }
}
public extension ReadonlyRealtimeProperty {
    static func ?? (optional: ReadonlyRealtimeProperty, defaultValue: @autoclosure () throws -> T) rethrows -> T {
        return try optional.wrapped ?? defaultValue()
    }
    static func ?? (optional: ReadonlyRealtimeProperty, defaultValue: @autoclosure () throws -> T?) rethrows -> T? {
        return try optional.wrapped ?? defaultValue()
    }
    static func =?(_ value: inout T, _ prop: ReadonlyRealtimeProperty) {
        if let v = prop.wrapped {
            value = v
        }
    }
    static func <==(_ value: inout T?, _ prop: ReadonlyRealtimeProperty) {
        value = prop.wrapped
    }
}
func <== <T>(_ value: inout T?, _ prop: ReadonlyRealtimeProperty<T>?) {
    value = prop?.wrapped
}
public extension ReadonlyRealtimeProperty {
    func mapValue<U>(_ transform: (T) throws -> U) rethrows -> U? {
        return try wrapped.map(transform)
    }
    func flatMapValue<U>(_ transform: (T) throws -> U?) rethrows -> U? {
        return try wrapped.flatMap(transform)
    }
}
public extension ReadonlyRealtimeProperty where T: _Optional {
    var unwrapped: T.Wrapped? {
        return lastEvent.wrapped
    }
    static func ?? (optional: T.Wrapped?, property: ReadonlyRealtimeProperty<T>) -> T.Wrapped? {
        return optional ?? property.unwrapped
    }
    static func <==(_ value: inout T.Wrapped?, _ prop: ReadonlyRealtimeProperty) {
        value = prop.unwrapped
    }
    public func then(_ f: (T.Wrapped) -> Void, else e: (() -> Void)? = nil) -> ReadonlyRealtimeProperty {
        if let v = unwrapped {
            f(v)
        } else {
            e?()
        }
        return self
    }
    public func `else`(_ f: () -> Void) {
        if nil == wrapped {
            f()
        }
    }
}
func <== <T>(_ value: inout T.Wrapped?, _ prop: ReadonlyRealtimeProperty<T>?) where T: _Optional {
    value = prop?.unwrapped
}
public extension ReadonlyRealtimeProperty where T: HasDefaultLiteral {
    static func <==(_ value: inout T, _ prop: ReadonlyRealtimeProperty) {
        value = prop.wrapped ?? T()
    }
}
public extension ReadonlyRealtimeProperty where T: _Optional, T.Wrapped: HasDefaultLiteral {
    static func <==(_ value: inout T.Wrapped, _ prop: ReadonlyRealtimeProperty) {
        value = prop.unwrapped ?? T.Wrapped()
    }
}
infix operator ==~
public extension ReadonlyRealtimeProperty where T: Equatable {
    static func ==~(lhs: T, rhs: ReadonlyRealtimeProperty<T>) -> Bool {
        return rhs.mapValue { $0 == lhs } ?? false
    }
}
public extension ReadonlyRealtimeProperty where T: HasDefaultLiteral & _ComparableWithDefaultLiteral {
    static func <==(_ value: inout T, _ prop: ReadonlyRealtimeProperty) {
        value = prop.wrapped ?? T()
    }
    func defaultOnEmpty() -> Self {
        self.representer = self.representer.defaultOnEmpty()
        return self
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
        try apply(fireData, strongly: true)
    }

    override public func apply(_ data: FireDataProtocol, strongly: Bool) throws {
        try super.apply(data, strongly: strongly)
        setValue(try representer.decode(data))
    }

    fileprivate func setValue(_ value: T) {
        localPropertyValue.set(value)
        insider.dataDidChange()
    }
}

public extension SharedProperty {
    public func changeValue(use changing: @escaping (T) throws -> T, completion: ((Bool, T) -> Void)? = nil) {
        guard let ref = dbRef else  {
            fatalError("Can`t get database reference")
        }
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
                do {
                    self.setValue(try self.representer.decode(s))
                    completion?(true, self.value)
                } catch {
                    completion?(false, self.value)
                }
            } else {
                debugFatalError("Transaction completed without error, but snapshot does not exist")

                completion?(false, self.value)
            }
        })
    }
}

public final class MutationPoint<T> {
    public let node: Node
    public required init(in node: Node) {
        guard node.isRooted else { fatalError("Node must be rooted") }
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
