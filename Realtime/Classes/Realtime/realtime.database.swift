//
//  realtime.database.swift
//  Realtime
//
//  Created by Denis Koryttsev on 31/07/2018.
//

import Foundation
import FirebaseDatabase

/// A type that has access to the data is stored in associated database node
public protocol DatabaseNode {
    /// A Realtime data from database cache
    var cachedData: RealtimeDataProtocol? { get }
    /// Updates database node is writing a passed dictionary.
    ///
    /// - Parameters:
    ///   - keyValuePairs: Dictionary to write
    ///   - completion: Closure to receive result of writing
    func update(use keyValuePairs: [String: Any], completion: ((Error?, DatabaseNode) -> Void)?)
}
extension DatabaseReference: DatabaseNode {
    public var cachedData: RealtimeDataProtocol? { return nil }
    public func update(use keyValuePairs: [String : Any], completion: ((Error?, DatabaseNode) -> Void)?) {
        if let completion = completion {
            updateChildValues(keyValuePairs, withCompletionBlock: completion)
        } else {
            updateChildValues(keyValuePairs)
        }
    }
}

/// Realtime database cache policy
///
/// - default: Default cache policy (usually, it corresponds `inMemory` case)
/// - noCache: No one cache is not used
/// - inMemory: The data stored in memory
/// - persistance: The data will be persisted to on-device (disk) storage.
public enum CachePolicy {
    case `default`
    case noCache
    case inMemory
    case persistance
//    case custom(RealtimeDatabase)
}

/// A event that corresponds some type of data mutating
///
/// - childAdded: A new child node is added to a location.
/// - childRemoved: A child node is removed from a location.
/// - childChanged: A child node at a location changes.
/// - childMoved: A child node moves relative to the other child nodes at a location.
/// - value: Any data changes at a location or, recursively, at any child node.
public enum DatabaseDataEvent: Int {
    case childAdded
    case childRemoved
    case childChanged
    case childMoved
    case value
}
extension DatabaseDataEvent {
    var firebase: DataEventType {
        return DataEventType(rawValue: rawValue)!
    }
}

/// A database that can used in `Realtime` framework.
public protocol RealtimeDatabase: class {
    /// A database cache policy.
    var cachePolicy: CachePolicy { get set }

    /// Generates an automatically calculated database key
    func generateAutoID() -> String
    /// Returns object is associated with database node,
    /// that makes access to manage data.
    ///
    /// - Parameter valueNode:
    /// - Returns: Object that has access to database data
    func node(with referenceNode: Node) -> DatabaseNode
    /// Performs the writing of a changes that contains in passed Transaction
    ///
    /// - Parameters:
    ///   - transaction: Write transaction
    ///   - completion: Closure to receive result of operation
    func commit(transaction: Transaction, completion: ((Error?, DatabaseNode) -> Void)?)
    /// Loads data by database reference
    ///
    /// - Parameters:
    ///   - node: Realtime database reference
    ///   - completion: Closure to receive data
    ///   - onCancel: Closure to receive cancel event
    func load(
        for node: Node,
        completion: @escaping (RealtimeDataProtocol) -> Void,
        onCancel: ((Error) -> Void)?
    )
    /// Runs the observation of data by specified database reference
    ///
    /// - Parameters:
    ///   - event: A type of data mutating
    ///   - node: Realtime database reference
    ///   - onUpdate: Closure to receive data
    ///   - onCancel: Closure to receive cancel event
    /// - Returns: A token that should use to stop the observation
    func observe(
        _ event: DatabaseDataEvent,
        on node: Node,
        onUpdate: @escaping (RealtimeDataProtocol) -> Void,
        onCancel: ((Error) -> Void)?
    ) -> UInt
    /// Removes all of existing observers on passed database reference.
    ///
    /// - Parameter node: Database reference
    func removeAllObservers(for node: Node)
    /// Removes observer of database data that is associated with token.
    ///
    /// - Parameters:
    ///   - node: Database reference
    ///   - token: An unsigned integer value
    func removeObserver(for node: Node, with token: UInt)
}
extension Database: RealtimeDatabase {
    public var cachePolicy: CachePolicy {
        set {
            switch newValue {
            case .persistance:
                isPersistenceEnabled = true
            default:
                RealtimeApp.app.cachePolicy = newValue
                isPersistenceEnabled = false
            }
        }
        get {
            if isPersistenceEnabled {
                return .persistance
            } else {
                return RealtimeApp.app.cachePolicy
            }
        }
    }

