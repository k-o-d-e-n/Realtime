//
//  Firebase.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 25/02/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

#if canImport(FirebaseDatabase) && (os(macOS) || os(iOS))
import FirebaseDatabase
import FirebaseStorage

public extension DatabaseReference {
    static func fromRoot(_ path: String, of database: Database = Database.database()) -> DatabaseReference {
        return database.reference(withPath: path)
    }
    var rootPath: String { return path(from: root) }
    func path(from ref: DatabaseReference) -> String {
        return String(url[ref.url.endIndex...])
    }
}

public struct Event: Listenable {
    let database: RealtimeDatabase
    let node: Node
    let event: DatabaseDataEvent

    /// Disposable listening of value
    public func listening(_ assign: Assign<ListenEvent<(RealtimeDataProtocol, DatabaseDataEvent)>>) -> Disposable {
        let token = database.listen(node: node, event: event, assign)
        return ListeningDispose({
            self.database.removeObserver(for: self.node, with: token)
        })
    }
}

extension RealtimeDatabase {
    public func data(_ event: DatabaseDataEvent, node: Node) -> Event {
        return Event(database: self, node: node, event: event)
    }

    fileprivate func listen(node: Node, event: DatabaseDataEvent, _ assign: Assign<ListenEvent<(RealtimeDataProtocol, DatabaseDataEvent)>>) -> UInt {
        let token = observe(
            event,
            on: node,
            onUpdate: { d, e in assign.call(.value((d, e))) },
            onCancel: <-assign.map { .error($0) }
        )
        return token
    }
}

extension Node {
    static func from(_ reference: DatabaseReference) -> Node {
        return Node.root.child(with: reference.rootPath)
    }
    public func reference(for database: Database = Database.database()) -> DatabaseReference {
        return .fromRoot(absolutePath, of: database)
    }
    public func file(for storage: Storage = Storage.storage()) -> StorageReference {
        return storage.reference(withPath: absolutePath)
    }
}

/// --------------------------- DataSnapshot Decoder ------------------------------

