//
//  cache.realtime.swift
//  Realtime
//
//  Created by Denis Koryttsev on 19/11/2018.
//

import Foundation
import FirebaseDatabase

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
    public var storage: RealtimeStorage? { return CacheNode.root }
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

class FileNode: ValueNode, StorageNode {
    var metadata: [String: Any] = [:]
    func delete(completion: ((Error?) -> Void)?) {
        self.value = nil
        self.metadata.removeAll()
    }

    func put(_ data: Data, metadata: [String : Any]?, completion: @escaping ([String : Any]?, Error?) -> Void) {
        self.value = data
        if let md = metadata {
            self.metadata = md
        }
        completion(metadata, nil)
    }

    override func fill(from ancestor: Node, into container: inout [String: Any]) {}
    var database: RealtimeDatabase? { return nil }
}

class CacheNode: ObjectNode, RealtimeDatabase, RealtimeStorage {
    var isConnectionActive: AnyListenable<Bool> { return AnyListenable(Constant(true)) }

    static let root: CacheNode = CacheNode(node: .root)
    var observers: [Node: Repeater<(RealtimeDataProtocol, DatabaseDataEvent)>] = [:]

    func clear() {
        childs.removeAll()
    }

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
        return Database.database().generateAutoID() // need avoid using Firebase database
    }

    func node(with referenceNode: Node) -> DatabaseNode {
        if referenceNode.isRoot {
            return self
        } else {
            return child(by: referenceNode) ?? ValueNode(node: referenceNode, value: nil)
        }
    }

    func commit(transaction: Transaction, completion: ((Error?, DatabaseNode) -> Void)?) {
        do {
            var notifications: [Node: (RealtimeDataProtocol, DatabaseDataEvent)] = [:]
            try merge(
                with: transaction.updateNode,
                conflictResolver: { old, new in
                    if observers.count > 0 {
                        notifications[new.location] = (new, .value)
                        new.location.parent.map({ notifications[$0] = (new, .child(new.value == nil ? .removed : .changed)) })
                    }
                    return new.value
                },
                didAppend: observers.isEmpty ? nil : { parent, child in
                    notifications[child.location] = (child, .value)
                    notifications[parent.location] = (child, .child(child.value == nil ? .removed : .added))
                }
            )
            completion?(nil, self)
            notifications.forEach { (args) in
                observers[args.key]?.send(.value(args.value))
            }
        } catch let e {
            completion?(e, self)
        }
    }

    func removeAllObservers(for node: Node) {
        observers.removeValue(forKey: node)
    }

    func removeObserver(for node: Node, with token: UInt) {
        observers[node]?.remove(token)
    }

    func load(for node: Node, timeout: DispatchTimeInterval, completion: @escaping (RealtimeDataProtocol) -> Void, onCancel: ((Error) -> Void)?) {
        if node == location {
            completion(self)
        } else {
            completion(child(by: node) ?? ValueNode(node: node, value: nil))
        }
    }

    private func repeater(for node: Node) -> Repeater<(RealtimeDataProtocol, DatabaseDataEvent)> {
        guard let rep = observers[node] else {
            let rep = Repeater<(RealtimeDataProtocol, DatabaseDataEvent)>(dispatcher: .default)
            observers[node] = rep
            return rep
        }
        return rep
    }

    func observe(_ event: DatabaseDataEvent, on node: Node, onUpdate: @escaping (RealtimeDataProtocol) -> Void, onCancel: ((Error) -> Void)?) -> UInt {
        let repeater: Repeater<(RealtimeDataProtocol, DatabaseDataEvent)> = self.repeater(for: node)
        
        return repeater.add(Closure.just { e in
            switch e {
            case .value(let val): onUpdate(val.0)
            case .error(let err): onCancel?(err)
            }
        }.filter({ (e) -> Bool in
            switch (e, event) {
            case (.error, _): return true
            case (.value(_, .value), .value): return true
            case (.value(_, .child(let received)), .child(let defined)):
                return received == defined
            default: return false
            }
        }))
    }

    // storage

    func node(with referenceNode: Node) -> StorageNode {
        if referenceNode.isRoot {
            fatalError("File cannot be put in root")
        } else {
            if case let file as FileNode = child(by: referenceNode) {
                return file
            } else {
                return FileNode(node: referenceNode, value: nil)
            }
        }
    }

    func commit(transaction: Transaction, completion: @escaping ([Transaction.FileCompletion]) -> Void) {
        let results = transaction.updateNode.files.map { (file) -> Transaction.FileCompletion in
            do {
                let nearest = self.nearestChild(by: Array(file.location.map({ $0.key }).reversed().dropFirst()))
                if nearest.leftPath.isEmpty {
                    try update(dbNode: nearest.node, with: file.value as Any)
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
                            nearestNode.childs.append(FileNode(node: node, value: file.value))
                        } else {
                            let next = ObjectNode(node: node)
                            nearestNode.childs.append(next)
                            nearestNode = next
                        }
                    }
                }
                return .meta(file.metadata)
            } catch let e {
                return .error(file.location, e)
            }
        }
        completion(results)
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
        debugFatalError(
            condition: RealtimeApp._isInitialized && node.underestimatedCount >= RealtimeApp.app.maxNodeDepth - 1,
            "Maximum depth limit of child nodes exceeded"
        )
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

    fileprivate func update(dbNode: UpdateNode, with value: Any) throws {
        if case let valNode as ValueNode = dbNode {
            valNode.value = value
        } else if case _ as ObjectNode = dbNode {
            try replaceNode(with: ValueNode(node: dbNode.location, value: value))
        } else {
            throw RealtimeError(source: .transaction([]), description: "Internal error")
        }
    }

    fileprivate func replaceNode(with dbNode: UpdateNode) throws {
        if case let parent as ObjectNode = child(by: dbNode.location.parent!) {
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
    func child(by node: Node) -> UpdateNode? {
        var after = node.after(ancestor: location)

        var current = self
        while let first = after.first, let f = current.childs.first(where: { $0.location == first }) {
            if f.location == node {
                return f
            } else {
                if case let o as ObjectNode = f {
                    after.remove(at: 0)
                    current = o
                } else {
                    return nil
                }
            }
        }
        return nil
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
    func merge(with other: ObjectNode, conflictResolver: (UpdateNode, UpdateNode) -> Any?, didAppend: ((UpdateNode, UpdateNode) -> Void)?) throws {
        try other.childs.forEach { (child) in
            if let currentChild = childs.first(where: { $0.location == child.location }) {
                if let objectChild = currentChild as? ObjectNode {
                    try objectChild.merge(with: child as! ObjectNode, conflictResolver: conflictResolver, didAppend: didAppend)
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
                didAppend?(self, child)
            }
        }
    }
}

extension UpdateNode where Self: RealtimeDataProtocol {
    public var priority: Any? { return nil }
    public var key: String? { return location.key }
}

extension ValueNode: RealtimeDataProtocol, Sequence {
    var priority: Any? { return nil }
    var childrenCount: UInt {
        guard case let dict as [String: Any] = value else {
            return 0
        }
        return UInt(dict.count)
    }
    func makeIterator() -> AnyIterator<RealtimeDataProtocol> {
        guard case let dict as [String: Any] = value else {
            return AnyIterator(EmptyIterator())
        }
        return AnyIterator(
            dict.lazy.map { (keyValue) in
                ValueNode(node: Node(key: keyValue.key, parent: self.location), value: keyValue.value)
            }.makeIterator()
        )
    }
    func exists() -> Bool { return value != nil }
    func hasChildren() -> Bool {
        guard case let dict as [String: Any] = value else {
            return false
        }
        return dict.count > 0
    }
    func hasChild(_ childPathString: String) -> Bool {
        guard case let dict as [String: Any] = value else {
            return false
        }
        return dict[childPathString] != nil
    }
    func child(forPath path: String) -> RealtimeDataProtocol {
        guard case let dict as [String: Any] = value else {
            return ValueNode(node: Node(key: path, parent: location), value: nil)
        }

        let node = Node(key: path, parent: location)
        return ValueNode(node: node, value: dict[path])
    }
    func compactMap<ElementOfResult>(_ transform: (RealtimeDataProtocol) throws -> ElementOfResult?) rethrows -> [ElementOfResult] {
        return []
    }
    func forEach(_ body: (RealtimeDataProtocol) throws -> Void) rethrows {
        guard case let dict as [String: Any] = value else {
            return
        }
        try dict.forEach { (keyValue) in
            try body(ValueNode(node: Node(key: keyValue.key, parent: location), value: keyValue.value))
        }
    }
    func map<T>(_ transform: (RealtimeDataProtocol) throws -> T) rethrows -> [T] {
        guard case let dict as [String: Any] = value else {
            return []
        }
        return try dict.map { (keyValue) in
            try transform(ValueNode(node: Node(key: keyValue.key, parent: location), value: keyValue.value))
        }
    }
    var debugDescription: String { return "\(location.absolutePath): \(value as Any)" }
    var description: String { return debugDescription }
}

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
    public func child(forNode node: Node) -> RealtimeDataProtocol {
        return child(by: node) ?? ValueNode(node: node, value: nil)
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
