//
//  Property.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 18/02/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation
import FirebaseDatabase

public extension RawRepresentable where Self.RawValue == String {
    internal func property<T>(in object: Object, representer: Representer<T>) -> Property<T> {
        return Property(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .representer: representer.requiredProperty()
            ]
        )
    }
    internal func property<T>(in object: Object, representer: Representer<T>) -> Property<T?> {
        return Property(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .representer: representer.optionalProperty()
            ]
        )
    }

    func readonlyProperty<T: RealtimeDataValue>(in object: Object, representer: Representer<T> = .any) -> ReadonlyProperty<T> {
        return ReadonlyProperty(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .representer: representer.requiredProperty()
            ]
        )
    }
    func readonlyProperty<T: RealtimeDataValue>(in object: Object, representer: Representer<T> = .any) -> ReadonlyProperty<T?> {
        return ReadonlyProperty(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .representer: representer.optionalProperty()
            ]
        )
    }
    func property<T: RealtimeDataValue>(in obj: Object) -> Property<T> {
        return property(in: obj, representer: .any)
    }
    func property<T: RealtimeDataValue>(in obj: Object) -> Property<T?> {
        return Property(
            in: Node(key: rawValue, parent: obj.node),
            options: [
                .database: obj.database as Any,
                .representer: Representer<T>.any.optionalProperty()
            ]
        )
    }

    func `enum`<V: RawRepresentable>(in object: Object, rawRepresenter: Representer<V.RawValue> = .any) -> Property<V> {
        return property(in: object, representer: Representer<V>.default(rawRepresenter))
    }
    func `enum`<V: RawRepresentable>(in object: Object, rawRepresenter: Representer<V.RawValue> = .any) -> Property<V?> {
        return property(in: object, representer: Representer<V>.default(rawRepresenter))
    }
    func date(in object: Object, strategy: DateCodingStrategy = .secondsSince1970) -> Property<Date> {
        return property(in: object, representer: Representer<Date>.date(strategy))
    }
    func date(in object: Object, strategy: DateCodingStrategy = .secondsSince1970) -> Property<Date?> {
        return property(in: object, representer: Representer<Date>.date(strategy))
    }
    func url(in object: Object) -> Property<URL> {
        return property(in: object, representer: Representer<URL>.default)
    }
    func url(in object: Object) -> Property<URL?> {
        return property(in: object, representer: Representer<URL>.default)
    }
    func codable<V: Codable>(in object: Object) -> Property<V> {
        return property(in: object, representer: Representer<V>.json())
    }
    func optionalCodable<V: Codable>(in object: Object) -> Property<V?> {
        return property(in: object, representer: Representer<V>.json())
    }

    func reference<V: Object>(in object: Object, mode: ReferenceMode, options: [ValueOption: Any] = [:]) -> Reference<V> {
        return Reference(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .reference: Reference<V>.Mode.required(mode, options: options)
            ]
        )
    }
    func reference<V: Object>(in object: Object, mode: ReferenceMode, options: [ValueOption: Any] = [:]) -> Reference<V?> {
        return Reference(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .reference: Reference<V?>.Mode.optional(mode, options: options)
            ]
        )
    }
    func relation<V: Object>(in object: Object, rootLevelsUp: UInt? = nil, ownerLevelsUp: UInt = 1, _ property: RelationMode) -> Relation<V> {
        return Relation(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .relation: Relation<V>.Options.required(
                    rootLevelsUp: rootLevelsUp,
                    ownerLevelsUp: ownerLevelsUp,
                    property: property
                )
            ]
        )
    }
    func relation<V: Object>(in object: Object, rootLevelsUp: UInt? = nil, ownerLevelsUp: UInt = 1, _ property: RelationMode) -> Relation<V?> {
        return Relation(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .relation: Relation<V?>.Options.optional(
                    rootLevelsUp: rootLevelsUp,
                    ownerLevelsUp: ownerLevelsUp,
                    property: property
                )
            ]
        )
    }

    func nested<Type: Object>(in object: Object, options: [ValueOption: Any] = [:]) -> Type {
        let property = Type(
            in: Node(key: rawValue, parent: object.node),
            options: options.merging([.database: object.database as Any], uniquingKeysWith: { _, new in new })
        )
        property.parent = object
        return property
    }
}

public extension ValueOption {
    static let relation = ValueOption("realtime.relation")
    static let reference = ValueOption("realtime.reference")
}

