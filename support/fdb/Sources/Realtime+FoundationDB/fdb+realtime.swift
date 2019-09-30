//
//  fdb+realtime.swift
//  fdb_client
//
//  Created by Denis Koryttsev on 17/06/2019.
//

import Foundation
import NIO
import FoundationDB
import Realtime

extension Node: TupleConvertible {
    public struct FoundationDBTupleAdapter: TupleAdapter {
        public typealias ValueType = Node
        public static let typeCodes: Set<UInt8> = [Tuple.EntryType.string.rawValue]

        public static func write(value: Node, into buffer: inout Data) {
            let nodes = value.dropLast()
            nodes.reversed().forEach { (node) in
                String.FoundationDBTupleAdapter.write(value: node.key, into: &buffer)
            }
        }

        public static func read(from buffer: Data, at offset: Int) throws -> Node {
            let tuple = Tuple.FoundationDBTupleAdapter.read(from: buffer, at: offset)
            return try Node(tuple: tuple)
        }
    }
}

extension Node {
    public var databaseValue: DatabaseValue {
        var buffer = Data()
        FoundationDBTupleAdapter.write(value: self, into: &buffer)
        return DatabaseValue(buffer)
    }

    public convenience init(databaseValue: DatabaseValue) throws {
        let tuple = Tuple(databaseValue: databaseValue)
        try self.init(tuple: tuple)
    }

    public convenience init(tuple: Tuple) throws {
        guard tuple.count != 0 else { fatalError("Tuple cannot be empty") }
        if tuple.count == 1 {
            self.init(key: try tuple.read(at: 0), parent: .root)
        } else {
            var node = Node(key: try tuple.read(at: 0), parent: .root)
            try (1..<tuple.count-1).forEach { (i) in
                node = Node(key: try tuple.read(at: i), parent: node)
            }
            self.init(key: try tuple.read(at: tuple.count-1), parent: node)
        }
    }
}

internal extension EventLoopFuture {
    func `do`(_ callback: @escaping (T) -> ()) -> EventLoopFuture<T> {
        whenSuccess(callback)
        return self
    }
    @discardableResult
    func `catch`(_ callback: @escaping (Error) -> ()) -> EventLoopFuture<T> {
        whenFailure(callback)
        return self
    }
}

extension ClusterDatabaseConnection: RealtimeDatabase {
    public var cachePolicy: CachePolicy {
        get { return .noCache }
        set(newValue) { print("Cluster database: Cache unimplemented") }
    }

    public func generateAutoID() -> String {
        return UUID().uuidString
    }

    public func commit(update: UpdateNode, completion: ((Error?) -> Void)?) {
        transaction({ (trans) -> Void in
            try update.enumerateValues({ (node, value) in
                guard case let valueData as Data = value else { throw ClusterDatabaseConnection.FdbApiError(4100) }
                trans.store(key: node.databaseValue, value: DatabaseValue(valueData))
            })
        })
        .do({ completion?(nil) })
        .catch({ completion?($0) })
    }

    public func load(for node: Node, timeout: DispatchTimeInterval, completion: @escaping (RealtimeDataProtocol) -> Void, onCancel: ((Error) -> Void)?) {
        let key = Tuple(databaseValue: node.databaseValue)
        enum Result {
            case single(Tuple?)
            case multiple([(key: Tuple, value: Tuple)])
        }
        transaction({ (trans) -> EventLoopFuture<Result> in
            return trans
                .read(range: key.childRange)
                .then({ [unowned self] (set) -> EventLoopFuture<Result> in
                    if set.rows.isEmpty {
                        return trans.read(key).map({ .single($0) })
                    } else {
                        return self.eventLoop.newSucceededFuture(result: .multiple(set.rows))
                    }
                })
        })
        .do({ [unowned self] (value) in
            switch value {
            case .single(let v): completion(DatabaseNode(result: .single(v?.databaseValue), database: self, node: node))
            case .multiple(let rows):
                let child = rows.lazy.map({ (key: $0.databaseValue, value: $1.databaseValue) }).child(key.databaseValue)
                completion(DatabaseNode(result: child, database: self, node: node))
            }
        })
        .catch({ (error) in
            onCancel?(error)
        })
    }