public protocol FirebaseDataSnapshot {
    var value: Any? { get }
}
extension FirebaseDataSnapshot where Self: RealtimeDataProtocol {
    private func _throwTypeMismatch<T, R>(_ t: T.Type, returns: R.Type) throws -> R {
        throw DecodingError.typeMismatch(
            t,
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: String(describing: value)
            )
        )
    }
    private func _decode<T>(_ type: T.Type) throws -> NSNumber {
        guard case let v as NSNumber = value else {
            return try _throwTypeMismatch(type, returns: NSNumber.self)
        }
        return v
    }
    private func _decodeString() throws -> String {
        guard case let v as NSString = value else {
            return try _throwTypeMismatch(String.self, returns: String.self)
        }
        return v as String
    }
    public func decodeNil() -> Bool { return value == nil || value is NSNull }
    public func decode(_ type: Bool.Type) throws -> Bool { return try _decode(Bool.self).boolValue }
    public func decode(_ type: Int.Type) throws -> Int { return try _decode(Int64.self).intValue }
    public func decode(_ type: Int8.Type) throws -> Int8 { return try _decode(Int8.self).int8Value }
    public func decode(_ type: Int16.Type) throws -> Int16 { return try _decode(Int16.self).int16Value }
    public func decode(_ type: Int32.Type) throws -> Int32 { return try _decode(Int32.self).int32Value }
    public func decode(_ type: Int64.Type) throws -> Int64 { return try _decode(Int64.self).int64Value }
    public func decode(_ type: UInt.Type) throws -> UInt { return try _decode(UInt64.self).uintValue }
    public func decode(_ type: UInt8.Type) throws -> UInt8 { return try _decode(UInt8.self).uint8Value }
    public func decode(_ type: UInt16.Type) throws -> UInt16 { return try _decode(UInt16.self).uint16Value }
    public func decode(_ type: UInt32.Type) throws -> UInt32 { return try _decode(UInt32.self).uint32Value }
    public func decode(_ type: UInt64.Type) throws -> UInt64 { return try _decode(UInt64.self).uint64Value }
    public func decode(_ type: Float.Type) throws -> Float { return try _decode(Float.self).floatValue }
    public func decode(_ type: Double.Type) throws -> Double { return try _decode(Double.self).doubleValue }
    public func decode(_ type: String.Type) throws -> String { return try _decodeString() }
    public func decode(_ type: Data.Type) throws -> Data { return try _throwTypeMismatch(Data.self, returns: Data.self) }
    public func decode<T>(_ type: T.Type) throws -> T where T : Decodable { return try T(from: self) }

    private func _asRealtimeDatabaseValue(_ value: Any) throws -> RealtimeDatabaseValue? {
        switch value {
        case let dict as NSDictionary:
            return RealtimeDatabaseValue(
                try dict.map({ key, value in
                    guard let k = try _asRealtimeDatabaseValue(key), let v = try _asRealtimeDatabaseValue(value) else {
                        throw RealtimeError(decoding: RealtimeDatabaseValue.self, dict, reason: "Cannot find correct value to convert to RealtimeDatabaseValue")
                    }
                    return RealtimeDatabaseValue((k, v))
                })
            )
        case let arr as NSArray: return try RealtimeDatabaseValue(arr.compactMap(_asRealtimeDatabaseValue))
        case let string as NSString: return RealtimeDatabaseValue(string)
        case let value as NSNumber:
            let numberType = CFNumberGetType(value)
            switch numberType {
            case .charType: return RealtimeDatabaseValue(value.boolValue)
            case .sInt8Type: return RealtimeDatabaseValue(value.int8Value)
            case .sInt16Type: return RealtimeDatabaseValue(value.int16Value)
            case .sInt32Type: return RealtimeDatabaseValue(value.int32Value)
            case .sInt64Type: return RealtimeDatabaseValue(value.int64Value)
            case .shortType, .intType, .longType, .longLongType, .cfIndexType, .nsIntegerType:
                return RealtimeDatabaseValue(value.int64Value)
            case .float32Type, .floatType: return RealtimeDatabaseValue(value.floatValue)
            case .float64Type, .doubleType, .cgFloatType:
                return RealtimeDatabaseValue(value.doubleValue)
            }
        case _ as NSNull: return nil
        default: return nil
        }
    }

    public func asDatabaseValue() throws -> RealtimeDatabaseValue? {
        return try value.flatMap(_asRealtimeDatabaseValue)
    }
}
extension DataSnapshot: RealtimeDataProtocol, FirebaseDataSnapshot, Sequence {
    public var database: RealtimeDatabase? { return ref.database }
    public var storage: RealtimeStorage? { return nil }
    public var node: Node? { return Node.from(ref) }
    public var key: String? { return self.ref.key }

    public func child(forPath path: String) -> RealtimeDataProtocol { return childSnapshot(forPath: path) }
    public func makeIterator() -> AnyIterator<RealtimeDataProtocol> {
        let childs = children
        return AnyIterator {
            return childs.nextObject() as? DataSnapshot
        }
    }
}
extension MutableData: RealtimeDataProtocol, FirebaseDataSnapshot, Sequence {
    public var database: RealtimeDatabase? { return nil }
    public var storage: RealtimeStorage? { return nil }
    public var node: Node? { return key.map(Node.init) }

    public func exists() -> Bool { return value.map { !($0 is NSNull) } ?? false }
    public func child(forPath path: String) -> RealtimeDataProtocol { return childData(byAppendingPath: path) }
    public func hasChild(_ childPathString: String) -> Bool { return hasChild(atPath: childPathString) }
    public func makeIterator() -> AnyIterator<RealtimeDataProtocol> {
        let childs = children
        return AnyIterator {
            return childs.nextObject() as? MutableData
        }
    }
}

extension DataSnapshot: Decoder {}
extension MutableData: Decoder {}

