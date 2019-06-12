//
//  realtime.database.swift
//  Realtime
//
//  Created by Denis Koryttsev on 31/07/2018.
//

import Foundation

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

public struct DatabaseDataChanges: OptionSet {
    public var rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}
public extension DatabaseDataChanges {
    /// - A new child node is added to a location.
    static let added: DatabaseDataChanges = DatabaseDataChanges(rawValue: 1 << 0)
    /// - A child node is removed from a location.
    static let removed: DatabaseDataChanges = DatabaseDataChanges(rawValue: 1 << 1)
    /// - A child node at a location changes.
    static let changed: DatabaseDataChanges = DatabaseDataChanges(rawValue: 1 << 2)
    /// - A child node moves relative to the other child nodes at a location.
    static let moved: DatabaseDataChanges = DatabaseDataChanges(rawValue: 1 << 3)

//    static let all: [DatabaseDataChanges] = [.added, .removed, .changed, .moved]
}

/// A event that corresponds some type of data mutating
///
/// - value: Any data changes at a location or, recursively, at any child node.
/// - child: Any data change is related some child node.
public enum DatabaseObservingEvent: Hashable, CustomDebugStringConvertible {
    case value
    case child(DatabaseDataChanges)

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .value: hasher.combine(0)
        case .child(let c): hasher.combine(c.rawValue)
        }
    }

    public var debugDescription: String {
        switch self {
        case .value: return "value"
        case .child(.added): return "child(added)"
        case .child(.removed): return "child(removed)"
        case .child(.changed): return "child(changed)"
        case .child(.moved): return "child(moved)"
        default: return "undefined"
        }
    }
}

public typealias DatabaseDataEvent = DatabaseObservingEvent

public enum RealtimeDataOrdering {
    case key
    case value
    case child(String)
}

public enum ConcurrentIterationResult {
    case abort
    case value(Any?)
}
public enum ConcurrentOperationResult {
    case error(Error)
    case data(RealtimeDataProtocol)
}

/// A database that can used in `Realtime` framework.
public protocol RealtimeDatabase: class {
    /// A database cache policy.
    var cachePolicy: CachePolicy { get set }
    /// Generates an automatically calculated database key
    func generateAutoID() -> String
    /// Performs the writing of a changes that contains in passed Transaction
    ///
    /// - Parameters:
    ///   - transaction: Write transaction
    ///   - completion: Closure to receive result of operation
    func commit(transaction: Transaction, completion: ((Error?) -> Void)?)
    /// Loads data by database reference
    ///
    /// - Parameters:
    ///   - node: Realtime database reference
    ///   - completion: Closure to receive data
    ///   - onCancel: Closure to receive cancel event
    func load(
        for node: Node,
        timeout: DispatchTimeInterval,
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
    func observe(
        _ event: DatabaseDataEvent,
        on node: Node, limit: UInt,
        before: Any?, after: Any?,
        ascending: Bool, ordering: RealtimeDataOrdering,
        completion: @escaping (RealtimeDataProtocol, DatabaseDataEvent) -> Void,
        onCancel: ((Error) -> Void)?
    ) -> Disposable

    func runTransaction(
        in node: Node,
        withLocalEvents: Bool,
        _ updater: @escaping (RealtimeDataProtocol) -> ConcurrentIterationResult,
        onComplete: ((ConcurrentOperationResult) -> Void)?
    )

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
    /// Sends connection state each time when it changed
    var isConnectionActive: AnyListenable<Bool> { get }
}

struct RealtimeData: RealtimeDataProtocol {
    let base: RealtimeDataProtocol
    let excludedKeys: [String]

    var database: RealtimeDatabase? { return base.database }
    var storage: RealtimeStorage? { return base.storage }
    var node: Node? { return base.node }
    var key: String? { return base.key }
    var value: Any? { return base.value }
    var priority: Any? { return base.priority }
    var childrenCount: UInt {
        return excludedKeys.reduce(into: base.childrenCount) { (res, key) -> Void in
            if base.hasChild(key) {
                res -= 1
            }
        }
    }
    func makeIterator() -> AnyIterator<RealtimeDataProtocol> {
        let baseIterator = base.makeIterator()
        let excludes = excludedKeys
        return AnyIterator({ () -> RealtimeDataProtocol? in
            var data: RealtimeDataProtocol?
            while data == nil, let d = baseIterator.next() {
                data = d.key.flatMap({ excludes.contains($0) ? nil : d })
            }
            return data
        })
    }
    func exists() -> Bool { return base.exists() }
    func hasChildren() -> Bool { return childrenCount > 0 }
    func hasChild(_ childPathString: String) -> Bool {
        if excludedKeys.contains(where: childPathString.hasPrefix) {
            return false
        } else {
            return base.hasChild(childPathString)
        }
    }
    func child(forPath path: String) -> RealtimeDataProtocol {
        if excludedKeys.contains(where: path.hasPrefix) {
            return ValueNode(node: Node(key: path, parent: node), value: nil)
        } else {
            return base.child(forPath: path)
        }
    }
    