    public func observe(_ event: DatabaseDataEvent, on node: Node, onUpdate: @escaping (RealtimeDataProtocol) -> Void, onCancel: ((Error) -> Void)?) -> UInt {
        return 0 // use watches that unimplemented in fdb-swift-binding
    }

    public func observe(_ event: DatabaseDataEvent, on node: Node, limit: UInt, before: Any?, after: Any?, ascending: Bool, ordering: RealtimeDataOrdering, completion: @escaping (RealtimeDataProtocol, DatabaseDataEvent) -> Void, onCancel: ((Error) -> Void)?) -> Disposable {
        return EmptyDispose()
    }

    public func runTransaction(in node: Node, withLocalEvents: Bool, _ updater: @escaping (RealtimeDataProtocol) -> ConcurrentIterationResult, onComplete: ((ConcurrentOperationResult) -> Void)?) {

    }

    public func removeAllObservers(for node: Node) {

    }

    public func removeObserver(for node: Node, with token: UInt) {

    }

    public var isConnectionActive: AnyListenable<Bool> {
        return AnyListenable(Constant(false))
    }

    struct DatabaseNode: RealtimeDataProtocol {
        let result: ResultSet.Child
        let location: Node
        var database: RealtimeDatabase?
        var storage: RealtimeStorage?
        var node: Node? { return location }
        var key: String? { return location.key }
        var value: Any? {
            do {
                switch result {
                case .single(let v):
                    return try v.map(Tuple.init(databaseValue:))?.readAny(at: 0)
                case .multiple:
                    var result = [String: Any?]()
                    return reduce(into: &result, updateAccumulatingResult: { (res, data) in
                        if let key = data.key {
                            res[key] = data.value
                        }
                    })
                }
            } catch let e {
                print("Error occurred:", String(describing: e))
                return nil
            }
        }
        var priority: Any? { return nil }
        var childrenCount: UInt {
            switch result {
            case .single: return 0
            case .multiple(let s, let d): return UInt(s.rows.count + d.count)
            }
        }

        var debugDescription: String { return "\(location.absolutePath): \(value as Any)" }
        var description: String { return debugDescription }

        init(result: ResultSet.Child, database: RealtimeDatabase?, node: Node) {
            self.location = node
            self.database = database
            self.result = result
        }

        func makeIterator() -> AnyIterator<RealtimeDataProtocol> {
            let db = database
            switch result {
            case .single: return AnyIterator(EmptyCollection.Iterator())
            case .multiple(let s, let deep):
                var base = s.rows.makeIterator()
                var deepBase = deep.makeIterator()
                return AnyIterator({ () -> DatabaseNode? in
                    do {
                        guard let next = base.next() else {
                            guard let next = deepBase.next() else { return nil }

                            let rows = next.value.child(next.key)
                            return try DatabaseNode(result: rows, database: db, node: Node(databaseValue: next.key))
                        }
                        return try DatabaseNode(result: .single(next.value), database: db, node: Node(databaseValue: next.key))
                    } catch let e {
                        print("Error occured", e)
                        return nil
                    }
                })
            }
        }

        func exists() -> Bool {
            switch result {
            case .single(let v): return v != nil
            case .multiple(let children, let rows): return children.rows.count > 0 || rows.count > 0
            }
        }

        func hasChildren() -> Bool {
            switch result {
            case .single: return false
            case .multiple(let children, let rows): return children.rows.count > 0 || rows.count > 0
            }
        }

        func hasChild(_ childPathString: String) -> Bool {
            switch result {
            case .single: return false
            case .multiple(let s, _): return s.read(location.child(with: childPathString).databaseValue) != nil
            }
        }

