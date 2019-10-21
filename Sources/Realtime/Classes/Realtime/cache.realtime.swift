//
//  cache.realtime.swift
//  Realtime
//
//  Created by Denis Koryttsev on 19/11/2018.
//

import Foundation

/// An object that contains value is associated by database reference.
public protocol UpdateNode: RealtimeDataProtocol {
    /// Database location reference
    var location: Node { get }
    /// Fills a contained values to container.
    ///
    /// - Parameters:
    ///   - container: `inout` dictionary container.
    ///   - reducer: Closure to reduce
    func reduceValues<C>(into container: inout C, _ reducer: (inout C, Node, RealtimeDatabaseValue?) throws -> Void) rethrows
}
extension UpdateNode {
    public var database: RealtimeDatabase? { return Cache.root }
    public var storage: RealtimeStorage? { return Cache.root }
    public var node: Node? { return location }

    public func reduceValues<C>(into container: C, _ reducer: (inout C, Node, RealtimeDatabaseValue?) throws -> Void) rethrows -> C {
        var container = container
        try reduceValues(into: &container, reducer)
        return container
    }
}
extension UpdateNode where Self: RealtimeDataProtocol {
    public var key: String? { return location.key }
}

enum CacheNode {
    case value(ValueNode)
    case file(FileNode)
    case object(ObjectNode)

    func asUpdateNode() -> UpdateNode {
        switch self {
        case .value(let v): return v
        case .file(let f): return f
        case .object(let o): return o
        }
    }

    var isEmpty: Bool {
        switch self {
        case .value(let v): return v.value == nil
        case .file(let f): return f.value == nil
        case .object(let o): return o.childs.isEmpty
        }
    }

    var location: Node {
        switch self {
        case .value(let v): return v.location
        case .file(let f): return f.location
        case .object(let o): return o.location
        }
    }
}

// MARK: ValueNode

class ValueNode: UpdateNode {
    let location: Node
    var value: RealtimeDatabaseValue?

    func reduceValues<C>(into container: inout C, _ reducer: (inout C, Node, RealtimeDatabaseValue?) throws -> Void) rethrows {
        try reducer(&container, location, value)
    }

    required init(node: Node, value: RealtimeDatabaseValue?) {
        debugFatalError(
            condition: RealtimeApp._isInitialized && node.underestimatedCount >= RealtimeApp.app.configuration.maxNodeDepth - 1,
            "Maximum depth limit of child nodes exceeded"
        )
        self.location = node
        self.value = value
    }
}
extension ValueNode: RealtimeDataProtocol, Sequence {
    var childrenCount: UInt {
        guard let v = value else { return 0 }
        switch v.backend {
        case .bool,.int8,.int16,.int32,.int64,.uint8,.uint16,.uint32,.uint64,.double,.float,.string,.data, .pair: return 0
        case .unkeyed(let c): return UInt(c.count)
        }
    }
    func makeIterator() -> AnyIterator<RealtimeDataProtocol> {
        guard let v = value else {
            return AnyIterator(EmptyCollection.Iterator())
        }
        switch v.backend {
        case .bool,.int8,.int16,.int32,.int64,.uint8,.uint16,.uint32,.uint64,.double,.float,.string,.data, .pair: return AnyIterator(EmptyCollection.Iterator())
        case .unkeyed(let c):
            guard let iterator = (try? c.enumerated().map { (i, dbValue) -> RealtimeDataProtocol in
                switch dbValue.backend {
                case .pair(let k, let v): return ValueNode(node: Node(key: try k.typed(as: String.self), parent: self.location), value: v)
                default: return ValueNode(node: Node(key: "\(i)", parent: self.location), value: dbValue)
                }
                }.makeIterator())
                else { return AnyIterator(EmptyCollection.Iterator()) }
            return AnyIterator(iterator)
        }
    }
    func exists() -> Bool { return value != nil }
    func hasChildren() -> Bool {
        guard let v = value else { return false }
        switch v.backend {
        case .bool,.int8,.int16,.int32,.int64,.uint8,.uint16,.uint32,.uint64,.double,.float,.string,.data, .pair: return false
        case .unkeyed(let c): return c.count > 0
        }
    }
    func hasChild(_ childPathString: String) -> Bool {
        guard let v = value else { return false }
        switch v.backend {
        case .bool,.int8,.int16,.int32,.int64,.uint8,.uint16,.uint32,.uint64,.double,.float,.string,.data, .pair: return false
        case .unkeyed(let c): return (try? c.enumerated().contains(where: { (i, dbValue) in
            switch dbValue.backend {
            case .pair(let k, _): return try k.typed(as: String.self) == childPathString
            default: return "\(i)" == childPathString
            }
        })) ?? false
        }
    }
    func child(forPath path: String) -> RealtimeDataProtocol {
        let childNode = location.child(with: path)
        guard let v = value else { return ValueNode(node: childNode, value: nil) }
        switch v.backend {
        case .bool,.int8,.int16,.int32,.int64,.uint8,.uint16,.uint32,.uint64,.double,.float,.string,.data, .pair: return ValueNode(node: childNode, value: nil)
        case .unkeyed(let c):
            return (try? c.enumerated().first(where: { (i, dbValue) in
                switch dbValue.backend {
                case .pair(let k, _): return try k.typed(as: String.self) == path
                default: return "\(i)" == path
                }
            }))?.map({ val in
                switch val.element.backend {
                case .pair(_, let v): return ValueNode(node: childNode, value: v)
                default: return ValueNode(node: childNode, value: val.element)
                }
            })
                ?? ValueNode(node: childNode, value: nil)
        }
    }
    var debugDescription: String { return "\(location.absolutePath): \(value as Any)" }
    var description: String { return debugDescription }

