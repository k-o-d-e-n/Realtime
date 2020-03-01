//
//  RealtimeBasic.swift
//  Realtime
//
//  Created by Denis Koryttsev on 31/01/2018.
//

import Foundation

// #
// ## https://stackoverflow.com/questions/24047991/does-swift-have-documentation-comments-or-tools/28633899#28633899
// Comment writing guide

#if swift(>=5.0)
internal let lazyStoragePath = "$__lazy_storage_$_"
#else
internal let lazyStoragePath = ".storage"
#endif

public struct RealtimeError: LocalizedError {
    let description: String
    public let source: Source

    public var localizedDescription: String { return description }

    init(source: Source, description: String) {
        self.source = source
        self.description = description
    }

    /// Shows part or process of Realtime where error is happened.
    ///
    /// - value: Error from someone class of property
    /// - collection: Error from someone class of collection
    /// - listening: Error from Listenable part
    /// - coding: Error on coding process
    /// - transaction: Error in `Transaction`
    /// - cache: Error in cache
    public enum Source {
        indirect case external(Error, Source)

        case value
        case file
        case collection

        case listening
        case coding
        case objectCoding([String: Error])
        case transaction([Error])
        case cache
        case database
        case storage
    }

    init(external error: Error, in source: Source, description: String = "") {
        self.source = .external(error, source)
        self.description = "External error: \(String(describing: error))"
    }
    init<T>(initialization type: T.Type, _ data: Any) {
        self.init(source: .coding, description: "Failed initialization type: \(T.self) with data: \(data)")
    }
    init<T>(decoding type: T.Type, _ data: Any, reason: String) {
        self.init(source: .coding, description: "Failed decoding data: \(data) to type: \(T.self). Reason: \(reason)")
    }
    init<T>(encoding value: T, reason: String) {
        self.init(source: .coding, description: "Failed encoding value of type: \(value). Reason: \(reason)")
    }
}

/// A type that contains key of database node
public protocol DatabaseKeyRepresentable {
    var dbKey: String! { get }
}

public protocol Versionable {
    func putVersion(into versioner: inout Versioner)
}
extension Versionable {
    var modelVersion: String {
        var versioner = Versioner()
        putVersion(into: &versioner)
        return versioner.finalize()
    }
}

// MARK: RealtimeValue

public extension RealtimeDataProtocol {
    internal func version() throws -> String? {
        let container = try self.container(keyedBy: InternalKeys.self)
        return try container.decodeIfPresent(String.self, forKey: .modelVersion)
    }
    func versioner() throws -> Versioner? {
        return try version().map(Versioner.init(version:))
    }
    func rawValue() throws -> RealtimeDatabaseValue? {
        let rawData = child(forPath: InternalKeys.raw.stringValue)
        return try rawData.asDatabaseValue()
    }
    func payload() throws -> RealtimeDatabaseValue? {
        let payloadData = child(forPath: InternalKeys.payload.stringValue)
        return try payloadData.asDatabaseValue()
    }
}

/// Internal protocol
public protocol _RealtimeValueUtilities {
    static func _isValid(asReference value: Self) -> Bool
    static func _isValid(asRelation value: Self) -> Bool
}
extension _RealtimeValueUtilities where Self: _RealtimeValue {
    public static func _isValid(asReference value: Self) -> Bool {
        return value.isRooted
    }
    public static func _isValid(asRelation value: Self) -> Bool {
        return value.isRooted
    }
}
extension _RealtimeValue: _RealtimeValueUtilities {}

/// Base protocol for all database entities
public protocol RealtimeValue: DatabaseKeyRepresentable, RealtimeDataRepresented {
    /// Indicates specific representation of this value, e.g. subclass or enum associated value
    var raw: RealtimeDatabaseValue? { get }
    /// Some data associated with value
    var payload: RealtimeDatabaseValue? { get }
    /// Node location in database
    var node: Node? { get }
}
/// RealtimeValue that can be initialized as standalone object
public protocol LazyRealtimeValue: RealtimeValue { // TODO: Unused
    associatedtype Options
    /// Creates new instance associated with database node
    ///
    /// - Parameter node: Node location for value
    /// - Parameter options: Dictionary of options
    init(in node: Node?, options: Options)
}
extension LazyRealtimeValue {
    /// Use current initializer if `RealtimeValue` has required user-defined options
    ///
    /// - Parameters:
    ///   - data: `RealtimeDataProtocol` object
    ///   - event: Event associated with data
    ///   - options: User-defined options
    /// - Throws: If data cannot be applied
    public init(data: RealtimeDataProtocol, event: DatabaseDataEvent, options: Options) throws {
        self.init(in: data.node, options: options)
        try apply(data, event: event)
    }
}

