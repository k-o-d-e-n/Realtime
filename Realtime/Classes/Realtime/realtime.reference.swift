//
//  RealtimeLinks.swift
//  Realtime
//
//  Created by Denis Koryttsev on 16/03/2018.
//

import Foundation


public enum ReferenceMode {
    case fullPath
    case key(from: Node)
}

/// Link value describing reference to some location of database.
struct ReferenceRepresentation: FireDataRepresented, FireDataValueRepresented, Codable {
    let ref: String

    init(ref: String) {
        self.ref = ref
    }

    var fireValue: FireDataValue {
        let v: [String: FireDataValue] = [CodingKeys.ref.stringValue: ref]
        return v
    }
    init(fireData: FireDataProtocol, exactly: Bool) throws {
        guard let ref: String = CodingKeys.ref.stringValue.map(from: fireData) else { throw RealtimeError(initialization: ReferenceRepresentation.self, fireData) }
        self.ref = ref
    }
}
extension ReferenceRepresentation {
    func make<V: RealtimeValue>(in node: Node = .root, options: [ValueOption: Any]) -> V {
        return V(in: node.child(with: ref), options: options)
    }
}
extension RealtimeValue {
    func reference(from node: Node = .root) -> ReferenceRepresentation? {
        return self.node.map { ReferenceRepresentation(ref: $0.path(from: node)) }
    }
    func relation(use property: String) -> RelationRepresentation? {
        return node.map { RelationRepresentation(path: $0.rootPath, property: property) }
    }
}

public enum RelationMode {
    case oneToOne(String)
    case oneToMany(String)

    func path(for relatedValueNode: Node) -> String {
        switch self {
        case .oneToOne(let p): return p
        case .oneToMany(let p): return p + "/" + relatedValueNode.key
        }
    }
}

struct RelationRepresentation: FireDataRepresented, FireDataValueRepresented, Codable {
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

    init(fireData: FireDataProtocol, exactly: Bool) throws {
        guard fireData.hasChildren() else { // TODO: For test, remove!
            guard let val = fireData.value as? [String: String],
                let path = val[CodingKeys.targetPath.rawValue],
                let prop = val[CodingKeys.relatedProperty.rawValue]
            else {
                    throw RealtimeError(initialization: RelationRepresentation.self, fireData)
            }

            self.targetPath = path
            self.relatedProperty = prop
            return
        }
        guard
            let path: String = CodingKeys.targetPath.map(from: fireData),
            let property: String = CodingKeys.relatedProperty.map(from: fireData)
        else { throw RealtimeError(initialization: RelationRepresentation.self, fireData) }

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
    init(fireData: FireDataProtocol, exactly: Bool) throws {
        guard
            let id = fireData.node?.key,
            let links: [String] = fireData.flatMap()
        else { throw RealtimeError(initialization: SourceLink.self, fireData) }
        
        self.id = id
        self.links = links
    }
}

extension Representer where V == [SourceLink] {
    static var links: Representer<V> {
        return Representer(
            encoding: { (items) -> Any? in
                return items.reduce([:], { (res, link) -> [String: Any] in
                    var res = res
                    res[link.id] = link.fireValue
                    return res
                })
            },
            decoding: { (data) -> [SourceLink] in
                return try data.map(SourceLink.init)
            }
        )
    }
}
