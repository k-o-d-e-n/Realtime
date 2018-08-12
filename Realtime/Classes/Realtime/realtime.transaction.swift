//
//  RealtimeTransaction.swift
//  Realtime
//
//  Created by Denis Koryttsev on 16/03/2018.
//

import Foundation
import FirebaseDatabase
import FirebaseStorage

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
public class RealtimeTransaction {
    let database: RealtimeDatabase
    let storage: Storage
    internal var updateNode: ObjectNode = ObjectNode(node: .root)
    fileprivate var preconditions: [(ResultPromise<Error?>) -> Void] = []
    fileprivate var completions: [(Bool) -> Void] = []
    fileprivate var cancelations: [() -> Void] = []
    fileprivate var scheduledMerges: [RealtimeTransaction]?
    fileprivate var state: State = .waiting
    fileprivate var substate: Substate = .none

    public var isCompleted: Bool { return state == .completed }
    public var isReverted: Bool { return substate == .reverted }
    public var isFailed: Bool { return state == .failed }
    public var isPerforming: Bool { return state == .performing }
    public var isMerged: Bool { return state == .merged }
    public var isInvalidated: Bool { return isCompleted || isFailed || isMerged || isReverted }

    public enum State {
        case waiting, performing, completed, failed
        case merged
    }
    public enum Substate {
        case none
        case reverted
    }

    public init(database: RealtimeDatabase = RealtimeApp.app.database,
                storage: Storage = Storage.storage()) {
        self.database = database
        self.storage = storage
    }

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

        let failPromise = ResultPromise<Error?> { err in
            if let e = err {
                addError(e)
            }
            group.leave()
        }
        currentPreconditions.forEach { $0(failPromise) }

        group.notify(queue: .main) {
            self.runPreconditions({ (errs) in
                completion(errors + errs)
            })
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
        state = success ? .completed : .failed
        clear()
    }

    deinit {
        if !isInvalidated {
            fatalError("RealtimeTransaction requires performing, reversion or merging")
        }
    }
}

extension RealtimeTransaction {
    public typealias CommitState = (state: State, substate: Substate)
    // TODO: Add configuration commit as single value or update value
    public func commit(revertOnError: Bool = true,
                       with completion: ((CommitState, [Error]?) -> Void)?,
                       filesCompletion: (([(StorageMetadata?, Error?)]) -> Void)? = nil) {
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
                try self.scheduledMerges?.forEach { try self.merge($0) }
                self.state = .performing

                self.performUpdate({ (err, _) in
                    let result = err == nil
                    if !result {
                        self.state = .failed
                        debugFatalError(String(describing: err))
                        if revertOnError {
                            self.revert()
                        }
                    }
                    self.invalidate(result)
                    completion?((self.state, self.substate), err.map { [$0] })
                })

                self.updateFiles({ (res) in
                    filesCompletion?(res)
                })
            } catch let e {
                completion?((self.state, self.substate), [e])
            }
        }
    }

    public func addFile(_ value: Any, by node: Realtime.Node) {
        _addValue(FileNode.self, value, by: node)
    }

    public func removeFile(by node: Realtime.Node) {
        _addValue(FileNode.self, nil, by: node)
    }

    public func addValue(_ value: Any, by node: Realtime.Node) {
        _addValue(ValueNode.self, value, by: node)
    }

    public func removeValue(by node: Realtime.Node) {
        _addValue(ValueNode.self, nil, by: node)
    }

    /// registers new single value for specified reference
    func _addValue(_ valueType: ValueNode.Type = ValueNode.self, _ value: Any?/*FireDataValue?*/, by node: Realtime.Node) { // TODO: Write different methods only for available values
        let nodes = node.reversed().dropFirst()
        var current = updateNode
        var iterator = nodes.makeIterator()
        while let n = iterator.next() {
            if let update = current.childs.first(where: { $0.node == n }) {
                if case let u as ObjectNode = update {
                    if n === node {
                        fatalError("Tries insert value higher than earlier writed values")
                    } else {
                        current = u
                    }
                } else if case let u as FileNode = update, n === node {
                    u.value = value
                    debugLog("Replaced file by node: \(node) with value: \(value as Any) in transaction: \(self)")
                } else if case let u as ValueNode = update, n === node {
                    if ValueNode.self == valueType {
                        debugLog("Replaced value by node: \(node) with value: \(value as Any) in transaction: \(self)")
                        u.value = value
                    } else {
                        fatalError("Tries to insert database value to storage node")
                    }
                } else {
                    fatalError("Tries insert value lower than earlier writed single value")
                }
            } else {
                if node === n {
                    current.childs.append(valueType.init(node: node, value: value))
                } else {
                    let child = ObjectNode(node: n)
                    current.childs.append(child)
                    current = child
                }
            }
        }
    }

    func performUpdate(_ completion: @escaping (Error?, DatabaseNode) -> Void) {
        guard updateNode.childs.count > 0 else {
            fatalError("Try commit empty transaction")
        }

        database.commit(transaction: self, completion: completion)
    }

    func updateFiles(_ completion: @escaping ([(StorageMetadata?, Error?)]) -> Void) {
//        guard updateNode.childs.count > 0 else {
//            fatalError("Try commit empty transaction")
//        }

        var nearest = updateNode
        while nearest.childs.count == 1, let next = nearest.childs.first as? ObjectNode {
            nearest = next
        }
        let files = nearest.files
        guard !files.isEmpty else { return completion([]) }

        let group = DispatchGroup()
        let lock = NSRecursiveLock()
        var completions: [(StorageMetadata?, Error?)] = []
        let addCompletion: (StorageMetadata?, Error?) -> Void = { md, err in
            lock.lock()
            completions.append((md, err))
            lock.unlock()
            group.leave()
        }
        files.indices.forEach { _ in group.enter() }
        files.forEach { (file) in
            guard case let data as Data = file.value else { fatalError("Unexpected type of value \(file.value as Any) for file by node: \(file.node)") }
            file.node.file(for: storage).putData(data, metadata: nil, completion: addCompletion)
        }
        group.notify(queue: .main) {
            completion(completions)
        }
    }

    /// registers new cancelation of made changes
    public func addReversion(_ reversion: @escaping () -> Void) {
        guard !isInvalidated else { fatalError("RealtimeTransaction is invalidated. Create new.") }

        cancelations.insert(reversion, at: 0)
    }

    /// registers new completion handler for transaction
    public func addCompletion(_ completion: @escaping (Bool) -> Void) {
        guard !isInvalidated else { fatalError("RealtimeTransaction is invalidated. Create new.") }

        completions.append(completion)
    }

    /// registers new precondition action
    public func addPrecondition(_ precondition: @escaping (ResultPromise<Error?>) -> Void) {
        guard !isInvalidated else { fatalError("RealtimeTransaction is invalidated. Create new.") }

        preconditions.append(precondition)
    }
}

