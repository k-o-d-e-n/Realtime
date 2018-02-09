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

public protocol Initializable {
    static var defValue: Self { get }
}

extension Bool: Initializable {
    public static var defValue: Bool { return false }
}

extension Int: Initializable {
    public static var defValue: Int { return 0 }
}

extension Optional: Initializable {
    public static var defValue: Optional { return Optional<Wrapped>(nilLiteral:()) }
}

extension Array: Initializable {
    public static var defValue: [Element] { return [Element]() }
}

extension Dictionary: Initializable {
    public static var defValue: [Key: Value] { return [Key: Value]() }
}

extension String: Initializable {
    public static var defValue: String { return "" }
}

extension Data: Initializable {
    public static var defValue: Data { return Data() }
}

public protocol _Serializer {
    associatedtype Entity: Initializable
    static func deserialize(entity: DataSnapshot) -> Entity
    static func serialize(entity: Entity) -> Any?
}

public class Serializer<Entity: Initializable>: _Serializer {
    public class func deserialize(entity: DataSnapshot) -> Entity {
        guard entity.exists() else { return Entity.defValue }
        
        return entity.value as! Entity
    }
    
    public class func serialize(entity: Entity) -> Any? {
        return entity
    }
}

public class ArraySerializer<Base: _Serializer>: _Serializer {
    public class func deserialize(entity: DataSnapshot) -> [Base.Entity] {
        guard entity.hasChildren() else { return Entity.defValue }
        
        return entity.children.map { Base.deserialize(entity: unsafeBitCast($0 as AnyObject, to: DataSnapshot.self)) }
    }
    
    public class func serialize(entity: [Base.Entity]) -> Any? {
        return entity.map { Base.serialize(entity: $0) }
    }
}

// MARK: System types

public class DateSerializer: _Serializer {
    public class func serialize(entity: Date?) -> Any? {
        return entity?.timeIntervalSince1970
    }
    
    public class func deserialize(entity: DataSnapshot) -> Date? {
        guard entity.exists() else { return nil }
        
        return Date(timeIntervalSince1970: entity.value as! TimeInterval)
    }
}

public class URLSerializer: _Serializer {
    public class func serialize(entity: URL?) -> Any? {
        return entity?.absoluteString
    }
    
    public class func deserialize(entity: DataSnapshot) -> URL? {
        guard entity.exists() else { return nil }
        
        return URL(string: entity.value as! String)
    }
}

public class EnumSerializer<EnumType: RawRepresentable>: _Serializer {
    public class func deserialize(entity: DataSnapshot) -> EnumType? {
        guard entity.exists(), let val = entity.value as? EnumType.RawValue else { return nil }
        
        return EnumType(rawValue: val)
    }
    
    public class func serialize(entity: EnumType?) -> Any? {
        return entity?.rawValue
    }
}

public class CodableSerializer<T: Codable & Initializable>: _Serializer {
    public class func serialize(entity: T) -> Any? {
        let data = try! JSONEncoder().encode(entity)
        return try! JSONDecoder().decode([String: Any?].self, from: data)
    }

    public class func deserialize(entity: DataSnapshot) -> T {
        return (try? T(from: entity)) ?? T.defValue
    }
}

// MARK: Containers

public class RealtimeLinkArraySerializer: _Serializer {
    public class func deserialize(entity: DataSnapshot) -> [RealtimeLink] {
        guard entity.exists() else { return Entity.defValue }
        
        return entity.children.map { RealtimeLink(snapshot: unsafeBitCast($0 as AnyObject, to: DataSnapshot.self)) }.flatMap { $0 }
    }
    
