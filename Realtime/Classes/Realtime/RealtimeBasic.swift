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

public protocol FireDataProtocol: Decoder, CustomDebugStringConvertible, CustomStringConvertible {
    var value: Any? { get }
    var priority: Any? { get }
    var children: NSEnumerator { get }
    var dataKey: String? { get }
    var dataRef: DatabaseReference? { get }
    var childrenCount: UInt { get }
    func exists() -> Bool
    func hasChildren() -> Bool
    func hasChild(_ childPathString: String) -> Bool
    func child(forPath path: String) -> FireDataProtocol
    func map<T>(_ transform: (FireDataProtocol) throws -> T) rethrows -> [T]
    func compactMap<ElementOfResult>(_ transform: (FireDataProtocol) throws -> ElementOfResult?) rethrows -> [ElementOfResult]
    func forEach(_ body: (FireDataProtocol) throws -> Swift.Void) rethrows
}
extension Sequence where Self: FireDataProtocol {
    public func makeIterator() -> AnyIterator<FireDataProtocol> {
        let childs = children
        return AnyIterator {
            return unsafeBitCast(childs.nextObject(), to: FireDataProtocol.self)
        }
    }
}

extension DataSnapshot: FireDataProtocol, Sequence {
    public var dataKey: String? {
        return key
    }

    public var dataRef: DatabaseReference? {
        return ref
    }

    public func child(forPath path: String) -> FireDataProtocol {
        return childSnapshot(forPath: path)
    }
}
extension MutableData: FireDataProtocol, Sequence {
    public var dataKey: String? {
        return key
    }

    public var dataRef: DatabaseReference? {
        return nil
    }

    public func exists() -> Bool {
        return value.map { !($0 is NSNull) } ?? false
    }

    public func child(forPath path: String) -> FireDataProtocol {
        return childData(byAppendingPath: path)
    }
    
    public func hasChild(_ childPathString: String) -> Bool {
        return hasChild(atPath: childPathString)
    }
}

public protocol FireDataRepresented {
    init(fireData: FireDataProtocol) throws
}
public protocol FireDataValueRepresented {
    var fireValue: FireDataValue { get }
}

public protocol DatabaseKeyRepresentable {
    var dbKey: String! { get }
}

// MARK: RealtimeValue

public struct RealtimeValueOption: Hashable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}
extension RealtimeValueOption {
    static var payload: RealtimeValueOption = RealtimeValueOption("realtime.value.payload")
}

/// Base protocol for all database entities
public protocol RealtimeValue: DatabaseKeyRepresentable, FireDataRepresented {
    /// Some data associated with value
    var payload: [String: FireDataValue]? { get }
    /// Node location in database
    var node: Node? { get }

    /// Designed initializer
    ///
    /// - Parameter node: Node location for value
    init(in node: Node?, options: [RealtimeValueOption: Any])
    /// Applies value of data snapshot
    ///
    /// - Parameters:
    ///   - snapshot: Snapshot value
    ///   - strongly: Indicates that snapshot should be applied as is (for example, empty values will be set to `nil`).
    ///               Pass `false` if snapshot represents part of data (for example filtered list).
    func apply(_ data: FireDataProtocol, strongly: Bool)

    /// Writes all local stored data to transaction as is. You shouldn't call it directly.
    ///
    /// - Parameters:
    ///   - transaction: Current transaction
    ///   - node: Database node where data will be store
    func write(to transaction: RealtimeTransaction, by node: Node)
}
public extension RealtimeValue {
    var dbKey: String! { return node?.key }
    var dbRef: DatabaseReference? {
        return node.flatMap { $0.isRooted ? $0.reference : nil }
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
            apply(fireData, strongly: false)
        }
    }

    func apply(_ data: FireDataProtocol) {
        apply(data, strongly: true)
    }
    func apply(parentDataIfNeeded parent: FireDataProtocol, strongly: Bool) {
        guard strongly || dbKey.has(in: parent) else { return }

        apply(dbKey.child(from: parent), strongly: strongly)
    }
}
extension HasDefaultLiteral where Self: RealtimeValue {}

public extension Hashable where Self: RealtimeValue {
    var hashValue: Int { return dbKey.hashValue }
    static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.node == rhs.node
    }
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

// MARK: Extended Realtime Value

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

public protocol RealtimeValueActions: RealtimeValueEvents {
    /// Single loading of value. Returns error if object hasn't rooted node.
    ///
    /// - Parameter completion: Closure that called on end loading or error
    func load(completion: Assign<(error: Error?, ref: DatabaseReference)>?)
    /// Indicates that value can observe. It is true when object has rooted node, otherwise false.
    var canObserve: Bool { get }
    /// Runs observing value, if
    ///
    /// - Returns: True if running was successful or observing already run, otherwise false
    @discardableResult func runObserving() -> Bool
    /// Stops observing, if observers no more.
    func stopObserving()
}
