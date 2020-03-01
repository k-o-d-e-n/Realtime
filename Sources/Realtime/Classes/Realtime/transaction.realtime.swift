//
//  Transaction.swift
//  Realtime
//
//  Created by Denis Koryttsev on 16/03/2018.
//

import Foundation

/// TODO: Reconsider it
public protocol Reverting: class {
    /// reverts last change
    func revert()

    /// returns closure to revert last change
    func currentReversion() -> () -> Void
}
extension Reverting where Self: ChangeableRealtimeValue {
    func revertIfChanged() {
        if hasChanges {
            revert()
        }
    }
}

/// Helps to make complex write transactions.
/// Provides addition of operations with completion handler, cancelation, and async preconditions.
public final class Transaction {
    let database: RealtimeDatabase
    let storage: RealtimeStorage
    internal var updateNode: ObjectNode = ObjectNode(node: .root)
    fileprivate var preconditions: [(PromiseVoid) -> Void] = []
    fileprivate var completions: [(Bool) -> Void] = []
    fileprivate var cancelations: [() -> Void] = []
    fileprivate var fileCancelations: [Node: () -> Void] = [:]
    fileprivate var scheduledMerges: [(Transaction, MergeStrategy)]?
    fileprivate var mergedToTransaction: Transaction?
    fileprivate var state: State = .waiting
    fileprivate var substate: Substate = .none

    public var hasOperations: Bool { return updateNode.childs.count > 0 || preconditions.count > 0 }
    public var isCompleted: Bool { return state == .completed }
    public var isReverted: Bool { return substate == .reverted }
    public var isFailed: Bool { return state == .failed }
    public var isPerforming: Bool { return state == .performing }
    public var isCancelled: Bool { return state == .cancelled }
    public var isMerged: Bool { return state == .merged }
    public var isInvalidated: Bool { return isCompleted || isFailed || isCancelled || isMerged || isReverted }

    public enum State {
        case waiting, performing, completed, cancelled, failed
        case merged
    }
    public enum Substate {
        case none
        case reverted
    }

    public init(database: RealtimeDatabase = RealtimeApp.app.database,
                storage: RealtimeStorage = RealtimeApp.app.storage) {
        self.database = database
        self.storage = storage
    }

    deinit {
        if !isInvalidated {
            fatalError("Transaction requires performing, reversion or merging")
        }
    }

    private func clear() {
        updateNode.childs.removeAll()
        cancelations.removeAll()
        completions.removeAll()
        preconditions.removeAll()
    }

    fileprivate func invalidate(_ success: Bool) {
        completions.forEach { $0(success) }
        clear()
    }
}
extension Transaction: CustomStringConvertible {
    public var description: String { return updateNode.description }
}

extension Transaction {
    public typealias CommitState = (state: State, substate: Substate)

    fileprivate func runPreconditions(_ completion: @escaping ([Error]) -> Void) {
        guard !preconditions.isEmpty else { completion([]); return }

        let currentPreconditions = self.preconditions
        self.preconditions.removeAll()

        let group = DispatchGroup()
        (0..<currentPreconditions.count).forEach { _ in group.enter() }

        let lock = NSRecursiveLock()
        var errors: [Error] = []
        let addError: (Error) -> Void = { err in
            lock.lock()
            errors.append(err)
            lock.unlock()
        }

        currentPreconditions.forEach { action in
            let failPromise = PromiseVoid()
            failPromise.resolve(addError).always(group.leave)
            action(failPromise)
        }

        group.notify(queue: .main) {
            self.runPreconditions({ (errs) in
                completion(errors + errs)
            })
        }
    }

    /// registers new single value for specified reference
    func _addValue(_ cacheValue: CacheNode) {
        debugFatalError(
            condition: database !== RealtimeApp.cache && cacheValue.location._hasMultiLevelNode,
            "Multi level node can use only for readonly operations."
        )
        updateNode._addValueAsInSingleTransaction(cacheValue)
    }