/// Defines read/write property where value is Realtime database reference
public final class Reference<Referenced: RealtimeValue & _RealtimeValueUtilities>: Property<Referenced> {
    public override var raw: RealtimeDataValue? { return super._raw }
    public override var payload: [String : RealtimeDataValue]? { return super._payload }

    public required init(in node: Node?, options: [ValueOption : Any]) {
        guard case let o as Mode = options[.reference] else { fatalError("Skipped required options") }
        super.init(in: node, options: options.merging([.representer: o.representer], uniquingKeysWith: { _, new in new }))
    }

    required public init(data: RealtimeDataProtocol, exactly: Bool) throws {
        fatalError("init(data:strongly:) cannot be called. Use combination init(in:options:) and apply(_:exactly:) instead")
    }

    @discardableResult
    public override func setValue(_ value: Referenced, in transaction: Transaction? = nil) throws -> Transaction {
        guard Referenced._isValid(asReference: value) else { fatalError("Value must with rooted node") }

        return try super.setValue(value, in: transaction)
    }

    public override func apply(_ data: RealtimeDataProtocol, exactly: Bool) throws {
        try _apply_RealtimeValue(data, exactly: exactly)
        try super.apply(data, exactly: exactly)
    }

    override func _write(to transaction: Transaction, by node: Node) throws {
        _write_RealtimeValue(to: transaction, by: node)
        try super._write(to: transaction, by: node)
    }

    public struct Mode {
        let representer: Representer<Referenced?>

        public static func required(_ mode: ReferenceMode, options: [ValueOption: Any]) -> Mode {
            return Mode(representer: Representer.reference(mode, options: options).requiredProperty())
        }

        public static func optional<U: RealtimeValue>(_ mode: ReferenceMode, options: [ValueOption: Any]) -> Mode where Referenced == Optional<U> {
            return Mode(representer: Representer.reference(mode, options: options).optionalProperty())
        }
    }

    public static func readonly(in node: Node?, mode: Mode) -> ReadonlyProperty<Referenced> {
        return ReadonlyProperty(in: node, options: [.representer: mode.representer])
    }
}

/// Defines read/write property where value is Realtime database relation
public final class Relation<Related: RealtimeValue & _RealtimeValueUtilities>: Property<Related> {
    var options: Options
    public override var raw: RealtimeDataValue? { return super._raw }
    public override var payload: [String : RealtimeDataValue]? { return super._payload }

    public required init(in node: Node?, options: [ValueOption: Any]) {
        guard case let relation as Relation<Related>.Options = options[.relation] else { fatalError("Skipped required options") }

        self.options = relation

        if let ownerNode = node?.ancestor(onLevelUp: self.options.ownerLevelsUp) {
            self.options.ownerNode.value = ownerNode
        }

        super.init(in: node, options: options.merging([.representer: relation.representer], uniquingKeysWith: { _, new in new }))
    }

    required public init(data: RealtimeDataProtocol, exactly: Bool) throws {
        fatalError("init(data:strongly:) cannot be called. Use combination init(in:options:) and apply(_:exactly:) instead")
    }

    @discardableResult
    public override func setValue(_ value: Related, in transaction: Transaction? = nil) throws -> Transaction {
        guard Related._isValid(asRelation: value) else { fatalError("Value must with rooted node") }

        return try super.setValue(value, in: transaction)
    }

    public override func willRemove(in transaction: Transaction, from ancestor: Node) {
        super.willRemove(in: transaction, from: ancestor)
        guard let node = self.node, node.isRooted else {
            fatalError("Cannot get node")
        }
        removeOldValueIfExists(in: transaction, by: node)
    }

    override func _write(to transaction: Transaction, by node: Node) throws {
        _write_RealtimeValue(to: transaction, by: node)
        if let ownerNode = node.ancestor(onLevelUp: options.ownerLevelsUp) {
            options.ownerNode.value = ownerNode
            try super._write(to: transaction, by: node)
            if let backwardValueNode = wrapped?.node {
                let backwardPropertyNode = backwardValueNode.child(with: options.property.path(for: ownerNode))
                let thisProperty = node.path(from: ownerNode)
                let backwardRelation = RelationRepresentation(
                    path: options.rootLevelsUp.map(ownerNode.path) ?? ownerNode.absolutePath,
                    property: thisProperty,
                    payload: (nil, nil) // fixme: stub
                )
                transaction.addValue(try backwardRelation.defaultRepresentation(), by: backwardPropertyNode)
            }
        } else {
            throw RealtimeError(source: .value, description: "Cannot get owner node from levels up: \(options.ownerLevelsUp)")
        }
    }