extension Optional: RealtimeValue, DatabaseKeyRepresentable, _RealtimeValueUtilities where Wrapped: RealtimeValue {
    public var raw: RealtimeDatabaseValue? { return self?.raw }
    public var payload: RealtimeDatabaseValue? { return self?.payload }
    public var node: Node? { return self?.node }

    public mutating func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        try self?.apply(data, event: event)
    }

    public static func _isValid(asReference value: Optional<Wrapped>) -> Bool {
        return value.map { $0.isRooted } ?? true
    }
    public static func _isValid(asRelation value: Optional<Wrapped>) -> Bool {
        return value.map { $0.isRooted } ?? true
    }
}
extension Optional: RealtimeDataRepresented where Wrapped: RealtimeDataRepresented {
    public init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        if data.exists() {
            self = .some(try Wrapped(data: data, event: event))
        } else {
            self = .none
        }
    }
}

public extension RealtimeValue {
    var dbKey: String! { return node?.key }

    /// Indicates that value has key
    var isKeyed: Bool { return node != nil }
    /// Indicates that value has no rooted node
    var isStandalone: Bool { return !isRooted }
    /// Indicates that value has parent node
    var isReferred: Bool { return node?.parent != nil }
    /// Indicates that value has rooted node
    var isRooted: Bool { return node?.isRooted ?? false }

    internal mutating func apply(parentDataIfNeeded parent: RealtimeDataProtocol, parentEvent: DatabaseDataEvent) throws {
        guard parentEvent == .value || dbKey.has(in: parent) else { return }

        /// if data has the data associated with current value,
        /// then data is full and we must pass `true` to `exactly` parameter.
        try apply(dbKey.child(from: parent), event: .value)
    }
}

/// A type that can used as key in `AssociatedValues` collection.
public typealias HashableValue = Hashable & RealtimeValue

public extension Equatable where Self: RealtimeValue {
    static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.node == rhs.node
    }
}
public extension Hashable where Self: RealtimeValue {
    func hash(into hasher: inout Hasher) {
        hasher.combine(dbKey)
    }
}
public extension Comparable where Self: RealtimeValue {
    static func < (lhs: Self, rhs: Self) -> Bool {
        return dbKeyLessThan(lhs, rhs: rhs)
    }

    static func dbKeyLessThan(_ lhs: Self, rhs: Self) -> Bool {
        switch (lhs.node, rhs.node) {
        case (.some(let l), .some(let r)): return l.key < r.key
        default: return false
        }
    }
}

// MARK: Extended Realtime Value

