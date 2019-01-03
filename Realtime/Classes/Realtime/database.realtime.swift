//
//  realtime.database.swift
//  Realtime
//
//  Created by Denis Koryttsev on 31/07/2018.
//

import Foundation
import FirebaseDatabase

extension DatabaseReference {
    public func update(use keyValuePairs: [String : Any], completion: ((Error?) -> Void)?) {
        if let completion = completion {
            updateChildValues(keyValuePairs, withCompletionBlock: { error, dbNode in
                completion(error.map({ RealtimeError(external: $0, in: .database) }))
            })
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

    public var hashValue: Int {
        switch self {
        case .value: return 0
        case .child(let c): return c.rawValue.hashValue
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

public enum RealtimeDataOrdering {
    case key
    case value
    case child(String)
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
        node: Node, limit: UInt,
        before: Any?, after: Any?,
        ascending: Bool, ordering: RealtimeDataOrdering,
        completion: @escaping (RealtimeDataProtocol, DatabaseDataEvent) -> Void,
        onCancel: ((Error) -> Void)?
    ) -> Disposable
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
        return reference().childByAutoId().key
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
        node: Node, limit: UInt,
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

//        var singleLoaded = false
//        let added = query.observe(
//            .childAdded,
//            with: { (data) in
//                if singleLoaded {
//                    completion(data, .child(.added))
//                }
//            },
//            withCancel: cancelHandler
//        )
//        let removed = query.observe(
//            .childRemoved,
//            with: { (data) in
//                if singleLoaded {
//                    completion(data, .child(.removed))
//                }
//            },
//            withCancel: cancelHandler
//        )
//        let changed = query.observe(
//            .childChanged,
//            with: { (data) in
//                if singleLoaded {
//                    completion(data, .child(.changed))
//                }
//            },
//            withCancel: cancelHandler
//        )
        query.observeSingleEvent(
            of: .value,
            with: { (data) in
                completion(data, .value)
//                singleLoaded = true
            },
            withCancel: cancelHandler
        )

        return EmptyDispose()
//        return ListeningDispose({
//            query.removeObserver(withHandle: added)
//            query.removeObserver(withHandle: removed)
//            query.removeObserver(withHandle: changed)
//        })
    }
}

/// Storage

import FirebaseStorage

public typealias RealtimeMetadata = [String: Any]

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

public protocol RealtimeStorage {
    func commit(transaction: Transaction, completion: @escaping ([Transaction.FileCompletion]) -> Void)
}

extension Storage: RealtimeStorage {
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
                reference(withPath: location.absolutePath).put(data, metadata: nil, completion: { (md, err) in
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

// Paging

public class PagingControl {
    weak var controller: PagingController?
    public var isAttached: Bool { return controller != nil }
    public var canMakeStep: Bool { return controller.map({ $0.isStarted }) ?? false }

    public init() {}

    public func next() {
        controller?.next()
    }
    public func previous() {
        controller?.previous()
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

    func start() {
        guard startPage == nil else {
            fatalError("Controller already started")
        }
        var disposable: Disposable?
        disposable = database.observe(
            node: node,
            limit: pageSize,
            before: nil,
            after: nil,
            ascending: ascending,
            ordering: .key,
            completion: { [weak self] data, event in
                guard let `self` = self else { return }
                self.endPage = data.childrenCount == self.pageSize ? nil : disposable
                self.startPage = disposable
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
    }

    func previous() {
        // replace start page
        guard self.startPage != nil else { fatalError("Firstly need call start") }
        guard let first = delegate?.firstKey(), first != firstKey else { return debugLog("No more data") }

        var disposable: Disposable?
        disposable = database.observe(
            node: node,
            limit: pageSize,
            before: ascending ? first : nil,
            after: ascending ? nil : first,
            ascending: ascending,
            ordering: .key,
            completion: { [weak self] data, event in
                guard let `self` = self, let delegate = self.delegate else { return }
                switch event {
                case .value:
                    if data.childrenCount == self.pageSize + 1 {
                        if let old = self.firstKey, let startPage = self.startPage {
                            self.pages[old] = startPage
                        }
                        self.startPage = disposable
                        self.firstKey = first
                    }
                    if data.hasChildren() {
                        delegate.pagingControllerDidReceive(data: RealtimeData(base: data, excludedKeys: [first]),
                                                            with: .child(.added))
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
    }

    func next() {
        // replace end page
        guard self.startPage != nil else { fatalError("Firstly need call start") }
        guard let last = self.delegate?.lastKey(), last != lastKey else { return debugLog("No more data") }

        var disposable: Disposable?
        disposable = database.observe(
            node: node,
            limit: pageSize,
            before: ascending ? nil : last,
            after: ascending ? last : nil,
            ascending: ascending,
            ordering: .key,
            completion: { [weak self] data, event in
                guard let `self` = self, let delegate = self.delegate else { return }
                switch event {
                case .value:
                    if data.childrenCount == self.pageSize + 1 {
                        if let oldLast = self.lastKey, let endPage = self.endPage {
                            self.pages[oldLast] = endPage
                        }
                        self.endPage = disposable
                        self.lastKey = last
                    }
                    if data.hasChildren() {
                        delegate.pagingControllerDidReceive(data: RealtimeData(base: data, excludedKeys: [last]),
                                                            with: .child(.added))
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
    }

    deinit {
        startPage?.dispose()
        pages.forEach({ $0.value.dispose() })
        endPage?.dispose()
    }
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
            if hasChild(key) {
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
    func hasChildren() -> Bool { return base.hasChildren() }
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
