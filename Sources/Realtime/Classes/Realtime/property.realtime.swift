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
        return Property(
            in: Node(key: rawValue, parent: object.node),
            options: .required(representer, db: object.database)
        )
    }
    func property<T>(in object: Object, representer: Representer<T>) -> Property<T?> {
        return Property(
            in: Node(key: rawValue, parent: object.node),
            options: .optional(representer, db: object.database)
        )
    }

    func readonlyProperty<T>(in object: Object, representer: Representer<T>) -> ReadonlyProperty<T> {
        return ReadonlyProperty(
            in: Node(key: rawValue, parent: object.node),
            options: .required(representer, db: object.database)
        )
    }
    func readonlyProperty<T>(in object: Object, representer: Representer<T>) -> ReadonlyProperty<Optional<T>> {
        return ReadonlyProperty(
            in: Node(key: rawValue, parent: object.node),
            options: .optional(representer, db: object.database)
        )
    }
    func readonlyProperty<T>(in object: Object) -> ReadonlyProperty<T> where T: ExpressibleByRealtimeDatabaseValue & RealtimeDataRepresented {
        return readonlyProperty(in: object, representer: Representer.realtimeDataValue)
    }
    func readonlyProperty<T>(in object: Object) -> ReadonlyProperty<Optional<T>> where T: ExpressibleByRealtimeDatabaseValue & RealtimeDataRepresented {
        return readonlyProperty(in: object, representer: Representer.realtimeDataValue)
    }

    func `enum`<V: RawRepresentable>(in object: Object, rawRepresenter: Representer<V.RawValue> = Representer.realtimeDataValue) -> Property<V> where V.RawValue: ExpressibleByRealtimeDatabaseValue & RealtimeDataRepresented {
        return property(in: object, representer: Representer<V>.default(rawRepresenter))
    }
    func `enum`<V: RawRepresentable>(in object: Object, rawRepresenter: Representer<V.RawValue> = Representer.realtimeDataValue) -> Property<V?> where V.RawValue: ExpressibleByRealtimeDatabaseValue & RealtimeDataRepresented {
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
        return property(in: object, representer: Representer<V>.codable)
    }
    func optionalCodable<V: Codable>(in object: Object) -> Property<V?> {
        return property(in: object, representer: Representer<V>.codable)
    }

    func reference<V: Object>(in object: Object, mode: ReferenceMode) -> Reference<V> {
        return Reference(
            in: Node(key: rawValue, parent: object.node),
            options: Reference<V>.Mode.required(mode, db: object.database, builder: { node, database, options in
                return V(in: node, options: RealtimeValueOptions(database: database, raw: options.raw, payload: options.payload))
            })
        )
    }
    func reference<V: Object>(in object: Object, mode: ReferenceMode) -> Reference<V?> {
        return Reference(
            in: Node(key: rawValue, parent: object.node),
            options: Reference<V?>.Mode.optional(mode, db: object.database, builder: { node, database, options in
                return V(in: node, options: RealtimeValueOptions(database: database, raw: options.raw, payload: options.payload))
            })
        )
    }
    func relation<V: Object>(in object: Object, rootLevelsUp: UInt? = nil, ownerLevelsUp: UInt = 1, _ property: RelationProperty) -> Relation<V> {
        return Relation(
            in: Node(key: rawValue, parent: object.node),
            options: Relation<V>.Options.required(
                db: object.database,
                rootLevelsUp: rootLevelsUp,
                ownerLevelsUp: ownerLevelsUp,
                property: property,
                builder: { node, database, options in
                    return V(in: node, options: RealtimeValueOptions(database: database, raw: options.raw, payload: options.payload))
                }
            )
        )
    }
    func relation<V: Object>(in object: Object, rootLevelsUp: UInt? = nil, ownerLevelsUp: UInt = 1, _ property: RelationProperty) -> Relation<V?> {
        return Relation(
            in: Node(key: rawValue, parent: object.node),
            options: Relation<V?>.Options.optional(
                db: object.database,
                rootLevelsUp: rootLevelsUp,
                ownerLevelsUp: ownerLevelsUp,
                property: property,
                builder: { node, database, options in
                    return V(in: node, options: RealtimeValueOptions(database: database, raw: options.raw, payload: options.payload))
                }
            )
        )
    }
}

