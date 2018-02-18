//
//  RealtimeNode.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 15/03/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation
import FirebaseDatabase

/// Describes node of database
public protocol RTNode: RawRepresentable, Equatable {
    associatedtype RawValue: Equatable = String
}

/// Typed node of database
public protocol AssociatedRTNode: RTNode {
    associatedtype ConcreteType: RealtimeValue
}
public extension RTNode where Self.RawValue == String {
    /// checks availability child in snapshot with node name   
    func has(in snapshot: DataSnapshot) -> Bool {
        return snapshot.hasChild(rawValue)
    }

    /// gets child snapshot by node name
    func snapshot(from parent: DataSnapshot) -> DataSnapshot {
        return parent.childSnapshot(forPath: rawValue)
    }

    func map<Returned>(from parent: DataSnapshot) -> Returned? {
        return parent.map(child: rawValue) { $0.value as? Returned }
    }

    func take(from parent: DataSnapshot, exactly: Bool, map: (DataSnapshot) -> Void) {
        parent.mapExactly(if: exactly, child: rawValue, map: map)
    }

    func path(from superpath: String, to subpath: String? = nil) -> String {
        return superpath + "/" + rawValue + (subpath.map { "/" + $0 } ?? "")
    }

    func subpath(with node: RealtimeNode) -> String {
        return subpath(with: node.rawValue)
    }
    func subpath(with path: String) -> String {
        return rawValue + "/" + path
    }

    func reference() -> DatabaseReference {
        return .fromRoot(rawValue)
    }

    func reference(from ref: DatabaseReference) -> DatabaseReference {
        return ref.child(rawValue)
    }

    func reference(from entity: RealtimeValue) -> DatabaseReference {
        return entity.dbRef.child(rawValue)
    }
}
public extension AssociatedRTNode where Self.RawValue == String {
    /// returns object referenced by node name in specific reference.
    func entity(in parent: DatabaseReference) -> ConcreteType {
        return ConcreteType(dbRef: reference(from: parent))
    }
}
extension AssociatedRTNode {
    private var type: ConcreteType.Type { return ConcreteType.self }
    public static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.rawValue == rhs.rawValue && lhs.type == rhs.type
    }
}

public extension RTNode where Self.RawValue == String, Self: ExpressibleByStringLiteral {
    typealias UnicodeScalarLiteralType = String
    typealias ExtendedGraphemeClusterLiteralType = String
    typealias StringLiteralType = String

    public init(stringLiteral value: String) {
        self.init(rawValue: value)!
    }

    public init(unicodeScalarLiteral value: String) {
        self.init(rawValue: value)!
    }

    public init(extendedGraphemeClusterLiteral value: String) {
        self.init(rawValue: value)!
    }
}
extension RTNode where Self.RawValue == String, Self: CustomStringConvertible {
    public var description: String { return rawValue }
}

// TODO: Use in structs (such as HumanName) as property
public struct RealtimeNode: RTNode, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}
extension RTNode {
    public static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }
    public static func ==<Other: RTNode>(lhs: Self, rhs: Other) -> Bool where Other.RawValue == RawValue {
        return lhs.rawValue == rhs.rawValue
    }
}
extension RealtimeNode {
    func associated<T: RealtimeValue>() -> AssociatedRealtimeNode<T> {
        return AssociatedRealtimeNode(rawValue: rawValue)
    }
}
extension String: RTNode {
    public var rawValue: String { return self }
    public init(rawValue: String) {
        self = rawValue
    }
}
extension String {
    var realtimeNode: RealtimeNode { return .init(rawValue: self) }
}

public struct AssociatedRealtimeNode<Concrete: RealtimeValue>: AssociatedRTNode, ExpressibleByStringLiteral, CustomStringConvertible {
    public typealias ConcreteType = Concrete
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}
extension AssociatedRealtimeNode {
    public static func ==(lhs: AssociatedRealtimeNode, rhs: RealtimeNode) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }
}

// TODO: Add possible to save relative link by parent level or root level