    func performUpdate(_ completion: @escaping (Error?) -> Void) {
        guard updateNode.childs.count > 0 else {
            fatalError("Try commit empty transaction")
        }
        database.commit(update: updateNode, completion: completion)
    }

    public enum FileCompletion {
        case meta(RealtimeMetadata)
        case error(Node, Error)
    }

    func performUpdateFiles(_ completion: @escaping ([FileCompletion]) -> Void) {
        storage.commit(transaction: self, completion: completion)
    }

    internal func _set<T: WritableRealtimeValue>(_ value: T, by node: Node) throws {
        guard node.isRooted else { fatalError("Node to set must be rooted") }

        try value.write(to: self, by: node)
    }

    /// adds operation of delete RealtimeValue
    internal func _delete<T: RealtimeValue & RealtimeValueEvents>(_ value: T) {
        guard let node = value.node, node.isRooted else { fatalError("Value must be rooted") }

        value.willRemove(in: self)
        removeValue(by: node)
    }

    internal func _update<T: ChangeableRealtimeValue & RealtimeValueEvents & Reverting>(_ value: T, by updatedNode: Node) throws {
        guard updatedNode.isRooted else { fatalError("Node to update must be rooted") }
        guard value.hasChanges else { return debugFatalError("Value has not changes") }

        value.willUpdate(through: updatedNode, in: self)
        try value.writeChanges(to: self, by: updatedNode)
        reverse(value)
    }
}
extension Transaction {
    func addLink<Value: RealtimeValue>(_ link: SourceLink, for value: Value) throws {
        addValue(try link.defaultRepresentation(), by: value.node!.linksItemsNode.child(with: link.id))
    }
}

// MARK: Public

extension Transaction: Reverting {
    /// reverts all changes for which cancellations have been added
    public func revert() {
        revertValues()
        revertFiles()
    }

    public func revertFiles() {
        guard state == .waiting || isFailed else { fatalError("Reversion cannot be made") }

        fileCancelations.forEach { $0.value() }
    }

    func revertFile(by node: Node) {
        guard state == .waiting || isFailed else { fatalError("Reversion cannot be made") }

        fileCancelations[node]?()
    }

    public func revertValues() {
        guard state == .waiting || isFailed else { fatalError("Reversion cannot be made") }

        cancelations.forEach { $0() }
        substate = .reverted
    }

    /// returns closure to revert last change
    public func currentReversion() -> () -> Void {
        guard !isInvalidated else { fatalError("Transaction is invalidated. Create new.") }

        let cancels = cancelations
        return { cancels.forEach { $0() } }
    }
}

public extension Transaction {
    /// Applies made changes in the database
    ///
    /// - Parameters:
    ///   - revertOnError: Indicates that all changes will be reverted on error
    ///   - completion: Completion closure with results
    func commit(
        revertOnError: Bool = true,
        with completion: ((CommitState, [Error]?) -> Void)?
    ) {
        commit(with: completion, filesCompletion: nil)
    }