/// Defines read/write property where value is Realtime database reference
public final class Reference<Referenced: RealtimeValue & _RealtimeValueUtilities>: Property<Referenced> {
    public override var raw: RealtimeDatabaseValue? { return super._raw }
    public override var payload: RealtimeDatabaseValue? { return super._payload }

    public required init(in node: Node?, options: Mode) {
        super.init(in: node, options: PropertyOptions(
            database: options.database,
            representer: options.availability,
            initial: nil
        ))
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
        let database: RealtimeDatabase?
        let availability: Representer<Referenced?>

        public static func required(_ mode: ReferenceMode, db: RealtimeDatabase?, builder: @escaping RCElementBuilder<RealtimeValueOptions, Referenced>) -> Mode {
            return Mode(database: db, availability: Representer.reference(mode, database: db, builder: builder).requiredProperty())
        }
        public static func writeRequired<U: RealtimeValue>(_ mode: ReferenceMode, db: RealtimeDatabase?, builder: @escaping RCElementBuilder<RealtimeValueOptions, U>) -> Mode where Referenced == Optional<U> {
            return Mode(database: db, availability: Representer<U>.reference(mode, database: db, builder: builder).writeRequiredProperty())
        }
        public static func optional<U: RealtimeValue>(_ mode: ReferenceMode, db: RealtimeDatabase?, builder: @escaping RCElementBuilder<RealtimeValueOptions, U>) -> Mode where Referenced == Optional<U> {
            return Mode(database: db, availability: Representer<U>.reference(mode, database: db, builder: builder).optionalProperty())
        }
    }

    public static func readonly(in node: Node?, mode: Mode) -> ReadonlyProperty<Referenced> {
        return ReadonlyProperty(in: node, options: PropertyOptions(database: nil, representer: mode.availability, initial: nil))
    }
}

/// Defines read/write property where value is Realtime database relation
public final class Relation<Related: RealtimeValue & _RealtimeValueUtilities>: Property<Related> {
    var options: Options
    public override var raw: RealtimeDatabaseValue? { return super._raw }
    public override var payload: RealtimeDatabaseValue? { return super._payload }

    public required init(in node: Node?, options: Options) {
        self.options = options

        if let ownerNode = node?.ancestor(onLevelUp: self.options.ownerLevelsUp) {
            self.options.ownerNode.value = ownerNode
        }

        super.init(in: node, options: PropertyOptions(
            database: options.database,
            representer: options.availability,
            initial: nil
        ))
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
        let database: RealtimeDatabase?
        /// Levels up by hierarchy to relation owner of this property
        let ownerLevelsUp: UInt
        /// String path from related object to his relation property
        let property: RelationProperty
        /// Levels up by hierarchy to the same node for both related values. Default nil, that means root node
        let rootLevelsUp: UInt?

        let ownerNode: ValueStorage<Node?>
        let availability: Representer<Related?>

        public static func required(db: RealtimeDatabase?, rootLevelsUp: UInt?, ownerLevelsUp: UInt, property: RelationProperty, builder: @escaping RCElementBuilder<RealtimeValueOptions, Related>) -> Options {
            let ownerNode = ValueStorage<Node?>.unsafe(strong: nil)
            return Options(
                database: db,
                ownerLevelsUp: ownerLevelsUp,
                property: property,
                rootLevelsUp: rootLevelsUp,
                ownerNode: ownerNode,
                availability: Representer.relation(property, rootLevelsUp: rootLevelsUp, ownerNode: ownerNode, database: db, builder: builder).requiredProperty()
            )
        }
        public static func writeRequired<U>(db: RealtimeDatabase?, rootLevelsUp: UInt?, ownerLevelsUp: UInt, property: RelationProperty, builder: @escaping RCElementBuilder<RealtimeValueOptions, U>) -> Options where Related == Optional<U> {
            let ownerNode = ValueStorage<Node?>.unsafe(strong: nil)
            return Options(
                database: db,
                ownerLevelsUp: ownerLevelsUp,
                property: property,
                rootLevelsUp: rootLevelsUp,
                ownerNode: ownerNode,
                availability: Representer<U>.relation(property, rootLevelsUp: rootLevelsUp, ownerNode: ownerNode, database: db, builder: builder).writeRequiredProperty()
            )
        }
        public static func optional<U>(db: RealtimeDatabase?, rootLevelsUp: UInt?, ownerLevelsUp: UInt, property: RelationProperty, builder: @escaping RCElementBuilder<RealtimeValueOptions, U>) -> Options where Related == Optional<U> {
            let ownerNode = ValueStorage<Node?>.unsafe(strong: nil)
            return Options(
                database: db,
                ownerLevelsUp: ownerLevelsUp,
                property: property,
                rootLevelsUp: rootLevelsUp,
                ownerNode: ownerNode,
                availability: Representer<U>.relation(property, rootLevelsUp: rootLevelsUp, ownerNode: ownerNode, database: db, builder: builder).optionalProperty()
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
        return ReadonlyProperty(in: node, options: PropertyOptions(database: nil, representer: config.availability, initial: nil))
    }
}

// MARK: Listenable realtime property

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

    public required init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        try super.init(data: data, event: event)
    }