        func child(forPath path: String) -> RealtimeDataProtocol {
            let childNode = location.child(with: path)
            switch result {
            case .single: return DatabaseNode(result: .single(nil), database: database, node: childNode)
            case .multiple(let s, let deep):
                let childTuple = childNode.databaseValue
                guard let child = s.read(childTuple) else {
                    guard let rows = deep[childTuple] ?? deep.first(where: { childTuple.hasPrefix($0.key) })?.value else {
                        return DatabaseNode(result: .single(nil), database: database, node: childNode)
                    }

                    let set = rows.child(childTuple)
                    return DatabaseNode(result: set, database: database, node: childNode)
                }
                return DatabaseNode(result: .single(child), database: database, node: childNode)
            }
        }

        func singleValueContainer() throws -> SingleValueDecodingContainer {
            return _SingleValueDecodingContainer(snapshot: self)
        }

        func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
            return KeyedDecodingContainer(_KeyedValueDecodingContainer(snapshot: self))
        }

        struct _SingleValueDecodingContainer: SingleValueDecodingContainer {
            let snapshot: DatabaseNode
            var codingPath: [CodingKey] { return [] }

            func _decode<T: TupleConvertible>(_ type: T.Type) throws -> T {
                switch snapshot.result {
                case .multiple, .single(.none): throw DecodingError.typeMismatch(T.self, DecodingError.Context(codingPath: [], debugDescription: ""))
                case .single(.some(let v)):
                    return try T.FoundationDBTupleAdapter.read(from: v.data, at: -1)
                }
            }

            func decodeNil() -> Bool {
                switch snapshot.result {
                case .single(.none): return true
                case .single(.some(let v)):
                    return v.data.isEmpty || v.data[0] == Tuple.EntryType.null.rawValue
                case .multiple(let set, _): return set.rows.isEmpty
                }
            }
            func decode(_ type: Bool.Type) throws -> Bool { return try _decode(type) }
            func decode(_ type: Int.Type) throws -> Int { return try _decode(type) }
            func decode(_ type: Int8.Type) throws -> Int8 { return try _decode(type) }
            func decode(_ type: Int16.Type) throws -> Int16 { return try _decode(type) }
            func decode(_ type: Int32.Type) throws -> Int32 { return try _decode(type) }
            func decode(_ type: Int64.Type) throws -> Int64 { return try _decode(type) }
            func decode(_ type: UInt.Type) throws -> UInt { return try _decode(type) }
            func decode(_ type: UInt8.Type) throws -> UInt8 { return try _decode(type) }
            func decode(_ type: UInt16.Type) throws -> UInt16 { return try _decode(type) }
            func decode(_ type: UInt32.Type) throws -> UInt32 { return try _decode(type) }
            func decode(_ type: UInt64.Type) throws -> UInt64 { return try _decode(type) }
            func decode(_ type: Float.Type) throws -> Float { return try _decode(type) }
            func decode(_ type: Double.Type) throws -> Double { return try _decode(type) }
            func decode(_ type: String.Type) throws -> String { return try _decode(type) }
            func decode<T>(_ type: T.Type) throws -> T where T : Decodable { return try T(from: snapshot) }
        }

        struct _KeyedValueDecodingContainer<K: CodingKey>: KeyedDecodingContainerProtocol {
            typealias Key = K
            let snapshot: DatabaseNode

            var codingPath: [CodingKey] { return [] }
            var allKeys: [Key] { return snapshot.compactMap { $0.node.flatMap { Key(stringValue: $0.key) } } }

            private func _decode<T: TupleConvertible>(_ type: T.Type, forKey key: Key) throws -> T {
                switch snapshot.result {
                case .single: throw DecodingError.typeMismatch(T.self, DecodingError.Context(codingPath: [], debugDescription: ""))
                case .multiple(let rs, _):
                    var tuple = Tuple(databaseValue: snapshot.location.databaseValue)
                    key.intValue.map({ tuple.append($0) }) ?? tuple.append(key.stringValue)
                    guard let v = rs.read(tuple.databaseValue) else {
                        throw DecodingError.valueNotFound(T.self, DecodingError.Context(codingPath: [key], debugDescription: snapshot.debugDescription))
                    }
                    return try Tuple.FoundationDBTupleAdapter.read(from: v.data, at: -1).read(at: 0)
                }
            }