    override func _writeChanges(to transaction: Transaction, by node: Node) throws {
        if hasChanges {
            try _write(to: transaction, by: node)
            transaction.addReversion(currentReversion())
            removeOldValueIfExists(in: transaction, by: node)
        }
    }

    public override func apply(_ data: RealtimeDataProtocol, exactly: Bool) throws {
        try _apply_RealtimeValue(data, exactly: exactly)
        try super.apply(data, exactly: exactly)
    }

    private func removeOldValueIfExists(in transaction: Transaction, by node: Node) {
        let options = self.options
        transaction.addPrecondition { [unowned transaction] (promise) in
            transaction.database.load(
                for: node,
                timeout: .seconds(10),
                completion: { data in
                    guard data.exists() else { return promise.fulfill() }
                    do {
                        if let ownerNode = node.ancestor(onLevelUp: options.ownerLevelsUp) {
                            let anchorNode = options.rootLevelsUp.flatMap(ownerNode.ancestor) ?? .root
                            let relation = try RelationRepresentation(data: data)
                            transaction.removeValue(by: anchorNode.child(with: relation.targetPath).child(with: relation.relatedProperty))
                            promise.fulfill()
                        } else {
                            throw RealtimeError(source: .value, description: "Cannot get owner node from levels up: \(options.ownerLevelsUp)")
                        }
                    } catch let e {
                        promise.reject(e)
                    }
                },
                onCancel: { e in
                    promise.reject(RealtimeError(external: e, in: .value))
                }
            )
        }
    }

    public struct Options {
        /// Levels up by hierarchy to relation owner of this property
        let ownerLevelsUp: UInt
        /// String path from related object to his relation property
        let property: RelationMode
        /// Levels up by hierarchy to the same node for both related values. Default nil, that means root node
        let rootLevelsUp: UInt?

        let ownerNode: ValueStorage<Node?>
        let representer: Representer<Related?>

        public static func required(rootLevelsUp: UInt?, ownerLevelsUp: UInt, property: RelationMode) -> Options {
            let ownerNode = ValueStorage<Node?>.unsafe(strong: nil)
            return Options(
                ownerLevelsUp: ownerLevelsUp,
                property: property,
                rootLevelsUp: rootLevelsUp,
                ownerNode: ownerNode,
                representer: Representer.relation(property, rootLevelsUp: rootLevelsUp, ownerNode: ownerNode).requiredProperty()
            )
        }

        public static func optional<U>(rootLevelsUp: UInt?, ownerLevelsUp: UInt, property: RelationMode) -> Options where Related == Optional<U> {
            let ownerNode = ValueStorage<Node?>.unsafe(strong: nil)
            return Options(
                ownerLevelsUp: ownerLevelsUp,
                property: property,
                rootLevelsUp: rootLevelsUp,
                ownerNode: ownerNode,
                representer: Representer.relation(property, rootLevelsUp: rootLevelsUp, ownerNode: ownerNode).optionalProperty()
            )
        }
    }

    public override var debugDescription: String {
        return """
        \(type(of: self)): \(String(ObjectIdentifier(self).hashValue, radix: 16)) {
            ref: \(node?.debugDescription ?? "not referred"),
            keepSynced: \(keepSynced),
            value:
                \(_value as Any)
        }
        """
    }

    public static func readonly(in node: Node?, config: Options) -> ReadonlyProperty<Related> {
        return ReadonlyProperty(in: node, options: [.representer: config.representer])
    }
}

// MARK: Listenable realtime property

public extension ValueOption {
    static let representer: ValueOption = ValueOption("realtime.property.representer")
    static let initialValue: ValueOption = ValueOption("realtime.property.initialValue")
}

