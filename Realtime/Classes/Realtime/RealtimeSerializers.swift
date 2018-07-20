//
//  RealtimeSerializers.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 09/05/2017.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation
import FirebaseDatabase

// TODO: View transformers in ObjectMapper as example implementation serializers

public protocol HasDefaultLiteral {
    init()
}

public protocol FireDataValue: FireDataRepresented {}
extension FireDataValue {
    public var localValue: Any? { return self }
    public init(firData: FireDataProtocol) throws {
        guard let v = firData.value as? Self else {
            throw RealtimeError("Failed data for type: \(Self.self)")
        }

        self = v
    }
}

extension Optional: FireDataValue, FireDataRepresented where Wrapped: FireDataValue {
    public var localValue: Any? { return self?.localValue }
    public init(firData: FireDataProtocol) throws {
        self = firData.value as? Wrapped
    }
}
extension Array: FireDataValue where Element: FireDataValue {}
extension Dictionary: FireDataValue where Key: FireDataValue, Value: FireDataValue {}

extension Optional  : HasDefaultLiteral { public init() { self = .none } }
extension Bool      : HasDefaultLiteral, FireDataValue {}
extension Int       : HasDefaultLiteral, FireDataValue {}
extension Double    : HasDefaultLiteral, FireDataValue {}
extension Float     : HasDefaultLiteral, FireDataValue {}
extension Int8      : HasDefaultLiteral, FireDataValue {}
extension Int16     : HasDefaultLiteral, FireDataValue {}
extension Int32     : HasDefaultLiteral, FireDataValue {}
extension Int64     : HasDefaultLiteral, FireDataValue {}
extension UInt      : HasDefaultLiteral, FireDataValue {}
extension UInt8     : HasDefaultLiteral, FireDataValue {}
extension UInt16    : HasDefaultLiteral, FireDataValue {}
extension UInt32    : HasDefaultLiteral, FireDataValue {}
extension UInt64    : HasDefaultLiteral, FireDataValue {}
extension String    : HasDefaultLiteral, FireDataValue {}
extension Data      : HasDefaultLiteral {}
extension Array     : HasDefaultLiteral {}
extension Dictionary: HasDefaultLiteral {}

extension Dictionary: MutableDataRepresented {//} where Key: MutableDataRepresented, Value: MutableDataRepresented {
    private struct Error: Swift.Error {
        var localizedDescription: String { return "Data could not convert to dictionary" }
    }
    public var localValue: Any? {
        return self
//        return reduce(into: [:], { (res, elem) in
//            res[elem.key.localValue] = elem.value.localValue
//        })
    }

    public init(data: MutableData) throws {
        guard let v = data.value as? [Key: Value] else { throw Error() }

        self = v
    }
}

extension Array: MutableDataRepresented where Element: FireDataRepresented {
    private struct Error: Swift.Error {
        var localizedDescription: String { return "Data could not convert to array" }
    }
    public var localValue: Any? { return map { $0.localValue } }

    public init(data: MutableData) throws {
        self = try data.children.map { try Element(firData: unsafeBitCast($0 as AnyObject, to: MutableData.self)) }
    }
}

// MARK: Serializer

public protocol _Serializer {
    associatedtype Entity: HasDefaultLiteral
    associatedtype SerializationResult
    static func deserialize(_ entity: DataSnapshot) -> Entity
    static func serialize(_ entity: Entity) -> SerializationResult
}

public class Serializer<Entity: HasDefaultLiteral>: _Serializer {
    public class func deserialize(_ entity: DataSnapshot) -> Entity {
        return (entity.value as? Entity) ?? Entity()
    }
    
    public class func serialize(_ entity: Entity) -> Any? {
        return entity
    }
}

public class FireDataValueSerializer<V: FireDataValue>: _Serializer {
    public static func deserialize(_ entity: DataSnapshot) -> V? {
        return try? V(firData: entity)
    }
    public static func serialize(_ entity: V?) -> Any? {
        return entity.localValue
    }
}