/// Link value describing reference to some location of database.
public struct RealtimeLink: DataSnapshotRepresented {
    typealias OptionalSourceProperty = RealtimeProperty<RealtimeLink?, RealtimeLinkSourceSerializer>
    typealias OptionalProperty = RealtimeProperty<RealtimeLink?, RealtimeLinkSerializer>
    enum Nodes {
        static let path = RealtimeNode(rawValue: "pth")
    }

    let id: String
    let paths: [String]

    var dbValue: [String: Any] { return [Nodes.path.rawValue: paths] }

    init(id: String, paths: [String]) {
        precondition(paths.count > 0, "RealtimeLink path must be not empty")
        self.id = id
        self.paths = paths
    }
    init(id: String, path: String) {
        precondition(path.count > 0, "RealtimeLink path must be not empty")
        self.id = id
        self.paths = [path]
    }

    public init?(snapshot: DataSnapshot) {
        if let pths: [String] = Nodes.path.map(from: snapshot) {
            self.init(id: snapshot.key, paths: pths)
        } else {
            if let pth: String = Nodes.path.map(from: snapshot) {
                self.init(id: snapshot.key, path: pth)
            } else {
                return nil
            }
        }
    }
    
    public func apply(snapshot: DataSnapshot, strongly: Bool) {
        fatalError("RealtimeLink is not mutated") // TODO: ?
    }
}

extension RealtimeLink {
    var dbRefs: [DatabaseReference] { return paths.map { .fromRoot($0) } }

    func entity<Entity: RealtimeValue>(_: Entity.Type) -> Entity { return Entity(dbRef: dbRefs.first!) }
}

extension RealtimeLink: Equatable {
    public static func ==(lhs: RealtimeLink, rhs: RealtimeLink) -> Bool {
        return lhs.id == rhs.id
    }
}

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
    fileprivate var update: Node!
    fileprivate var preconditions: [(ResultPromise<Error?>) -> Void] = []
    fileprivate var completions: [(Bool) -> Void] = []
    fileprivate var cancelations: [() -> Void] = []
    fileprivate var scheduledMerges: [RealtimeTransaction]?
    fileprivate var state: State = .waiting
    
    public var isCompleted: Bool { return state == .completed }
    public var isReverted: Bool { return state == .reverted }
    public var isFailed: Bool { return state == .failed }
    public var isPerforming: Bool { return state == .performing }
    public var isMerged: Bool { return state == .merged }
    public var isInvalidated: Bool { return isCompleted || isMerged || isFailed || isReverted }

    enum State {
        case waiting, performing
        case completed, failed, reverted, merged
    }

    public init() {}

    fileprivate func runPreconditions(_ completion: @escaping ([Error]) -> Void) {
        guard !preconditions.isEmpty else { completion([]); return }

        let group = DispatchGroup()
        (0..<preconditions.count).forEach { _ in group.enter() }

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
        while let precondition = preconditions.popLast() {
            precondition(failPromise)
        }

        group.notify(queue: .main) {
            self.runPreconditions(completion)
        }
    }

    private func clear() {
        update = nil
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
        if !isReverted && !isCompleted && !isMerged { fatalError("RealtimeTransaction requires performing, reversion or merging") }
    }
}

extension RealtimeTransaction {
    // TODO: Add configuration commit as single value or update value
    public func commit(revertOnError: Bool = true, with completion: (([Error]?) -> Void)? = nil) {
        runPreconditions { (errors) in
            guard errors.isEmpty else {
                if revertOnError {
                    self.revert()
                }
                debugFatalError(errors.description);
                self.invalidate(false)
                completion?(errors);
                return
            }
            self.scheduledMerges?.forEach(self.merge)
            self.state = .performing

            self.update.commit({ (err, _) in
                let result = err == nil
                if !result {
                    debugFatalError(String(describing: err))
                    if revertOnError {
                        self.revert()
                    }
                }
                self.invalidate(result)
                completion?(err.map { errors + [$0] })
            })
        }
    }

    /// registers new single value for specified reference
    public func addNode(ref: DatabaseReference, value: Any?) {
        addNode(item: (ref, .value(value)))
    }
    
