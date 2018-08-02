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

public protocol UpdateNode: FireDataProtocol {
    var node: Node { get }
    var value: Any? { get }
    func fill(from ancestor: Node, into container: inout [String: Any])
}

class ValueNode: UpdateNode {
    let node: Node
    var value: Any?

    func fill(from ancestor: Node, into container: inout [String: Any]) {
        container[node.path(from: ancestor)] = value as Any
    }

    required init(node: Node, value: Any?) {
        self.node = node
        self.value = value
    }
}

class FileNode: ValueNode {
    override func fill(from ancestor: Node, into container: inout [String: Any]) {}
}

class ObjectNode: UpdateNode, CustomStringConvertible {
    let node: Node
    var childs: [UpdateNode] = []
    var isCompound: Bool { return true }
    var value: Any? {
        return updateValue
    }
    var updateValue: [String: Any] {
        var val: [String: Any] = [:]
        fill(from: node, into: &val)
        return val
    }
    var files: [FileNode] {
        return childs.reduce(into: [], { (res, node) in
            if case let objNode as ObjectNode = node {
                res.append(contentsOf: objNode.files)
            } else if case let fileNode as FileNode = node {
                res.append(fileNode)
            }
        })
    }

    func fill(from ancestor: Node, into container: inout [String: Any]) {
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
    func child(by path: [String]) -> UpdateNode? {
        guard !path.isEmpty else { return self }

        var path = path
        let first = path.remove(at: 0)
        guard let f = childs.first(where: { $0.node.key == first }) else {
            return nil
        }

        if case let o as ObjectNode = f {
            return o.child(by: path)
        } else {
            return path.isEmpty ? f : nil
        }
    }
    func merge(with other: ObjectNode, conflictResolver: (UpdateNode, UpdateNode) -> Any?) {
        other.childs.forEach { (child) in
            if let currentChild = childs.first(where: { $0.node == child.node }) {
                if let objectChild = currentChild as? ObjectNode {
                    objectChild.merge(with: child as! ObjectNode, conflictResolver: conflictResolver)
                } else if case let c as ValueNode = currentChild {
                    if type(of: c) == type(of: child) {
                        c.value = conflictResolver(currentChild, child)
                    } else {
                        fatalError("Database value and storage value located in the same node.")
                    }
                } else {
                    fatalError("Undefined node")
                }
            } else {
                childs.append(child)
            }
        }
    }
}

extension UpdateNode where Self: FireDataProtocol {
    public var dataRef: DatabaseReference? { return node.reference() }
    public var dataKey: String? { return node.key }
    public var priority: Any? { return nil }
}

extension ValueNode: FireDataProtocol, Sequence {
    var priority: Any? { return nil }
    var childrenCount: UInt { return 0 }
    func makeIterator() -> AnyIterator<FireDataProtocol> { return AnyIterator(EmptyIterator()) }
    func exists() -> Bool { return value != nil }
    func hasChildren() -> Bool { return false }
    func hasChild(_ childPathString: String) -> Bool { return false }
    func child(forPath path: String) -> FireDataProtocol { return ValueNode(node: Node(key: path, parent: node), value: nil) }
    func compactMap<ElementOfResult>(_ transform: (FireDataProtocol) throws -> ElementOfResult?) rethrows -> [ElementOfResult] {
        return []
    }
    func forEach(_ body: (FireDataProtocol) throws -> Void) rethrows {}
    func map<T>(_ transform: (FireDataProtocol) throws -> T) rethrows -> [T] { return [] }
    var debugDescription: String { return "\(node.rootPath): \(value as Any)" }
    var description: String { return debugDescription }
}

/// Cache in future
extension ObjectNode: FireDataProtocol, Sequence {
    public var childrenCount: UInt {
        return UInt(childs.count)
    }

    public func makeIterator() -> AnyIterator<FireDataProtocol> {
        return AnyIterator(childs.lazy.map { $0 as FireDataProtocol }.makeIterator())
    }

    public func exists() -> Bool {
        return true
    }

    public func hasChildren() -> Bool {
        return childs.count > 0
    }

    public func hasChild(_ childPathString: String) -> Bool {
        return child(by: childPathString.split(separator: "/").lazy.map(String.init)) != nil
    }

    public func child(forPath path: String) -> FireDataProtocol {
        return child(by: path.split(separator: "/").lazy.map(String.init)) ?? ValueNode(node: Node(key: path, parent: node), value: nil)
    }

    public func map<T>(_ transform: (FireDataProtocol) throws -> T) rethrows -> [T] {
        return try childs.map(transform)
    }

    public func compactMap<ElementOfResult>(_ transform: (FireDataProtocol) throws -> ElementOfResult?) rethrows -> [ElementOfResult] {
        return try childs.compactMap(transform)
    }

    public func forEach(_ body: (FireDataProtocol) throws -> Void) rethrows {
        return try childs.forEach(body)
    }

    public var debugDescription: String { return description }
}

/// Helps to make complex write transactions.
/// Provides addition of operations with completion handler, cancelation, and async preconditions.
public class RealtimeTransaction {
    let database: Database
    let storage: Storage
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
    public var isInvalidated: Bool { return isCompleted || isFailed || isMerged || isReverted }

    public enum State {
        case waiting, performing, completed, failed
        case merged
    }
    public enum Substate {
        case none
        case reverted
    }

    public init(database: Database = Database.database(), storage: Storage = Storage.storage()) {
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

            self.updateFiles({ (res) in
                filesCompletion?(res)
            })
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

    func performUpdate(_ completion: @escaping (Error?, DatabaseReference) -> Void) {
        guard updateNode.childs.count > 0 else {
            fatalError("Try commit empty transaction")
        }

        var nearest = updateNode
        while nearest.childs.count == 1, let next = nearest.childs.first as? ObjectNode {
            nearest = next
        }
        let updateValue = nearest.updateValue
        if updateValue.count > 0 {
            nearest.node.reference(for: database).update(use: nearest.updateValue, completion: completion)
        }
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
                value.didSave(in: updatedNode.parent!, by: updatedNode.key)
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
    public func merge(_ other: RealtimeTransaction, conflictResolver: (UpdateNode, UpdateNode) -> Any? = { f, s in f.value }) {
        guard other !== self else { return debugFatalError("Attemption merge the same transaction") }
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

extension RealtimeTransaction {
    func addLink<Value: RealtimeValue>(_ link: SourceLink, for value: Value) {
        addValue(link.fireValue, by: value.node!.linksNode.child(with: link.id))
    }
}
