//
//  Property.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 18/02/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation

public extension RawRepresentable where Self.RawValue == String {
    func property<T>(in object: Object, representer: Representer<T>) -> Property<T> {
        return Property.required(
            in: Node(key: rawValue, parent: object.node),
            representer: representer,
            options: [
                .database: object.database as Any,
                .representer: Availability<T>.required(representer)
            ]
        )
    }
    func property<T>(in object: Object, representer: Representer<T>) -> Property<T?> {
        return Property(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .representer: Availability<T?>.optional(representer)
            ]
        )
    }

    func readonlyProperty<T: RealtimeDataValue>(in object: Object, representer: Representer<T> = .realtimeDataValue) -> ReadonlyProperty<T> {
        return ReadonlyProperty(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .representer: Availability<T>.required(representer)
            ]
        )
    }
    func readonlyProperty<T: RealtimeDataValue>(in object: Object, representer: Representer<T> = .realtimeDataValue) -> ReadonlyProperty<T?> {
        return ReadonlyProperty(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .representer: Availability<T?>.optional(representer)
            ]
        )
    }
    func property<T: RealtimeDataValue>(in obj: Object) -> Property<T> {
        return property(in: obj, representer: .realtimeDataValue)
    }
    func property<T: RealtimeDataValue>(in obj: Object) -> Property<T?> {
        return Property(
            in: Node(key: rawValue, parent: obj.node),
            options: [
                .database: obj.database as Any,
                .representer: Availability<T?>.optional(Representer<T>.realtimeDataValue)
            ]
        )
    }

    func `enum`<V: RawRepresentable>(in object: Object, rawRepresenter: Representer<V.RawValue> = .realtimeDataValue) -> Property<V> where V.RawValue: RealtimeDataValue {
        return property(in: object, representer: Representer<V>.default(rawRepresenter))
    }
    func `enum`<V: RawRepresentable>(in object: Object, rawRepresenter: Representer<V.RawValue> = .realtimeDataValue) -> Property<V?> where V.RawValue: RealtimeDataValue {
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
    #if os(macOS) || os(iOS)
    func codable<V: Codable>(in object: Object) -> Property<V> {
        return property(in: object, representer: Representer<V>.json())
    }
    func optionalCodable<V: Codable>(in object: Object) -> Property<V?> {
        return property(in: object, representer: Representer<V>.json())
    }
    #endif

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
    func relation<V: Object>(in object: Object, rootLevelsUp: UInt? = nil, ownerLevelsUp: UInt = 1, _ property: RelationProperty) -> Relation<V> {
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
    func relation<V: Object>(in object: Object, rootLevelsUp: UInt? = nil, ownerLevelsUp: UInt = 1, _ property: RelationProperty) -> Relation<V?> {
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
    public override var raw: RealtimeDatabaseValue? { return super._raw }
    public override var payload: RealtimeDatabaseValue? { return super._payload }

    public required init(in node: Node?, options: [ValueOption : Any]) {
        guard case let o as Mode = options[.reference] else { fatalError("Skipped required options") }
        super.init(in: node, options: options.merging([.representer: o.availability], uniquingKeysWith: { _, new in new }))
    }

    required public init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        fatalError("init(data:event:) cannot be called. Use combination init(in:options:) and apply(_:event:) instead")
    }

    @discardableResult
    public override func setValue(_ value: Referenced, in transaction: Transaction? = nil) throws -> Transaction {
        guard Referenced._isValid(asReference: value) else { fatalError("Value must with rooted node") }

        return try super.setValue(value, in: transaction)
    }

    public override func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        try _apply_RealtimeValue(data)
        try super.apply(data, event: event)
    }

    override func _write(to transaction: Transaction, by node: Node) throws {
        _write_RealtimeValue(to: transaction, by: node)
        try super._write(to: transaction, by: node)
    }

    public struct Mode {
        let availability: Availability<Referenced>

        public static func required(_ mode: ReferenceMode, options: [ValueOption: Any]) -> Mode {
            return Mode(availability: Availability<Referenced>.required(Representer.reference(mode, options: options)))
        }
        public static func writeRequired<U: RealtimeValue>(_ mode: ReferenceMode, options: [ValueOption: Any]) -> Mode where Referenced == Optional<U> {
            return Mode(availability: Availability<Referenced>.writeRequired(Representer<U>.reference(mode, options: options)))
        }
        public static func optional<U: RealtimeValue>(_ mode: ReferenceMode, options: [ValueOption: Any]) -> Mode where Referenced == Optional<U> {
            return Mode(availability: Availability<Referenced>.optional(Representer<U>.reference(mode, options: options)))
        }
    }

    public static func readonly(in node: Node?, mode: Mode) -> ReadonlyProperty<Referenced> {
        return ReadonlyProperty(in: node, options: [.representer: mode.availability])
    }
}