    // TODO: Improve performance and interface
    /// registers new update value for specified reference 
    public func addNode(item updateItem: (ref: DatabaseReference, value: Node.Value)) {
        guard !isInvalidated else { fatalError("RealtimeTransaction is invalidated. Create new.") }

        guard update != nil else {
            update = updateItem.ref.parent.map {
                Node(ref: $0, value: .nodes([Node(updateItem)]))
            } ?? Node(ref: updateItem.ref, value: updateItem.value)
            return
        }

        if update.ref.isEqual(for: updateItem.ref) {
            update.merge(updateItem.value)
        } else if update.ref.isChild(for: updateItem.ref) {
            while let parent = update.parent() {
                update = parent
                if parent.ref.isEqual(for: updateItem.ref) {
                    update.merge(updateItem.value)
                    break
                }
            }
        } else if updateItem.ref.isChild(for: update.ref) {
            if let node = update.search(updateItem.ref) {
                node.merge(updateItem.value)
            } else {
                var updateNode: Node = Node(updateItem)
                while let parentRef = updateNode.ref.parent {
                    if let parent = update.search(parentRef) {
                        parent.merge(.nodes([updateNode]))
                        break
                    } else {
                        updateNode = updateNode.parent()!
                    }
                }
            }
        } else {
            while let parent = update.parent() {
                update = parent
                if updateItem.ref.isChild(for: parent.ref) {
                    break
                }
            }
            var updateNode = Node(updateItem)
            while let parentUpdate = updateNode.parent() {
                if parentUpdate.ref.isEqual(for: update.ref) {
                    update.merge(.nodes([updateNode]))
                    break
                } else {
                    updateNode = parentUpdate
                }
            }
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
        state = .reverted
    }

    /// returns closure to revert last change
    public func currentReversion() -> () -> Void {
        guard !isInvalidated else { fatalError("RealtimeTransaction is invalidated. Create new.") }

        let cancels = cancelations
        return { cancels.forEach { $0() } }
    }
}
extension RealtimeTransaction: CustomStringConvertible {
    public var description: String { return update?.description ?? "Transaction is empty" }
}
public extension RealtimeTransaction {
    /// adds operation of save RealtimeValue as single value
    func set<T: RealtimeValue & RealtimeValueEvents>(_ value: T) {
        addNode(item: (value.dbRef, .value(value.localValue)))
        addCompletion { (result) in
            if result {
                value.didSave()
            }
        }
    }

    /// adds operation of delete RealtimeValue
    func delete<T: RealtimeValue & RealtimeValueEvents>(_ value: T) {
        addNode(item: (value.dbRef, .value(nil)))
        addCompletion { (result) in
            if result {
                value.didRemove()
            }
        }
    }

    /// adds operation of update RealtimeValue
    func update<T: ChangeableRealtimeValue & RealtimeValueEvents & Reverting>(_ value: T) {
        guard value.hasChanges else { debugFatalError("Value has not changes"); return }

        value.insertChanges(to: self)
        addCompletion { (result) in
            if result {
                value.didSave()
            }
        }
        revertion(for: value)
    }

    /// adds current revertion action for reverting entity 
    public func revertion<T: Reverting>(for cancelable: T) {
        addReversion(cancelable.currentReversion())
    }

    /// method to merge actions of other transaction
    func merge(_ other: RealtimeTransaction) {
        guard other !== self else { debugFatalError("Attemption merge the same transaction"); return }
        guard other.preconditions.isEmpty else {
            other.preconditions.forEach(addPrecondition)
            other.preconditions.removeAll()
            scheduledMerges = scheduledMerges.map { $0 + [other] } ?? [other]
            return
        }
        if let value = other.update?.value {
            addNode(item: (other.update.ref, value))
        }
        other.completions.forEach(addCompletion)
        addReversion(other.currentReversion())
        other.state = .merged
    }
}

// TODO: Improve performance
extension RealtimeTransaction {
    /// Class describing updates in specific reference
    public class Node: Equatable, CustomStringConvertible {
        public var description: String {
            guard let thisValue = value else { return "Not active node by ref: \(ref)" }
            return """
            node: {
                ref: \(ref)
                value: \(thisValue)
            }
            """
        }
        let ref: DatabaseReference
//        var parent: Node?
        var value: Value?

        var singleValue: Any? {
            guard let thisValue = value else { fatalError("Value is not defined") }
            switch thisValue {
            case .value(let v): return v
            case .nodes(let nodes):
                let value: [String: Any] = nodes.reduce(into: [:], { (res, node) in
                    res[node.ref.key] = node.singleValue
                })
                return value
            }
        }