public enum PropertyState<T> {
    case local(T)
    case remote(T)
    case removed(local: Bool)
    indirect case error(Error, last: PropertyState<T>?)
    //        case reverted(ListenValue<T>?)
}
extension PropertyState: _Optional {
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
        case .removed: return nil
        case .local(let v): return v
        case .remote(let v): return v
        case .error(_, let v): return v?.wrapped
        }
    }

    public var error: Error? {
        switch self {
        case .error(let e, _): return e
        default: return nil
        }
    }

    public typealias Wrapped = T

    public init(nilLiteral: ()) {
        self = .removed(local: true)
    }

    internal var lastNonError: PropertyState<T>? {
        switch self {
        case .error(_, let last): return last?.lastNonError
        default: return self
        }
    }
}
public extension PropertyState where T: _Optional {
    var wrapped: T.Wrapped? {
        switch self {
        case .removed: return nil
        case .local(let v): return v.wrapped
        case .remote(let v): return v.wrapped
        case .error(_, let v): return v?.wrapped
        }
    }
    static func <==(_ value: inout T.Wrapped?, _ prop: PropertyState<T>) {
        value = prop.wrapped
    }
}
extension PropertyState: Equatable where T: Equatable {
    public static func ==(lhs: PropertyState<T>, rhs: PropertyState<T>) -> Bool {
        switch (lhs, rhs) {
        case (.removed(let lhs), .removed(let rhs)): return lhs == rhs
        case (.local(let lhs), .local(let rhs)): return lhs == rhs
        case (.remote(let lhs), .remote(let rhs)): return lhs == rhs
        default: return false
        }
    }
}

infix operator =?
infix operator =!
public extension PropertyState {
    static func ?? (optional: PropertyState<T>, defaultValue: @autoclosure () throws -> T) rethrows -> T {
        return try optional.wrapped ?? defaultValue()
    }
    static func ?? (optional: PropertyState<T>, defaultValue: @autoclosure () throws -> T?) rethrows -> T? {
        return try optional.wrapped ?? defaultValue()
    }
    static func =?(_ value: inout T, _ prop: PropertyState<T>) {
        if let v = prop.wrapped {
            value = v
        }
    }
    static func =?(_ value: inout T?, _ prop: PropertyState<T>) {
        if let v = prop.wrapped {
            value = v
        }
    }
    static func <==(_ value: inout T?, _ prop: PropertyState<T>) {
        value = prop.wrapped
    }
    static func =!(_ value: inout T, _ prop: PropertyState<T>) {
        value = prop.wrapped!
    }
}

public typealias WriteRequiredProperty<T> = Property<T!>
public typealias OptionalProperty<T> = Property<T?>

/// Defines read/write property with any value
public class Property<T>: ReadonlyProperty<T>, ChangeableRealtimeValue, WritableRealtimeValue, Reverting {
    fileprivate var oldValue: PropertyState<T>?
    internal var _changedValue: T? {
        switch _value {
        case .some(.local(let v)): return v
        case .none, .some(.remote), .some(.error), .some(.removed): return nil
        }
    }
    override var _hasChanges: Bool { return _changedValue != nil }

    public func revert() {
        guard hasChanges else { return }

        _value = oldValue
    }
    public func currentReversion() -> () -> Void {
        return { [weak self] in
            self?.revert()
        }
    }

    /// Writes new value to property using passed transaction
    ///
    /// - Parameters:
    ///   - value: New value
    ///   - transaction: Current write transaction
    /// - Returns: Passed or created transaction
    /// - Throws: If value cannot represented using property representer
    @discardableResult
    public func setValue(_ value: T, in transaction: Transaction? = nil) throws -> Transaction {
        guard let node = self.node, node.isRooted, let database = self.database else { fatalError("Mutation cannot be done. Value is not rooted") }

        _setLocalValue(value)
        let transaction = transaction ?? Transaction(database: database)
        try _writeChanges(to: transaction, by: node)
        transaction.addCompletion { (result) in
            if result {
                self.didSave(in: database)
            }
        }
        return transaction
    }

    public func change(_ using: (T?) -> T) {
        _setLocalValue(using(wrapped))
    }

    public func remove() {
        _setRemoved(isLocal: true)
    }

    public override func didSave(in database: RealtimeDatabase, in parent: Node, by key: String) {
        super.didSave(in: database, in: parent, by: key)
        debugAction {
            if _value == nil {
                do {
                    /// test required property
                    _ = try representer.encode(nil)
                } catch {
                    debugFatalError("Required property '\(key)': \(type(of: self)) has been saved, but value does not exists")
                }
            }
        }
    }

    internal func cacheValue(_ node: Node, value: Any?) -> CacheNode {
        return .value(ValueNode(node: node, value: value))
    }