    /// Applies made changes in the database
    ///
    /// - Parameters:
    ///   - revertOnError: Indicates that all changes will be reverted on error
    ///   - completion: Completion closure with results
    ///   - filesCompletion: Completion closure with results
    func commit(
        revertOnError: Bool = true,
        filesConcurrency concurrency: Bool = false,
        with completion: ((CommitState, [Error]?) -> Void)?,
        filesCompletion: (([FileCompletion]) -> Void)?
    ) {
        runPreconditions { (errors) in
            guard errors.isEmpty else {
                if revertOnError {
                    self.revert()
                }
                debugFatalError(errors.description)
                self.invalidate(false)
                completion?((self.state, self.substate), errors)
                return
            }
            do {
                try self.scheduledMerges?.forEach(self._merge)
                self.state = .performing

                guard self.updateNode.childs.count > 0 else {
                    fatalError("Try commit empty transaction")
                }

                var error: Error?
                let group = DispatchGroup()

                func runFiles() {
                    self.performUpdateFiles({ (res) in
                        if revertOnError {
                            res.forEach({ (result) in
                                switch result {
                                case .error(let n, let e):
                                    debugLog(e.localizedDescription)
                                    self.revertFile(by: n)
                                default: break
                                }
                            })
                        }
                        group.leave()
                        filesCompletion?(res)
                    })
                }

                group.enter(); group.enter()
                self.performUpdate({ (err) in
                    error = err
                    group.leave()
                    if (!concurrency) {
                        runFiles()
                    }
                })

                if (concurrency) {
                    runFiles()
                }

                // quick fix: .main not working on macos
                #if os(iOS)
                let queue = DispatchQueue.main
                #else
                let queue = DispatchQueue.global()
                #endif
                group.notify(queue: queue, execute: {
                    if let e = error {
                        self.state = .failed
                        debugFatalError(e.localizedDescription)
                        if revertOnError {
                            self.revertValues()
                        }
                    } else {
                        self.state = .completed
                    }
                    self.invalidate(self.state != .failed)
                    completion?((self.state, self.substate), error.map { [$0] })
                })
            } catch let e {
                completion?((self.state, self.substate), [e])
            }
        }
    }

    /// registers new cancelation of made changes
    func addReversion(_ reversion: @escaping () -> Void) {
        if let merged = mergedToTransaction {
            merged.addReversion(reversion)
        } else {
            guard !isInvalidated else { fatalError("Transaction is invalidated. Create new.") }

            cancelations.insert(reversion, at: 0)
        }
    }

    /// registers new cancelation of made changes
    func addFileReversion(_ node: Node, _ reversion: @escaping () -> Void) {
        if let merged = mergedToTransaction {
            merged.addFileReversion(node, reversion)
        } else {
            guard !isInvalidated else { fatalError("Transaction is invalidated. Create new.") }

            fileCancelations[node] = reversion
        }
    }

    /// registers new completion handler for transaction
    func addCompletion(_ completion: @escaping (Bool) -> Void) {
        if let merged = mergedToTransaction {
            merged.addCompletion(completion)
        } else {
            guard !isInvalidated else { fatalError("Transaction is invalidated. Create new.") }

            completions.append(completion)
        }
    }

    /// registers new precondition action
    func addPrecondition(_ precondition: @escaping (PromiseVoid) -> Void) {
        if let merged = mergedToTransaction {
            merged.addPrecondition(precondition)
        } else {
            guard !isInvalidated else { fatalError("Transaction is invalidated. Create new.") }

            preconditions.append(precondition)
        }
    }

    /// Adds `Data` value as file
    ///
    /// - Parameters:
    ///   - value: `Data` type value
    ///   - node: Target node
    func addFile(_ value: Data, metadata: RealtimeMetadata = [:], by node: Node) {
        if let merged = mergedToTransaction {
            merged.addFile(value, by: node)
        } else {
            guard node.isRooted else { fatalError("Node should be rooted") }

            let file = FileNode(node: node, value: RealtimeDatabaseValue(value))
            file.metadata = metadata
            _addValue(.file(file))
        }
    }

    func addFile<T>(_ file: File<T>, by node: Node? = nil) throws {
        if let merged = mergedToTransaction {
            try merged.addFile(file, by: node)
        } else {
            guard let node = node ?? file.node else { fatalError("Node should be rooted") }

            try file._write(to: self, by: node)
        }
    }

    /// Removes file by specified node
    ///
    /// - Parameters:
    ///   - node: Target node
    func removeFile(by node: Node) {
        if let merged = mergedToTransaction {
            merged.removeFile(by: node)
        } else {
            guard node.isRooted else { fatalError("Node should be rooted") }

            _addValue(.file(FileNode(node: node, value: nil)))
        }
    }