// MARK - App init

public extension RealtimeApp.Configuration {
    static func firebase(
        linksNode: BranchNode? = nil,
        cachePolicy: CachePolicy = .noCache,
        storageCache: RealtimeStorageCache? = nil
        ) -> RealtimeApp.Configuration {
        return RealtimeApp.Configuration(
            linksNode: linksNode,
            maxNodeDepth: 32,
            unavailableSymbols: CharacterSet(charactersIn: ".#$][/"),
            cachePolicy: cachePolicy,
            storageCache: storageCache
        )
    }
}

extension RealtimeApp {
    public static func firebase(
        databaseUrl: String? = nil, storageUrl: String? = nil,
        configuration: Configuration = .firebase()
        ) {
        initialize(
            with: databaseUrl.map(Database.database) ?? Database.database(),
            storage: storageUrl.map(Storage.storage) ?? Storage.storage(),
            configuration: configuration
        )
    }
}

// MARK - Database + Storage

import FirebaseDatabase

extension DatabaseReference {
    public func update(use keyValuePairs: [String : Any?], completion: ((Error?) -> Void)?) {
        if let completion = completion {
            updateChildValues(keyValuePairs as [String: Any], withCompletionBlock: { error, dbNode in
                completion(error.map({ RealtimeError(external: $0, in: .database) }))
            })
        } else {
            updateChildValues(keyValuePairs as [String: Any])
        }
    }
}

extension DatabaseDataEvent {
    init(firebase events: [DataEventType]) {
        if events.isEmpty || events.contains(.value) {
            self = .value
        } else {
            self = .child(events.reduce(into: DatabaseDataChanges(rawValue: 0), { (res, event) in
                res.rawValue &= event.rawValue - 1
            }))
        }
    }

    var firebase: [DataEventType] {
        switch self {
        case .value: return [.value]
        case .child(let c):
            return [DataEventType.childAdded, DataEventType.childChanged,
                    DataEventType.childMoved, DataEventType.childRemoved].filter { (e) -> Bool in
                        switch e {
                        case .childAdded: return c.contains(.added)
                        case .childChanged: return c.contains(.changed)
                        case .childMoved: return c.contains(.moved)
                        case .childRemoved: return c.contains(.removed)
                        default: return false
                        }
            }
        }
    }
}

extension RealtimeDatabaseValue {
    func extractAsFirebaseKey() throws -> String {
        let incompatibleKey: (Any) throws -> String = { v in throw RealtimeError(source: .coding, description: "Non-string keys are not allowed in Firebase database. Received: \(v)") }
        return try extract(
            bool: incompatibleKey,
            int8: incompatibleKey,
            int16: incompatibleKey,
            int32: incompatibleKey,
            int64: incompatibleKey,
            uint8: incompatibleKey,
            uint16: incompatibleKey,
            uint32: incompatibleKey,
            uint64: incompatibleKey,
            double: incompatibleKey,
            float: incompatibleKey,
            string: { $0 },
            data: incompatibleKey,
            pair: { v1, v2 in throw RealtimeError(source: .coding, description: "Non-string keys are not allowed in Firebase database. Received: \((v1, v2))") },
            collection: incompatibleKey
        )
    }
    static func firebaseCollectionCompatible(_ values: [RealtimeDatabaseValue]) throws -> [String: Any] {
        return try values.reduce(into: [:], { (res, value) in
            switch value.backend {
            case .pair(let k, let v):
                res[try k.extractAsFirebaseKey()] = try v.extractFirebaseCompatible()
            case .bool(let v as Any),
                .int8(let v as Any),
                .int16(let v as Any),
                .int32(let v as Any),
                .int64(let v as Any),
                .uint8(let v as Any),
                .uint16(let v as Any),
                .uint32(let v as Any),
                .uint64(let v as Any),
                .double(let v as Any),
                .float(let v as Any),
                .string(let v as Any),
                .data(let v as Any):
                res["\(res.count)"] = v
            case .unkeyed(let v):
                res["\(res.count)"] = try RealtimeDatabaseValue.firebaseCollectionCompatible(v)
            }
        })
    }
    func extractFirebaseCompatible() throws -> Any {
        let any: (Any) -> Any = { $0 }
        return try extract(
            bool: any,
            int8: any,
            int16: any,
            int32: any,
            int64: any,
            uint8: any,
            uint16: any,
            uint32: any,
            uint64: any,
            double: any,
            float: any,
            string: any,
            data: any,
            pair: { _, _ in throw RealtimeError(source: .coding, description: "Unsupported value") },
            collection: RealtimeDatabaseValue.firebaseCollectionCompatible
        )
    }
}