extension RealtimeTransaction: Reverting {
    /// reverts all changes for which cancellations have been added
    public func revert() {
        guard state == .waiting || isFailed else { fatalError("Reversion cannot be made") }

        cancelations.forEach { $0() }
        substate = .reverted
    }

    /// returns closure to revert last change
    public func currentReversion() -> () -> Void {
        guard !isInvalidated else { fatalError("RealtimeTransaction is invalidated. Create new.") }

        let cancels = cancelations
        return { cancels.forEach { $0() } }
    }
}
extension RealtimeTransaction: CustomStringConvertible {
    public var description: String { return updateNode.description }
}
public extension RealtimeTransaction {
    /// adds operation of save RealtimeValue as single value
    func set<T: WritableRealtimeValue & RealtimeValueEvents>(_ value: T, by node: Realtime.Node) throws {
        try _set(value, by: node)
        addCompletion { (result) in
            if result {
                value.didSave(in: node.parent!, by: node.key)
            }
        }
    }

    /// adds operation of delete RealtimeValue
    func delete<T: RealtimeValue & RealtimeValueEvents>(_ value: T) throws {
        try _delete(value)
        addCompletion { (result) in
            if result {
                value.didRemove()
            }
        }
    }

    /// adds operation of update RealtimeValue
    func update<T: ChangeableRealtimeValue & RealtimeValueEvents & Reverting>(_ value: T) throws {
        guard let updatedNode = value.node else { fatalError("Value must be rooted") }

        try _update(value, by: updatedNode)
        addCompletion { (result) in
            if result {
                value.didSave(in: updatedNode.parent ?? .root, by: updatedNode.key)
            }
        }
    }

    internal func _set<T: WritableRealtimeValue>(_ value: T, by node: Realtime.Node) throws {
        guard node.isRooted else { fatalError("Node to set must be rooted") }

        try value.write(to: self, by: node)
    }

    /// adds operation of delete RealtimeValue
    internal func _delete<T: RealtimeValue & RealtimeValueEvents>(_ value: T) throws {
        guard let node = value.node, node.isRooted else { fatalError("Value must be rooted") }

        value.willRemove(in: self)
        removeValue(by: node)
    }

    internal func _update<T: ChangeableRealtimeValue & RealtimeValueEvents & Reverting>(_ value: T, by updatedNode: Realtime.Node) throws {
        guard updatedNode.isRooted else { fatalError("Node to update must be rooted") }
        guard value.hasChanges else { return debugFatalError("Value has not changes") }

        try value.writeChanges(to: self, by: updatedNode)
        revertion(for: value)
    }

    /// adds current revertion action for reverting entity
    public func revertion<T: Reverting>(for cancelable: T) {
        addReversion(cancelable.currentReversion())
    }

    /// method to merge actions of other transaction
    public func merge(_ other: RealtimeTransaction, conflictResolver: (UpdateNode, UpdateNode) -> Any? = { f, s in f.value }) throws {
        guard other !== self else { fatalError("Attemption merge the same transaction") }
        guard other.preconditions.isEmpty else {
            other.preconditions.forEach(addPrecondition)
            other.preconditions.removeAll()
            scheduledMerges = scheduledMerges.map { $0 + [other] } ?? [other]
            return
        }
        try updateNode.merge(with: other.updateNode, conflictResolver: conflictResolver)
        other.completions.forEach(addCompletion)
        addReversion(other.currentReversion())
        other.state = .merged
    }
}

extension RealtimeTransaction {
    func addLink<Value: RealtimeValue>(_ link: SourceLink, for value: Value) {
        addValue(link.fireValue, by: value.node!.linksNode.child(with: link.id))
    }
}