    public class func serialize(entity: [RealtimeLink]) -> Any? {
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


/// ---------------------------

// TODO: Avoid as!
extension DataSnapshot: Decoder {
    public var codingPath: [CodingKey] {
        return children.map { ($0 as! DataSnapshot).key }
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

struct DataSnapshotSingleValueContainer: SingleValueDecodingContainer {
    let snapshot: DataSnapshot

    var codingPath: [CodingKey] { return snapshot.children.map { ($0 as! DataSnapshot).key } }

    func decodeNil() -> Bool {
        if let v = snapshot.value {
            return v is NSNull
        }
        return true
    }

    func decode(_ type: Bool.Type) throws -> Bool {
        return snapshot.value as! Bool
    }

    func decode(_ type: Int.Type) throws -> Int {
        return snapshot.value as! Int
    }

    func decode(_ type: Int8.Type) throws -> Int8 {
        return snapshot.value as! Int8
    }

    func decode(_ type: Int16.Type) throws -> Int16 {
        return snapshot.value as! Int16
    }

    func decode(_ type: Int32.Type) throws -> Int32 {
        return snapshot.value as! Int32
    }

    func decode(_ type: Int64.Type) throws -> Int64 {
        return snapshot.value as! Int64
    }

    func decode(_ type: UInt.Type) throws -> UInt {
        return snapshot.value as! UInt
    }

    func decode(_ type: UInt8.Type) throws -> UInt8 {
        return snapshot.value as! UInt8
    }

    func decode(_ type: UInt16.Type) throws -> UInt16 {
        return snapshot.value as! UInt16
    }

    func decode(_ type: UInt32.Type) throws -> UInt32 {
        return snapshot.value as! UInt32
    }

    func decode(_ type: UInt64.Type) throws -> UInt64 {
        return snapshot.value as! UInt64
    }

    func decode(_ type: Float.Type) throws -> Float {
        return snapshot.value as! Float
    }

    func decode(_ type: Double.Type) throws -> Double {
        return snapshot.value as! Double
    }

    func decode(_ type: String.Type) throws -> String {
        return snapshot.value as! String
    }

    func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
        return try T(from: snapshot)
    }
}

struct DataSnapshotUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    let snapshot: DataSnapshot
    let enumerator: NSEnumerator

    init(snapshot: DataSnapshot) {
        self.snapshot = snapshot
        self.enumerator = snapshot.children
    }

    var codingPath: [CodingKey] { return snapshot.children.map { ($0 as! DataSnapshot).key } }

    var count: Int? { return Int(snapshot.childrenCount) }

    var isAtEnd: Bool { return currentIndex >= count! }

    var currentIndex: Int { return Int.max }

    mutating func decodeNil() throws -> Bool {
        if let value = (enumerator.nextObject() as? DataSnapshot)?.value {
            return value is NSNull
        }
        return true
    }

    mutating func decode(_ type: Bool.Type) throws -> Bool {
        return (enumerator.nextObject() as? DataSnapshot)?.value as! Bool
    }

    mutating func decode(_ type: Int.Type) throws -> Int {
        return (enumerator.nextObject() as? DataSnapshot)?.value as! Int
    }

    mutating func decode(_ type: Int8.Type) throws -> Int8 {
        return (enumerator.nextObject() as? DataSnapshot)?.value as! Int8
    }

    mutating func decode(_ type: Int16.Type) throws -> Int16 {
        return (enumerator.nextObject() as? DataSnapshot)?.value as! Int16
    }

    mutating func decode(_ type: Int32.Type) throws -> Int32 {
        return (enumerator.nextObject() as? DataSnapshot)?.value as! Int32
    }

    mutating func decode(_ type: Int64.Type) throws -> Int64 {
        return (enumerator.nextObject() as? DataSnapshot)?.value as! Int64
    }

    mutating func decode(_ type: UInt.Type) throws -> UInt {
        return (enumerator.nextObject() as? DataSnapshot)?.value as! UInt
    }

    mutating func decode(_ type: UInt8.Type) throws -> UInt8 {
        return (enumerator.nextObject() as? DataSnapshot)?.value as! UInt8
    }

    mutating func decode(_ type: UInt16.Type) throws -> UInt16 {
        return (enumerator.nextObject() as? DataSnapshot)?.value as! UInt16
    }