    public func generateAutoID() -> String {
        return reference().childByAutoId().key
    }

    public func node(with valueNode: Node) -> DatabaseNode {
        if valueNode.isRoot {
            return reference()
        } else {
            return reference(withPath: valueNode.rootPath)
        }
    }

    public func commit(transaction: Transaction, completion: ((Error?, DatabaseNode) -> Void)?) {
        let updateNode = transaction.updateNode
        guard updateNode.childs.count > 0 else {
            fatalError("Try commit empty transaction")
        }

        var nearest = updateNode
        while nearest.childs.count == 1, let next = nearest.childs.first as? ObjectNode {
            nearest = next
        }
        let updateValue = nearest.updateValue
        if updateValue.count > 0 {
            node(with: nearest.location).update(use: nearest.updateValue, completion: completion)
        }
    }

    public func load(
        for node: Node,
        completion: @escaping (RealtimeDataProtocol) -> Void,
        onCancel: ((Error) -> Void)?) {
        node.reference(for: self).observeSingleEvent(
            of: .value,
            with: completion,
            withCancel: onCancel
        )
    }

    public func observe(
        _ event: DatabaseDataEvent,
        on node: Node,
        onUpdate: @escaping (RealtimeDataProtocol) -> Void,
        onCancel: ((Error) -> Void)?) -> UInt {
        return node.reference(for: self).observe(event.firebase, with: onUpdate, withCancel: onCancel)
    }

    public func removeAllObservers(for node: Node) {
        node.reference(for: self).removeAllObservers()
    }

    public func removeObserver(for node: Node, with token: UInt) {
        node.reference(for: self).removeObserver(withHandle: token)
    }
}

/// An object that contains value is associated by database reference.
public protocol UpdateNode: RealtimeDataProtocol, DatabaseNode {
    /// Database location reference
    var location: Node { get }
    /// Value
    var value: Any? { get }
    /// Fills a contained values to container.
    ///
    /// - Parameters:
    ///   - ancestor: An ancestor database reference
    ///   - container: `inout` dictionary container.
    func fill(from ancestor: Node, into container: inout [String: Any])
}
extension UpdateNode {
    public var cachedData: RealtimeDataProtocol? { return self }
    public var database: RealtimeDatabase? { return CacheNode.root }
    public var node: Node? { return location }
}

class ValueNode: UpdateNode {
    let location: Node
    var value: Any?

    func fill(from ancestor: Node, into container: inout [String: Any]) {
        container[location.path(from: ancestor)] = value as Any
    }

    required init(node: Node, value: Any?) {
        self.location = node
        self.value = value
    }

    func update(use keyValuePairs: [String : Any], completion: ((Error?, DatabaseNode) -> Void)?) {
        fatalError("Database value node cannot updated with multikeyed object")
    }
}

class FileNode: ValueNode {
    override func fill(from ancestor: Node, into container: inout [String: Any]) {}
    var database: RealtimeDatabase? { return nil }
}

class CacheNode: ObjectNode, RealtimeDatabase {
    static let root: CacheNode = CacheNode(node: .root)

    var cachePolicy: CachePolicy {
        set {
            switch newValue {
            case .persistance: break
                /// makes persistance configuration
            default: break
            }
        }
        get { return .inMemory }
    }

    func generateAutoID() -> String {
        return Database.database().generateAutoID()
    }

    func node(with valueNode: Node) -> DatabaseNode {
        if valueNode.isRoot {
            return self
        } else {
            let path = valueNode.rootPath
            return child(by: path.split(separator: "/").lazy.map(String.init)) ?? ValueNode(node: Node(key: path, parent: location), value: nil)
        }
    }

