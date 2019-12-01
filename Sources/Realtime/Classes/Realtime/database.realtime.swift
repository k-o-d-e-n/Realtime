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
public enum DatabaseDataEvent: Hashable, CustomDebugStringConvertible {
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

@available(*, deprecated, renamed: "DatabaseDataEvent", message: "Use DatabaseDataEvent instead")
public typealias DatabaseObservingEvent = DatabaseDataEvent

public enum RealtimeDataOrdering: Equatable {
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
    func commit(update: UpdateNode, completion: ((Error?) -> Void)?)
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
        onUpdate: @escaping (RealtimeDataProtocol, DatabaseDataEvent) -> Void,
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

    func asDatabaseValue() throws -> RealtimeDatabaseValue? { return try base.asDatabaseValue() }

    func decodeNil() -> Bool { return base.decodeNil() }
    func decode(_ type: Bool.Type) throws -> Bool { return try base.decode(type) }
    func decode(_ type: Int.Type) throws -> Int { return try base.decode(type) }
    func decode(_ type: Int8.Type) throws -> Int8 { return try base.decode(type) }
    func decode(_ type: Int16.Type) throws -> Int16 { return try base.decode(type) }
    func decode(_ type: Int32.Type) throws -> Int32 { return try base.decode(type) }
    func decode(_ type: Int64.Type) throws -> Int64 { return try base.decode(type) }
    func decode(_ type: UInt.Type) throws -> UInt { return try base.decode(type) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { return try base.decode(type) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { return try base.decode(type) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { return try base.decode(type) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { return try base.decode(type) }
    func decode(_ type: Float.Type) throws -> Float { return try base.decode(type) }
    func decode(_ type: Double.Type) throws -> Double { return try base.decode(type) }
    func decode(_ type: String.Type) throws -> String { return try base.decode(type) }
    func decode(_ type: Data.Type) throws -> Data { return try base.decode(type) }
    func decode<T>(_ type: T.Type) throws -> T where T : Decodable { return try T(from: self) }
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
    func commit(transaction: Transaction, completion: @escaping ([Transaction.FileCompletion]) -> Void) // TODO: Replace transaction parameter with UpdateNode
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
    deinit {
        startPage?.dispose()
        pages.forEach({ $0.value.dispose() })
        endPage?.dispose()
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
}
