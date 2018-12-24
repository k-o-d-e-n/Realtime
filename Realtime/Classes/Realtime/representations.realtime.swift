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
    let source: String
    let payload: (raw: RealtimeDataValue?, user: [String: RealtimeDataValue]?) // TODO: ReferenceRepresentation is not responds to payload (may be)

    init(ref: String, payload: (raw: RealtimeDataValue?, user: [String: RealtimeDataValue]?)) {
        self.source = ref
        self.payload = payload
    }

    func defaultRepresentation() throws -> Any {
        var v: [String: RealtimeDataValue] = [InternalKeys.source.stringValue: source]
        var valuePayload: [String: RealtimeDataValue] = [:]
        if let rw = payload.raw {
            valuePayload[InternalKeys.raw.rawValue] = rw
        }
        if let pl = payload.user {
            valuePayload[InternalKeys.payload.rawValue] = pl
        }
        v[InternalKeys.value.rawValue] = valuePayload
        return v
    }

    init(data: RealtimeDataProtocol, exactly: Bool) throws {
        guard
            let ref: String = try InternalKeys.source.stringValue.map(from: data)
        else
            { throw RealtimeError(initialization: ReferenceRepresentation.self, data) }
        let valueData = InternalKeys.value.child(from: data)
        self.source = ref
        self.payload = (try valueData.rawValue(), try valueData.payload())
    }
}
extension ReferenceRepresentation {
    func make<V: RealtimeValue>(fromAnchor node: Node = .root, options: [ValueOption: Any]) -> V {
        var options = options
        options[.rawValue] = payload.raw
        if let pl = payload.user {
            options[.userPayload] = pl
        }
        return V(in: node.child(with: source), options: options)
    }
}

/// Defines relation type.
/// Associated value is path to relation property
///
/// - **oneToOne**: Defines 'one to one' relation type.
/// `String` value is path to property from owner object
/// - **oneToMany**: Defines 'one to many' relation type.
/// `String` value is path to property from owner object
public enum RelationMode {
    case oneToOne(String)
    case oneToMany(String)
    case manyToMany(String)

    var propertyPath: String {
        switch self {
        case .oneToOne(let p), .oneToMany(let p), .manyToMany(let p):
            return p
        }
    }

    func path(for relatedValueNode: Node) -> String {
        switch self {
        case .oneToOne(let p): return p
        case .oneToMany(let p), .manyToMany(let p):
            return p + "/" + relatedValueNode.key
        }
    }
}

public struct RelationRepresentation: RealtimeDataRepresented, RealtimeDataValueRepresented {
    /// Path to related object
    let targetPath: String
    /// Property of related object that represented this relation
    let relatedProperty: String
    let payload: (raw: RealtimeDataValue?, user: [String: RealtimeDataValue]?)

    init(path: String, property: String, payload: (raw: RealtimeDataValue?, user: [String: RealtimeDataValue]?)) {
        self.targetPath = path
        self.relatedProperty = property
        self.payload = payload
    }

    enum CodingKeys: String, CodingKey {
        case targetPath = "t_pth"
        case relatedProperty = "r_prop"
    }

    public func defaultRepresentation() throws -> Any {
        var v: [String: RealtimeDataValue] = [CodingKeys.targetPath.rawValue: targetPath,
                                              CodingKeys.relatedProperty.rawValue: relatedProperty]
        var valuePayload: [String: RealtimeDataValue] = [:]
        if let rw = payload.raw {
            valuePayload[InternalKeys.raw.rawValue] = rw
        }
        if let pl = payload.user {
            valuePayload[InternalKeys.payload.rawValue] = pl
        }
        v[InternalKeys.value.rawValue] = valuePayload
        return v
    }

    public init(data: RealtimeDataProtocol, exactly: Bool) throws {
        guard
            let path: String = try CodingKeys.targetPath.map(from: data),
            let property: String = try CodingKeys.relatedProperty.map(from: data)
        else { throw RealtimeError(initialization: RelationRepresentation.self, data) }

        let valueData = InternalKeys.value.child(from: data)
        self.targetPath = path
        self.relatedProperty = property
        self.payload = (try valueData.rawValue(), try valueData.payload())
    }
}
extension RelationRepresentation {
    func make<V: RealtimeValue>(fromAnchor node: Node, options: [ValueOption: Any]) -> V {
        var options = options
        options[.rawValue] = payload.raw
        if let pl = payload.user {
            options[.userPayload] = pl
        }
        return V(in: node.child(with: targetPath), options: options)
    }
}

struct SourceLink: RealtimeDataRepresented, RealtimeDataValueRepresented, Codable {
    let links: [String]
    let id: String

    init(id: String, links: [String]) {
        self.id = id
        self.links = links
    }

    func defaultRepresentation() throws -> Any {
        return links
    }

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
                return try items.reduce([:], { (res, link) -> [String: Any] in
                    var res = res
                    res[link.id] = try link.defaultRepresentation()
                    return res
                })
            },
            decoding: { (data) -> [SourceLink] in
                return try data.map(SourceLink.init)
            }
        )
    }
}