    mutating func decode(_ type: UInt32.Type) throws -> UInt32 {
        return (enumerator.nextObject() as? DataSnapshot)?.value as! UInt32
    }

    mutating func decode(_ type: UInt64.Type) throws -> UInt64 {
        return (enumerator.nextObject() as? DataSnapshot)?.value as! UInt64
    }

    mutating func decode(_ type: Float.Type) throws -> Float {
        return (enumerator.nextObject() as? DataSnapshot)?.value as! Float
    }

    mutating func decode(_ type: Double.Type) throws -> Double {
        return (enumerator.nextObject() as? DataSnapshot)?.value as! Double
    }

    mutating func decode(_ type: String.Type) throws -> String {
        return (enumerator.nextObject() as? DataSnapshot)?.value as! String
    }

    mutating func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
        guard let child = enumerator.nextObject() as? DataSnapshot else { fatalError() }
        return try T(from: child)
    }

    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        guard let child = enumerator.nextObject() as? DataSnapshot else { fatalError() }
        return try child.container(keyedBy: type)
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard let child = enumerator.nextObject() as? DataSnapshot else { fatalError() }
        return try child.unkeyedContainer()
    }

    mutating func superDecoder() throws -> Decoder {
        fatalError()
    }
}

struct DataSnapshotDecodingContainer<K: CodingKey>: KeyedDecodingContainerProtocol {
    typealias Key = K
    let snapshot: DataSnapshot

    var codingPath: [CodingKey] { return snapshot.codingPath }

    var allKeys: [Key] { return snapshot.children.flatMap { Key(stringValue: ($0 as! DataSnapshot).key) } }

    func contains(_ key: Key) -> Bool {
        return snapshot.hasChild(key.stringValue)
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        if contains(key) {
            return snapshot.childSnapshot(forPath: key.stringValue).value is NSNull
        }
        return true
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        return snapshot.childSnapshot(forPath: key.stringValue).value as! Bool
    }

    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
        return snapshot.childSnapshot(forPath: key.stringValue).value as! Int
    }

    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
        return snapshot.childSnapshot(forPath: key.stringValue).value as! Int8
    }

    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
        return snapshot.childSnapshot(forPath: key.stringValue).value as! Int16
    }

    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
        return snapshot.childSnapshot(forPath: key.stringValue).value as! Int32
    }

    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
        return snapshot.childSnapshot(forPath: key.stringValue).value as! Int64
    }

    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
        return snapshot.childSnapshot(forPath: key.stringValue).value as! UInt
    }

    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
        return snapshot.childSnapshot(forPath: key.stringValue).value as! UInt8
    }

    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
        return snapshot.childSnapshot(forPath: key.stringValue).value as! UInt16
    }

    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
        return snapshot.childSnapshot(forPath: key.stringValue).value as! UInt32
    }

    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
        return snapshot.childSnapshot(forPath: key.stringValue).value as! UInt64
    }

    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        return snapshot.childSnapshot(forPath: key.stringValue).value as! Float
    }

    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        return snapshot.childSnapshot(forPath: key.stringValue).value as! Double
    }

    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        return snapshot.childSnapshot(forPath: key.stringValue).value as! String
    }

    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable {
        return try T(from: snapshot.childSnapshot(forPath: key.stringValue))
    }

    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        return try snapshot.childSnapshot(forPath: key.stringValue).container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        return try snapshot.childSnapshot(forPath: key.stringValue).unkeyedContainer()
    }

    func superDecoder() throws -> Decoder {
        fatalError()
    }

    func superDecoder(forKey key: Key) throws -> Decoder {
        fatalError()
    }
}
extension String: CodingKey {
    public var intValue: Int? { return Int(self) }
    public init?(intValue: Int) {
        self.init(intValue)
    }
    public var stringValue: String { return self }
    public init?(stringValue: String) {
        self.init(stringValue)
    }
}