    var debugDescription: String { return base.debugDescription + "\nexcludes: \(excludedKeys)" }
    var description: String { return base.description + "\nexcludes: \(excludedKeys)" }
}

public typealias RealtimeMetadata = [String: Any]
public protocol RealtimeStorageCache {
    func file(for node: Node, completion: @escaping (Data?) -> Void)
    func put(_ file: Data, for node: Node, completion: ((Error?) -> Void)?)
}

public protocol RealtimeStorage {
    func load(
        for node: Node,
        timeout: DispatchTimeInterval,
        completion: @escaping (Data?) -> Void,
        onCancel: ((Error) -> Void)?
        ) -> RealtimeStorageTask
    func commit(transaction: Transaction, completion: @escaping ([Transaction.FileCompletion]) -> Void)
}

public protocol RealtimeTask {
    var completion: AnyListenable<Void> { get }
}

public protocol RealtimeStorageTask: RealtimeTask {
    var progress: AnyListenable<Progress> { get }
    var success: AnyListenable<RealtimeMetadata?> { get }

    func pause()
    func cancel()
    func resume()
}
public extension RealtimeStorageTask {
    var completion: AnyListenable<Void> { return success.map({ _ in () }).asAny() }
}

// Paging

public class PagingControl {
    weak var controller: PagingController?
    public var isAttached: Bool { return controller != nil }
    public var canMakeStep: Bool { return controller.map({ $0.isStarted }) ?? false }

    public init() {}

    public func start(observeNew observe: Bool, completion: (() -> Void)?) {
        controller?.start(observeNew: observe, completion: completion)
    }

    public func stop() {
        controller?.stop()
    }

    public func next() -> Bool {
        return controller?.next() ?? false
    }
    public func previous() -> Bool {
        return controller?.previous() ?? false
    }
}

protocol PagingControllerDelegate: class {
    func firstKey() -> String?
    func lastKey() -> String?
    func pagingControllerDidReceive(data: RealtimeDataProtocol, with event: DatabaseDataEvent)
    func pagingControllerDidCancel(with error: Error)
}

class PagingController {
    private let database: RealtimeDatabase
    private let node: Node
    var pageSize: UInt
    let ascending: Bool
    private weak var delegate: PagingControllerDelegate?
    private var startPage: Disposable?
    private var pages: [String: Disposable] = [:]
    private var endPage: Disposable?
    private var firstKey: String?
    private var lastKey: String?
    private var observedNew: Bool = false
    var isStarted: Bool { return startPage != nil }

    init(database: RealtimeDatabase, node: Node,
         pageSize: UInt,
         ascending: Bool,
         delegate: PagingControllerDelegate) {
        self.node = node
        self.database = database
        self.ascending = ascending
        self.pageSize = pageSize
        self.delegate = delegate
    }

    func start(observeNew observe: Bool = true, completion: (() -> Void)? = nil) {
        guard startPage == nil else {
            fatalError("Controller already started")
        }
        self.observedNew = observe
        var disposable: Disposable?
        var completion = completion
        disposable = database.observe(
            .child(observe ? .added : []),
            on: node,
            limit: pageSize,
            before: nil,
            after: nil,
            ascending: ascending,
            ordering: .key,
            completion: { [weak self] data, event in
                guard let `self` = self else { return }
                if event == .value {
                    self.endPage = data.childrenCount == self.pageSize ? nil : disposable
                    self.startPage = disposable
                    if let compl = completion {
                        compl()
                        completion = nil
                    }
                }
                self.delegate?.pagingControllerDidReceive(data: data, with: event)
            },
            onCancel: { [weak self] (error) in
                self?.delegate?.pagingControllerDidCancel(with: error)
            }
        )
    }

    func stop() {
        startPage?.dispose()
        pages.forEach({ $0.value.dispose() })
        startPage = nil
        endPage?.dispose()
        endPage = nil
    }