    func commit(transaction: Transaction, completion: ((Error?, DatabaseNode) -> Void)?) {
        do {
            try merge(with: transaction.updateNode, conflictResolver: { _, new in new.value })
            completion?(nil, self)
        } catch let e {
            completion?(e, self)
        }
    }

    func removeAllObservers(for node: Node) {
        fatalError()
    }

    func removeObserver(for node: Node, with token: UInt) {
        fatalError()
    }

    func load(for node: Node, completion: @escaping (RealtimeDataProtocol) -> Void, onCancel: ((Error) -> Void)?) {
        completion(child(forPath: node.rootPath))
    }

    func observe(_ event: DatabaseDataEvent, on node: Node, onUpdate: @escaping (RealtimeDataProtocol) -> Void, onCancel: ((Error) -> Void)?) -> UInt {
        fatalError()
    }
}

class ObjectNode: UpdateNode, CustomStringConvertible {
    let location: Node
    var childs: [UpdateNode] = []
    var isCompound: Bool { return true }
    var value: Any? {
        return updateValue
    }
    var updateValue: [String: Any] {
        var val: [String: Any] = [:]
        fill(from: location, into: &val)
        return val
    }
    var files: [FileNode] {
        return childs.reduce(into: [], { (res, node) in
            if case let objNode as ObjectNode = node {
                res.append(contentsOf: objNode.files)
            } else if case let fileNode as FileNode = node {
                res.append(fileNode)
            }
        })
    }
    var description: String {
        return """
            values: \(updateValue),
            files: \(files)
        """
    }

    init(node: Node) {
        self.location = node
    }

    func fill(from ancestor: Node, into container: inout [String: Any]) {
        childs.forEach { $0.fill(from: ancestor, into: &container) }
    }

    func update(use keyValuePairs: [String : Any], completion: ((Error?, DatabaseNode) -> Void)?) {
        do {
            try keyValuePairs.forEach { (key, value) in
                let path = key.split(separator: "/").map(String.init)
                let nearest = nearestChild(by: path)
                if nearest.leftPath.isEmpty {
                    try update(dbNode: nearest.node, with: value)
                } else {
                    var nearestNode: ObjectNode
                    if case _ as ValueNode = nearest.node {
                        nearestNode = ObjectNode(node: nearest.node.location)
                        try replaceNode(with: nearestNode)
                    } else if case let objNode as ObjectNode = nearest.node {
                        nearestNode = objNode
                    } else {
                        throw RealtimeError(source: .transaction([]), description: "Internal error")
                    }
                    for (i, part) in nearest.leftPath.enumerated() {
                        let node = Node(key: part, parent: nearestNode.location)
                        if i == nearest.leftPath.count - 1 {
                            nearestNode.childs.append(ValueNode(node: node, value: value))
                        } else {
                            let next = ObjectNode(node: node)
                            nearestNode.childs.append(next)
                            nearestNode = next
                        }
                    }
                }
            }
            completion?(nil, self)
        } catch let e {
            completion?(e, self)
        }
    }

    private func update(dbNode: UpdateNode, with value: Any) throws {
        if case let valNode as ValueNode = dbNode {
            valNode.value = value
        } else if case _ as ObjectNode = dbNode {
            try replaceNode(with: ValueNode(node: dbNode.location, value: value))
        } else {
            throw RealtimeError(source: .transaction([]), description: "Internal error")
        }
    }

    private func replaceNode(with dbNode: UpdateNode) throws {
        if case let parent as ObjectNode = child(by: dbNode.location.ancestor(onLevelUp: 1)!.rootPath.split(separator: "/").lazy.map(String.init)) {
            parent.childs.remove(at: parent.childs.index(where: { $0.node === dbNode.node })!)
            parent.childs.append(dbNode)
        } else {
            throw RealtimeError(source: .transaction([]), description: "Internal error")
        }
    }
}