    override func _writeChanges(to transaction: Transaction, by node: Node) throws {
        if let changed = _changedValue {
            /// skip the call of super (_RealtimeValue)
            _addReversion(to: transaction, by: node)
            try transaction._addValue(cacheValue(node, value: representer.encode(changed)))
        }
    }

    /// Property does not respond for versions and raw value, and also payload.
    /// To change value version/raw can use enum, but use modified representer.
    override func _write(to transaction: Transaction, by node: Node) throws {
        /// skip the call of super (_RealtimeValue)
        switch _value {
        case .none:
            /// throws error if property required
            /// does not add to transaction with consideration about empty node to save operation
            /// otherwise need to use update operation
            do {
                _ = try representer.encode(nil)
            } catch let e {
                debugFatalError("Required property has not been set '\(node)': \(type(of: self))")
                throw e
            }
        case .some(.local(let v)):
            _addReversion(to: transaction, by: node)
            try transaction._addValue(cacheValue(node, value: representer.encode(v)))
        default:
            debugFatalError("Unexpected behavior")
            throw RealtimeError(encoding: T.self, reason: "Unexpected state for current operation")
        }
    }

    internal func _addReversion(to transaction: Transaction, by node: Node) {
        transaction.addReversion(currentReversion())
    }

    internal func _setLocalValue(_ value: T) {
        if !hasChanges {
            oldValue = _value
        }
        _setValue(.local(value))
    }

    override func _setRemoved(isLocal: Bool) {
        if isLocal && !hasChanges {
            oldValue = _value
        }
        super._setRemoved(isLocal: isLocal)
    }
}

infix operator <==: AssignmentPrecedence
public extension Property {
    static func <== (_ prop: Property, _ value: @autoclosure () throws -> T) rethrows {
        prop._setLocalValue(try value())
    }
}

/// Defines readonly property with any value
@available(*, introduced: 0.4.3)
public class ReadonlyProperty<T>: _RealtimeValue, RealtimeValueActions {
    fileprivate var _value: PropertyState<T>?
    fileprivate let repeater: Repeater<PropertyState<T>> = Repeater.unsafe()
    fileprivate(set) var representer: Representer<T?>

    internal var _raw: RealtimeDataValue? { return super.raw }
    internal var _payload: [String : RealtimeDataValue]? { return super.payload }

    public override var raw: RealtimeDataValue? { return nil }
    public override var payload: [String : RealtimeDataValue]? { return nil }

    public var keepSynced: Bool = false {
        didSet {
            guard oldValue != keepSynced else { return }
            if keepSynced { runObserving() }
            else { stopObserving() }
        }
    }
    
    // MARK: Initializers, deinitializer

    public convenience init<U>(in node: Node?, representer: Representer<U>, options: [ValueOption: Any] = [:]) {
        self.init(in: node, options: options.merging([.representer: representer.requiredProperty()], uniquingKeysWith: { _, new in new }))
    }

    public convenience init<U>(in node: Node?, representer: Representer<U>, options: [ValueOption: Any] = [:]) where Optional<U> == T {
        self.init(in: node, options: options.merging([.representer: representer.optionalProperty()], uniquingKeysWith: { _, new in new }))
    }

    public convenience init<U>(in node: Node?, representer: Representer<U>, options: [ValueOption: Any] = [:]) where ImplicitlyUnwrappedOptional<U> == T {
        self.init(in: node, options: options.merging([.representer: representer.writeRequiredProperty()], uniquingKeysWith: { _, new in new }))
    }
    
    /// Designed initializer
    ///
    /// Available options:
    /// - .initialValue *(optional)* - default property value
    /// - .representer *(required)* - instance of type `Representer<T>`.
    ///
    /// **Warning**: You must pass representer that returns through next methods of `Representer<T>`:
    /// - func requiredProperty() - throws error if value is not presented
    /// - func optionalProperty() - can have empty value
    /// - func writeRequiredProperty() - throws error in save operation if value is not set
    ///
    /// - Parameters:
    ///   - node: Database node reference
    ///   - options: Option values
    public required init(in node: Node?, options: [ValueOption: Any]) {
        guard case let representer as Representer<T?> = options[.representer] else { fatalError("Bad options") }

        if let inital = options[.initialValue], let v = inital as? T {
            self._value = .local(v)
        }
        self.representer = representer
        super.init(in: node, options: options)
    }

