//
//  RealtimeNode.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 15/03/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation

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
    /// key of reference to source location
    case source = "__src"
}

/// Represents branch of database tree
public final class BranchNode: Node {
    public init(key: String) {
        super.init(key: key, parent: .root)
    }
    public init<T: RawRepresentable>(key: T) where T.RawValue == String {
        super.init(key: key.rawValue, parent: .root)
    }
    override public var parent: Node? { set { fatalError("Branch node always starts from root node") } get { return .root } }
    override public var isRoot: Bool { return false }
    override public var isAnchor: Bool { return true }
    override public var isRooted: Bool { return true }
    override public var root: Node? { return .root }
    override public var first: Node? { return nil }
    override public func path(from node: Node) -> String { return key }
    override public func hasAncestor(node: Node) -> Bool { return node == .root }
    override func move(toNodeKeyedBy key: String) -> Node { fatalError("Branch node cannot be moved") }
    override func copy() -> Node {
        /// branch node unchangeable therefore we can return self
        return self
    }
    override func _validate() {
        debugFatalError(
            condition: RealtimeApp._isInitialized && key.split(separator: "/")
                .contains(where: { $0.rangeOfCharacter(from: RealtimeApp.app.configuration.unavailableSymbols) != nil }),
            "Key has unavailable symbols"
        )
    }
    override public var description: String { return "branch: \(key)" }
}
/// Node for internal database services
final class ServiceNode: Node {
    public init(key: String) {
        super.init(key: key, parent: .root)
    }
    public init<T: RawRepresentable>(key: T) where T.RawValue == String {
        super.init(key: key.rawValue, parent: .root)
    }
    override public var parent: Node? { set { fatalError("Service node always starts from root node") } get { return .root } }
    override var isRoot: Bool { return false }
    override var isAnchor: Bool { return true }
    override var isRooted: Bool { return true }
    override var root: Node? { return .root }
    override var first: Node? { return nil }
    override func path(from node: Node) -> String { return key }
    override func hasAncestor(node: Node) -> Bool { return node == .root }
    override func move(toNodeKeyedBy key: String) -> Node { fatalError("Service node cannot be moved") }
    override func copy() -> Node { return ServiceNode(key: key) }
    override func _validate() {}
    override public var description: String { return "service: \(key)" }
}

/// Represents reference to database tree node
public class Node: Hashable, Comparable {
    /// Root node
    public static let root: Node = Root()
    final class Root: Node {
        init() { super.init(key: "", parent: nil) }
        override var parent: Node? { set { fatalError("Root node has no parent") } get { return nil } }
        override var isRoot: Bool { return true }
        override var isAnchor: Bool { return true }
        override var isRooted: Bool { return true }
        override var root: Node? { return nil }
        override var first: Node? { return nil }
        override var rootPath: String { return "" }
        override func path(from node: Node) -> String { fatalError("Root node cannot have parent nodes") }
        override func hasAncestor(node: Node) -> Bool { return false }
        override func move(toNodeKeyedBy key: String) -> Node { fatalError("Root node cannot be moved") }
        override func copy() -> Node { return Node.root }
        override func _validate() {}
        override var description: String { return "root" }
    }

    /// Node key
    public let key: String
    /// Parent node
    public internal(set) var parent: Node?

    public func hash(into hasher: inout Hasher) {
        forEach { (node) in
            hasher.combine(node.key)
        }
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
        self.key = key
        self.parent = parent

        _validate()
    }

    /// True if node is instance stored in Node.root
    public var isRoot: Bool { return false }
    /// True if node has root ancestor
    public var isRooted: Bool { return root === Node.root }
    /// Returns the most senior node. It may no equal Node.root
    public var root: Node? { return parent.map { $0.root ?? $0 } }
    /// Returns the most senior node excluding Node.root instance or nil if node is not rooted.
    public var first: Node? { return parent.flatMap { $0.isRoot ? self : $0.first } }

    public var isAnchor: Bool { return false }
    /// Returns current anchor node
    public var branch: Node? { return isAnchor ? self : parent?.branch }

    /// Returns path from the most senior node.
    public var absolutePath: String {
        return parent.map { $0.isRoot ? key : $0.absolutePath + "/" + key } ?? key
    }

    /// Returns path from the nearest anchor node or
    /// if anchor node does not exist from the most senior node.
    public var path: String {
        return parent.map { $0.isAnchor ? key : $0.path + "/" + key } ?? key
    }

    @available(*, renamed: "absolutePath", deprecated, message: "Use `path` or `absolutePath` instead.")
    public var rootPath: String { return absolutePath }

