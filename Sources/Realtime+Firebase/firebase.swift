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
    public func listening(_ assign: Assign<ListenEvent<RealtimeDataProtocol>>) -> Disposable {
        let token = database.listen(node: node, event: event, assign)
        return ListeningDispose({
            self.database.removeObserver(for: self.node, with: token)
        })
    }

    /// Listening with possibility to control active state
    public func listeningItem(_ assign: Assign<ListenEvent<RealtimeDataProtocol>>) -> ListeningItem {
        let event = self.event
        let token = database.listen(node: node, event: event, assign)
        return ListeningItem(
            resume: { self.database.listen(node: self.node, event: event, assign) },
            pause: { self.database.removeObserver(for: self.node, with: $0) },
            token: token
        )
    }
}

extension RealtimeDatabase {
    public func data(_ event: DatabaseDataEvent, node: Node) -> Event {
        return Event(database: self, node: node, event: event)
    }

    fileprivate func listen(node: Node, event: DatabaseDataEvent, _ assign: Assign<ListenEvent<RealtimeDataProtocol>>) -> UInt {
        let token = observe(
            event,
            on: node,
            onUpdate: <-assign.map { .value($0) },
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

extension DataSnapshot: RealtimeDataProtocol, Sequence {
    public var key: String? {
        return self.ref.key
    }

    public var database: RealtimeDatabase? { return ref.database }
    public var storage: RealtimeStorage? { return nil }
    public var node: Node? { return Node.from(ref) }

    public func asSingleValue() -> Any? { return value }

    public func child(forPath path: String) -> RealtimeDataProtocol {
        return childSnapshot(forPath: path)
    }

    public func makeIterator() -> AnyIterator<RealtimeDataProtocol> {
        let childs = children
        return AnyIterator {
            return childs.nextObject() as? DataSnapshot
        }
    }

    public func satisfy<T>(to type: T.Type) -> Bool {
        switch value {
        case .some(_ as NSDictionary): return type == NSDictionary.self
        case .some(_ as NSArray): return type == NSArray.self
        case .some(_ as NSString): return type == NSString.self || type == String.self
        case .some(let value as NSNumber):
            guard type != NSNumber.self else { return true }
            let numberType = CFNumberGetType(value)
            switch numberType {
            case .charType: return type == Bool.self
            case .sInt8Type: return type == Int8.self
            case .sInt16Type: return type == Int16.self
            case .sInt32Type: return type == Int32.self
            case .sInt64Type: return type == Int64.self
            case .shortType, .intType, .longType, .longLongType, .cfIndexType, .nsIntegerType:
                return type == Int.self
            case .float32Type, .float64Type, .floatType, .doubleType, .cgFloatType:
                return type == Float.self || type == Double.self || type == CGFloat.self
            }
        case .some(_ as NSNull): return type == NSNull.self
        case .none: return type == NSNull.self
        default: return value as? T != nil
        }
    }
}
extension MutableData: RealtimeDataProtocol, Sequence {
    public var database: RealtimeDatabase? { return nil }
    public var storage: RealtimeStorage? { return nil }
    public var node: Node? { return key.map(Node.init) }

    public func asSingleValue() -> Any? { return value }

    public func exists() -> Bool {
        return value.map { !($0 is NSNull) } ?? false
    }

    public func child(forPath path: String) -> RealtimeDataProtocol {
        return childData(byAppendingPath: path)
    }

    public func hasChild(_ childPathString: String) -> Bool {
        return hasChild(atPath: childPathString)
    }

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
            case ._untyped: throw RealtimeError(source: .coding, description: "Untyped values no more supported")
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
                .map({ try $0.singleValueContainer().decode(Bool.self) })
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
        onUpdate: @escaping (RealtimeDataProtocol) -> Void,
        onCancel: ((Error) -> Void)?) -> UInt {
        return node.reference(for: self).observe(event.firebase.first!, with: onUpdate, withCancel: { e in // TODO: Event takes only first, apply observing all events
            onCancel?(RealtimeError(external: e, in: .database))
        })
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
        func listeningItem(_ assign: Closure<ListenEvent<StorageTaskSnapshot>, Void>) -> ListeningItem {
            let handler = assign.map({ .value($0) }).closure
            let handles = statuses.map({ task.observe($0, handler: handler) })
            return ListeningItem(
                resume: { () -> [String] in
                    return self.statuses.map({ self.task.observe($0, handler: handler) })
            },
                pause: { $0.forEach(self.task.removeObserver) },
                token: handles
            )
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
                guard case let data as Data = value.untyped else {
                    fatalError("Unexpected type of value \(file.value as Any) for file by node: \(file.location)")
                }
                reference(withPath: location.absolutePath).put(data, metadata: file.metadata, completion: { (md, err) in
                    addCompletion(location, md, err)
                })
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
