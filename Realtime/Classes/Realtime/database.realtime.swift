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
            updateChildValues(keyValuePairs, withCompletionBlock: { error, dbNode in
                completion(error.map({ RealtimeError(external: $0, in: .database) }), dbNode)
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
public enum DatabaseObservingEvent: Hashable {
    case value
    case child(DatabaseDataChanges)

    public var hashValue: Int {
        switch self {
        case .value: return 0
        case .child(let c): return c.rawValue.hashValue
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

    var isConnectionActive: AnyListenable<Bool> { get }
}
extension Database: RealtimeDatabase {
    public var isConnectionActive: AnyListenable<Bool> {
        return AnyListenable(
            data(.value, node: Node(key: ".info/connected", parent: .root))
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
            return reference(withPath: valueNode.absolutePath)
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
        } else if let compl = completion {
            compl(nil, node(with: nearest.location))
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
}

/// Storage

import FirebaseStorage

public typealias RealtimeMetadata = [String: Any]

public protocol StorageNode {
    func delete(completion: ((Error?) -> Void)?)
    func put(_ data: Data, metadata: RealtimeMetadata?, completion: @escaping (RealtimeMetadata?, Error?) -> Void)
}

extension StorageReference: StorageNode {
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
    func node(with referenceNode: Node) -> StorageNode
    func commit(transaction: Transaction, completion: @escaping ([Transaction.FileCompletion]) -> Void)
}

extension Storage: RealtimeStorage {
    public func node(with referenceNode: Node) -> StorageNode {
        return reference(withPath: referenceNode.rootPath)
    }

    public func commit(transaction: Transaction, completion: @escaping ([Transaction.FileCompletion]) -> Void) {
        var nearest = transaction.updateNode
        while nearest.childs.count == 1, let next = nearest.childs.first as? ObjectNode {
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
                node(with: file.location).put(data, metadata: nil, completion: { (md, err) in
                    addCompletion(location, md, err)
                })
            } else {
                node(with: file.location).delete(completion: { (err) in
                    addCompletion(location, nil, err.map({ RealtimeError(external: $0, in: .value) }))
                })
            }
        }
        group.notify(queue: .main) {
            completion(completions)
        }
    }
}
