//
//  RealtimeLinks.swift
//  Realtime
//
//  Created by Denis Koryttsev on 16/03/2018.
//

import Foundation

/// Defines the method of obtaining path for reference
///
/// - fullPath: Obtains path from root node
/// - path: Obtains path from specified node
public enum ReferenceMode {
    case fullPath
    case path(from: Node)
}

/// Link value describing reference to some location of database.
struct ReferenceRepresentation: RealtimeDataRepresented, RealtimeDataValueRepresented {
    let ref: String
    let payload: (system: InternalPayload, user: [String: RealtimeDataValue]?)

    init(ref: String, payload: (system: InternalPayload, user: [String: RealtimeDataValue]?)) {
        self.ref = ref
        self.payload = payload
    }

    enum CodingKeys: String, CodingKey {
        case ref = "ref"
    }

    var rdbValue: RealtimeDataValue {
        var v: [String: RealtimeDataValue] = [CodingKeys.ref.stringValue: ref]
        if let mv = payload.system.version {
            v[InternalKeys.modelVersion.rawValue] = mv
        }
        if let rw = payload.system.raw {
            v[InternalKeys.raw.rawValue] = rw
        }
        if let pl = payload.user {
            v[InternalKeys.payload.rawValue] = pl
        }
        return v
    }
    init(data: RealtimeDataProtocol, exactly: Bool) throws {
        guard let ref: String = try CodingKeys.ref.stringValue.map(from: data) else { throw RealtimeError(initialization: ReferenceRepresentation.self, data) }
        self.ref = ref
        self.payload = ((try InternalKeys.modelVersion.map(from: data), try InternalKeys.raw.map(from: data)), try InternalKeys.payload.map(from: data))
    }
}
extension ReferenceRepresentation {
    func make<V: RealtimeValue>(in node: Node = .root, options: [ValueOption: Any]) -> V {
        var options = options
        options[.internalPayload] = payload.system
        if let pl = payload.user {
            options[.payload] = pl
        }
        return V(in: node.child(with: ref), options: options)
    }
}
extension RealtimeValue {
    func reference(from node: Node = .root) -> ReferenceRepresentation? {
        return self.node.map { ReferenceRepresentation(ref: $0.path(from: node), payload: (systemPayload, payload)) }
    }
    func relation(use property: String) -> RelationRepresentation? {
        return node.map { RelationRepresentation(path: $0.rootPath, property: property) }
    }
}

/// Defines relation type.
/// Associated value is path to relation property
///
/// - oneToOne: Defines 'one to one' relation type
/// - oneToMany: Defines 'one to many' relation type
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

struct RelationRepresentation: RealtimeDataRepresented, RealtimeDataValueRepresented, Codable {
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

    var rdbValue: RealtimeDataValue {
        let v: [String: RealtimeDataValue] = [CodingKeys.targetPath.rawValue: targetPath,
                                          CodingKeys.relatedProperty.rawValue: relatedProperty]
        return v
    }

    init(data: RealtimeDataProtocol, exactly: Bool) throws {
        guard
            let path: String = try CodingKeys.targetPath.map(from: data),
            let property: String = try CodingKeys.relatedProperty.map(from: data)
        else { throw RealtimeError(initialization: RelationRepresentation.self, data) }

        self.targetPath = path
        self.relatedProperty = property
    }
}

struct SourceLink: RealtimeDataRepresented, RealtimeDataValueRepresented, Codable {
    let links: [String]
    let id: String

    init(id: String, links: [String]) {
        self.id = id
        self.links = links
    }

    var rdbValue: RealtimeDataValue { return links }
    init(data: RealtimeDataProtocol, exactly: Bool) throws {
        guard
            let id = data.key
        else { throw RealtimeError(initialization: SourceLink.self, data) }
        
        self.id = id
        self.links = try data.unbox(as: [String].self)
    }
}

extension Representer where V == [SourceLink] {
    static var links: Representer<V> {
        return Representer(
            encoding: { (items) -> Any? in
                return items.reduce([:], { (res, link) -> [String: Any] in
                    var res = res
                    res[link.id] = link.rdbValue
                    return res
                })
            },
            decoding: { (data) -> [SourceLink] in
                return try data.map(SourceLink.init)
            }
        )
    }
}