extension Database: RealtimeDatabase {
    public var isConnectionActive: AnyListenable<Bool> {
        return AnyListenable(
            data(.value, node: ServiceNode(key: ".info/connected"))
                .map({ try $0.0.singleValueContainer().decode(Bool.self) })
        )
    }

    public var cachePolicy: CachePolicy {
        set {
            switch newValue {
            case .persistance:
                isPersistenceEnabled = true
            default:
                isPersistenceEnabled = false
            }
        }
        get {
            if isPersistenceEnabled {
                return .persistance
            } else {
                return RealtimeApp.app.configuration.cachePolicy
            }
        }
    }

    public func generateAutoID() -> String {
        return reference().childByAutoId().key!
    }

    public func commit(update: UpdateNode, completion: ((Error?) -> Void)?) {
        var updateValue: [String: Any?] = [:]
        do {
            try update.reduceValues(into: &updateValue, { container, node, value in
                container[node.path(from: update.location)] = .some(try value?.extractFirebaseCompatible())
            })
        } catch let e {
            completion?(e)
        }
        if updateValue.count > 0 {
            let ref = update.location.isRoot ? reference() : reference(withPath: update.location.absolutePath)
            ref.update(use: updateValue, completion: completion)
        } else if let compl = completion {
            debugFatalError("Empty transaction commit")
            compl(nil)
        }
    }

    public func load(
        for node: Node,
        timeout: DispatchTimeInterval,
        completion: @escaping (RealtimeDataProtocol) -> Void,
        onCancel: ((Error) -> Void)?) {
        var invalidated: Int32 = 0
        let ref = node.reference(for: self)
        let invalidate = { (token: UInt) -> Bool in
            if OSAtomicCompareAndSwap32Barrier(0, 1, &invalidated) {
                ref.removeObserver(withHandle: token)
                return true
            } else {
                return false
            }
        }
        var token: UInt!
        token = ref.observe(
            .value,
            with: { d in
                if invalidate(token) {
                    completion(d)
                }
        },
            withCancel: { e in
                if invalidate(token) {
                    onCancel?(RealtimeError(external: e, in: .database))
                }
            }
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: {
            if invalidate(token) {
                onCancel?(RealtimeError(source: .database, description: "Operation timeout"))
            }
        })
    }

    public func observe(
        _ event: DatabaseDataEvent,
        on node: Node,
        onUpdate: @escaping (RealtimeDataProtocol, DatabaseDataEvent) -> Void,
        onCancel: ((Error) -> Void)?) -> UInt {
        // TODO: Event takes only first, apply observing all events
        return node.reference(for: self).observe(
            event.firebase.first!,
            with: { d in onUpdate(d, event) },
            withCancel: { e in
                onCancel?(RealtimeError(external: e, in: .database))
            }
        )
    }

    public func removeAllObservers(for node: Node) {
        node.reference(for: self).removeAllObservers()
    }

    public func removeObserver(for node: Node, with token: UInt) {
        node.reference(for: self).removeObserver(withHandle: token)
    }