        var updateValue: [String: Any?] {
            guard value != nil else { fatalError("Value is not defined") }

            var allValues: [Node] = []
            retrieveValueNodes(to: &allValues)
            return allValues.reduce(into: [:], { (res, node) in
                res[node.ref.path(from: ref)] = node.singleValue
            })
        }

        func commit(_ completion: @escaping (Error?, DatabaseReference) -> Void) {
            guard let thisValue = value else { fatalError("Value is not defined") }

            switch thisValue {
            case .value(let v):
                ref.setValue(v, withCompletionBlock: completion)
            case .nodes(_):
                ref.update(use: updateValue, completion: completion)
            }
        }

        private func retrieveValueNodes(to array: inout [Node]) {
            guard let thisValue = value else { fatalError("Value is not defined") }

            switch thisValue {
            case .value(_): array.append(self)
            case .nodes(let nodes): nodes.forEach { $0.retrieveValueNodes(to: &array) }
            }
        }

        /// Enum describing value of node (as single value or set of subnodes)
        public enum Value {
            case value(Any?)
            case nodes([Node])
        }

        init(ref: DatabaseReference, value: Value) {
            self.ref = ref
            self.value = value
        }

        convenience init(_ update: (ref: DatabaseReference, value: Value)) {
            self.init(ref: update.ref, value: update.value)
        }

        func parent() -> Node? {
//            guard parent == nil else { fatalError("Node already has parent") }
            guard let parentRef = ref.parent else { return nil }

            let parent = Node(ref: parentRef, value: .nodes([self]))
//            self.parent = parent
            return parent
        }
        func child(_ ref: DatabaseReference) -> Node {
            let child = Node(ref: ref, value: .nodes([]))
//            child.parent = self
            merge(.nodes([child]))
            return child
        }
        func search(_ ref: DatabaseReference) -> Node? {
            guard !ref.isEqual(for: self.ref) else { return self }

            guard let thisValue = value else { return nil }
            switch thisValue {
            case .value(_): return nil
            case .nodes(let nodes):
                for node in nodes {
                    if node.ref.isEqual(for: ref) {
                        return node
                    } else if ref.isChild(for: node.ref), let refNode = node.search(ref) {
                        return refNode
                    }
                }
            }
            return nil
        }
        func searchNearestParent(_ ref: DatabaseReference) -> Node? {
            guard let thisValue = value else { return nil }

            switch thisValue {
            case .value(_): return self
            case .nodes(let nodes):
                for node in nodes {
                    if node.ref.isEqual(for: ref) {
                        return node
                    } else if ref.isChild(for: node.ref) {
                        if let refNode = node.searchNearestParent(ref) {
                            return refNode
                        } else {
                            return node
                        }
                    }
                }
                return self
            }
        }
        func merge(_ value: Node.Value) {
            guard let thisValue = self.value else { self.value = value; return }

            switch value {
            case .value(_):
                self.value = value
            case .nodes(let nodes):
                switch thisValue {
                case .value(_):
                    self.value = value
                case .nodes(let thisNodes):
                    let separatedNodes = nodes.reduce(into: (same: ([(new: Node, old: Node)]()), some: [Node]()), { (res, node) in
                        if let index = thisNodes.index(of: node) {
                            res.same.append((node, thisNodes[index]))
                        } else {
                            res.some.append(node)
                        }
                    })
                    let merged: [Node] = separatedNodes.same.map {
                        if let newValue = $0.new.value {
                            $0.old.merge(newValue)
                        }
                        return $0.old
                    }
                    let some = thisNodes.filter { !nodes.contains($0) } + separatedNodes.some

                    self.value = .nodes(some + merged)
                }
            }
        }

        public static func ==(lhs: Node, rhs: Node) -> Bool {
            return lhs.ref.isEqual(for: rhs.ref)
        }
    }
}

enum Nodes {
    static let modelVersion = RealtimeNode(rawValue: "__mv")
    static let links = RealtimeNode(rawValue: "__links")
    static let items = RealtimeNode(rawValue: "__itms")
}
