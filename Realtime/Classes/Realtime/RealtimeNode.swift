//
//  RealtimeNode.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 15/03/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation
import FirebaseDatabase

public protocol RTNode: RawRepresentable {
    associatedtype RawValue = String
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

// TODO: For cancellation transaction need remove all changes from related objects
// TODO: All local changes should make using RealtimeTransaction
public class RealtimeTransaction {
    private var updates: [Database.UpdateItem] = []
    private var completions: [(Error?) -> Void] = []
    public internal(set) var isCompleted: Bool = false

    public init() {}

    public func perform(with completion: ((Error?) -> Void)? = nil) {
        Database.database().update(use: updates) { (err, _) in
            self.isCompleted = true
            self.completions.forEach { $0(err) }
            completion?(err)
        }
    }

    public func addUpdate(item updateItem: Database.UpdateItem) {
        var index = 0
        let indexes = updates.reduce([Int]()) { (indexes, item) -> [Int] in
            defer {
                if updateItem.ref.isChild(for: item.ref) { fatalError("Invalid update item, reason: item is child for other update item") }
                index += 1
            }
            return indexes + (item.ref.isChild(for: updateItem.ref) || item.ref.isEqual(for: updateItem.ref) ? [index] : [])
        }

        indexes.forEach { updates.remove(at: $0) }
        updates.append(updateItem)
    }

    public func addCompletion(_ completion: @escaping (Error?) -> Void) {
        completions.append(completion)
    }

    deinit {
        if !isCompleted { fatalError("RealtimeTransaction requires for performing") }
    }
}

enum Nodes {
    static let modelVersion = RealtimeNode(rawValue: "__mv")
    static let links = RealtimeNode(rawValue: "__links")
    static let items = RealtimeNode(rawValue: "__itms")
}
