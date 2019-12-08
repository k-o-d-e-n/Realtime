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
struct ReferenceRepresentation: RealtimeDataRepresented {
    let source: String
    let payload: (raw: RealtimeDatabaseValue?, user: RealtimeDatabaseValue?) // TODO: ReferenceRepresentation is not responds to payload (may be)

    init(ref: String, payload: (raw: RealtimeDatabaseValue?, user: RealtimeDatabaseValue?)) {
        self.source = ref
        self.payload = payload
    }

    func defaultRepresentation() throws -> RealtimeDatabaseValue {
        var v: [RealtimeDatabaseValue] = [RealtimeDatabaseValue((RealtimeDatabaseValue(InternalKeys.source.stringValue), RealtimeDatabaseValue(source)))]
        var valuePayload: [RealtimeDatabaseValue] = []
        if let rw = payload.raw {
            valuePayload.append(RealtimeDatabaseValue((RealtimeDatabaseValue(InternalKeys.raw.rawValue), RealtimeDatabaseValue(rw))))
        }
        if let pl = payload.user {
            valuePayload.append(RealtimeDatabaseValue((RealtimeDatabaseValue(InternalKeys.payload.rawValue), RealtimeDatabaseValue(pl))))
        }
        if valuePayload.count > 0 {
            v.append(RealtimeDatabaseValue((RealtimeDatabaseValue(InternalKeys.value.rawValue), RealtimeDatabaseValue(valuePayload))))
        }
        return RealtimeDatabaseValue(v)
    }

    func write(to transaction: Transaction, by node: Node) throws {
        transaction.addValue(source, by: node.child(with: InternalKeys.source))
        if let rw = payload.raw {
            transaction.addValue(rw, by: node.child(with: InternalKeys.value).child(with: InternalKeys.raw))
        }
        if let pl = payload.user {
            transaction.addValue(pl, by: node.child(with: InternalKeys.value).child(with: InternalKeys.payload))
        }
    }

    init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        self.source = try data.child(forPath: InternalKeys.source.stringValue).singleValueContainer().decode(String.self)
        let valueData = InternalKeys.value.child(from: data)
        self.payload = (try valueData.rawValue(), try valueData.payload())
    }
}
extension ReferenceRepresentation {
    func options(_ db: RealtimeDatabase?) -> RealtimeValueOptions {
        return RealtimeValueOptions(database: db, raw: payload.raw, payload: payload.user)
    }
}

/// Defines relation type.
/// Associated value is path to relation property
///
/// - **one**: Defines 'one to one' relation type.
/// `String` value is path to property from owner object
/// - **many**: Defines 'one to many' relation type.
/// `String` value is path to property from owner object
public enum RelationProperty {
    case one(name: String)
    case many(format: String)

    func path(for relatedValueNode: Node) -> String {
        switch self {
        case .one(let p): return p
        case .many(let f):
            #if !os(Linux)
                return String(format: f, relatedValueNode.key)
            #else
                return String(format: f, args: [relatedValueNode.key])
            #endif
        }
    }
}

#if os(Linux)
extension String {
    init(format: String, args: [String]) {
        var result = ""

		let appendCharacter = { (character: Character) in
		    result += String(character)
		}
		let appendArgument = { (argument: String?) in
		    result += (argument ?? "")
		}

		var indices = format.characters.indices
		var args = Array(args.reversed())

		while indices.count > 0 {
		    guard let currentIndex = indices.popFirst() else {
                        continue
		    }
		    let currentCharacter = format[currentIndex]
		    guard currentCharacter == "%" && indices.count > 0 else {
                        appendCharacter(currentCharacter)
			continue
		    }

		    guard let nextIndex = indices.popFirst() else {
                        continue
		    }
		    let nextCharacter = format[nextIndex]

		    guard nextCharacter != "%" else {
                        appendCharacter("%") // one % instead of %%
                        continue
		    }

		    guard nextCharacter == "@" else {
                        appendCharacter(nextCharacter)
                        continue
		    }

		    appendArgument(args.popLast())
		}

		self = result
    }
}
#endif

