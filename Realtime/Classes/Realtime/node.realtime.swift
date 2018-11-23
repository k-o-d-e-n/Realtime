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

enum InternalKeys: String, CodingKey {
    /// version of RealtimeValue
    case modelVersion = "__mv"
    /// root database key for links hierarchy
    case links = "__lnks"
    /// key of RealtimeValue in 'links' branch which stores all external links to this values
    case linkItems = "__l_itms"
    /// key of RealtimeCollection in 'links' branch which stores prototypes of all collection elements
    case items = "__itms"
    /// key of collection element prototype which indicates priority
    case index = "__i"
    /// key to store user payload data
    case payload = "__pl"
    /// key of associated collection element prototype
    case key = "__key"
    /// key of associated collection element prototype
    case value = "__val"
    /// ket of collection element prototype to store link key
    case link = "__lnk"
    /// Indicates raw value of enum, or subclass
    case raw = "__raw"
}

/// Represents branch of database tree
public final class BranchNode: Node {
    public init(key: String) {
        super.init(key: key, parent: .root)
    }
    public init<T: RawRepresentable>(key: T) where T.RawValue == String {
        super.init(key: key.rawValue, parent: .root)
    }
    override public var parent: Node? { set {} get { return .root } }
    override var isRoot: Bool { return false }
    override var isAnchor: Bool { return true }
    override var isRooted: Bool { return true }
    override var root: Node? { return .root }
    override var first: Node? { return nil }
    override func path(from node: Node) -> String { return key }
    override func hasAncestor(node: Node) -> Bool { return node == .root }
    override public var description: String { return "branch: \(key)" }
}

/// Represents reference to database tree node
public class Node: Hashable {
    /// Root node
    public static let root: Node = Root()
    final class Root: Node {
        init() { super.init(key: "", parent: nil) }
        override var parent: Node? { set {} get { return nil } }
        override var isRoot: Bool { return true }
        override var isAnchor: Bool { return true }
        override var isRooted: Bool { return true }
        override var root: Node? { return nil }
        override var first: Node? { return nil }
        override var rootPath: String { return "" }
        override func path(from node: Node) -> String { fatalError("Root node cannot have parent nodes") }
        override func hasAncestor(node: Node) -> Bool { return false }
        override var description: String { return "root" }
    }

    /// Node key
    public let key: String
    /// Parent node
    public internal(set) var parent: Node?

    // TODO: Hasher Swift 4.2
    public var hashValue: Int {
        return parent?.reduce(into: key.hashValue, { $0 = $0 &- $1.hashValue }) ?? key.hashValue
    }

    /// Creates new instance with automatically generated key
    ///
    /// - Parameter parent: Parent node reference of `nil`
    public convenience init(parent: Node? = nil) {
        self.init(key: RealtimeApp.app.database.generateAutoID(), parent: parent)
    }

    public convenience init<Key: RawRepresentable>(key: Key, parent: Node? = nil) where Key.RawValue == String {
        self.init(key: key.rawValue, parent: parent)
    }

    public convenience init(key: String) {
        self.init(key: key, parent: nil)
    }

    public init(key: String, parent: Node?) {
        debugFatalError(
            condition: RealtimeApp._isInitialized && (parent?.underestimatedCount ?? 0) >= RealtimeApp.app.maxNodeDepth - 1,
            "Maximum depth limit of child nodes exceeded"
        )
        self.key = key
        self.parent = parent
    }

    /// True if node is instance stored in Node.root
    var isRoot: Bool { return false }
    /// True if node has root ancestor
    var isRooted: Bool { return root === Node.root }
    /// Returns the most senior node. It may no equal Node.root
    var root: Node? { return parent.map { $0.root ?? $0 } }
    /// Returns the most senior node excluding Node.root instance.
    var first: Node? { return parent.flatMap { $0.isRoot ? self : $0.first } }

    var isAnchor: Bool { return false }
    /// Returns current anchor node
    var branch: Node? { return isAnchor ? self : parent?.branch }

    /// Returns path from the most senior node.
    public var absolutePath: String {
        return parent.map { $0.isRoot ? key : $0.absolutePath + "/" + key } ?? key
    }

    /// Returns path from the nearest anchor node or
    /// if anchor node does not exist from the most senior node.
    public var path: String {
        return parent.map { $0.isAnchor ? key : $0.path + "/" + key } ?? key
    }

    @available(iOS, renamed: "absolutePath", deprecated: 0.8.5, message: "Use `path` or `absolutePath` instead.")
    public var rootPath: String { return absolutePath }

    /// Returns path from passed node.
    ///
    /// - Parameter node: Ancestor node.
    /// - Returns: String representation of path from ancestor node to current
    func path(from node: Node) -> String {
        guard node != self else { fatalError("Path does not exists for the same nodes") }

        var path = key
        var current: Node = self
        while let next = current.parent {
            if next != node {
                path = next.key + "/" + path
            } else {
                return path
            }
            current = next
        }

        fatalError("Path cannot be get from non parent node")
    }

