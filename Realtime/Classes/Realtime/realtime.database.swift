//
//  realtime.database.swift
//  Realtime
//
//  Created by Denis Koryttsev on 31/07/2018.
//

import Foundation
import FirebaseDatabase

public protocol DatabaseNode {
    var cachedData: FireDataProtocol? { get }
    func update(use keyValuePairs: [String: Any], completion: ((Error?, DatabaseNode) -> Void)?)
}
extension DatabaseReference: DatabaseNode {
    public var cachedData: FireDataProtocol? { return nil }
    public func update(use keyValuePairs: [String : Any], completion: ((Error?, DatabaseNode) -> Void)?) {
        if let completion = completion {
            updateChildValues(keyValuePairs, withCompletionBlock: completion)
        } else {
            updateChildValues(keyValuePairs)
        }
    }
}

public protocol RealtimeDatabase {
    func generateAutoID() -> String

    func node() -> DatabaseNode
    func node(with valueNode: Node) -> DatabaseNode

    func commit(transaction: RealtimeTransaction, completion: ((Error?, DatabaseNode) -> Void)?)

    func load(
        for node: Node,
        completion: @escaping (FireDataProtocol) -> Void,
        onCancel: ((Error?) -> Void)?
    )

    func observe(
        _ event: DataEventType,
        on node: Node,
        onUpdate: @escaping (FireDataProtocol) -> Void,
        onCancel: ((Error?) -> Void)?
    ) -> UInt

    func removeAllObservers(for node: Node)
    func removeObserver(for node: Node, with token: UInt)
}
extension Database: RealtimeDatabase {
    public func generateAutoID() -> String {
        return reference().childByAutoId().key
    }

    public func node() -> DatabaseNode {
        return reference()
    }

    public func node(with valueNode: Node) -> DatabaseNode {
        return reference(withPath: valueNode.rootPath)
    }

    public func commit(transaction: RealtimeTransaction, completion: ((Error?, DatabaseNode) -> Void)?) {
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
        completion: @escaping (FireDataProtocol) -> Void,
        onCancel: ((Error?) -> Void)?) {
        node.reference(for: self).observeSingleEvent(
            of: .value,
            with: completion,
            withCancel: onCancel
        )
    }

    public func observe(
        _ event: DataEventType,
        on node: Node,
        onUpdate: @escaping (FireDataProtocol) -> Void,
        onCancel: ((Error?) -> Void)?) -> UInt {
        return node.reference(for: self).observe(event, with: onUpdate, withCancel: onCancel)
    }

    public func removeAllObservers(for node: Node) {
        node.reference(for: self).removeAllObservers()
    }

    public func removeObserver(for node: Node, with token: UInt) {
        node.reference(for: self).removeObserver(withHandle: token)
    }
}

public protocol UpdateNode: FireDataProtocol, DatabaseNode {
    var location: Node { get }
    var value: Any? { get }
    func fill(from ancestor: Node, into container: inout [String: Any])
}
extension UpdateNode {
    public var cachedData: FireDataProtocol? { return self }
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

    func generateAutoID() -> String {
        return Database.database().generateAutoID()
    }

    func node() -> DatabaseNode {
        return self
    }

    func node(with valueNode: Node) -> DatabaseNode {
        let path = valueNode.rootPath
        return child(by: path.split(separator: "/").lazy.map(String.init)) ?? ValueNode(node: Node(key: path, parent: location), value: nil)
    }

    func commit(transaction: RealtimeTransaction, completion: ((Error?, DatabaseNode) -> Void)?) {
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

    func load(for node: Node, completion: @escaping (FireDataProtocol) -> Void, onCancel: ((Error?) -> Void)?) {
        completion(child(forPath: node.rootPath))
    }

    func observe(_ event: DataEventType, on node: Node, onUpdate: @escaping (FireDataProtocol) -> Void, onCancel: ((Error?) -> Void)?) -> UInt {
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
    var description: String { return String(describing: updateValue) }

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

extension UpdateNode where Self: FireDataProtocol {
    public var priority: Any? { return nil }
}

extension ValueNode: FireDataProtocol, Sequence {
    var priority: Any? { return nil }
    var childrenCount: UInt { return 0 }
    func makeIterator() -> AnyIterator<FireDataProtocol> { return AnyIterator(EmptyIterator()) }
    func exists() -> Bool { return value != nil }
    func hasChildren() -> Bool { return false }
    func hasChild(_ childPathString: String) -> Bool { return false }
    func child(forPath path: String) -> FireDataProtocol { return ValueNode(node: Node(key: path, parent: location), value: nil) }
    func compactMap<ElementOfResult>(_ transform: (FireDataProtocol) throws -> ElementOfResult?) rethrows -> [ElementOfResult] {
        return []
    }
    func forEach(_ body: (FireDataProtocol) throws -> Void) rethrows {}
    func map<T>(_ transform: (FireDataProtocol) throws -> T) rethrows -> [T] { return [] }
    var debugDescription: String { return "\(location.rootPath): \(value as Any)" }
    var description: String { return debugDescription }
}

/// Cache in future
extension ObjectNode: FireDataProtocol, Sequence {
    public var childrenCount: UInt {
        return UInt(childs.count)
    }

    public func makeIterator() -> AnyIterator<FireDataProtocol> {
        return AnyIterator(childs.lazy.map { $0 as FireDataProtocol }.makeIterator())
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

    public func child(forPath path: String) -> FireDataProtocol {
        return child(by: path.split(separator: "/").lazy.map(String.init)) ?? ValueNode(node: Node(key: path, parent: location), value: nil)
    }

    public func map<T>(_ transform: (FireDataProtocol) throws -> T) rethrows -> [T] {
        return try childs.map(transform)
    }

    public func compactMap<ElementOfResult>(_ transform: (FireDataProtocol) throws -> ElementOfResult?) rethrows -> [ElementOfResult] {
        return try childs.compactMap(transform)
    }

    public func forEach(_ body: (FireDataProtocol) throws -> Void) rethrows {
        return try childs.forEach(body)
    }

    public var debugDescription: String { return description }
}