public class ArraySerializer<Base: _Serializer>: _Serializer {
    public class func deserialize(_ entity: DataSnapshot) -> [Base.Entity] {
        guard entity.hasChildren() else { return Entity() }
        
        return entity.children.map { Base.deserialize(unsafeBitCast($0 as AnyObject, to: DataSnapshot.self)) }
    }
    
    public class func serialize(_ entity: [Base.Entity]) -> [Base.SerializationResult] {
        return entity.map(Base.serialize)
    }
}

// MARK: System types

public class DateSerializer: _Serializer {
    public class func serialize(_ entity: Date?) -> TimeInterval? {
        return entity?.timeIntervalSince1970
    }
    
    public class func deserialize(_ entity: DataSnapshot) -> Date? {
        guard entity.exists() else { return nil }
        
        return Date(timeIntervalSince1970: entity.value as! TimeInterval)
    }
}

public class URLSerializer: _Serializer {
    public class func serialize(_ entity: URL?) -> String? {
        return entity?.absoluteString
    }
    
    public class func deserialize(_ entity: DataSnapshot) -> URL? {
        guard entity.exists() else { return nil }
        
        return URL(string: entity.value as! String)
    }
}

public class OptionalEnumSerializer<EnumType: RawRepresentable>: _Serializer {
    public class func deserialize(_ entity: DataSnapshot) -> EnumType? {
        guard entity.exists(), let val = entity.value as? EnumType.RawValue else { return nil }
        
        return EnumType(rawValue: val)
    }
    
    public class func serialize(_ entity: EnumType?) -> EnumType.RawValue? {
        return entity?.rawValue
    }
}

public class EnumSerializer<EnumType: RawRepresentable & HasDefaultLiteral>: _Serializer {
    public class func deserialize(_ entity: DataSnapshot) -> EnumType {
        guard entity.exists(), let val = entity.value as? EnumType.RawValue else { return EnumType() }

        return EnumType(rawValue: val) ?? EnumType()
    }

    public class func serialize(_ entity: EnumType) -> EnumType.RawValue? {
        return entity.rawValue
    }
}

public class CodableSerializer<T: Codable & HasDefaultLiteral>: _Serializer {
    public class func serialize(_ entity: T) -> Any? {
        let data = try! JSONEncoder().encode(entity)
        return try? JSONSerialization.jsonObject(with: data, options: .allowFragments)
    }

    public class func deserialize(_ entity: DataSnapshot) -> T {
        return (try? T(from: entity)) ?? T()
    }
}

// MARK: Containers

class SourceLinkArraySerializer: _Serializer {
    class func deserialize(_ entity: DataSnapshot) -> [SourceLink] {
        guard entity.exists() else { return Entity() }
        
        return entity.children.map { SourceLink(snapshot: unsafeBitCast($0 as AnyObject, to: DataSnapshot.self)) }.compactMap { $0 }
    }
    
    class func serialize(_ entity: [SourceLink]) -> [String: Any] {
        return entity.reduce([:], { (res, link) -> [String: Any] in
            var res = res
            res[link.id] = link.localValue
            return res
        })
    }
}

class DataSnapshotRepresentedSerializer<L: DataSnapshotRepresented>: _Serializer {
    class func deserialize(_ entity: DataSnapshot) -> L? { return L(snapshot: entity) }
    class func serialize(_ entity: L?) -> Any? { return entity.flatMap { $0.localValue } }
}

public class LinkableValueSerializer<V: RealtimeValue>: _Serializer {
    public static func deserialize(_ entity: DataSnapshot) -> V? {
        return DataSnapshotRepresentedSerializer<Reference>.deserialize(entity)?.make()
    }
    public static func serialize(_ entity: V?) -> Any? {
        return entity?.makeReference().localValue
    }
}

