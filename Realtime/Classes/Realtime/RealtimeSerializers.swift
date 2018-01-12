//
//  RealtimeSerializers.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 09/05/2017.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation
import FirebaseDatabase

// TODO: Try move to Codable

// TODO: View transformers in ObjectMapper as example implementation serializers

protocol Initializable {
    static var defValue: Self { get }
}

extension Bool: Initializable {
    static var defValue: Bool { return false }
}

extension Optional: Initializable {
    static var defValue: Optional { return Optional<Wrapped>(nilLiteral:()) }
}

extension Array: Initializable {
    static var defValue: [Element] { return [Element]() }
}

extension Dictionary: Initializable {
    static var defValue: [Key: Value] { return [Key: Value]() }
}

extension String: Initializable {
    static var defValue: String { return "" }
}

extension Data: Initializable {
    static var defValue: Data { return Data() }
}

protocol _Serializer: class {
    associatedtype Entity: Initializable
    static func deserialize(entity: DataSnapshot) -> Entity
    static func serialize(entity: Entity) -> Any?
}

class Serializer<Entity: Initializable>: _Serializer {
    class func deserialize(entity: DataSnapshot) -> Entity {
        guard entity.exists() else { return Entity.defValue }
        
        return entity.value as! Entity
    }
    
    class func serialize(entity: Entity) -> Any? {
        return entity
    }
}

class ArraySerializer<Base: _Serializer>: _Serializer {
    class func deserialize(entity: DataSnapshot) -> [Base.Entity] {
        guard entity.hasChildren() else { return Entity.defValue }
        
        return entity.children.map { Base.deserialize(entity: unsafeBitCast($0 as AnyObject, to: DataSnapshot.self)) }
    }
    
    class func serialize(entity: [Base.Entity]) -> Any? {
        return entity.map { Base.serialize(entity: $0) }
    }
}

// MARK: System types

class DateSerializer: _Serializer {
    class func serialize(entity: Date?) -> Any? {
        return entity?.timeIntervalSince1970
    }
    
    class func deserialize(entity: DataSnapshot) -> Date? {
        guard entity.exists() else { return nil }
        
        return Date(timeIntervalSince1970: entity.value as! TimeInterval)
    }
}

class URLSerializer: _Serializer {
    class func serialize(entity: URL?) -> Any? {
        return entity?.absoluteString
    }
    
    class func deserialize(entity: DataSnapshot) -> URL? {
        guard entity.exists() else { return nil }
        
        return URL(string: entity.value as! String)
    }
}

class EnumSerializer<EnumType: RawRepresentable>: _Serializer {
    class func deserialize(entity: DataSnapshot) -> EnumType? {
        guard entity.exists(), let val = entity.value as? EnumType.RawValue else { return nil }
        
        return EnumType(rawValue: val)
    }
    
    class func serialize(entity: EnumType?) -> Any? {
        return entity?.rawValue
    }
}

// MARK: Containers

class RealtimeLinkArraySerializer: _Serializer {
    class func deserialize(entity: DataSnapshot) -> [RealtimeLink] {
        guard entity.exists() else { return Entity.defValue }
        
        return entity.children.map { RealtimeLink(snapshot: unsafeBitCast($0 as AnyObject, to: DataSnapshot.self)) }.flatMap { $0 }
    }
    
    class func serialize(entity: [RealtimeLink]) -> Any? {
        return entity.reduce([:], { (res, link) -> [String: Any] in
            var res = res
            res[link.id] = link.dbValue
            return res
        })
    }
}

class RealtimeLinkSourceSerializer: _Serializer {
    class func deserialize(entity: DataSnapshot) -> RealtimeLink? { return RealtimeLink(snapshot: entity) }
    class func serialize(entity: RealtimeLink?) -> Any? { return entity.map { [$0.id: $0.dbValue] } }
}
class RealtimeLinkSerializer: _Serializer {
    class func deserialize(entity: DataSnapshot) -> RealtimeLink? { return RealtimeLink(snapshot: entity) }
    class func serialize(entity: RealtimeLink?) -> Any? { return entity.map { $0.dbValue } }
}

//class RealtimeLinkTargetSerializer: _Serializer {
//    class func deserialize(entity: DataSnapshot) -> RealtimeLink? { return RealtimeLink(snapshot: entity) }
//    class func serialize(entity: RealtimeLink?) -> Any? { return entity.map { [$0.id: $0.targetValue] } }
//}