    /// Adds Realtime database value
    ///
    /// - Parameters:
    ///   - value: Type erased value
    ///   - node: Target node
    func addValue(_ value: RealtimeDatabaseValue?, by node: Node) {
        if let merged = mergedToTransaction {
            merged.addValue(value, by: node)
        } else {
            guard node.isRooted else { fatalError("Node should be rooted") }

            _addValue(.value(ValueNode(node: node, value: value)))
        }
    }
    func addValue<T: ExpressibleByRealtimeDatabaseValue>(_ value: T, by node: Node) {
        addValue(RealtimeDatabaseValue(value), by: node)
    }

    /// Removes Realtime data by specified node
    ///
    /// - Parameters:
    ///   - node: Target node
    func removeValue(by node: Node) {
        if let merged = mergedToTransaction {
            merged.removeValue(by: node)
        } else {
            guard node.isRooted else { fatalError("Node should be rooted") }

            _addValue(.value(ValueNode(node: node, value: nil)))
        }
    }

    /// adds operation of save RealtimeValue as single value
    func set<T: WritableRealtimeValue & RealtimeValueEvents>(_ value: T, by node: Node) throws {
        if let merged = mergedToTransaction {
            try merged.set(value, by: node)
        } else {
            let database = self.database
            try _set(value, by: node)
            addCompletion { (result) in
                if result {
                    value.didSave(in: database, in: node.parent ?? .root, by: node.key)
                }
            }
        }
    }

    /// adds operation of delete RealtimeValue
    func delete<T: RealtimeValue & RealtimeValueEvents>(_ value: T) {
        if let merged = mergedToTransaction {
            merged.delete(value)
        } else {
            _delete(value)
            addCompletion { (result) in
                if result {
                    value.didRemove()
                }
            }
        }
    }

    /// adds operation of update RealtimeValue
    func update<T: ChangeableRealtimeValue & RealtimeValueEvents & Reverting>(_ value: T) throws {
        if let merged = mergedToTransaction {
            try merged.update(value)
        } else {
            guard let updatedNode = value.node else { fatalError("Value must be rooted") }

            try _update(value, by: updatedNode)
            addCompletion { (result) in
                if result {
                    value.didUpdate(through: updatedNode)
                }
            }
        }
    }

    /// adds current revertion action for reverting entity
    func reverse<T: Reverting>(_ cancelable: T) {
        addReversion(cancelable.currentReversion())
    }

    enum MergeStrategy {
        case old
        case new
    }

    /// method to merge actions of other transaction
    func merge(_ other: Transaction, strategy: MergeStrategy = .new) throws {
        guard other.mergedToTransaction == nil else { fatalError("Transaction already merged to other transaction") }
        try _merge(other, strategy: strategy)
    }

    internal func _merge(_ other: Transaction, strategy: MergeStrategy = .new) throws {
        guard other !== self else { fatalError("Attemption merge the same transaction") }
        guard other.preconditions.isEmpty else {
            other.preconditions.forEach(addPrecondition)
            other.preconditions.removeAll()
            other.mergedToTransaction = self
            scheduledMerges = scheduledMerges.map { $0 + [(other, strategy)] } ?? [(other, strategy)]
            return
        }
        try updateNode._mergeWithObject(
            theSameReference: other.updateNode,
            conflictResolver: { old, new in
                switch strategy {
                case .new: return new
                case .old: return old
                }
            },
            didAppend: nil
        )
        other.completions.forEach(addCompletion)
        addReversion(other.currentReversion())
        other.state = .merged
        other.mergedToTransaction = nil
    }

    /// cancels transaction without revertion
    func cancel() {
        guard mergedToTransaction == nil else { fatalError("Transaction already merged to other transaction") }
        state = .cancelled
        invalidate(false)
    }
}


public extension Transaction {
    func encode<T: Encodable>(_ value: T, by node: Node) throws {
        try value.encode(to: TransactionEncoder(node: node, transaction: self))
    }
}