    var hasHandleUpdateForPrevious: Bool { return ascending || !observedNew }
    func previous() -> Bool {
        guard self.startPage != nil else { fatalError("Firstly need call start") }
        guard let first = delegate?.firstKey(), (first != firstKey || hasHandleUpdateForPrevious) else {
            debugLog("No more data")
            return false
        }

        var disposable: Disposable?
        disposable = database.observe(
            .child([]), // with .child([]) disposable has no significance
            on: node,
            limit: pageSize,
            before: ascending ? first : nil,
            after: ascending ? nil : first,
            ascending: ascending,
            ordering: .key,
            completion: { [weak self] data, event in
                guard let `self` = self, let delegate = self.delegate else { return }
                switch event {
                case .value:
                    //                    if data.childrenCount == self.pageSize + 1 {
                    //                        if let old = self.firstKey, let startPage = self.startPage {
                    //                            self.pages[old] = startPage
                    //                        }
                    //                        self.startPage = disposable
                    self.firstKey = first /// set previous last key to keep available to next call, or if has no data stop all next loading
                    //                    }
                    if data.hasChildren() {
                        let realtimeData = RealtimeData(base: data, excludedKeys: [first])
                        if realtimeData.hasChildren() {
                            delegate.pagingControllerDidReceive(data: realtimeData,
                                                                with: .child(.added))
                        }
                    }
                case .child(.added):
                    if data.key != first {
                        delegate.pagingControllerDidReceive(data: data, with: event)
                    }
                default:
                    delegate.pagingControllerDidReceive(data: data, with: event)
                }
            },
            onCancel: { [weak self] (error) in
                self?.delegate?.pagingControllerDidCancel(with: error)
            }
        )

        return true
    }

    var hasHandleUpdateForNext: Bool { return !(ascending && observedNew) }
    func next() -> Bool {
        guard self.startPage != nil else { fatalError("Firstly need call start") }
        guard let last = self.delegate?.lastKey(), (last != lastKey || hasHandleUpdateForNext) else {
            debugLog("No more data")
            return false
        }

        var disposable: Disposable?
        disposable = database.observe(
            .child([]), // with .child([]) disposable has no significance
            on: node,
            limit: pageSize,
            before: ascending ? nil : last,
            after: ascending ? last : nil,
            ascending: ascending,
            ordering: .key,
            completion: { [weak self] data, event in
                guard let `self` = self, let delegate = self.delegate else { return }
                switch event {
                case .value:
                    //                    if data.childrenCount == self.pageSize + 1 {
                    //                        if let oldLast = self.lastKey, let endPage = self.endPage {
                    //                            self.pages[oldLast] = endPage
                    //                        }
                    //                        self.endPage = disposable
                    self.lastKey = last /// set previous last key to keep available to next call, or if has no data stop all next loading
                    //                    }
                    if data.hasChildren() {
                        let realtimeData = RealtimeData(base: data, excludedKeys: [last])
                        if realtimeData.hasChildren() {
                            delegate.pagingControllerDidReceive(data: realtimeData,
                                                                with: .child(.added))
                        }
                    }
                case .child(.added):
                    if data.key != last {
                        delegate.pagingControllerDidReceive(data: data, with: event)
                    }
                default:
                    delegate.pagingControllerDidReceive(data: data, with: event)
                }
            },
            onCancel: { [weak self] (error) in
                self?.delegate?.pagingControllerDidCancel(with: error)
            }
        )

        return true
    }

    deinit {
        startPage?.dispose()
        pages.forEach({ $0.value.dispose() })
        endPage?.dispose()
    }
}


// MARK - Firebase

#if canImport(FirebaseDatabase) && (os(macOS) || os(iOS))
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

extension Database: RealtimeDatabase {
    public var isConnectionActive: AnyListenable<Bool> {
        return AnyListenable(
            data(.value, node: ServiceNode(key: ".info/connected"))
                .map({ $0.value as? Bool })
                .compactMap()
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

    public func commit(transaction: Transaction, completion: ((Error?) -> Void)?) {
        let updateNode = transaction.updateNode
        guard updateNode.childs.count > 0 else {
            fatalError("Try commit empty transaction")
        }

        var nearest = updateNode
        while nearest.childs.count == 1, case .some(.object(let next)) = nearest.childs.first {
            nearest = next
        }
        let updateValue = nearest.values
        if updateValue.count > 0 {
            let ref = nearest.location.isRoot ? reference() : reference(withPath: nearest.location.absolutePath)
            ref.update(use: updateValue, completion: completion)
        } else if let compl = completion {
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
        return node.reference(for: self).observe(event.firebase.first!, with: onUpdate, withCancel: { e in
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
        return AnyListenable(Status(task: self, status: .progress).compactMap({ $0.progress }))
    }
    public var success: AnyListenable<RealtimeMetadata?> {
        return AnyListenable(Status(task: self, status: .success).map({ snapshot in
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
        let status: StorageTaskStatus

        func listening(_ assign: Closure<ListenEvent<StorageTaskSnapshot>, Void>) -> Disposable {
            let handle = task.observe(status, handler: assign.map({ .value($0) }).closure)
            return ListeningDispose({
                self.task.removeObserver(withHandle: handle)
            })
        }
        func listeningItem(_ assign: Closure<ListenEvent<StorageTaskSnapshot>, Void>) -> ListeningItem {
            let handler = assign.map({ .value($0) }).closure
            let handle = task.observe(status, handler: handler)
            return ListeningItem(
                resume: { () -> String? in
                    return self.task.observe(self.status, handler: handler)
                },
                pause: task.removeObserver,
                token: handle
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
                guard case let data as Data = value else {
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
