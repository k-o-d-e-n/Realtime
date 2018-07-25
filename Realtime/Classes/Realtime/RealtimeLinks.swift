//
//  RealtimeLinks.swift
//  Realtime
//
//  Created by Denis Koryttsev on 16/03/2018.
//

import Foundation

/// Link value describing reference to some location of database.

struct Reference: FireDataRepresented, FireDataValueRepresented, Codable {
    let ref: String

    init(ref: String) {
        self.ref = ref
    }

    var fireValue: FireDataValue {
        let v: [String: FireDataValue] = [CodingKeys.ref.stringValue: ref]
        return v
    }
    init(fireData: FireDataProtocol) throws {
        guard let ref: String = CodingKeys.ref.stringValue.map(from: fireData) else { throw RealtimeError("Fail") }
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

struct Relation: FireDataRepresented, FireDataValueRepresented, Codable {
    /// Path to related object
    let targetPath: String
    /// Property of related object that represented this relation
    let relatedProperty: String

    init(path: String, property: String) {
        self.targetPath = path
        self.relatedProperty = property
    }

    enum CodingKeys: String, CodingKey {
        case targetPath = "t_pth"
        case relatedProperty = "r_prop"
    }

    var fireValue: FireDataValue {
        let v: [String: FireDataValue] = [CodingKeys.targetPath.rawValue: targetPath,
                                          CodingKeys.relatedProperty.rawValue: relatedProperty]
        return v
    }

    init(fireData: FireDataProtocol) throws {
        guard
            let path: String = CodingKeys.targetPath.map(from: fireData),
            let property: String = CodingKeys.relatedProperty.map(from: fireData)
        else { throw RealtimeError("Fail") }

        self.targetPath = path
        self.relatedProperty = property
    }
}

struct SourceLink: FireDataRepresented, FireDataValueRepresented, Codable {
    let links: [String]
    let id: String

    init(id: String, links: [String]) {
        self.id = id
        self.links = links
    }

    var fireValue: FireDataValue { return links }
    init(fireData: FireDataProtocol) throws {
        guard
            let id = fireData.dataKey,
            let links: [String] = fireData.flatMap()
        else { throw RealtimeError("Fail") }
        
        self.id = id
        self.links = links
    }
}