    public required init(data: RealtimeDataProtocol, exactly: Bool) throws {
        #if DEBUG
        fatalError("init(data:exactly:) cannot be called. Use combination init(in:options:) and apply(_:exactly:) instead")
        #else
        throw RealtimeError(decoding: type(of: self).self, data, reason: "Unavailable initializer")
        #endif
    }
    
    public override func load(timeout: DispatchTimeInterval = .seconds(10), completion: Assign<Error?>?) {
        super.load(
            timeout: timeout,
            completion: Assign.just({ (err) in
                if let e = err {
                    switch e {
                    case _ as RealtimeError: break
                    default: self._setError(e)
                    }
                }
            })
            .with(work: completion)
        )
    }

    @discardableResult
    public func runObserving() -> Bool {
        return _runObserving(.value)
    }

    public func stopObserving() {
        if !keepSynced || (observing[.value].map({ $0.counter > 1 }) ?? true) {
            _stopObserving(.value)
        }
    }

    public func loadValue(completion: Assign<T>, fail: Assign<Error>) {
        load(completion: .just { err in
            if let v = self._value {
                switch v {
                case .error(let e, last: _): fail.assign(e)
                case .remote(let v): completion.assign(v)
                default:
                    fail.assign(RealtimeError(source: .value, description: "Undefined error in \(self)"))
                }
            } else {
                fail.assign(RealtimeError(source: .value, description: "Undefined error in \(self)"))
            }
        })
    }

    override func _writeChanges(to transaction: Transaction, by node: Node) throws {
        /// readonly property cannot have changes
    }

    override func _write(to transaction: Transaction, by node: Node) throws {
        /// readonly property cannot write something
    }
    
    // MARK: Events
    
    override public func didSave(in database: RealtimeDatabase, in parent: Node, by key: String) {
        super.didSave(in: database, in: parent, by: key)
        switch _value {
        case .some(.local(let v)):
            _setValue(.remote(v))
        default: break
        }
    }

    public override func didUpdate(through ancestor: Node) {
        super.didUpdate(through: ancestor)
        switch _value {
        case .some(.local(let v)):
            _setValue(.remote(v))
        default: break
        }
    }
    
    override public func didRemove(from ancestor: Node) {
        super.didRemove(from: ancestor)
        _setRemoved(isLocal: false)
    }
    
    // MARK: Changeable

    override public func apply(_ data: RealtimeDataProtocol, exactly: Bool) throws {
        /// skip the call of super
        guard exactly else {
            /// skip partial data, because it is not his responsibility and representer can throw error
            return
        }
        do {
            if let value = try representer.decode(data) {
                _setValue(.remote(value))
            } else {
                _setRemoved(isLocal: false)
            }
        } catch let e {
            _setError(e)
            throw e
        }
    }

    internal func _setValue(_ value: PropertyState<T>) {
        _value = value
        repeater.send(.value(value))
    }

    func _setRemoved(isLocal: Bool) {
        _value = .removed(local: isLocal)
        repeater.send(.value(.removed(local: isLocal)))
    }

    internal func _setError(_ error: Error) {
        _value = .error(error, last: _value?.lastNonError)
        repeater.send(.error(error))
    }

    public override var debugDescription: String {
        return """
        \(type(of: self)): \(ObjectIdentifier(self).memoryAddress) {
            ref: \(node?.debugDescription ?? "not referred"),
            keepSynced: \(keepSynced),
            value: \(_value as Any)
        }
        """
    }
}
extension ReadonlyProperty: Listenable {
    public func listening(_ assign: Assign<ListenEvent<PropertyState<T>>>) -> Disposable {
        defer {
            switch _value {
            case .none: break
            case .some(let e): assign.call(.value(e))
            }
        }
        return repeater.listening(assign)
    }
}
extension ReadonlyProperty: Equatable where T: Equatable {
    public static func ==(lhs: ReadonlyProperty, rhs: ReadonlyProperty) -> Bool {
        guard lhs.node == rhs.node else { return false }

        return lhs ==== rhs
    }
}
public extension ReadonlyProperty {
    /// Last property state
    var lastEvent: PropertyState<T>? {
        return _value
    }