    /// Returns path from passed node.
    ///
    /// - Parameter node: Ancestor node.
    /// - Returns: String representation of path from ancestor node to current
    public func path(from node: Node) -> String {
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

    /// Returns ancestor node that is child to passed node
    ///
    /// - Parameter ancestor: Related ancestor node
    /// - Returns: Ancestor node or nil
    public func first(after ancestor: Node) -> Node? {
        guard ancestor != self else { fatalError("Cannot get from the same node") }

        var current: Node = self
        while let next = current.parent {
            if next != ancestor {
                return current
            } else {
                current = next
            }
        }

        fatalError("Cannot be get from non parent node")
    }

    func after(ancestor: Node) -> [Node] {
        guard ancestor != self else { fatalError("Cannot get from the same node") }

        var result: [Node] = [self]
        while let next = result[0].parent {
            if next == ancestor {
                return result
            } else {
                result.insert(next, at: 0)
            }
        }

        fatalError("Cannot be get from non parent node")
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
    public func hasAncestor(node: Node) -> Bool {
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

    func nearestCommonPrefix(for node: Node) -> Node? {
        guard self !== node else { return self }

        let otherNodes = node.reversed()
        let thisNodes = self.reversed()
        guard otherNodes.first == thisNodes.first else { return nil }

        var prefixNode: Node?
        for i in (1 ..< Swift.min(otherNodes.count, thisNodes.count)) {
            let next = thisNodes[i]
            if otherNodes[i].key != next.key {
                return prefixNode
            } else {
                prefixNode = next
            }
        }
        return prefixNode
    }

    internal func _validate() {
        debugFatalError(
            condition: !RealtimeApp._isInitialized,
            "You must initialize Realtime"
        )
        debugFatalError(
            condition: (parent?.underestimatedCount ?? 0) >= RealtimeApp.app.configuration.maxNodeDepth - 1,
            "Maximum depth limit of child nodes exceeded"
        )
        debugFatalError(
            condition: key.split(separator: "/")
                .contains(where: { $0.rangeOfCharacter(from: RealtimeApp.app.configuration.unavailableSymbols) != nil }),
            "Key has unavailable symbols"
        )
    }

    /// Creates node and set it as parent
    /// - Parameters:
    ///   - key: Key of parent node
    /// - Returns: Parent node
    internal func move(toNodeKeyedBy key: String) -> Node {
        let parent = Node(key: key)
        self.parent = parent
        return parent
    }

    /// Creates copy of node without explicit referencing.
    /// Regular node has no parent reference.
    /// Special node that has attached to root node also will have reference to root.
    internal func copy() -> Node {
        return Node(key: key)
    }

    public static func ==(lhs: Node, rhs: Node) -> Bool {
        guard lhs !== rhs else { return true }
        guard lhs.key == rhs.key else { return false }

        var lhsAncestor = lhs
        var rhsAncestor = rhs
        while let left = lhsAncestor.parent, let right = rhsAncestor.parent {
            if left.key == right.key {
                lhsAncestor = left
                rhsAncestor = right
            } else {
                return false
            }
        }

        return lhsAncestor.key == rhsAncestor.key
    }
    public static func < (lhs: Node, rhs: Node) -> Bool {
        return lhs.key < rhs.key
    }

    public var description: String { return absolutePath }
    public var debugDescription: String { return description }
}
extension Node: CustomStringConvertible, CustomDebugStringConvertible {}
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
            current = current.move(toNodeKeyedBy: next.key)
        }
        current.moveTo(node)
        return copied
    }
    /// Changed parent to passed node
    ///
    /// - Parameter node: Target node
    func moveTo(_ node: Node) {
        precondition(node !== self, "Parent cannot be equal child")
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
    internal static var linksNode: Node { return RealtimeApp.app.configuration.linksNode }
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
        return (linksItemsNode.child(with: linkKey), SourceLink(id: linkKey, links: targetNodes.map { $0.absolutePath }))
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

//    func map<Returned>(from parent: RealtimeDataProtocol) throws -> Returned? {
//        guard parent.hasChild(rawValue) else { return nil }
//
//        return try parent.child(forPath: rawValue).singleValueContainer().decode(Returned.self)
//    }

    func path(from superpath: String, to subpath: String? = nil) -> String {
        return superpath + "/" + rawValue + (subpath.map { "/" + $0 } ?? "")
    }

    func subpath<Node: RawRepresentable>(with node: Node) -> String where Node.RawValue == String {
        return subpath(with: node.rawValue)
    }
    func subpath(with path: String) -> String {
        return rawValue + "/" + path
    }
}

extension String: RawRepresentable {
    public var rawValue: String { return self }
    public init(rawValue: String) {
        self = rawValue
    }
}

extension Node {
    var _hasMultiLevelNode: Bool {
        return contains(where: { $0.key.split(separator: "/").count > 1 && type(of: $0) != BranchNode.self })
    }
}