    public func observe(
        _ event: DatabaseDataEvent,
        on node: Node, limit: UInt,
        before: Any?, after: Any?,
        ascending: Bool, ordering: RealtimeDataOrdering,
        completion: @escaping (RealtimeDataProtocol, DatabaseDataEvent) -> Void,
        onCancel: ((Error) -> Void)?
        ) -> Disposable {
        var query: DatabaseQuery = reference(withPath: node.absolutePath)
        switch ordering {
        case .key: query = query.queryOrderedByKey()
        case .value: query = query.queryOrderedByValue()
        case .child(let key): query = query.queryOrdered(byChild: key)
        }
        var needExcludeKey = false
        if let before = before {
            query = query.queryEnding(atValue: before)
            needExcludeKey = true
        }
        if let after = after {
            query = query.queryStarting(atValue: after)
            needExcludeKey = true
        }
        let resultLimit = limit + (needExcludeKey ? 1 : 0)
        query = ascending ? query.queryLimited(toFirst: resultLimit) : query.queryLimited(toLast: resultLimit)

        let cancelHandler: ((Error) -> Void)? = onCancel.map { closure in
            return { (error) in
                closure(RealtimeError(external: error, in: .database))
            }
        }

        switch event {
        case .value:
            let handle = query.observe(
                .value,
                with: { (data) in
                    completion(data, .value)
                },
                withCancel: cancelHandler
            )
            return ListeningDispose({
                query.removeObserver(withHandle: handle)
            })
        case .child(let changes):
            var singleLoaded = false
            let added = changes.contains(.added) ? query.observe(
                .childAdded,
                with: { (data) in
                    if singleLoaded {
                        completion(data, .child(.added))
                    }
                },
                withCancel: cancelHandler
                ) : nil
            let removed = changes.contains(.removed) ? query.observe(
                .childRemoved,
                with: { (data) in
                    if singleLoaded {
                        completion(data, .child(.removed))
                    }
                },
                withCancel: cancelHandler
                ) : nil
            let changed = changes.contains(.changed) ? query.observe(
                .childChanged,
                with: { (data) in
                    if singleLoaded {
                        completion(data, .child(.changed))
                    }
                },
                withCancel: cancelHandler
                ) : nil
            query.observeSingleEvent(
                of: .value,
                with: { (data) in
                    completion(data, .value)
                    singleLoaded = true
                },
                withCancel: cancelHandler
            )

            return ListeningDispose({
                added.map(query.removeObserver)
                removed.map(query.removeObserver)
                changed.map(query.removeObserver)
            })
        }
    }

    public func runTransaction(
        in node: Node,
        withLocalEvents: Bool,
        _ updater: @escaping (RealtimeDataProtocol) -> ConcurrentIterationResult,
        onComplete: ((ConcurrentOperationResult) -> Void)?
        ) {
        reference(withPath: node.absolutePath).runTransactionBlock(
            { mutableData in
                switch updater(mutableData) {
                case .abort: return .abort()
                case .value(let v):
                    mutableData.value = v
                    return .success(withValue: mutableData)
                }
        },
            andCompletionBlock: onComplete.map({ closure in
                return { error, flag, data in
                    if let e = error {
                        closure(.error(RealtimeError(external: e, in: .database)))
                    } else if flag, let d = data {
                        closure(.data(d))
                    } else {
                        closure(.error(RealtimeError(source: .database, description: "Unexpected result of concurrent operation")))
                    }
                }
            }),
            withLocalEvents: withLocalEvents
        )
    }
}

/// Storage

import FirebaseStorage

extension StorageReference {
    public func put(_ data: Data, metadata: RealtimeMetadata?, completion: @escaping (RealtimeMetadata?, Error?) -> Void) {
        var smd: StorageMetadata?
        if let md = metadata {
            smd = StorageMetadata(dictionary: md)
            debugFatalError(condition: smd == nil, "Initializing metadata is failed")
        }
        putData(data, metadata: smd, completion: { md, err in
            completion(md?.dictionaryRepresentation(), err.map({ RealtimeError(external: $0, in: .storage) }))
        })
    }
}