public class RelationableValueSerializer<V: RealtimeValue>: _Serializer {
    public static func deserialize(_ entity: DataSnapshot) -> (String, V)? {
        guard let relation = DataSnapshotRepresentedSerializer<Relation>.deserialize(entity) else { return nil }
        return (relation.sourceID, relation.ref.make())
    }
    public static func serialize(_ entity: (String, V)?) -> Any? {
        return entity.flatMap { $1.makeRelation(use: $0).localValue }
    }
}

/// --------------------------- DataSnapshot Decoder ------------------------------

extension DataSnapshot: Decoder {
    public var codingPath: [CodingKey] {
        return []
    }

    public var userInfo: [CodingUserInfoKey : Any] {
        return [CodingUserInfoKey(rawValue: "ref")!: ref]
    }

    public func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        return KeyedDecodingContainer(DataSnapshotDecodingContainer(snapshot: self))
    }

    public func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        return DataSnapshotUnkeyedDecodingContainer(snapshot: self)
    }

    public func singleValueContainer() throws -> SingleValueDecodingContainer {
        return DataSnapshotSingleValueContainer(snapshot: self)
    }
}

fileprivate struct DataSnapshotSingleValueContainer: SingleValueDecodingContainer {
    let snapshot: DataSnapshot
    var codingPath: [CodingKey] { return snapshot.codingPath }

    func decodeNil() -> Bool {
        if let v = snapshot.value {
            return v is NSNull
        }
        return true
    }

    private func _decode<T>(_ type: T.Type) throws -> T {
        guard case let v as T = snapshot.value else {
            throw DecodingError.valueNotFound(T.self, DecodingError.Context(codingPath: codingPath, debugDescription: snapshot.debugDescription))
        }
        return v
    }

    func decode(_ type: Bool.Type) throws -> Bool { return try _decode(type) }
    func decode(_ type: Int.Type) throws -> Int { return try _decode(type) }
    func decode(_ type: Int8.Type) throws -> Int8 { return try _decode(type) }
    func decode(_ type: Int16.Type) throws -> Int16 { return try _decode(type) }
    func decode(_ type: Int32.Type) throws -> Int32 { return try _decode(type) }
    func decode(_ type: Int64.Type) throws -> Int64 { return try _decode(type) }
    func decode(_ type: UInt.Type) throws -> UInt { return try _decode(type) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { return try _decode(type) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { return try _decode(type) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { return try _decode(type) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { return try _decode(type) }
    func decode(_ type: Float.Type) throws -> Float { return try _decode(type) }
    func decode(_ type: Double.Type) throws -> Double { return try _decode(type) }
    func decode(_ type: String.Type) throws -> String { return try _decode(type) }
    func decode<T>(_ type: T.Type) throws -> T where T : Decodable { return try T(from: snapshot) }
}

fileprivate struct DataSnapshotUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    let snapshot: DataSnapshot
    let enumerator: NSEnumerator

    init(snapshot: DataSnapshot) {
        self.snapshot = snapshot
        self.enumerator = snapshot.children
        self.currentIndex = 0
    }

    var codingPath: [CodingKey] { return snapshot.codingPath }
    var count: Int? { return Int(snapshot.childrenCount) }
    var isAtEnd: Bool { return currentIndex >= count! }
    var currentIndex: Int

    mutating func decodeNil() throws -> Bool {
        if let value = try nextDecoder().value {
            return value is NSNull
        }
        return true
    }

    private mutating func nextDecoder() throws -> DataSnapshot {
        guard case let next as DataSnapshot = enumerator.nextObject() else {
            throw DecodingError.dataCorruptedError(in: self, debugDescription: snapshot.debugDescription)
        }
        currentIndex += 1
        return next
    }

    private mutating func _decode<T>(_ type: T.Type) throws -> T {
        let next = try nextDecoder()
        guard case let v as T = next.value else {
            throw DecodingError.valueNotFound(T.self, DecodingError.Context(codingPath: [DataSnapshot._CodingKey(intValue: currentIndex)!], debugDescription: next.debugDescription))
        }
        return v
    }

    mutating func decode(_ type: Bool.Type) throws -> Bool { return try _decode(type) }
    mutating func decode(_ type: Int.Type) throws -> Int { return try _decode(type) }
    mutating func decode(_ type: Int8.Type) throws -> Int8 { return try _decode(type) }
    mutating func decode(_ type: Int16.Type) throws -> Int16 { return try _decode(type) }
    mutating func decode(_ type: Int32.Type) throws -> Int32 { return try _decode(type) }
    mutating func decode(_ type: Int64.Type) throws -> Int64 { return try _decode(type) }
    mutating func decode(_ type: UInt.Type) throws -> UInt { return try _decode(type) }
    mutating func decode(_ type: UInt8.Type) throws -> UInt8 { return try _decode(type) }
    mutating func decode(_ type: UInt16.Type) throws -> UInt16 { return try _decode(type) }
    mutating func decode(_ type: UInt32.Type) throws -> UInt32 { return try _decode(type) }
    mutating func decode(_ type: UInt64.Type) throws -> UInt64 { return try _decode(type) }
    mutating func decode(_ type: Float.Type) throws -> Float { return try _decode(type) }
    mutating func decode(_ type: Double.Type) throws -> Double { return try _decode(type) }
    mutating func decode(_ type: String.Type) throws -> String { return try _decode(type) }
    mutating func decode<T>(_ type: T.Type) throws -> T where T : Decodable { return try T(from: try nextDecoder()) }

    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type)
        throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        return try nextDecoder().container(keyedBy: type)
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer { return try nextDecoder().unkeyedContainer() }
    mutating func superDecoder() throws -> Decoder { return snapshot }
}

struct DataSnapshotDecodingContainer<K: CodingKey>: KeyedDecodingContainerProtocol {
    typealias Key = K
    let snapshot: DataSnapshot

    var codingPath: [CodingKey] { return [] }
    var allKeys: [Key] { return snapshot.children.compactMap { Key(stringValue: ($0 as! DataSnapshot).key) } }

    private func childDecoder(forKey key: Key) throws -> DataSnapshot {
        guard contains(key) else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: [key], debugDescription: snapshot.debugDescription))
        }
        return snapshot.childSnapshot(forPath: key.stringValue)
    }

    private func _decode<T>(_ type: T.Type, forKey key: Key) throws -> T {
        let child = try childDecoder(forKey: key)
        guard case let v as T = child.value else {
            throw DecodingError.valueNotFound(T.self, DecodingError.Context(codingPath: [key], debugDescription: child.debugDescription))
        }
        return v
    }

    func contains(_ key: Key) -> Bool {
        return snapshot.hasChild(key.stringValue)
    }

    func decodeNil(forKey key: Key) throws -> Bool { return try childDecoder(forKey: key).value is NSNull }
    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { return try _decode(type, forKey: key) }
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int { return try _decode(type, forKey: key) }
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { return try _decode(type, forKey: key) }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { return try _decode(type, forKey: key) }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { return try _decode(type, forKey: key) }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { return try _decode(type, forKey: key) }
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { return try _decode(type, forKey: key) }
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { return try _decode(type, forKey: key) }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { return try _decode(type, forKey: key) }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { return try _decode(type, forKey: key) }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { return try _decode(type, forKey: key) }
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float { return try _decode(type, forKey: key) }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { return try _decode(type, forKey: key) }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { return try _decode(type, forKey: key) }
    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable {
        return try T(from: childDecoder(forKey: key))
    }
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        return try childDecoder(forKey: key).container(keyedBy: type)
    }
    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        return try childDecoder(forKey: key).unkeyedContainer()
    }
    func superDecoder() throws -> Decoder { return snapshot }
    func superDecoder(forKey key: Key) throws -> Decoder { return snapshot }
}
extension DataSnapshot {
    struct _CodingKey: CodingKey {
        internal var intValue: Int?
        internal init?(intValue: Int) {
            self.intValue = intValue
            self.stringValue = String(intValue)
        }
        internal var stringValue: String
        internal init?(stringValue: String) {
            self.stringValue = stringValue
        }
    }
}
