//
//  RealtimeLinks.swift
//  Realtime
//
//  Created by Denis Koryttsev on 16/03/2018.
//

import Foundation

/// Link value describing reference to some location of database.

private enum LinkNodes {
    static let path = "pth"
    static let sourceID = "s_id"
}

struct Reference: FireDataRepresented, Codable {
    let ref: String

    init(ref: String) {
        self.ref = ref
    }

    var localValue: Any? { return [LinkNodes.path.rawValue: ref] }
    init(fireData: FireDataProtocol) throws {
        guard let ref: String = LinkNodes.path.map(from: fireData) else { throw RealtimeError("Fail") }
        self.ref = ref
    }
}
extension Reference {
    func make<V: RealtimeValue>(in node: Node = .root) -> V { return V(in: node.child(with: ref)) }
}
extension RealtimeValue {
    func reference(from node: Node = .root) -> Reference? {
        return self.node.map { Reference(ref: $0.path(from: node)) }
    }
    func relation(use property: String) -> Relation? {
        return node.map { Relation(path: $0.rootPath, property: property) }
    }
}

struct Relation: FireDataRepresented {
    /// Path to related object
    let targetPath: String
    /// Property of related object that represented this relation
    let relatedProperty: String

    init(path: String, property: String) {
        self.targetPath = path
        self.relatedProperty = property
    }

    enum CodingKeys: String {
        case targetPath = "t_pth"
        case relatedProperty = "r_prop"
    }

    var localValue: Any? { return [CodingKeys.targetPath.rawValue: targetPath,
                                   CodingKeys.relatedProperty.rawValue: relatedProperty] }

    init(fireData: FireDataProtocol) throws {
        guard
            let path: String = CodingKeys.targetPath.map(from: fireData),
            let property: String = CodingKeys.relatedProperty.map(from: fireData)
        else { throw RealtimeError("Fail") }

        self.targetPath = path
        self.relatedProperty = property
    }
}

public struct SourceLink: FireDataRepresented {
    let links: [String]
    let id: String

    init(id: String, links: [String]) {
        self.id = id
        self.links = links
    }

    public var localValue: Any? { return links }
    public init(fireData: FireDataProtocol) throws {
        guard
            let id = fireData.dataKey,
            let links: [String] = fireData.flatMap()
        else { throw RealtimeError("Fail") }
        
        self.id = id
        self.links = links
    }
}