extension StorageDownloadTask: RealtimeStorageTask {
    public var progress: AnyListenable<Progress> {
        return AnyListenable(Status(task: self, statuses: [.progress]).compactMap({ $0.progress }))
    }
    public var success: AnyListenable<RealtimeMetadata?> {
        return AnyListenable(Status(task: self, statuses: [.success, .failure]).map({ snapshot in
            if let e = snapshot.error {
                if case let nsError as NSError = e, let code = StorageErrorCode(rawValue: nsError.code), code == .objectNotFound {
                    return nil
                } else {
                    throw RealtimeError(external: e, in: .storage)
                }
            } else {
                return snapshot.metadata?.dictionaryRepresentation()
            }
        }))
    }
}
extension StorageDownloadTask {
    struct Status: Listenable {
        let task: StorageDownloadTask
        let statuses: [StorageTaskStatus]

        func listening(_ assign: Closure<ListenEvent<StorageTaskSnapshot>, Void>) -> Disposable {
            let handles = statuses.map({ task.observe($0, handler: assign.map({ .value($0) }).closure) })
            return ListeningDispose({
                handles.forEach(self.task.removeObserver)
            })
        }
    }
}

extension Storage: RealtimeStorage {
    public func load(
        for node: Node,
        timeout: DispatchTimeInterval,
        completion: @escaping (Data?) -> Void,
        onCancel: ((Error) -> Void)?
        ) -> RealtimeStorageTask {
        //        var invalidated: Int32 = 0
        let ref = node.file(for: self)
        //        let invalidate = { (task: StorageDownloadTask?) -> Bool in
        //            if OSAtomicCompareAndSwap32Barrier(0, 1, &invalidated) {
        //                task?.cancel()
        //                return true
        //            } else {
        //                return false
        //            }
        //        }
        var task: StorageDownloadTask!
        task = ref.getData(maxSize: .max) { (data, error) in
            //            guard invalidate(nil) else { return }
            switch error {
            case .none: completion(data)
            case .some(let nsError as NSError):
                if let code = StorageErrorCode(rawValue: nsError.code), code == .objectNotFound {
                    completion(nil)
                } else {
                    onCancel?(nsError)
                }
            default: onCancel?(error!)
            }
        }

        //        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: {
        //            if invalidate(task) {
        //                onCancel?(RealtimeError(source: .database, description: "Operation timeout"))
        //            }
        //        })

        return task
    }
    public func commit(transaction: Transaction, completion: @escaping ([Transaction.FileCompletion]) -> Void) {
        var nearest = transaction.updateNode
        while nearest.childs.count == 1, case .some(.object(let next)) = nearest.childs.first {
            nearest = next
        }
        let files = nearest.files
        guard !files.isEmpty else { return completion([]) }

        let group = DispatchGroup()
        let lock = NSRecursiveLock()
        var completions: [Transaction.FileCompletion] = []
        let addCompletion: (Node, [String: Any]?, Error?) -> Void = { node, md, err in
            lock.lock()
            completions.append(
                md.map({ .meta($0) }) ??
                    .error(
                        node,
                        err ?? RealtimeError(source: .file, description: "Unexpected error on upload file")
                )
            )
            lock.unlock()
            group.leave()
        }
        files.indices.forEach { _ in group.enter() }
        files.forEach { (file) in
            let location = file.location
            if let value = file.value {
                do {
                    let data = try value.typed(as: Data.self)
                    reference(withPath: location.absolutePath).put(data, metadata: file.metadata, completion: { (md, err) in
                        addCompletion(location, md, err)
                    })
                } catch {
                    addCompletion(location, nil, RealtimeError(source: .storage, description: "Internal error: Cannot get file data."))
                }
            } else {
                reference(withPath: location.absolutePath).delete(completion: { (err) in
                    addCompletion(location, nil, err.map({ RealtimeError(external: $0, in: .value) }))
                })
            }
        }
        group.notify(queue: .main) {
            completion(completions)
        }
    }
}
#endif