    func asDatabaseValue() throws -> RealtimeDatabaseValue? { return value }

    private func _decode<T>(_ type: T.Type) throws -> RealtimeDatabaseValue {
        guard let v = value else {
            throw DecodingError.valueNotFound(T.self, DecodingError.Context(codingPath: location.map({ _RealtimeCodingKey(stringValue: $0.key)! }), debugDescription: String(describing: value)))
        }
        return v
    }
    private func _decodeInt<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        guard let val = try _decode(type).losslessMap(to: T.self) else {
            throw DecodingError.typeMismatch(T.self, DecodingError.Context(codingPath: location.map({ _RealtimeCodingKey(stringValue: $0.key)! }), debugDescription: String(describing: value)))
        }
        return val
    }
    func decodeNil() -> Bool { return value == nil }
    func decode(_ type: Bool.Type) throws -> Bool { return try _decode(Bool.self).typed(as: Bool.self) }
    func decode(_ type: Int.Type) throws -> Int { return try Int(_decodeInt(Int64.self)) }
    func decode(_ type: Int8.Type) throws -> Int8 { return try _decodeInt(Int8.self) }
    func decode(_ type: Int16.Type) throws -> Int16 { return try _decodeInt(Int16.self) }
    func decode(_ type: Int32.Type) throws -> Int32 { return try _decodeInt(Int32.self) }
    func decode(_ type: Int64.Type) throws -> Int64 { return try _decodeInt(Int64.self) }
    func decode(_ type: UInt.Type) throws -> UInt { return try UInt(_decodeInt(UInt64.self)) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { return try _decodeInt(UInt8.self) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { return try _decodeInt(UInt16.self) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { return try _decodeInt(UInt32.self) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { return try _decodeInt(UInt64.self) }
    func decode(_ type: Float.Type) throws -> Float { return try _decode(Float.self).typed(as: Float.self) }
    func decode(_ type: Double.Type) throws -> Double { return try _decode(Double.self).typed(as: Double.self) }
    func decode(_ type: String.Type) throws -> String { return try _decode(String.self).typed(as: String.self) }
    func decode(_ type: Data.Type) throws -> Data { return try _decode(Data.self).typed(as: Data.self) }
    func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
        guard type != Data.self else {
            return try unsafeBitCast(decode(Data.self), to: T.self) 
        }
        return try T(from: self)
    }
}

class FileNode: ValueNode {
    var metadata: [String: Any] = [:]

    required init(node: Node, value: RealtimeDatabaseValue?) {
        precondition(value.map({ rdbv in
            guard case .data = rdbv.backend else { return false }
            return true
        }) ?? true, "Unexpected file data")
        super.init(node: node, value: value)
    }

    func delete(completion: ((Error?) -> Void)?) {
        self.value = nil
        self.metadata.removeAll()
    }

    func put(_ data: Data, metadata: [String : Any]?, completion: @escaping ([String : Any]?, Error?) -> Void) {
        self.value = RealtimeDatabaseValue(data)
        if let md = metadata {
            self.metadata = md
        }
        completion(metadata, nil)
    }

    override func reduceValues<C>(into container: inout C, _ reducer: (inout C, Node, RealtimeDatabaseValue?) throws -> Void) rethrows {}
    var database: RealtimeDatabase? { return nil }
}

// MARK: ObjectNode

class ObjectNode: UpdateNode, CustomStringConvertible {
    let location: Node
    var childs: [CacheNode] = []
    var isCompound: Bool { return true }
    var files: [FileNode] {
        return childs.reduce(into: [], { (res, node) in
            switch node {
            case .file(let f): res.append(f)
            case .object(let o): res.append(contentsOf: o.files)
            case .value: break
            }
        })
    }
    var description: String {
        return """
        values: \(debugValue),
        files: \(files)
        """
    }
    var debugValue: [String: Any?] {
        var val: [String: Any?] = [:]
        reduceValues(into: &val) { (c, n, v) in
            c[n.path(from: location)] = .some(v?.debug)
        }
        return val
    }

    init(node: Node, childs: [CacheNode] = []) {
        debugFatalError(
            condition: RealtimeApp._isInitialized && node.underestimatedCount >= RealtimeApp.app.configuration.maxNodeDepth - 1,
            "Maximum depth limit of child nodes exceeded"
        )
        self.location = node
        self.childs = childs
    }

    func reduceValues<C>(into container: inout C, _ reducer: (inout C, Node, RealtimeDatabaseValue?) throws -> Void) rethrows {
        try childs.forEach { (node) in
            switch node {
            case .value(let v as UpdateNode), .object(let v as UpdateNode): try v.reduceValues(into: &container, reducer)
            case .file: break
            }
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

        switch f {
        case .object(let o): return o.child(by: path)
        case .value(let v), .file(let v as ValueNode):
            return path.isEmpty ? v : nil
        }
    }
    func child(by node: Node) -> CacheNode? {
        var after = node.after(ancestor: location)

        var current = self
        while let first = after.first, let f = current.childs.first(where: { $0.location == first }) {
            if f.location == node {
                return f
            } else {
                switch f {
                case .object(let o):
                    after.remove(at: 0)
                    current = o
                case .value, .file:
                    return nil
                }
            }
        }
        return nil
    }
    func nearestChild(by path: [String]) -> (node: CacheNode, leftPath: [String]) {
        guard !path.isEmpty else { return (.object(self), path) }

        var path = path
        let first = path.remove(at: 0)
        guard let f = childs.first(where: { $0.location.key == first }) else {
            path.insert(first, at: 0)
            return (.object(self), path)
        }

        switch f {
        case .object(let o):
            return o.nearestChild(by: path)
        case .value, .file:
            return (f, path)
        }
    }
    func nearestCommonNode(with node: Node) -> CacheNode {
        guard self.location !== node else { return .object(self) }

        var after = node.after(ancestor: location)
        var current = self
        while let first = after.first, let f = current.childs.first(where: { $0.location == first }) {
            switch f {
            case .object(let o):
                if o.location == node {
                    return f
                } else {
                    after.remove(at: 0)
                    current = o
                }
            case .value, .file: return f
            }
        }
        return .object(self)
    }

    fileprivate func update(dbNode: CacheNode, with value: RealtimeDatabaseValue?) throws {
        switch dbNode {
        case .value(let v): v.value = value
        case .file(let f): f.value = value
        case .object(let o):
            try replaceNode(with: .value(ValueNode(node: o.location, value: value)))
        }
    }

    fileprivate func replaceNode(with dbNode: CacheNode) throws {
        if case .some(.object(let parent)) = child(by: dbNode.location.parent!) {
            parent.childs.remove(at: parent.childs.index(where: { $0.asUpdateNode().location === dbNode.location })!)
            if !dbNode.isEmpty {
                parent.childs.append(dbNode)
            }
        } else {
            throw RealtimeError(source: .cache, description: "Internal error")
        }
    }

    func _mergeTheSameReference(in node: Node, _ current: CacheNode, _ update: CacheNode,
                                conflictResolver: (CacheNode, CacheNode) -> CacheNode,
                                didAppend: ((ObjectNode, CacheNode) -> Void)?) throws {
        switch (current, update) {
        case (.object(let l), .object(let r)):
            try l._mergeWithObject(theSameReference: r, conflictResolver: conflictResolver, didAppend: didAppend)
        default:
            let index = self.childs.index(where: { $0.location == node })!
            let resolved = conflictResolver(current, update)
            if resolved.isEmpty {
                self.childs.remove(at: index)
            } else {
                self.childs[index] = resolved
            }
        }
    }

    func _mergeWithObject(theSameReference object: ObjectNode, conflictResolver: (CacheNode, CacheNode) -> CacheNode, didAppend: ((ObjectNode, CacheNode) -> Void)?) throws {
        let childs = self.childs
        try object.childs.forEach { (child) in
            let childNode = child.location
            if let update = childs.first(where: { $0.location == childNode }) {
                try _mergeTheSameReference(in: childNode, update, child, conflictResolver: conflictResolver, didAppend: didAppend)
            } else {
                self.childs.append(child)
                didAppend?(self, child)
            }
        }
    }

    func _addValueAsInSingleTransaction(_ cacheNode: CacheNode) {
        switch cacheNode {
        case .object:
            fatalError("ObjectNode cannot be added to transaction")
        case .value(let v), .file(let v as ValueNode):
            let node = v.location
            var current = self
            let nodes = node.after(ancestor: location)
            var iterator = nodes.makeIterator()
            while let n = iterator.next() {
                if let update = current.childs.first(where: { $0.location == n }) {
                    switch update {
                    case .object(let o):
                        if n === node {
                            fatalError("Tries insert value higher than earlier writed values")
                        } else {
                            current = o
                        }
                    case .value(let old), .file(let old as ValueNode):
                        if n === node {
                            debugFatalError(condition: type(of: old) != type(of: v), "Tries to insert database value to storage node or conversely")
                            old.value = v.value
                            debugPrintLog("Replaced value by node: \(node) with value: \(v.value as Any) in transaction: \(ObjectIdentifier(self).memoryAddress)")
                        } else {
                            fatalError("Tries insert value lower than earlier writed single value")
                        }
                    }
                } else {
                    if node === n {
                        current.childs.append(cacheNode)
                    } else {
                        let child = ObjectNode(node: n)
                        current.childs.append(.object(child))
                        current = child
                    }
                }
            }
        }
    }

    func merge(with other: CacheNode, conflictResolver: (CacheNode, CacheNode) -> CacheNode, didAppend: ((ObjectNode, CacheNode) -> Void)?) throws {
        let node = other.location
        if node == location {
            switch other {
            case .object(let o):
                try _mergeWithObject(theSameReference: o, conflictResolver: conflictResolver, didAppend: didAppend)
            case .value, .file:
                throw RealtimeError(source: .cache, description: "Merge operation requires full replace operation")
            }
        } else if node.hasAncestor(node: location) {
            var current = self
            let nodes = node.after(ancestor: location)
            var iterator = nodes.makeIterator()
            while let n = iterator.next() {
                if let update = current.childs.first(where: { $0.location == n }) {
                    if node === n {
                        try current._mergeTheSameReference(in: node, update, other, conflictResolver: conflictResolver, didAppend: didAppend)
                    } else {
                        switch update {
                        case .object(let o): current = o
                        case .value, .file:
                            let index = current.childs.index(where: { $0.location == n })!
                            let leftNodes = node.after(ancestor: n)
                            current.childs[index] = .object(leftNodes.reversed().dropLast().reduce(ObjectNode(node: node, childs: [other]), { objNode, ref in
                                let child = CacheNode.object(objNode)
                                let next = ObjectNode(node: ref, childs: [child])
                                didAppend?(next, child)
                                return next
                            }))
                        }
                    }
                } else {
                    if node === n {
                        current.childs.append(other)
                        didAppend?(current, other)
                    } else {
                        let child = ObjectNode(node: n)
                        current.childs.append(.object(child))
                        didAppend?(current, .object(child))
                        current = child
                    }
                }
            }
        } else {
            fatalError("Cannot be merged, because value referenced to unrelated location")
        }
    }
}

extension ObjectNode: RealtimeDataProtocol, Sequence {
    public var childrenCount: UInt { return UInt(childs.count) }
    public func makeIterator() -> AnyIterator<RealtimeDataProtocol> {
        return AnyIterator(childs.lazy.map { $0.asUpdateNode() }.makeIterator())
    }
    public func exists() -> Bool { return true }
    public func hasChildren() -> Bool { return childs.count > 0 }
    public func hasChild(_ childPathString: String) -> Bool {
        return child(by: childPathString.split(separator: "/").lazy.map(String.init)) != nil
    }
    public func child(forPath path: String) -> RealtimeDataProtocol {
        return child(by: path.split(separator: "/").lazy.map(String.init)) ?? ValueNode(node: Node(key: path, parent: location), value: nil)
    }
    public func child(forNode node: Node) -> RealtimeDataProtocol {
        return child(by: node)?.asUpdateNode() ?? ValueNode(node: node, value: nil)
    }
    public func map<T>(_ transform: (RealtimeDataProtocol) throws -> T) rethrows -> [T] {
        return try childs.map({ try transform($0.asUpdateNode()) })
    }
    public func compactMap<ElementOfResult>(_ transform: (RealtimeDataProtocol) throws -> ElementOfResult?) rethrows -> [ElementOfResult] {
        return try childs.compactMap({ try transform($0.asUpdateNode()) })
    }
    public func forEach(_ body: (RealtimeDataProtocol) throws -> Void) rethrows {
        return try childs.forEach({ try body($0.asUpdateNode()) })
    }
    public var debugDescription: String { return description }

    func asDatabaseValue() throws -> RealtimeDatabaseValue? {
        let builder = try childs.reduce(into: RealtimeDatabaseValue.Dictionary(), { (container, node) in
            switch node {
            case .value(let v), .file(let v as ValueNode):
                try v.asDatabaseValue().map({ container.setValue($0, forKey: v.location.key) })
            case .object(let v):
                try v.asDatabaseValue().map({ container.setValue($0, forKey: v.location.key) })
            }
        })
        return builder.isEmpty ? nil : builder.build()
    }

    private func _throwTypeMismatch<T>(_ type: T.Type) throws -> T {
        throw DecodingError.typeMismatch(type.self, DecodingError.Context(codingPath: location.map({ _RealtimeCodingKey(stringValue: $0.key)! }), debugDescription: debugDescription))
    }
    func decodeNil() -> Bool { return false }
    func decode(_ type: Bool.Type) throws -> Bool { return try _throwTypeMismatch(type) }
    func decode(_ type: Int.Type) throws -> Int { return try _throwTypeMismatch(type) }
    func decode(_ type: Int8.Type) throws -> Int8 { return try _throwTypeMismatch(type) }
    func decode(_ type: Int16.Type) throws -> Int16 { return try _throwTypeMismatch(type) }
    func decode(_ type: Int32.Type) throws -> Int32 { return try _throwTypeMismatch(type) }
    func decode(_ type: Int64.Type) throws -> Int64 { return try _throwTypeMismatch(type) }
    func decode(_ type: UInt.Type) throws -> UInt { return try _throwTypeMismatch(type) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { return try _throwTypeMismatch(type) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { return try _throwTypeMismatch(type) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { return try _throwTypeMismatch(type) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { return try _throwTypeMismatch(type) }
    func decode(_ type: Float.Type) throws -> Float { return try _throwTypeMismatch(type) }
    func decode(_ type: Double.Type) throws -> Double { return try _throwTypeMismatch(type) }
    func decode(_ type: String.Type) throws -> String { return try _throwTypeMismatch(type) }
    func decode(_ type: Data.Type) throws -> Data { return try _throwTypeMismatch(type) }
    func decode<T>(_ type: T.Type) throws -> T where T : Decodable { return try T(from: self) }
}

// MARK: Cache

extension CacheNode {
    func putAdditionNotifications(parent: ObjectNode, to collector: inout [Node: (RealtimeDataProtocol, DatabaseDataEvent)]) {
        switch self {
        case .object(let o):
            o.childs.forEach({ $0.putAdditionNotifications(parent: o, to: &collector) })
        case .value(let v), .file(let v as ValueNode):
            collector[v.location] = (v, .value)
            collector[parent.location] = (v, .child(v.value == nil ? .removed : .added))
        }
    }
}

class Cache: ObjectNode, RealtimeDatabase, RealtimeStorage {
    var isConnectionActive: AnyListenable<Bool> { return AnyListenable(Constant(true)) }

    static let root: Cache = Cache(node: .root)
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
        return UUID().uuidString // can be use function from firebase
    }

    func commit(update: UpdateNode, completion: ((Error?) -> Void)?) {
        guard case let objNode as ObjectNode = update else { fatalError("Unexpected update object") }
        do {
            var notifications: [Node: (RealtimeDataProtocol, DatabaseDataEvent)] = [:]
            try _mergeWithObject(
                theSameReference: objNode,
                conflictResolver: { old, new in
                    if observers.count > 0 {
                        notifications[new.location] = (new.asUpdateNode(), .value)
                        new.location.parent.map({ notifications[$0] = (new.asUpdateNode(), .child(new.isEmpty ? .removed : .changed)) })
                    }
                    return new
                },
                didAppend: observers.isEmpty ? nil : { parent, child in
                    child.putAdditionNotifications(parent: parent, to: &notifications)
                }
            )
            completion?(nil)
            notifications.forEach { (args) in
                observers[args.key]?.send(.value(args.value))
            }
        } catch let e {
            completion?(e)
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
            completion(child(by: node)?.asUpdateNode() ?? ValueNode(node: node, value: nil))
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

    func observe(_ event: DatabaseDataEvent, on node: Node, onUpdate: @escaping (RealtimeDataProtocol, DatabaseDataEvent) -> Void, onCancel: ((Error) -> Void)?) -> UInt {
        let repeater: Repeater<(RealtimeDataProtocol, DatabaseDataEvent)> = self.repeater(for: node)

        return repeater.add(Closure
            .just { e in
                switch e {
                case .value(let val): onUpdate(val.0, event)
                case .error(let err): onCancel?(err)
                }
            }
            .filter({ (e) -> Bool in
                switch (e, event) {
                case (.error, _): return true
                case (.value(_, .value), .value): return true
                case (.value(_, .child(let received)), .child(let defined)):
                    return received == defined
                default: return false
                }
            }))
    }

    func observe(_ event: DatabaseDataEvent, on node: Node, limit: UInt, before: Any?, after: Any?, ascending: Bool, ordering: RealtimeDataOrdering,
                 completion: @escaping (RealtimeDataProtocol, DatabaseDataEvent) -> Void,
                 onCancel: ((Error) -> Void)?) -> Disposable {
        fatalError("Unimplemented")
    }

    func runTransaction(in node: Node, withLocalEvents: Bool, _ updater: @escaping (RealtimeDataProtocol) -> ConcurrentIterationResult, onComplete: ((ConcurrentOperationResult) -> Void)?) {
        fatalError("Unimplemented")
    }

    // storage

    func load(for node: Node, timeout: DispatchTimeInterval, completion: @escaping (Data?) -> Void, onCancel: ((Error) -> Void)?) -> RealtimeStorageTask {
        if node == location {
            fatalError("Cannot load file from root")
        } else if let node = child(by: node) {
            switch node {
            case .file(let file):
                do {
                    let data = try file.value?.typed(as: Data.self)
                    completion(data)
                } catch let e {
                    onCancel?(e)
                }
            default: completion(nil)
            }
        } else {
            completion(nil)
        }
        return CacheStorageTask()
    }

    struct CacheStorageTask: RealtimeStorageTask {
        var progress: AnyListenable<Progress> { return AnyListenable(Constant(Progress(totalUnitCount: 0))) }
        var success: AnyListenable<RealtimeMetadata?> { return AnyListenable(Constant(nil)) }
        func pause() {}
        func cancel() {}
        func resume() {}
    }

    func commit(transaction: Transaction, completion: @escaping ([Transaction.FileCompletion]) -> Void) {
        let results = transaction.updateNode.files.map { (file) -> Transaction.FileCompletion in
            do {
                let nearest = self.nearestChild(by: Array(file.location.map({ $0.key }).reversed().dropFirst()))
                if nearest.leftPath.isEmpty {
                    try update(dbNode: nearest.node, with: file.value)
                } else {
                    var nearestNode: ObjectNode
                    switch nearest.node {
                    case .value(let v), .file(let v as ValueNode):
                        nearestNode = ObjectNode(node: v.location)
                        try replaceNode(with: .object(nearestNode))
                    case .object(let o):
                        nearestNode = o
                    }
                    for (i, part) in nearest.leftPath.enumerated() {
                        let node = Node(key: part, parent: nearestNode.location)
                        if i == nearest.leftPath.count - 1 {
                            nearestNode.childs.append(.file(FileNode(node: node, value: file.value)))
                        } else {
                            let next = ObjectNode(node: node)
                            nearestNode.childs.append(.object(next))
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