    public override init(in node: Node?, options: PropertyOptions) {
        super.init(in: node, options: options)
    }

    public func revert() {
        if let old = _oldValue {
            _setValue(old)
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
            _setRemote(v)
        default: break
        }
    }

    public override func didUpdate(through ancestor: Node) {
        super.didUpdate(through: ancestor)
        self._oldValue = nil
        switch _value {
        case .local(let v):
            _setRemote(v)
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

    override func _setRemote(_ value: T) {
        super._setRemote(value)
        _oldValue = nil
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

    public struct PropertyOptions {
        let base: RealtimeValueOptions
        let representer: Representer<T?>
        let initialValue: T? // TODO: Remove, because initial value set as local value, though on step initialization as @propertyWrapper may be useful

        init(database: RealtimeDatabase?, representer: Representer<T?>, initial value: T? = nil) {
            self.base = RealtimeValueOptions(database: database)
            self.representer = representer
            self.initialValue = value
        }

        public static func required(_ representer: Representer<T>, db: RealtimeDatabase?, initial: T? = nil) -> PropertyOptions {
            return self.init(database: db, representer: representer.requiredProperty(), initial: initial)
        }
        public static func optional<U>(_ representer: Representer<U>, db: RealtimeDatabase?, initial: T? = nil) -> Self where Optional<U> == T {
            return self.init(database: db, representer: representer.optionalProperty(), initial: initial)
        }
        public static func writeRequired<U>(_ representer: Representer<U>, db: RealtimeDatabase?, initial: T? = nil) -> Self where Optional<U> == T {
            return self.init(database: db, representer: representer.writeRequiredProperty(), initial: initial)
        }
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
    public init(in node: Node?, options: PropertyOptions) {
        if let inital = options.initialValue {
            self._value = .local(inital)
        } else {
            self._value = .none
        }
        self.representer = options.representer
        super.init(node: node, options: options.base)
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
                _setRemote(value)
            } else {
                // actually does not call anyway
                _setRemoved(isLocal: false)
            }
        } catch let e {
            _setError(e)
            throw e
        }
    }

    internal func _setRemote(_ value: T) {
        _setValue(.remote(value))
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
    func set(value: RealtimeDatabaseValue, in transaction: Transaction? = nil) -> Transaction {
        let transaction = transaction ?? Transaction(database: database)
        transaction.addValue(value, by: node)

        return transaction
    }
    func mutate(by key: String? = nil, use value: RealtimeDatabaseValue, in transaction: Transaction? = nil) -> Transaction {
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

public extension MutationPoint where T: Codable {
    @discardableResult
    func addValue(by key: String? = nil, use value: T, in transaction: Transaction? = nil) throws -> Transaction {
        let transaction = transaction ?? Transaction(database: database)
        let representer = Representer<T>.codable
        if let v = try representer.encode(value) {
            transaction.addValue(v, by: key.map { node.child(with: $0) } ?? node.childByAutoId())
        } else {
            throw RealtimeError(encoding: T.self, reason: "Convertion to json was unsuccessful")
        }

        return transaction
    }
}
