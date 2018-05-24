//
//  RealtimeNode.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 15/03/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation
import FirebaseDatabase

enum Nodes {
    static let modelVersion = RealtimeNode(rawValue: "__mv")
    static let links = RealtimeNode(rawValue: "__links")
    static let items = RealtimeNode(rawValue: "__itms")
}

public class Node: Equatable {
    public static let root: Node = Root(key: "")
    class Root: Node {
        override var isRoot: Bool { return true }
        override var isRooted: Bool { return true }
        override var root: Node? { return nil }
        override var first: Node? { return nil }
        override var rootPath: String { return "" }
        override func path(from node: Node) -> String { fatalError("Root node cannot have parent nodes") }
        override func hasParent(node: Node) -> Bool { return false }
        override var reference: DatabaseReference { return .root() }
        override var description: String { return "root" }
    }

    let key: String
    var parent: Node?

    public init(key: String = DatabaseReference.root().childByAutoId().key, parent: Node? = nil) {
        self.key = key
        self.parent = parent
    }

    var isRoot: Bool { return false }
    var isRooted: Bool { return root === Node.root }
    var root: Node? { return parent.map { $0.root ?? $0 } }
    var first: Node? { return parent.flatMap { $0.isRoot ? self : $0.first } }

    public var rootPath: String {
        return parent.map { $0.rootPath + "/" + key } ?? key
    }

    func path(from node: Node) -> String {
        guard node != self else { fatalError("Path does not exists for the same nodes") }

        var path = key
        var current: Node = self
        while let next = current.parent {
            if next != node {
                path = next.key + "/" + path
            } else {
                return "/" + path
            }
            current = next
        }

        fatalError("Path cannot be get from non parent node")
    }

    func hasParent(node: Node) -> Bool {
        var current: Node = self
        while let parent = current.parent {
            if node == parent {
                return true
            }
            current = parent
        }
        return false
    }

    public static func ==(lhs: Node, rhs: Node) -> Bool {
        guard lhs !== rhs else { return true }
        guard lhs.key == rhs.key else { return false }

        return lhs.rootPath == rhs.rootPath
    }

    public var description: String { return rootPath }
    public var debugDescription: String { return description }
    
    var reference: DatabaseReference { return .fromRoot(rootPath) }
}
extension Node: CustomStringConvertible, CustomDebugStringConvertible {}
public extension Node {
    static func from(_ snapshot: DataSnapshot) -> Node {
        return from(snapshot.ref)
    }
    static func from(_ reference: DatabaseReference) -> Node {
        return Node.root.child(with: reference.rootPath)
    }
    func childByAutoId() -> Node {
        return Node(parent: self)
    }
    func child(with path: String) -> Node {
        return path
            .split(separator: "/", omittingEmptySubsequences: true)
            .reduce(self) { Node(key: String($1), parent: $0) }
    }
    func copy(to node: Node) -> Node {
        var copying: Node = self
        var current: Node = Node(key: copying.key)
        let copied = current
        while let next = copying.parent, !next.isRoot {
            copying = next
            current = current.moveTo(nodeKeyedBy: next.key)
        }
        current.moveTo(node)
        return copied
    }
    func moveTo(nodeKeyedBy key: String) -> Node {
        let parent = Node(key: key)
        self.parent = parent
        return parent
    }
    func moveTo(_ node: Node) {
        self.parent = node
    }
}
public extension Node {
    static var linksNode: Node { return Node.root.child(with: Nodes.links.rawValue) }
    var linksNode: Node { return copy(to: Node.linksNode) }
    func generate(linkTo targetNode: Node) -> (sourceNode: Node, link: SourceLink) {
        return generate(linkTo: [targetNode])
    }
    func generate(linkTo targetNodes: [Node]) -> (sourceNode: Node, link: SourceLink) {
        return generate(linkKeyedBy: DatabaseReference.root().childByAutoId().key, to: targetNodes)
    }
    func generate(linkKeyedBy linkKey: String, to targetNodes: [Node]) -> (sourceNode: Node, link: SourceLink) {
        return (linksNode.child(with: linkKey), SourceLink(id: linkKey, links: targetNodes.map { $0.rootPath }))
    }
}

extension Node: Sequence {
    public func makeIterator() -> AnyIterator<Node> {
        var current: Node? = self
        return AnyIterator {
            defer { current = current?.parent }
            return current
        }
    }
}

public extension FireDataProtocol {
    func map<Mapped>(_ transform: (Any) -> Mapped = { $0 as! Mapped }) -> Mapped? { return value.map(transform) }
    func flatMap<Mapped>(_ transform: (Any) -> Mapped? = { $0 as? Mapped }) -> Mapped? { return value.flatMap(transform) }
    func map<Mapped>(child path: String, map: (FireDataProtocol) -> Mapped?) -> Mapped? {
        guard hasChild(path) else { return nil }
        return map(child(forPath: path))
    }
    func mapExactly(if truth: Bool, child path: String, map: (FireDataProtocol) -> Void) { if truth || hasChild(path) { map(child(forPath: path)) } }
}

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

    /// checks availability child in snapshot with node name
    func has(in snapshot: FireDataProtocol) -> Bool {
        return snapshot.hasChild(rawValue)
    }

    /// gets child snapshot by node name
    func child(from parent: FireDataProtocol) -> FireDataProtocol {
        return parent.child(forPath: rawValue)
    }

    func map<Returned>(from parent: FireDataProtocol) -> Returned? {
        return parent.map(child: rawValue) { $0.value as? Returned }
    }

    func take(from parent: FireDataProtocol, exactly: Bool, map: (FireDataProtocol) -> Void) {
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
}
public extension AssociatedRTNode where Self.RawValue == String {
    /// returns object referenced by node name in specific reference.
    func entity(in node: Node?) -> ConcreteType {
        return ConcreteType(in: Node(key: rawValue, parent: node))
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