public struct RelationRepresentation: RealtimeDataRepresented {
    /// Path to related object
    let targetPath: String
    /// Property of related object that represented this relation
    let relatedProperty: String
    let payload: (raw: RealtimeDatabaseValue?, user: RealtimeDatabaseValue?)

    init(path: String, property: String, payload: (raw: RealtimeDatabaseValue?, user: RealtimeDatabaseValue?)) {
        self.targetPath = path
        self.relatedProperty = property
        self.payload = payload
    }

    enum CodingKeys: String, CodingKey {
        case targetPath = "t_pth"
        case relatedProperty = "r_prop"
    }

    public func defaultRepresentation() throws -> RealtimeDatabaseValue {
        var v: [RealtimeDatabaseValue] = [
            RealtimeDatabaseValue((RealtimeDatabaseValue(CodingKeys.targetPath.rawValue), RealtimeDatabaseValue(targetPath))),
            RealtimeDatabaseValue((RealtimeDatabaseValue(CodingKeys.relatedProperty.rawValue), RealtimeDatabaseValue(relatedProperty)))
        ]
        var valuePayload: [RealtimeDatabaseValue] = []
        if let rw = payload.raw {
            valuePayload.append(RealtimeDatabaseValue((RealtimeDatabaseValue(InternalKeys.raw.rawValue), RealtimeDatabaseValue(rw))))
        }
        if let pl = payload.user {
            valuePayload.append(RealtimeDatabaseValue((RealtimeDatabaseValue(InternalKeys.payload.rawValue), RealtimeDatabaseValue(pl))))
        }
        v.append(RealtimeDatabaseValue((RealtimeDatabaseValue(InternalKeys.value.rawValue), RealtimeDatabaseValue(valuePayload))))
        return RealtimeDatabaseValue(v)
    }

    public func write(to transaction: Transaction, by node: Node) throws {
        transaction.addValue(targetPath, by: node.child(with: CodingKeys.targetPath))
        transaction.addValue(relatedProperty, by: node.child(with: CodingKeys.relatedProperty))
        if let rw = payload.raw {
            transaction.addValue(rw, by: node.child(with: InternalKeys.value).child(with: InternalKeys.raw))
        }
        if let pl = payload.user {
            transaction.addValue(pl, by: node.child(with: InternalKeys.value).child(with: InternalKeys.payload))
        }
    }

    public init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        self.targetPath = try data.child(forPath: CodingKeys.targetPath.stringValue).singleValueContainer().decode(String.self)
        self.relatedProperty = try data.child(forPath: CodingKeys.relatedProperty.stringValue).singleValueContainer().decode(String.self)
        let valueData = InternalKeys.value.child(from: data)
        self.payload = (try valueData.rawValue(), try valueData.payload())
    }
}
extension RelationRepresentation {
    func options(_ db: RealtimeDatabase?) -> RealtimeValueOptions {
        return RealtimeValueOptions(database: db, raw: payload.raw, payload: payload.user)
    }
}

struct SourceLink: RealtimeDataRepresented, Codable {
    let links: [String]
    let id: String

    init(id: String, links: [String]) {
        self.id = id
        self.links = links
    }

    func defaultRepresentation() throws -> RealtimeDatabaseValue {
        return RealtimeDatabaseValue(links.map(RealtimeDatabaseValue.init(_:)))
    }

    init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        guard
            let id = data.key
        else { throw RealtimeError(initialization: SourceLink.self, data) }
        
        self.id = id
        let container = try data.singleValueContainer()
        self.links = try container.decode([String].self)
    }
}

extension Representer where V == [SourceLink] {
    static var links: Representer<V> {
        return Representer(
            encoding: { (items) -> RealtimeDatabaseValue? in
                return RealtimeDatabaseValue(try items.reduce(into: [], { (res, link) -> Void in
                    res.append(RealtimeDatabaseValue((RealtimeDatabaseValue(link.id), try link.defaultRepresentation())))
                }))
            },
            decoding: { (data) -> [SourceLink] in
                return try data.map(SourceLink.init)
            }
        )
    }
}