    /// Current value of property
    /// `nil` if property has no value, or has been removed
    var wrapped: T? {
        return _value?.wrapped
    }
}
public extension ReadonlyProperty {
    static func ?? (optional: ReadonlyProperty, defaultValue: @autoclosure () throws -> T) rethrows -> T {
        return try optional.wrapped ?? defaultValue()
    }
    static func ?? (optional: ReadonlyProperty, defaultValue: @autoclosure () throws -> T?) rethrows -> T? {
        return try optional.wrapped ?? defaultValue()
    }
    static func =?(_ value: inout T, _ prop: ReadonlyProperty) {
        if let v = prop.wrapped {
            value = v
        }
    }
    static func <==(_ value: inout T?, _ prop: ReadonlyProperty) {
        value = prop.wrapped
    }
}
public func <== <T>(_ value: inout T?, _ prop: ReadonlyProperty<T>?) {
    value = prop?.wrapped
}
public extension ReadonlyProperty {
    func mapValue<U>(_ transform: (T) throws -> U) rethrows -> U? {
        return try wrapped.map(transform)
    }
    func flatMapValue<U>(_ transform: (T) throws -> U?) rethrows -> U? {
        return try wrapped.flatMap(transform)
    }
}
public extension ReadonlyProperty where T: _Optional {
    var unwrapped: T.Wrapped? {
        return _value.flatMap { $0.wrapped }
    }
    static func ?? (optional: T.Wrapped?, property: ReadonlyProperty<T>) -> T.Wrapped? {
        return optional ?? property.unwrapped
    }
    static func <==(_ value: inout T.Wrapped?, _ prop: ReadonlyProperty) {
        value = prop.unwrapped
    }
}
func <== <T>(_ value: inout T.Wrapped?, _ prop: ReadonlyProperty<T>?) where T: _Optional {
    value = prop?.unwrapped
}
public extension ReadonlyProperty where T: HasDefaultLiteral {
    static func <==(_ value: inout T, _ prop: ReadonlyProperty) {
        value = prop.wrapped ?? T()
    }
}
public extension ReadonlyProperty where T: _Optional, T.Wrapped: HasDefaultLiteral {
    static func <==(_ value: inout T.Wrapped, _ prop: ReadonlyProperty) {
        value = prop.unwrapped ?? T.Wrapped()
    }
}
infix operator ====: ComparisonPrecedence
infix operator !===: ComparisonPrecedence
public extension ReadonlyProperty where T: Equatable {
    static func ====(lhs: T, rhs: ReadonlyProperty) -> Bool {
        switch (lhs, rhs.wrapped) {
        case (_, .none): return false
        case (let l, .some(let r)): return l == r
        }
    }
    static func ====(lhs: ReadonlyProperty, rhs: T) -> Bool {
        switch (rhs, lhs.wrapped) {
        case (_, .none): return false
        case (let l, .some(let r)): return l == r
        }
    }
    static func ====(lhs: ReadonlyProperty, rhs: ReadonlyProperty) -> Bool {
        guard lhs !== rhs else { return true }
        return rhs.wrapped == lhs.wrapped
    }
    static func !===(lhs: T, rhs: ReadonlyProperty) -> Bool {
        return !(lhs ==== rhs)
    }
    static func !===(lhs: ReadonlyProperty, rhs: T) -> Bool {
        return !(lhs ==== rhs)
    }
    static func !===(lhs: ReadonlyProperty, rhs: ReadonlyProperty) -> Bool {
        return !(lhs ==== rhs)
    }
    static func ====(lhs: T?, rhs: ReadonlyProperty) -> Bool {
        switch (lhs, rhs.wrapped) {
        case (.none, .none): return true
        case (.none, .some), (.some, .none): return false
        case (.some(let l), .some(let r)): return l == r
        }
    }
    static func ====(lhs: ReadonlyProperty, rhs: T?) -> Bool {
        switch (rhs, lhs.wrapped) {
        case (.none, .none): return true
        case (.none, .some), (.some, .none): return false
        case (.some(let l), .some(let r)): return l == r
        }
    }
    static func !===(lhs: T?, rhs: ReadonlyProperty) -> Bool {
        return !(lhs ==== rhs)
    }
    static func !===(lhs: ReadonlyProperty, rhs: T?) -> Bool {
        return !(lhs ==== rhs)
    }
}
public extension ReadonlyProperty where T: Equatable & _Optional {
    static func ====(lhs: T, rhs: ReadonlyProperty) -> Bool {
        return rhs.wrapped == lhs
    }
    static func ====(lhs: ReadonlyProperty, rhs: T) -> Bool {
        return lhs.mapValue({ $0 == rhs }) ?? (rhs.wrapped == nil)
    }
}
public extension ReadonlyProperty where T: HasDefaultLiteral & _ComparableWithDefaultLiteral {
    static func <==(_ value: inout T, _ prop: ReadonlyProperty) {
        value = prop.wrapped ?? T()
    }
    func defaultOnEmpty() -> Self {
        self.representer = Representer(defaultOnEmpty: representer)
        return self
    }
}