extension ObjectNode {
    func child(by path: [String]) -> UpdateNode? {
        guard !path.isEmpty else { return self }

        var path = path
        let first = path.remove(at: 0)
        guard let f = childs.first(where: { $0.location.key == first }) else {
            return nil
        }

        if case let o as ObjectNode = f {
            return o.child(by: path)
        } else {
            return path.isEmpty ? f : nil
        }
    }
    func nearestChild(by path: [String]) -> (node: UpdateNode, leftPath: [String]) {
        guard !path.isEmpty else { return (self, path) }

        var path = path
        let first = path.remove(at: 0)
        guard let f = childs.first(where: { $0.location.key == first }) else {
            path.insert(first, at: 0)
            return (self, path)
        }

        if case let o as ObjectNode = f {
            return o.nearestChild(by: path)
        } else {
            return (f, path)
        }
    }
    func merge(with other: ObjectNode, conflictResolver: (UpdateNode, UpdateNode) -> Any?) throws {
        try other.childs.forEach { (child) in
            if let currentChild = childs.first(where: { $0.location == child.location }) {
                if let objectChild = currentChild as? ObjectNode {
                    try objectChild.merge(with: child as! ObjectNode, conflictResolver: conflictResolver)
                } else if case let c as ValueNode = currentChild {
                    if type(of: c) == type(of: child) {
                        c.value = conflictResolver(currentChild, child)
                    } else {
                        throw RealtimeError(source: .cache, description: "Database value and storage value located in the same node.")
                    }
                } else {
                    throw RealtimeError(source: .cache, description: "Database value and storage value located in the same node.")
                }
            } else {
                childs.append(child)
            }
        }
    }
}

extension UpdateNode where Self: RealtimeDataProtocol {
    public var priority: Any? { return nil }
}

extension ValueNode: RealtimeDataProtocol, Sequence {
    var priority: Any? { return nil }
    var childrenCount: UInt { return 0 }
    func makeIterator() -> AnyIterator<RealtimeDataProtocol> { return AnyIterator(EmptyIterator()) }
    func exists() -> Bool { return value != nil }
    func hasChildren() -> Bool { return false }
    func hasChild(_ childPathString: String) -> Bool { return false }
    func child(forPath path: String) -> RealtimeDataProtocol { return ValueNode(node: Node(key: path, parent: location), value: nil) }
    func compactMap<ElementOfResult>(_ transform: (RealtimeDataProtocol) throws -> ElementOfResult?) rethrows -> [ElementOfResult] {
        return []
    }
    func forEach(_ body: (RealtimeDataProtocol) throws -> Void) rethrows {}
    func map<T>(_ transform: (RealtimeDataProtocol) throws -> T) rethrows -> [T] { return [] }
    var debugDescription: String { return "\(location.rootPath): \(value as Any)" }
    var description: String { return debugDescription }
}

/// Cache in future
extension ObjectNode: RealtimeDataProtocol, Sequence {
    public var childrenCount: UInt {
        return UInt(childs.count)
    }

    public func makeIterator() -> AnyIterator<RealtimeDataProtocol> {
        return AnyIterator(childs.lazy.map { $0 as RealtimeDataProtocol }.makeIterator())
    }

    public func exists() -> Bool {
        return true
    }

    public func hasChildren() -> Bool {
        return childs.count > 0
    }

    public func hasChild(_ childPathString: String) -> Bool {
        return child(by: childPathString.split(separator: "/").lazy.map(String.init)) != nil
    }

    public func child(forPath path: String) -> RealtimeDataProtocol {
        return child(by: path.split(separator: "/").lazy.map(String.init)) ?? ValueNode(node: Node(key: path, parent: location), value: nil)
    }

    public func map<T>(_ transform: (RealtimeDataProtocol) throws -> T) rethrows -> [T] {
        return try childs.map(transform)
    }

    public func compactMap<ElementOfResult>(_ transform: (RealtimeDataProtocol) throws -> ElementOfResult?) rethrows -> [ElementOfResult] {
        return try childs.compactMap(transform)
    }

    public func forEach(_ body: (RealtimeDataProtocol) throws -> Void) rethrows {
        return try childs.forEach(body)
    }

    public var debugDescription: String { return description }
}