    /// Returns ancestor node on specified level up
    ///
    /// - Parameter level: Number of levels up to ancestor
    /// - Returns: Ancestor node
    func ancestor(onLevelUp level: UInt) -> Node? {
        guard level > 0 else { fatalError("Level must be more than 0") }
        
        var currentLevel = 1
        var ancestor = parent
        while currentLevel < level, let ancr = ancestor {
            ancestor = ancr.parent
            currentLevel += 1
        }

        return ancestor
    }

    /// Returns path from ancestor node on level up
    ///
    /// - Parameter level: Level up
    /// - Returns: String of path
    func path(fromLevelUp level: UInt) -> String {
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

    /// Finds ancestor
    ///
    /// - Parameter node: Ancestor node
    /// - Returns: Result of search
    func hasAncestor(node: Node) -> Bool {
        // TODO: Improve checking by comparing on both sides
        var current: Node = self
        while let parent = current.parent {
            if node == parent {
                return true
            }
            current = parent
        }
        return false
    }

    internal func movedToNode(keyedBy key: String) -> Node {
        let parent = Node(key: key)
        self.parent = parent
        return parent
    }

    public static func ==(lhs: Node, rhs: Node) -> Bool {
        guard lhs !== rhs else { return true }
        guard lhs.key == rhs.key else { return false }

        return lhs.rootPath == rhs.rootPath
    }

    public var description: String { return rootPath }
    public var debugDescription: String { return description }
}
extension Node: CustomStringConvertible, CustomDebugStringConvertible {}
public extension Node {
    static func from(_ reference: DatabaseReference) -> Node {
        return Node.root.child(with: reference.rootPath)
    }
    public func reference(for database: Database = Database.database()) -> DatabaseReference {
        return .fromRoot(rootPath, of: database)
    }
    public func file(for storage: Storage = Storage.storage()) -> StorageReference {
        return storage.reference(withPath: rootPath)
    }
}
public extension Node {
    /// Returns a child reference of database tree
    ///
    /// - Parameter path: Value that represents as path is separated `/` character.
    /// - Returns: Database reference node
    static func root<Path: RawRepresentable>(_ path: Path) -> Node where Path.RawValue == String {
        return Node.root.child(with: path.rawValue)
    }

    static func branch<Path: RawRepresentable>(_ path: Path) -> Node where Path.RawValue == String {
        return BranchNode(key: path)
    }

    /// Generates an automatically calculated key of database.
    func childByAutoId() -> Node {
        return Node(parent: self)
    }
    /// Returns a child reference of database tree
    ///
    /// - Parameter path: Value that represents as path is separated `/` character.
    /// - Returns: Database reference node
    func child<Path: RawRepresentable>(with path: Path) -> Node where Path.RawValue == String {
        return child(with: path.rawValue)
    }
    /// Returns a child reference of database tree
    ///
    /// - Parameter path: `String` value that represents as path is separated `/` character.
    /// - Returns: Database reference node
    func child(with path: String) -> Node {
        return path
            .split(separator: "/", omittingEmptySubsequences: true)
            .reduce(self) { Node(key: String($1), parent: $0) }
    }
    /// Copies full chain of nodes to passed node
    ///
    /// - Parameter node: Some node
    /// - Returns: Copied node
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
    /// Changed parent to passed node
    ///
    /// - Parameter node: Target node
    func moveTo(_ node: Node) {
        self.parent = node
    }
    /// Slices chain of nodes
    ///
    /// - Parameter count: Number of first nodes to slice
    /// - Returns: Two piece of chain
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
    internal static var linksNode: Node { return RealtimeApp.app.linksNode }
    internal var linksNode: Node {
        guard isRooted else { fatalError("Try get links node from not rooted node: \(self)") }
        return copy(to: Node.linksNode)
    }
    internal var linksItemsNode: Node {
        return child(with: InternalKeys.linkItems).linksNode
    }
    internal func generate(linkTo targetNode: Node) -> (node: Node, link: SourceLink) {
        return generate(linkTo: [targetNode])
    }
    internal func generate(linkTo targetNodes: [Node]) -> (node: Node, link: SourceLink) {
        return generate(linkKeyedBy: RealtimeApp.app.database.generateAutoID(), to: targetNodes)
    }
    internal func generate(linkKeyedBy linkKey: String, to targetNodes: [Node]) -> (node: Node, link: SourceLink) {
        return (linksItemsNode.child(with: linkKey), SourceLink(id: linkKey, links: targetNodes.map { $0.rootPath }))
    }
}

extension Node: Sequence {
    public var underestimatedCount: Int { return reduce(into: 0, { r, _ in r += 1 }) }
    public func makeIterator() -> AnyIterator<Node> {
        var current: Node? = self
        return AnyIterator {
            defer { current = current?.parent }
            return current
        }
    }
}


public extension RawRepresentable where Self.RawValue == String {
    /// checks availability child in snapshot with node name   
    func has(in snapshot: RealtimeDataProtocol) -> Bool {
        return snapshot.hasChild(rawValue)
    }

    /// gets child snapshot by node name
    func child(from parent: RealtimeDataProtocol) -> RealtimeDataProtocol {
        return parent.child(forPath: rawValue)
    }

    func map<Returned>(from parent: RealtimeDataProtocol) throws -> Returned? {
        guard parent.hasChild(rawValue) else { return nil }

        return try parent.child(forPath: rawValue).unbox(as: Returned.self)
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

