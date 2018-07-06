//
//  RealtimeTransaction.swift
//  Realtime
//
//  Created by Denis Koryttsev on 16/03/2018.
//

import Foundation

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

public protocol UpdateNode {
    var node: Node { get }
    var value: Any? { get }
    func fill(from ancestor: Node, into container: inout [String: Any?])
}

class ValueNode: UpdateNode {
    let node: Node
    var value: Any?

    func fill(from ancestor: Node, into container: inout [String: Any?]) {
        container[node.path(from: ancestor)] = value
    }

    init(node: Node, value: Any?) {
        self.node = node
        self.value = value
    }
}

class ObjectNode: UpdateNode, CustomStringConvertible {
    let node: Node
    var childs: [UpdateNode] = []
    var isCompound: Bool { return true }
    var value: Any? {
        return updateValue
    }
    var updateValue: [String: Any?] {
        var val: [String: Any?] = [:]
        fill(from: node, into: &val)
        return val
    }

    func fill(from ancestor: Node, into container: inout [String: Any?]) {
        childs.forEach { $0.fill(from: ancestor, into: &container) }
    }

    var description: String { return String(describing: updateValue) }

    init(node: Node) {
        self.node = node
    }

    static func root() -> ObjectNode {
        return ObjectNode(node: .root)
    }
}

extension ObjectNode {
    func merge(with other: ObjectNode, conflictResolver: (UpdateNode, UpdateNode) -> Any?) {
        other.childs.forEach { (child) in
            if let currentChild = childs.first(where: { $0.node == child.node }) {
                if let objectChild = currentChild as? ObjectNode {
                    objectChild.merge(with: child as! ObjectNode, conflictResolver: conflictResolver)
                } else if let c = currentChild as? ValueNode {
                    c.value = conflictResolver(currentChild, child)
                } else {
                    fatalError()
                }
            } else {
                childs.append(child)
            }
        }
    }
}

/// Helps to make complex write transactions.
/// Provides addition of operations with completion handler, cancelation, and async preconditions.
public class RealtimeTransaction {
    internal var updateNode: ObjectNode = .root()
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
    public var isInvalidated: Bool { return isCompleted || isFailed || isMerged }

    public enum State {
        case waiting, performing, completed, failed
        case merged
    }
    public enum Substate {
        case none
        case reverted
    }

    public init() {}

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
                       with completion: ((CommitState, [Error]?) -> Void)? = nil) {
        runPreconditions { (errors) in
            guard errors.isEmpty else {
                if revertOnError {
                    self.revert()
                }
                debugFatalError(errors.description);
                self.invalidate(false)
                completion?((self.state, self.substate), errors);
                return
            }
            self.scheduledMerges?.forEach { self.merge($0) }
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
                completion?((self.state, self.substate), err.map { errors + [$0] })
            })
        }
    }

    /// registers new single value for specified reference
    public func addValue(_ value: Any?, by node: Realtime.Node) {
        var nodes = node.reversed().dropFirst().makeIterator()
        var current = updateNode
        while let n = nodes.next() {
            if let update = current.childs.first(where: { $0.node == n }) {
                if let u = update as? ObjectNode {
                    current = u
                } else if let u = update as? ValueNode, u.node == node {
                    u.value = value
                } else {
                    fatalError("Error in internal implementation")
                }
            } else {
                if node == n {
                    current.childs.append(ValueNode(node: node, value: value))
                } else {
                    let child = ObjectNode(node: n)
                    current.childs.append(child)
                    current = child
                }
            }
        }
    }

    // TODO: nearest search uses to resolve permission error
    func performUpdate(_ completion: @escaping (Error?, DatabaseReference) -> Void) {
        var nearest = updateNode
        while nearest.childs.count == 1, let next = nearest.childs.first as? ObjectNode {
            nearest = next
        }
        nearest.node.reference.update(use: nearest.updateValue, completion: completion)
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
    func set<T: RealtimeValue & RealtimeValueEvents>(_ value: T, by node: Realtime.Node? = nil) {
        guard let savedNode = node ?? value.node, savedNode.isRooted else { fatalError() }

        _set(value, by: savedNode)
        addCompletion { (result) in
            if result {
                value.didSave(in: savedNode.parent!, by: savedNode.key)
            }
        }
    }

    /// adds operation of delete RealtimeValue
    func delete<T: RealtimeValue & RealtimeValueEvents>(_ value: T) {
        _delete(value)
        addCompletion { (result) in
            if result {
                value.didRemove()
            }
        }
    }

    /// adds operation of update RealtimeValue
    func update<T: ChangeableRealtimeValue & RealtimeValueEvents & Reverting>(_ value: T) {
        guard let updatedNode = value.node else { fatalError() }

        _update(value, by: updatedNode)
        addCompletion { (result) in
            if result {
                value.didSave(in: updatedNode.parent!, by: updatedNode.key)
            }
        }
    }

    internal func _set<T: RealtimeValue & RealtimeValueEvents>(_ value: T, by node: Realtime.Node) {
        guard node.isRooted else { fatalError() }

        addValue(value.localValue, by: node)
    }

    /// adds operation of delete RealtimeValue
    internal func _delete<T: RealtimeValue & RealtimeValueEvents>(_ value: T) {
        guard value.isRooted else { fatalError() }

        value.willRemove(in: self)
        addValue(nil, by: value.node!)
    }

    internal func _update<T: ChangeableRealtimeValue & RealtimeValueEvents & Reverting>(_ value: T, by updatedNode: Realtime.Node) {
        guard value.hasChanges else { debugFatalError("Value has not changes"); return }
        guard updatedNode.isRooted else { fatalError("Node to update must be rooted") }

        value.insertChanges(to: self, by: updatedNode)
        revertion(for: value)
    }

    /// adds current revertion action for reverting entity
    public func revertion<T: Reverting>(for cancelable: T) {
        addReversion(cancelable.currentReversion())
    }

    /// method to merge actions of other transaction
    func merge(_ other: RealtimeTransaction, conflictResolver: (UpdateNode, UpdateNode) -> Any? = { f, s in f.value }) {
        guard other !== self else { debugFatalError("Attemption merge the same transaction"); return }
        guard other.preconditions.isEmpty else {
            other.preconditions.forEach(addPrecondition)
            other.preconditions.removeAll()
            scheduledMerges = scheduledMerges.map { $0 + [other] } ?? [other]
            return
        }
        updateNode.merge(with: other.updateNode, conflictResolver: conflictResolver)
        other.completions.forEach(addCompletion)
        addReversion(other.currentReversion())
        other.state = .merged
    }
}

public extension RealtimeTransaction {
    func addValue<Value: RealtimeValue>(_ value: Value) {
        guard value.isRooted else { fatalError() }
        addValue(value.localValue, by: value.node!)
    }
}
