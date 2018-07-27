//
//  RealtimeSerializers.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 09/05/2017.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation
import FirebaseDatabase

// MARK: Serializer

@available(*, deprecated: 0.3.7, message: "Use Representer instead")
public protocol _Serializer {
    associatedtype Entity: HasDefaultLiteral
    associatedtype SerializationResult
    static func deserialize(_ entity: FireDataProtocol) -> Entity
    static func serialize(_ entity: Entity) -> SerializationResult
}

public class Serializer<Entity: HasDefaultLiteral>: _Serializer {
    public class func deserialize(_ entity: FireDataProtocol) -> Entity {
        return (entity.value as? Entity) ?? Entity()
    }
    
    public class func serialize(_ entity: Entity) -> Any? {
        return entity
    }
}

public class FireDataValueSerializer<V: FireDataValue>: _Serializer {
    public static func deserialize(_ entity: FireDataProtocol) -> V? {
        return try? V(fireData: entity)
    }
    public static func serialize(_ entity: V?) -> Any? {
        return entity
    }
}

public class ArraySerializer<Base: _Serializer>: _Serializer {
    public class func deserialize(_ entity: FireDataProtocol) -> [Base.Entity] {
        guard entity.hasChildren() else { return Entity() }
        
        return entity.map(Base.deserialize)
    }
    
    public class func serialize(_ entity: [Base.Entity]) -> [Base.SerializationResult] {
        return entity.map(Base.serialize)
    }
}

// MARK: Containers

class SourceLinkArraySerializer: _Serializer {
    class func deserialize(_ entity: FireDataProtocol) -> [SourceLink] {
        guard entity.exists() else { return Entity() }
        
        return (try? entity.map(SourceLink.init)) ?? []
    }
    
    class func serialize(_ entity: [SourceLink]) -> [String: Any] {
        return entity.reduce([:], { (res, link) -> [String: Any] in
            var res = res
            res[link.id] = link.fireValue
            return res
        })
    }
}

class DataSnapshotRepresentedSerializer<L: FireDataRepresented & FireDataValueRepresented>: _Serializer {
    class func deserialize(_ entity: FireDataProtocol) -> L? { return try? L(fireData: entity) }
    class func serialize(_ entity: L?) -> Any? { return entity.flatMap { $0.fireValue } }
}