/// A type that makes possible to do someone actions related with value
public protocol RealtimeValueActions: RealtimeValueEvents {
    /// Single loading of value. Returns error if object hasn't rooted node.
    ///
    /// - Parameter completion: Closure that called on end loading or error
    func load(timeout: DispatchTimeInterval) -> RealtimeTask
    /// Indicates that value can observe. It is true when object has rooted node, otherwise false.
    var canObserve: Bool { get }
    /// Enables/disables auto downloading of the data and keeping in sync
    var keepSynced: Bool { get set }
    /// Runs or keeps observing value.
    ///
    /// If observing already run, value remembers each next call of function
    /// as requirement to keep observing while is not called `stopObserving()`.
    /// The call of function must be balanced with `stopObserving()` function.
    ///
    /// - Returns: True if running was successful or observing already run, otherwise false
    @discardableResult func runObserving() -> Bool
    /// Stops observing, if observers no more, else decreases the observers counter.
    func stopObserving()
}
/// A type that can receive Realtime database events
public protocol RealtimeValueEvents {
    /// Must call always before save(update) action
    ///
    /// - Parameters:
    ///   - transaction: Save transaction
    ///   - parent: Parent node to save
    ///   - key: Location in parent node
    func willSave(in transaction: Transaction, in parent: Node, by key: String)
    /// Notifies object that it has been saved in specified parent node
    ///
    /// - Parameter parent: Parent node
    /// - Parameter key: Location in parent node
    func didSave(in database: RealtimeDatabase, in parent: Node, by key: String)
    /// Must call always before save(update) action
    ///
    /// - Parameters:
    ///   - ancestor: Ancestor where action called
    ///   - transaction: Update transaction
    func willUpdate(through ancestor: Node, in transaction: Transaction)
    /// Notifies object that it has been updated through some ancestor node
    ///
    /// - Parameter ancestor: Ancestor where action called
    func didUpdate(through ancestor: Node)
    /// Must call always before removing action
    ///
    /// - Parameters:
    ///   - transaction: Remove transaction
    ///   - ancestor: Ancestor where remove action called
    func willRemove(in transaction: Transaction, from ancestor: Node)
    /// Notifies object that it has been removed from specified ancestor node
    ///
    /// - Parameter ancestor: Ancestor node
    func didRemove(from ancestor: Node)
}
extension RealtimeValueEvents where Self: RealtimeValue {
    func willSave(in transaction: Transaction, in parent: Node) {
        guard let node = self.node else {
            return debugFatalError("Unkeyed value will be saved to undefined location in parent node: \(parent.absolutePath)")
        }
        willSave(in: transaction, in: parent, by: node.key)
    }
    func didSave(in database: RealtimeDatabase, in parent: Node) {
        if let node = self.node {
            didSave(in: database, in: parent, by: node.key)
        } else {
            debugFatalError("Unkeyed value has been saved to undefined location in parent node: \(parent.absolutePath)")
        }
    }
    func didSave(in database: RealtimeDatabase) {
        if let parent = node?.parent, let node = self.node {
            didSave(in: database, in: parent, by: node.key)
        } else {
            debugFatalError("Rootless value has been saved to undefined location")
        }
    }
    func willRemove(in transaction: Transaction) {
        if let parent = node?.parent {
            willRemove(in: transaction, from: parent)
        } else {
            debugFatalError("Rootless value will be removed from itself location")
        }
    }
    func didRemove() {
        if let parent = node?.parent {
            didRemove(from: parent)
        } else {
            debugFatalError("Rootless value has been removed from itself location")
        }
    }
}

/// Value that can writes as single values
public protocol WritableRealtimeValue: RealtimeValue {
    /// Writes all local stored data to transaction as is. You shouldn't call it directly.
    ///
    /// - Parameters:
    ///   - transaction: Current transaction
    ///   - node: Database node where data will be store
    func write(to transaction: Transaction, by node: Node) throws
}
public extension RealtimeValue {
    func writeSystemValues(to transaction: Transaction, by node: Node) throws {
        if let rw = raw {
            transaction.addValue(rw, by: Node(key: InternalKeys.raw, parent: node))
        }
        if let pl = payload {
            transaction.addValue(pl, by: Node(key: InternalKeys.payload, parent: node))
        }
    }
}
extension WritableRealtimeValue where Self: Versionable {
    func writeSystemValues(to transaction: Transaction, by node: Node) throws {
        var versioner = Versioner()
        putVersion(into: &versioner)
        if !versioner.isEmpty {
            let finalizedVersion = versioner.finalize()
            transaction.addValue(RealtimeDatabaseValue(finalizedVersion), by: Node(key: InternalKeys.modelVersion, parent: node))
        }
        if let rw = raw {
            transaction.addValue(rw, by: Node(key: InternalKeys.raw, parent: node))
        }
        if let pl = payload {
            transaction.addValue(pl, by: Node(key: InternalKeys.payload, parent: node))
        }
    }
}

/// Value that can be changed partially
public protocol ChangeableRealtimeValue: RealtimeValue {
    /// Indicates that value was changed
    var hasChanges: Bool { get }

    /// Writes all changes of value to passed transaction
    ///
    /// - Parameters:
    ///   - transaction: Current transaction
    ///   - node: Node for this value
    func writeChanges(to transaction: Transaction, by node: Node) throws
}