            private func _childValue(forKey key: Key) throws -> DatabaseNode {
                switch snapshot.result {
                case .single: throw DecodingError.typeMismatch(Any.self, DecodingError.Context(codingPath: [], debugDescription: ""))
                case .multiple(let rs, _):
                    var tuple = Tuple(databaseValue: snapshot.location.databaseValue)
                    key.intValue.map({ tuple.append($0) }) ?? tuple.append(key.stringValue)
                    guard let v = rs.read(tuple.databaseValue) else {
                        throw DecodingError.valueNotFound(Any.self, DecodingError.Context(codingPath: [key], debugDescription: snapshot.debugDescription))
                    }
                    return DatabaseNode(result: .single(v), database: snapshot.database, node: snapshot.location.child(with: key.stringValue))
                }
            }

            func contains(_ key: Key) -> Bool {
                return snapshot.hasChild(key.stringValue)
            }

            func decodeNil(forKey key: Key) throws -> Bool {
                switch snapshot.result {
                case .single: return true
                case .multiple(let rs, _):
                    var tuple = Tuple(databaseValue: snapshot.location.databaseValue)
                    key.intValue.map({ tuple.append($0) }) ?? tuple.append(key.stringValue)
                    return rs.read(tuple.databaseValue) == nil
                }
            }
            func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { return try _decode(type, forKey: key) }
            func decode(_ type: Int.Type, forKey key: Key) throws -> Int { return try _decode(type, forKey: key) }
            func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { return try _decode(type, forKey: key) }
            func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { return try _decode(type, forKey: key) }
            func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { return try _decode(type, forKey: key) }
            func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { return try _decode(type, forKey: key) }
            func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { return try _decode(type, forKey: key) }
            func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { return try _decode(type, forKey: key) }
            func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { return try _decode(type, forKey: key) }
            func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { return try _decode(type, forKey: key) }
            func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { return try _decode(type, forKey: key) }
            func decode(_ type: Float.Type, forKey key: Key) throws -> Float { return try _decode(type, forKey: key) }
            func decode(_ type: Double.Type, forKey key: Key) throws -> Double { return try _decode(type, forKey: key) }
            func decode(_ type: String.Type, forKey key: Key) throws -> String { return try _decode(type, forKey: key) }
            func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable {
                return try T(from: _childValue(forKey: key))
            }
            func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
                return try _childValue(forKey: key).container(keyedBy: type)
            }
            func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
                return try _childValue(forKey: key).unkeyedContainer()
            }
            func superDecoder() throws -> Decoder { return snapshot }
            func superDecoder(forKey key: Key) throws -> Decoder { return snapshot }
        }
    }
}

extension ClusterDatabaseConnection {
    public func load(for node: Node, timeout: DispatchTimeInterval, in eventLoop: EventLoop? = nil) -> EventLoopFuture<RealtimeDataProtocol> {
        let promise = (eventLoop ?? self.eventLoop).newPromise(of: RealtimeDataProtocol.self)
        load(for: node, timeout: timeout, completion: promise.succeed(result:), onCancel: promise.fail(error:))
        return promise.futureResult
    }
}

extension Realtime.Transaction {
    public func commit(in eventLoop: EventLoop) -> EventLoopFuture<CommitState> {
        let promise = eventLoop.newPromise(of: CommitState.self)

        commit { (state, errors) in
            if let err = errors?.first {
                promise.fail(error: err)
            } else {
                promise.succeed(result: state)
            }
        }

        return promise.futureResult
    }
}


// Representers

public extension Representer where V: TupleConvertible & Decodable {
    static func fdb_tuple() -> Representer<V> {
        return Representer<V>(
            encoding: { (value) -> Any? in
                return Tuple(value).databaseValue.data
            },
            decoding: { (data) -> V in
                let container = try data.singleValueContainer()
                return try container.decode(V.self)
            }
        )
    }
}