/// Defines read/write property where value is Realtime database relation
public final class Relation<Related: RealtimeValue & _RealtimeValueUtilities>: Property<Related> {
    var options: Options
    public override var raw: RealtimeDatabaseValue? { return super._raw }
    public override var payload: RealtimeDatabaseValue? { return super._payload }

    public required init(in node: Node?, options: [ValueOption: Any]) {
        guard case let relation as Relation<Related>.Options = options[.relation] else { fatalError("Skipped required options") }

        self.options = relation

        if let ownerNode = node?.ancestor(onLevelUp: self.options.ownerLevelsUp) {
            self.options.ownerNode.value = ownerNode
        }

        super.init(in: node, options: options.merging([.representer: relation.availability], uniquingKeysWith: { _, new in new }))
    }

    required public init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        fatalError("init(data:event:) cannot be called. Use combination init(in:options:) and apply(_:event:) instead")
    }

    @discardableResult
    public override func setValue(_ value: Related, in transaction: Transaction? = nil) throws -> Transaction {
        guard Related._isValid(asRelation: value) else { fatalError("Value must with rooted node") }

        return try super.setValue(value, in: transaction)
    }

    override func _write(to transaction: Transaction, by node: Node) throws {
        _write_RealtimeValue(to: transaction, by: node)
        if let ownerNode = node.ancestor(onLevelUp: options.ownerLevelsUp) {
            options.ownerNode.value = ownerNode
            try super._write(to: transaction, by: node)
        } else {
            throw RealtimeError(source: .value, description: "Cannot get owner node from levels up: \(options.ownerLevelsUp)")
        }
    }

    override func _writeChanges(to transaction: Transaction, by node: Node) throws {
        if hasChanges {
            try _write(to: transaction, by: node)
            transaction.addReversion(currentReversion())
        }
    }

    public override func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        try _apply_RealtimeValue(data)
        try super.apply(data, event: event)
    }

    public struct Options {
        /// Levels up by hierarchy to relation owner of this property
        let ownerLevelsUp: UInt
        /// String path from related object to his relation property
        let property: RelationProperty
        /// Levels up by hierarchy to the same node for both related values. Default nil, that means root node
        let rootLevelsUp: UInt?

        let ownerNode: ValueStorage<Node?>
        let availability: Availability<Related>

        public static func required(rootLevelsUp: UInt?, ownerLevelsUp: UInt, property: RelationProperty) -> Options {
            let ownerNode = ValueStorage<Node?>.unsafe(strong: nil)
            return Options(
                ownerLevelsUp: ownerLevelsUp,
                property: property,
                rootLevelsUp: rootLevelsUp,
                ownerNode: ownerNode,
                availability: Availability.required(Representer.relation(property, rootLevelsUp: rootLevelsUp, ownerNode: ownerNode))
            )
        }
        public static func writeRequired<U>(rootLevelsUp: UInt?, ownerLevelsUp: UInt, property: RelationProperty) -> Options where Related == Optional<U> {
            let ownerNode = ValueStorage<Node?>.unsafe(strong: nil)
            return Options(
                ownerLevelsUp: ownerLevelsUp,
                property: property,
                rootLevelsUp: rootLevelsUp,
                ownerNode: ownerNode,
                availability: Availability.writeRequired(Representer<U>.relation(property, rootLevelsUp: rootLevelsUp, ownerNode: ownerNode))
            )
        }
        public static func optional<U>(rootLevelsUp: UInt?, ownerLevelsUp: UInt, property: RelationProperty) -> Options where Related == Optional<U> {
            let ownerNode = ValueStorage<Node?>.unsafe(strong: nil)
            return Options(
                ownerLevelsUp: ownerLevelsUp,
                property: property,
                rootLevelsUp: rootLevelsUp,
                ownerNode: ownerNode,
                availability: Availability.optional(Representer<U>.relation(property, rootLevelsUp: rootLevelsUp, ownerNode: ownerNode))
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
        return ReadonlyProperty(in: node, options: [.representer: config.availability])
    }
}

// MARK: Listenable realtime property

public extension ValueOption {
    static let representer: ValueOption = ValueOption("realtime.property.representer")
    static let initialValue: ValueOption = ValueOption("realtime.property.initialValue")
}

public enum PropertyState<T> {
    case none
    case local(T)
    case remote(T)
    case removed(local: Bool)
    indirect case error(Error, last: PropertyState<T>?)
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
        case .none, .removed: return nil
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
        self = .none
    }

    internal var lastNonError: PropertyState<T>? {
        switch self {
        case .error(_, let last): return last?.lastNonError
        default: return self
        }
    }
}
public extension PropertyState where T: _Optional {
    var unwrapped: T.Wrapped? {
        switch self {
        case .none, .removed: return nil
        case .local(let v): return v.wrapped
        case .remote(let v): return v.wrapped
        case .error(_, let v): return v?.unwrapped
        }
    }
    static func <==(_ value: inout T.Wrapped?, _ prop: PropertyState<T>) {
        value = prop.unwrapped
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

public extension PropertyState {
    static func ?? (optional: PropertyState<T>, defaultValue: @autoclosure () throws -> T) rethrows -> T {
        return try optional.wrapped ?? defaultValue()
    }
    static func ?? (optional: PropertyState<T>, defaultValue: @autoclosure () throws -> T?) rethrows -> T? {
        return try optional.wrapped ?? defaultValue()
    }
    static func <==(_ value: inout T?, _ prop: PropertyState<T>) {
        value = prop.wrapped
    }
}
public extension PropertyState where T: _Optional {
    static func ?? <Def>(optional: PropertyState<T>, defaultValue: @autoclosure () throws -> Def) rethrows -> T.Wrapped where Def == T.Wrapped {
        return try optional.unwrapped ?? defaultValue()
    }
    static func ?? <Def>(optional: PropertyState<T>, defaultValue: @autoclosure () throws -> Def?) rethrows -> T.Wrapped? where Def == T.Wrapped {
        return try optional.unwrapped ?? defaultValue()
    }
}

/// Defines read/write property with any value
public class Property<T>: ReadonlyProperty<T>, ChangeableRealtimeValue, WritableRealtimeValue, Reverting {
    fileprivate var _oldValue: PropertyState<T>?
    override var _hasChanges: Bool {
        return _oldValue != nil
    }
    public var oldValue: PropertyState<T>? { return _oldValue }

    public func revert() {
        if let old = _oldValue {
            _value = old
            _oldValue = nil
        }
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

    /// Changes current value using mutation closure
    ///
    /// - Parameter using: Mutation closure
    public func change(_ using: (T?) -> T) {
        _setLocalValue(using(wrapped))
    }

    /// Removes property value.
    /// Note: Before run write operation you must set any value again, even if value has optional type,
    /// otherwise operation will be ended with error.
    public func remove() {
        _setRemoved(isLocal: true)
    }

    public override func didSave(in database: RealtimeDatabase, in parent: Node, by key: String) {
        super.didSave(in: database, in: parent, by: key)
        self._oldValue = nil
        switch _value {
        case .none, .removed:
            debugAction {
                do {
                    /// test required property
                    _ = try representer.encode(nil)
                } catch {
                    debugFatalError("Required property '\(key)': \(type(of: self)) has been saved, but value does not exists")
                }
            }
        case .local(let v):
            _setValue(.remote(v))
        default: break
        }
    }

    public override func didUpdate(through ancestor: Node) {
        super.didUpdate(through: ancestor)
        self._oldValue = nil
        switch _value {
        case .local(let v):
            _setValue(.remote(v))
        default: break
        }
    }

    internal func cacheValue(_ node: Node, value: RealtimeDatabaseValue?) -> CacheNode {
        return .value(ValueNode(node: node, value: value))
    }

    override func _writeChanges(to transaction: Transaction, by node: Node) throws {
        /// skip the call of super (_RealtimeValue)
        switch _value {
        case .local(let changed):
            _addReversion(to: transaction, by: node)
            try transaction._addValue(cacheValue(node, value: representer.encode(changed)))
        case .removed(true):
            debugFatalError("Property has not been set")
            throw RealtimeError(encoding: T.self, reason: "Property has not been set")
        case .none, .remote, .error, .removed(false): break
        }
    }

    /// Property does not respond for versions and raw value, and also payload.
    /// To change value version/raw can use enum, but use modified representer.
    override func _write(to transaction: Transaction, by node: Node) throws {
        /// skip the call of super (_RealtimeValue)
        switch _value {
        case .none, .removed:
            /// throws error if property required
            /// does not add to transaction with consideration about empty node to save operation
            /// otherwise need to use update operation
            do {
                _ = try representer.encode(nil)
            } catch let e {
                debugFatalError("Required property has not been set '\(node)': \(type(of: self))")
                throw e
            }
        case .local(let v):
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
            _oldValue = _value
        }
        _setValue(.local(value))
    }

    override func _setRemoved(isLocal: Bool) {
        if isLocal && !hasChanges {
            _oldValue = _value
        }
        super._setRemoved(isLocal: isLocal)
    }
}

prefix operator §
public extension ReadonlyProperty {
    static prefix func § (prop: ReadonlyProperty) -> T? {
        return prop.wrapped
    }
}

infix operator <==: AssignmentPrecedence
public extension Property {
    static func <== (_ prop: Property, _ value: @autoclosure () throws -> T) rethrows {
        prop._setLocalValue(try value())
    }
}
infix operator <!=: AssignmentPrecedence
public extension Property where T: Equatable {
    static func <!= (_ prop: Property, _ value: @autoclosure () throws -> T) rethrows {
        let newValue = try value()
        switch (prop.state, prop._oldValue) {
        case (.remote(let oldValue), _):
            if oldValue != newValue {
                prop._setLocalValue(newValue)
            }
        case (.local, .some(let old)):
            if old.wrapped == newValue {
                prop._setLocalValue(newValue)
            }
        default:
            prop._setLocalValue(newValue)
        }
    }
}

public struct Availability<T> {
    let property: () -> Representer<T?>
    public var representer: Representer<T?> { return property() }

    init(_ property: @escaping () -> Representer<T?>) {
        self.property = property
    }

    public static func required(_ representer: Representer<T>) -> Availability {
        return Availability(Representer.requiredProperty(representer))
    }
    public static func writeRequired<V>(_ representer: Representer<V>) -> Availability where Optional<V> == T {
        return Availability(Representer.writeRequiredProperty(representer))
    }
    public static func optional<V>(_ representer: Representer<V>) -> Availability where Optional<V> == T {
        return Availability(Representer.optionalProperty(representer))
    }
}
extension Availability where T: HasDefaultLiteral & _ComparableWithDefaultLiteral {
    func defaultOnEmpty() -> Availability {
        return Availability({ self.representer.defaultOnEmpty() })
    }
}

/// Defines readonly property with any value
public class ReadonlyProperty<T>: _RealtimeValue, RealtimeValueActions {
    fileprivate var _value: PropertyState<T>
    fileprivate(set) var representer: Representer<T?>
    fileprivate let repeater: Repeater<PropertyState<T>> = Repeater.unsafe()

    internal var _raw: RealtimeDatabaseValue? { return super.raw }
    internal var _payload: RealtimeDatabaseValue? { return super.payload }

    public override var raw: RealtimeDatabaseValue? { return nil }
    public override var payload: RealtimeDatabaseValue? { return nil }

    public var keepSynced: Bool = false {
        didSet {
            guard oldValue != keepSynced else { return }
            if keepSynced { runObserving() }
            else { stopObserving() }
        }
    }
    
    // MARK: Initializers, deinitializer

    public static func required(in node: Node?, representer: Representer<T>, options: [ValueOption: Any] = [:]) -> Self {
        return self.init(in: node, options: options.merging([.representer: Availability.required(representer)], uniquingKeysWith: { _, new in new }))
    }
    public static func optional<U>(in node: Node?, representer: Representer<U>, options: [ValueOption: Any] = [:]) -> Self where Optional<U> == T {
        return self.init(in: node, options: options.merging([.representer: Availability.optional(representer)], uniquingKeysWith: { _, new in new }))
    }
    public static func writeRequired<U>(in node: Node?, representer: Representer<U>, options: [ValueOption: Any] = [:]) -> Self where Optional<U> == T {
        return self.init(in: node, options: options.merging([.representer: Availability.writeRequired(representer)], uniquingKeysWith: { _, new in new }))
    }

    /// Designed initializer
    ///
    /// Available options:
    /// - .initialValue *(optional)* - default property value
    /// - .representer *(required)* - instance of type `Representer<T>`.
    ///
    /// **Warning**: You must pass representer that returns through next methods of `Availability<T>`:
    /// - func required() - throws error if value is not presented
    /// - func optional() - can have empty value
    /// - func writeRequired() - throws error in save operation if value is not set
    ///
    /// - Parameters:
    ///   - node: Database node reference
    ///   - options: Option values
    public required init(in node: Node?, options: [ValueOption: Any]) {
        guard case let availability as Availability<T> = options[.representer] else { fatalError("Bad options") }

        if let inital = options[.initialValue], let v = inital as? T {
            self._value = .local(v)
        } else {
            self._value = .none
        }
        self.representer = availability.representer
        super.init(in: node, options: options)
    }

    public required init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        #if DEBUG
        fatalError("init(data:exactly:) cannot be called. Use combination init(in:options:) and apply(_:exactly:) instead")
        #else
        throw RealtimeError(decoding: type(of: self).self, data, reason: "Unavailable initializer")
        #endif
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

    public func loadValue() -> AnyListenable<T> {
        return loadState().map({ (state) -> T in
            switch state {
            case .none, .removed, .local: throw RealtimeError(source: .value, description: "Unexpected value")
            case .remote(let v): return v
            case .error(let e, _): throw e
            }
        }).asAny()
    }
    public func loadState() -> AnyListenable<PropertyState<T>> {
        return load().completion.map({ self.state }).asAny()
    }

    override func _writeChanges(to transaction: Transaction, by node: Node) throws {
        /// readonly property cannot have changes
    }

    override func _write(to transaction: Transaction, by node: Node) throws {
        /// readonly property cannot write something
    }
    
    // MARK: Events
    
    override public func didRemove(from ancestor: Node) {
        super.didRemove(from: ancestor)
        _setRemoved(isLocal: false)
    }
    
    // MARK: Changeable

    override public func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        /// skip the call of super
        guard event == .value else {
            /// skip partial data, because it is not his responsibility and representer can throw error
            return
        }
        do {
            if let value = try representer.decode(data) {
                _setValue(.remote(value))
            } else {
                // actually does not call anyway
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
        _value = .error(error, last: _value.lastNonError)
        repeater.send(.error(error))
    }

    override func _dataObserverDidCancel(_ error: Error) {
        super._dataObserverDidCancel(error)
        _setError(error)
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
            assign.call(.value(_value))
        }
        return repeater.listening(assign)
    }
    public func listeningItem(_ assign: Closure<ListenEvent<PropertyState<T>>, Void>) -> ListeningItem {
        defer {
            assign.call(.value(_value))
        }
        return repeater.listeningItem(assign)
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
    var state: PropertyState<T> {
        return _value
    }

    /// Current value of property
    /// `nil` if property has no value, or has been removed
    var wrapped: T? {
        return _value.wrapped
    }
}
public extension ReadonlyProperty {
    static func ?? (optional: ReadonlyProperty, defaultValue: @autoclosure () throws -> T) rethrows -> T {
        return try optional.wrapped ?? defaultValue()
    }
    static func ?? (optional: ReadonlyProperty, defaultValue: @autoclosure () throws -> T?) rethrows -> T? {
        return try optional.wrapped ?? defaultValue()
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
        return _value.unwrapped
    }
    static func ?? (optional: T.Wrapped?, property: ReadonlyProperty<T>) -> T.Wrapped? {
        return optional ?? property.unwrapped
    }
    static func <==(_ value: inout T.Wrapped?, _ prop: ReadonlyProperty) {
        value = prop.unwrapped
    }
}
public func <== <T>(_ value: inout T.Wrapped?, _ prop: ReadonlyProperty<T>?) where T: _Optional {
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
public extension ReadonlyProperty where T: Comparable {
    static func < (lhs: ReadonlyProperty<T>, rhs: T) -> Bool {
        return lhs.mapValue({ $0 < rhs }) ?? false
    }
    static func > (lhs: ReadonlyProperty<T>, rhs: T) -> Bool {
        return lhs.mapValue({ $0 > rhs }) ?? false
    }
    static func < (lhs: T, rhs: ReadonlyProperty<T>) -> Bool {
        return rhs.mapValue({ $0 > lhs }) ?? false
    }
    static func > (lhs: T, rhs: ReadonlyProperty<T>) -> Bool {
        return rhs.mapValue({ $0 < lhs }) ?? false
    }
}

// TODO: Reconsider usage it. Some RealtimeValue things are not need here.
public final class SharedProperty<T>: _RealtimeValue where T: RealtimeDataValue & HasDefaultLiteral {
    private var _value: State
    public var value: T {
        switch _value {
        case .error(_, let old): return old
        case .value(let v): return v
        }
    }
    let repeater: Repeater<T> = Repeater.unsafe()
    let representer: Representer<T> = .realtimeDataValue

    enum State {
        case error(Error, old: T)
        case value(T)
    }

    // MARK: Initializers, deinitializer

    public required init(in node: Node?, options: [ValueOption: Any]) {
        self._value = .value(T())
        super.init(in: node, options: options)
    }

    // MARK: Events

    override public func didRemove(from ancestor: Node) {
        super.didRemove(from: ancestor)
        setState(.value(T()))
    }

    // MARK: Changeable

    public required init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        self._value = .value(T())
        try super.init(data: data, event: event)
    }

    override public func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        try super.apply(data, event: event)
        setState(.value(try representer.decode(data)))
    }

    fileprivate func setError(_ error: Error) {
        setState(.error(error, old: value))
    }

    fileprivate func setState(_ value: State) {
        self._value = value
        switch value {
        case .error(let e, _): repeater.send(.error(e))
        case .value(let v): return repeater.send(.value(v))
        }
    }
}
extension SharedProperty: Listenable {
    public func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
        return repeater.listening(assign)
    }
    public func listeningItem(_ assign: Closure<ListenEvent<T>, Void>) -> ListeningItem {
        return repeater.listeningItem(assign)
    }
}

public extension SharedProperty {
    func change(use updater: @escaping (T) throws -> T) {
        guard let database = self.database, let node = self.node, node.isRooted else  {
            fatalError("Can`t get database reference")
        }
        let representer = self.representer
        database.runTransaction(
            in: node,
            withLocalEvents: true,
            { (data) -> ConcurrentIterationResult in
                do {
                    let currentValue = data.exists() ? try T.init(data: data) : T()
                    let newValue = try updater(currentValue)
                    return .value(try representer.encode(newValue))
                } catch let e {
                    debugFatalError(e.localizedDescription)
                    return .abort
                }
            },
            onComplete: { result in
                switch result {
                case .error(let e): self.setError(e)
                case .data(let data):
                    do {
                        self.setState(.value(try self.representer.decode(data)))
                    } catch let e {
                        self.setError(e)
                    }
                }
            }
        )
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
public extension MutationPoint {
    func set(value: RealtimeDatabaseValue, in transaction: Transaction? = nil) throws -> Transaction {
        let transaction = transaction ?? Transaction(database: database)
        transaction.addValue(value, by: node)

        return transaction
    }
    func mutate(by key: String? = nil, use value: RealtimeDatabaseValue, in transaction: Transaction? = nil) throws -> Transaction {
        let transaction = transaction ?? Transaction(database: database)
        transaction.addValue(value, by: key.map { node.child(with: $0) } ?? node.childByAutoId())

        return transaction
    }
}
public extension MutationPoint where T: RealtimeDataValue {
    func set(value: T, in transaction: Transaction? = nil) -> Transaction {
        let transaction = transaction ?? Transaction(database: database)
        transaction.addValue(value, by: node)

        return transaction
    }
    @discardableResult
    func mutate(by key: String? = nil, use value: T, in transaction: Transaction? = nil) -> Transaction {
        let transaction = transaction ?? Transaction(database: database)
        transaction.addValue(value, by: key.map { node.child(with: $0) } ?? node.childByAutoId())

        return transaction
    }
}
public extension MutationPoint {
    func removeValue(for key: String, in transaction: Transaction? = nil) -> Transaction {
        let transaction = transaction ?? Transaction(database: database)
        transaction.removeValue(by: node.child(with: key))

        return transaction
    }
}
#if os(macOS) || os(iOS)
public extension MutationPoint where T: Codable {
    @discardableResult
    func addValue(by key: String? = nil, use value: T, in transaction: Transaction? = nil) throws -> Transaction {
        let transaction = transaction ?? Transaction(database: database)
        let representer = Representer<T>.json()
        if let v = try representer.encode(value) {
            transaction.addValue(v, by: key.map { node.child(with: $0) } ?? node.childByAutoId())
        } else {
            throw RealtimeError(encoding: T.self, reason: "Convertion to json was unsuccessful")
        }

        return transaction
    }
}
#endif
