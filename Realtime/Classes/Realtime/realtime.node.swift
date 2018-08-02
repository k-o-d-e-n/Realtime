//
//  RealtimeNode.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 15/03/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation
import FirebaseDatabase
import FirebaseStorage

enum InternalKeys: String {
    case modelVersion = "__mv"
    case links = "__links"
    case items = "__itms"
    case index = "__i"
    case payload = "__pl"
    /// Indicates raw value of enum, or subclass
    case raw = "__raw"
}

public class Node: Equatable {
    public static let root: Node = Root()
    class Root: Node {
        init() { super.init(key: "") }
        override var isRoot: Bool { return true }
        override var isRooted: Bool { return true }
        override var root: Node? { return nil }
        override var first: Node? { return nil }
        override var rootPath: String { return "" }
        override func path(from node: Node) -> String { fatalError("Root node cannot have parent nodes") }
        override func hasParent(node: Node) -> Bool { return false }
        override func reference(for database: Database) -> DatabaseReference { return .root(of: database) }
        override var description: String { return "root" }
    }

    public let key: String
    public var parent: Node?

    public convenience init(parent: Node? = nil) {
        self.init(key: DatabaseReference.root().childByAutoId().key, parent: parent)
    }

    public convenience init<Key: RawRepresentable>(key: Key, parent: Node? = nil) where Key.RawValue == String {
        self.init(key: key.rawValue, parent: parent)
    }

    public init(key: String, parent: Node? = nil) {
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

    func ancestor(onLevelUp level: Int) -> Node? {
        guard level > 0 else { fatalError("Level must be more than 0") }
        
        var currentLevel = 1
        var ancestor = parent
        while currentLevel < level, let ancr = ancestor {
            ancestor = ancr.parent
            currentLevel += 1
        }

        return ancestor
    }

    func path(fromLevelUp level: Int) -> String {
        var path = key
        var currentLevel = 0
        var current = self
        while currentLevel < level {
            if let next = current.parent {
                path = next.key + "/" + path
                current = next
                currentLevel += 1
            } else {
                fatalError("Path cannot be get from level: \(level)")
            }
        }

        return path
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

    public func reference(for database: Database = Database.database()) -> DatabaseReference {
        return .fromRoot(rootPath, of: database)
    }
    public func file(for storage: Storage = Storage.storage()) -> StorageReference {
        return storage.reference(withPath: rootPath)
    }
}
extension Node: CustomStringConvertible, CustomDebugStringConvertible {}
public extension Node {
    static func root<Path: RawRepresentable>(_ path: Path) -> Node where Path.RawValue == String {
        return Node.root.child(with: path.rawValue)
    }
    static func from(_ snapshot: FireDataProtocol) -> Node? {
        return snapshot.dataRef.map(Node.from)
    }
    static func from(_ reference: DatabaseReference) -> Node {
        return Node.root.child(with: reference.rootPath)
    }
    func childByAutoId() -> Node {
        return Node(parent: self)
    }
    func child<Path: RawRepresentable>(with path: Path) -> Node where Path.RawValue == String {
        return child(with: path.rawValue)
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
            current = current.movedToNode(keyedBy: next.key)
        }
        current.moveTo(node)
        return copied
    }
    func movedToNode(keyedBy key: String) -> Node {
        let parent = Node(key: key)
        self.parent = parent
        return parent
    }
    func moveTo(_ node: Node) {
        self.parent = node
    }
    func slicedFirst(_ count: Int = 1) -> (dropped: Node, sliced: Node)? {
        guard count != 0, parent != nil else { return nil }

        let nodes = reversed()
        let firstIsRoot = nodes.first!.isRoot
        var iterator = nodes.makeIterator()
        var dropped: Node?
        (0..<count + (firstIsRoot ? 1 : 0)).forEach { _ in
            if let next = iterator.next(), next !== Node.root {
                dropped = next
            } else {
                dropped = nil
            }
        }
        guard let d = dropped else { return nil }

        var sliced: Node?
        while let next = iterator.next() {
            if sliced == nil {
                sliced = Node(key: next.key, parent: firstIsRoot ? .root : nil)
            } else {
                sliced = Node(key: next.key, parent: sliced)
            }
        }
        guard let s = sliced else { return nil }

        return (d, s)
    }
}
public extension Node {
    static var linksNode: Node { return Node.root.child(with: InternalKeys.links) }
    var linksNode: Node {
        guard isRooted else { fatalError("Try get links node from not rooted node: \(self)") }
        return copy(to: Node.linksNode)
    }
    internal func generate(linkTo targetNode: Node) -> (node: Node, link: SourceLink) {
        return generate(linkTo: [targetNode])
    }
    internal func generate(linkTo targetNodes: [Node]) -> (node: Node, link: SourceLink) {
        return generate(linkKeyedBy: DatabaseReference.root().childByAutoId().key, to: targetNodes)
    }
    internal func generate(linkKeyedBy linkKey: String, to targetNodes: [Node]) -> (node: Node, link: SourceLink) {
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
    func map<Mapped>(child path: String, map: (FireDataProtocol) -> Mapped? = { $0.flatMap() }) -> Mapped? {
        guard hasChild(path) else { return nil }
        return map(child(forPath: path))
    }
    func mapExactly(if truth: Bool, child path: String, map: (FireDataProtocol) -> Void) { if truth || hasChild(path) { map(child(forPath: path)) } }
}

public extension RawRepresentable where Self.RawValue == String {
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

    func subpath<Node: RawRepresentable>(with node: Node) -> String where Node.RawValue == String {
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

extension String: RawRepresentable {
    public var rawValue: String { return self }
    public init(rawValue: String) {
        self = rawValue
    }
}