// TODO: Reconsider usage it. Some RealtimeValue things are not need here.
public final class SharedProperty<T>: _RealtimeValue where T: RealtimeDataValue & HasDefaultLiteral {
    private var _value: T
    public var value: T { return _value }
    let repeater: Repeater<T> = Repeater.unsafe()
    let representer: Representer<T> = .any

    // MARK: Initializers, deinitializer

    public required init(in node: Node?, options: [ValueOption: Any]) {
        self._value = T()
        super.init(in: node, options: options)
    }

    // MARK: Events

    override public func didRemove(from ancestor: Node) {
        super.didRemove(from: ancestor)
        setValue(T())
    }

    // MARK: Changeable

    public required init(data: RealtimeDataProtocol, exactly: Bool) throws {
        self._value = T()
        try super.init(data: data, exactly: exactly)
    }

    override public func apply(_ data: RealtimeDataProtocol, exactly: Bool) throws {
        try super.apply(data, exactly: exactly)
        setValue(try representer.decode(data))
    }

    fileprivate func setValue(_ value: T) {
        self._value = value
        repeater.send(.value(value))
    }
}
extension SharedProperty: Listenable {
    public func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
        return repeater.listening(assign)
    }
}

public extension SharedProperty {
    public func changeValue(use changing: @escaping (T) throws -> T,
                            completion: ((Bool, T) -> Void)? = nil) {
        guard let ref = node?.reference() else  {
            fatalError("Can`t get database reference")
        }
        ref.runTransactionBlock({ data in
            do {
                let dataValue = data.exists() ? try T.init(data: data) : T()
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
    let database: RealtimeDatabase
    public let node: Node
    public required init(in database: RealtimeDatabase = RealtimeApp.app.database, by node: Node) {
        guard node.isRooted else { fatalError("Node must be rooted") }

        self.node = node
        self.database = database
    }
}
public extension MutationPoint where T: RealtimeDataRepresented & RealtimeDataValueRepresented {
    func set(value: T, in transaction: Transaction? = nil) throws -> Transaction {
        let transaction = transaction ?? Transaction(database: database)
        transaction.addValue(try value.defaultRepresentation(), by: node)

        return transaction
    }
    func mutate(by key: String? = nil, use value: T, in transaction: Transaction? = nil) throws -> Transaction {
        let transaction = transaction ?? Transaction(database: database)
        transaction.addValue(try value.defaultRepresentation(), by: key.map { node.child(with: $0) } ?? node.childByAutoId())

        return transaction
    }
}
public extension MutationPoint where T: RealtimeDataValue {
    func set(value: T, in transaction: Transaction? = nil) -> Transaction {
        let transaction = transaction ?? Transaction(database: database)
        transaction.addValue(value, by: node)

        return transaction
    }
    func mutate(by key: String? = nil, use value: T, in transaction: Transaction? = nil) -> Transaction {
        let transaction = transaction ?? Transaction(database: database)
        transaction.addValue(value, by: key.map { node.child(with: $0) } ?? node.childByAutoId())

        return transaction
    }
}
extension MutationPoint {
    func removeValue(for key: String, in transaction: Transaction? = nil) -> Transaction {
        let transaction = transaction ?? Transaction(database: database)
        transaction.removeValue(by: node.child(with: key))

        return transaction
    }
}
public extension MutationPoint where T: Codable {
    @discardableResult
    func addValue(by key: String? = nil, use value: T, in transaction: Transaction? = nil) throws -> Transaction {
        let transaction = transaction ?? Transaction(database: database)
        let representer = Representer<T>.json()
        if let v = try representer.encode(value) {
            transaction.addValue(v, by: key.map { node.child(with: $0) } ?? node.childByAutoId())
        }

        return transaction
    }
}
