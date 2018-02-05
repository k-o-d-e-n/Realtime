//
//  RealtimeNode.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 15/03/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation
import FirebaseDatabase

public protocol RTNode: RawRepresentable, Equatable {
    associatedtype RawValue: Equatable = String
}
public protocol AssociatedRTNode: RTNode {
    associatedtype ConcreteType: RealtimeValue
}
public extension RTNode where Self.RawValue == String {
    func has(in snapshot: DataSnapshot) -> Bool {
        return snapshot.hasChild(rawValue)
    }

    func snapshot(from parent: DataSnapshot) -> DataSnapshot {
        return parent.childSnapshot(forPath: rawValue)
    }

    func map<Returned>(from parent: DataSnapshot) -> Returned? {
        return parent.map(child: rawValue) { $0.value as! Returned }
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

    func reference(from ref: DatabaseReference) -> DatabaseReference {
        return ref.child(rawValue)
    }

    func reference(from entity: RealtimeValue) -> DatabaseReference {
        return entity.dbRef.child(rawValue)
    }
}
public extension AssociatedRTNode where Self.RawValue == String {
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

public struct RealtimeLink: DataSnapshotRepresented {
    typealias OptionalSourceProperty = RealtimeProperty<RealtimeLink?, RealtimeLinkSourceSerializer>
    typealias OptionalProperty = RealtimeProperty<RealtimeLink?, RealtimeLinkSerializer>
    enum Nodes {
        static let path = RealtimeNode(rawValue: "pth")
    }

    let id: String
    let path: String

    var dbValue: [String: Any] { return [Nodes.path.rawValue: path] }

    init(id: String, path: String) {
        precondition(path.count > 0, "RealtimeLink path must be not empty")
        self.id = id
        self.path = path
    }

    public init?(snapshot: DataSnapshot) {
        guard let pth: String = Nodes.path.map(from: snapshot) else { return nil }
        self.init(id: snapshot.key, path: pth)
    }
    
    public func apply(snapshot: DataSnapshot, strongly: Bool) {
        fatalError("RealtimeLink is not mutated") // TODO: ?
    }
}

extension RealtimeLink {
    var dbRef: DatabaseReference { return .fromRoot(path) }

    func entity<Entity: RealtimeValue>(_: Entity.Type) -> Entity { return Entity(dbRef: dbRef) }
}

extension RealtimeLink: Equatable {
    public static func ==(lhs: RealtimeLink, rhs: RealtimeLink) -> Bool {
        return lhs.id == rhs.id
    }
}

public protocol Reverting: class {
    func revert()
    func currentReversion() -> () -> Void
}
extension Reverting where Self: ChangeableRealtimeValue {
    func revertIfChanged() {
        if hasChanges {
            revert()
        }
    }
}

public class RealtimeTransaction {
    fileprivate var updates: [Database.UpdateItem] = []
    fileprivate var completions: [(Error?) -> Void] = []
    fileprivate var cancelations: [() -> Void] = []
    fileprivate var state: State = .waiting
    public var isCompleted: Bool { return state == .completed }
    public var isReverted: Bool { return state == .reverted }
    public var isFailed: Bool { return state == .failed }
    public var isPerforming: Bool { return state == .performing }
    public var isMerged: Bool { return state == .merged }
    public var isInvalidated: Bool { return isCompleted || isMerged || isFailed || isReverted }

    fileprivate var update: Node!

    enum State {
        case waiting, performing
        case completed, failed, reverted, merged
    }

    public init() {}

    // TODO: Add configuration commit as single value or update value
    public func commit(with completion: ((Error?) -> Void)? = nil) {
        state = .performing
        update.commit({ (err, _) in
            self.completions.forEach { $0(err) }
            self.state = err == nil ? .completed : .failed
            completion?(err)
        })
    }

    public func addNode(ref: DatabaseReference, value: Any?) {
        addNode(item: (ref, .value(value)))
    }
    // TODO: Improve interface
    public func addNode(item updateItem: (ref: DatabaseReference, value: Node.Value)) {
        guard !isInvalidated else { fatalError("RealtimeTransaction is invalidated. Create new.") }

        guard update != nil else { update = Node(ref: updateItem.ref.parent!, value: .nodes([Node(updateItem)])); return }

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

    public func addReversion(_ reversion: @escaping () -> Void) {
        guard !isInvalidated else { fatalError("RealtimeTransaction is invalidated. Create new.") }

        cancelations.insert(reversion, at: 0)
    }

    public func addCompletion(_ completion: @escaping (Error?) -> Void) {
        guard !isInvalidated else { fatalError("RealtimeTransaction is invalidated. Create new.") }

        completions.append(completion)
    }

    deinit {
        if !isReverted && !isCompleted && !isMerged { fatalError("RealtimeTransaction requires performing, reversion or merging") }
    }
}
extension RealtimeTransaction: Reverting {
    public func revert() {
        guard state == .waiting || isFailed else { fatalError("Reversion cannot be made") }

        cancelations.forEach { $0() }
        state = .reverted
    }

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
    func set<T: RealtimeValue & RealtimeValueEvents>(_ value: T) {
        addNode(item: (value.dbRef, .value(value.localValue)))
        addCompletion { (err) in
            guard err == nil else { return }
            value.didSave()
        }
    }
    func delete<T: RealtimeValue & RealtimeValueEvents>(_ value: T) {
        addNode(item: (value.dbRef, .value(nil)))
        addCompletion { (err) in
            guard err == nil else { return }
            value.didRemove()
        }
    }
    func update<T: ChangeableRealtimeValue & RealtimeValueEvents & Reverting>(_ value: T) {
        value.insertChanges(to: self)
        addCompletion { (err) in
            guard err == nil else { return }
            value.didSave()
        }
        revertion(for: value)
    }
    public func revertion<T: Reverting>(for cancelable: T) {
        addReversion(cancelable.currentReversion())
    }
    func merge(_ other: RealtimeTransaction) {
        addNode(item: (other.update.ref, other.update.value!))
        other.completions.forEach(addCompletion)
        addReversion(other.currentReversion())
        other.state = .merged
    }
}

// TODO: Improve performance
extension RealtimeTransaction {
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

        func commit(_ completion: @escaping (Error?, DatabaseReference) -> Void) {
            guard let thisValue = value else { fatalError("Value is not defined") }

            switch thisValue {
            case .value(let v):
                ref.setValue(v, withCompletionBlock: completion)
            case .nodes(_):
                ref.update(use: updateValue, completion: completion)
            }
        }

        var updateValue: [String: Any] {
            guard value != nil else { fatalError("Value is not defined") }

            var allValues: [Node] = []
            retrieveValueNodes(to: &allValues)
            return allValues.reduce(into: [:], { (res, node) in
                res[node.ref.path(from: ref)] = node.singleValue
            })
        }

        private func retrieveValueNodes(to array: inout [Node]) {
            guard let thisValue = value else { fatalError("Value is not defined") }

            switch thisValue {
            case .value(_): array.append(self)
            case .nodes(let nodes): nodes.forEach { $0.retrieveValueNodes(to: &array) }
            }
        }

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
