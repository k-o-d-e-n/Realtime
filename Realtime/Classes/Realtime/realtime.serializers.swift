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
