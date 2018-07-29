//
//  RealtimeBasic.swift
//  Realtime
//
//  Created by Denis Koryttsev on 31/01/2018.
//

import Foundation
import FirebaseDatabase

struct RealtimeError: Error {
    let localizedDescription: String

    init(_ descr: String) {
        self.localizedDescription = descr
    }
}

internal let lazyStoragePath = ".storage"

public protocol DatabaseKeyRepresentable {
    var dbKey: String! { get }
}

// MARK: RealtimeValue

typealias InternalPayload = (version: Int?, raw: FireDataValue?)

public struct RealtimeValueOption: Hashable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}
public extension RealtimeValueOption {
    static let payload: RealtimeValueOption = RealtimeValueOption("realtime.value.payload")
    internal static let internalPayload: RealtimeValueOption = RealtimeValueOption("realtime.value.internalPayload")
}
public extension Dictionary where Key == RealtimeValueOption {
    var version: Int? {
        return (self[.internalPayload] as? InternalPayload)?.version
    }
    var rawValue: FireDataValue? {
        return (self[.internalPayload] as? InternalPayload)?.raw
    }
}
public extension FireDataProtocol {
    var version: Int? {
        return InternalKeys.modelVersion.map(from: self)
    }
    var rawValue: FireDataValue? {
        return InternalKeys.raw.map(from: self)
    }
}

/// Base protocol for all database entities
public protocol RealtimeValue: DatabaseKeyRepresentable, FireDataRepresented {
    /// Current version of value.
    var version: Int? { get }
    /// Indicates specific representation of this value, e.g. subclass or enum associated value
    var raw: FireDataValue? { get }
    /// Some data associated with value
    var payload: [String: FireDataValue]? { get }
    /// Node location in database
    var node: Node? { get }

    /// Designed initializer
    ///
    /// - Parameter node: Node location for value
    init(in node: Node?, options: [RealtimeValueOption: Any])
}

extension Optional: RealtimeValue, DatabaseKeyRepresentable where Wrapped: RealtimeValue {
    public var version: Int? { return self?.version }
    public var raw: FireDataValue? { return self?.raw }
    public var payload: [String : FireDataValue]? { return self?.payload }
    public var node: Node? { return self?.node }
    public init(in node: Node?, options: [RealtimeValueOption : Any]) {
        self = .some(Wrapped(in: node, options: options))
    }
    public mutating func apply(_ data: FireDataProtocol, strongly: Bool) throws {
        try self?.apply(data, strongly: strongly)
    }
}
extension Optional: FireDataRepresented where Wrapped: FireDataRepresented {
    public init(fireData: FireDataProtocol) throws {
        if fireData.exists() {
            self = .some(try Wrapped(fireData: fireData))
        } else {
            self = .none
        }
    }
}

public extension RealtimeValue {
    var dbKey: String! { return node?.key }
    func dbRef(_ database: Database = Database.database()) -> DatabaseReference? {
        return node.flatMap { $0.isRooted ? $0.reference(for: database) : nil }
    }

    var isInserted: Bool { return isRooted }
    var isStandalone: Bool { return !isRooted }
    var isReferred: Bool { return node?.parent != nil }
    var isRooted: Bool { return node?.isRooted ?? false }

    init(in node: Node?) { self.init(in: node, options: [:]) }
    init() { self.init(in: nil) }
    init(fireData: FireDataProtocol, strongly: Bool) throws {
        if strongly {
            try self.init(fireData: fireData)
        } else {
            self.init(in: fireData.dataRef.map(Node.from))
            try apply(fireData, strongly: false)
        }
    }

    mutating func apply(parentDataIfNeeded parent: FireDataProtocol, strongly: Bool) throws {
        guard strongly || dbKey.has(in: parent) else { return }

        try apply(dbKey.child(from: parent), strongly: strongly)
    }
}
extension HasDefaultLiteral where Self: RealtimeValue {}

public extension Hashable where Self: RealtimeValue {
    var hashValue: Int { return dbKey.hashValue }
    static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.node == rhs.node
    }
}

// MARK: Extended Realtime Value

public protocol RealtimeValueActions: RealtimeValueEvents {
    /// Single loading of value. Returns error if object hasn't rooted node.
    ///
    /// - Parameter completion: Closure that called on end loading or error
    func load(completion: Assign<Error?>?)
    /// Indicates that value can observe. It is true when object has rooted node, otherwise false.
    var canObserve: Bool { get }
    /// Runs observing value, if
    ///
    /// - Returns: True if running was successful or observing already run, otherwise false
    @discardableResult func runObserving() -> Bool
    /// Stops observing, if observers no more.
    func stopObserving()
}
public protocol RealtimeValueEvents {
    /// Must call always before save(update) action
    ///
    /// - Parameters:
    ///   - transaction: Save transaction
    ///   - parent: Parent node to save
    ///   - key: Location in parent node
    func willSave(in transaction: RealtimeTransaction, in parent: Node, by key: String)
    /// Notifies object that it has been saved in specified parent node
    ///
    /// - Parameter parent: Parent node
    /// - Parameter key: Location in parent node
    func didSave(in parent: Node, by key: String)
    /// Must call always before removing action
    ///
    /// - Parameters:
    ///   - transaction: Remove transaction
    ///   - ancestor: Ancestor where remove action called
    func willRemove(in transaction: RealtimeTransaction, from ancestor: Node)
    /// Notifies object that it has been removed from specified ancestor node
    ///
    /// - Parameter ancestor: Ancestor node
    func didRemove(from ancestor: Node)
}
extension RealtimeValueEvents where Self: RealtimeValue {
    func willSave(in transaction: RealtimeTransaction, in parent: Node) {
        guard let node = self.node else {
            return debugFatalError("Unkeyed value will be saved to undefined location in parent node: \(parent.rootPath)")
        }
        willSave(in: transaction, in: parent, by: node.key)
    }
    func didSave(in parent: Node) {
        if let node = self.node {
            didSave(in: parent, by: node.key)
        } else {
            debugFatalError("Unkeyed value has been saved to undefined location in parent node: \(parent.rootPath)")
        }
    }
    func didSave() {
        if let parent = node?.parent, let node = self.node {
            didSave(in: parent, by: node.key)
        } else {
            debugFatalError("Rootless value has been saved to undefined location")
        }
    }
    func willRemove(in transaction: RealtimeTransaction) {
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

/// Values that can writes as single values
public protocol WritableRealtimeValue: RealtimeValue {
    /// Writes all local stored data to transaction as is. You shouldn't call it directly.
    ///
    /// - Parameters:
    ///   - transaction: Current transaction
    ///   - node: Database node where data will be store
    func write(to transaction: RealtimeTransaction, by node: Node)
}

/// Values that can be changed partially
public protocol ChangeableRealtimeValue: RealtimeValue {
    /// Indicates that value was changed
    var hasChanges: Bool { get }

    /// Writes all changes of value to passed transaction
    ///
    /// - Parameters:
    ///   - transaction: Current transaction
    ///   - node: Node for this value
    func writeChanges(to transaction: RealtimeTransaction, by node: Node)
}

