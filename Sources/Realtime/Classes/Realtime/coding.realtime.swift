//
//  realtime.coding.swift
//  Realtime
//
//  Created by Denis Koryttsev on 25/07/2018.
//

import Foundation

// MARK: RealtimeDataProtocol ---------------------------------------------------------------

/// A type that contains data associated with database node.
public protocol RealtimeDataProtocol: Decoder, SingleValueDecodingContainer, CustomDebugStringConvertible, CustomStringConvertible {
    var database: RealtimeDatabase? { get }
    var storage: RealtimeStorage? { get }
    var node: Node? { get }
    var key: String? { get }
    var childrenCount: UInt { get }

    func makeIterator() -> AnyIterator<RealtimeDataProtocol>
    func exists() -> Bool
    func hasChildren() -> Bool
    func hasChild(_ childPathString: String) -> Bool
    func child(forPath path: String) -> RealtimeDataProtocol

    func asDatabaseValue() throws -> RealtimeDatabaseValue?
    func decode(_ type: Data.Type) throws -> Data
}
extension RealtimeDataProtocol {
    public func map<T>(_ transform: (RealtimeDataProtocol) throws -> T) rethrows -> [T] {
        return try makeIterator().map(transform)
    }
    public func compactMap<ElementOfResult>(_ transform: (RealtimeDataProtocol) throws -> ElementOfResult?) rethrows -> [ElementOfResult] {
        return try makeIterator().compactMap(transform)
    }
    public func forEach(_ body: (RealtimeDataProtocol) throws -> Swift.Void) rethrows {
        return try makeIterator().forEach(body)
    }
    public func reduce<Result>(_ initialResult: Result, nextPartialResult: (Result, RealtimeDataProtocol) throws -> Result) rethrows -> Result {
        return try makeIterator().reduce(initialResult, nextPartialResult)
    }
    public func reduce<Result>(into result: Result, updateAccumulatingResult: (inout Result, RealtimeDataProtocol) throws -> Void) rethrows -> Result {
        return try makeIterator().reduce(into: result, updateAccumulatingResult)
    }
}

struct _RealtimeCodingKey: CodingKey {
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
extension Decoder where Self: RealtimeDataProtocol {
    public var codingPath: [CodingKey] {
        return node?.map({ _RealtimeCodingKey(stringValue: $0.key)! }) ?? []
    }
    public var userInfo: [CodingUserInfoKey : Any] {
        return [
            CodingUserInfoKey(rawValue: "node")!: node as Any,
            CodingUserInfoKey(rawValue: "database")!: database as Any,
            CodingUserInfoKey(rawValue: "storage")!: storage as Any
        ]
    }

    public func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        return KeyedDecodingContainer(DataSnapshotDecodingContainer(snapshot: self))
    }
    public func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        return DataSnapshotUnkeyedDecodingContainer(snapshot: self)
    }
    public func singleValueContainer() throws -> SingleValueDecodingContainer { return self }

    fileprivate func childDecoder<Key: CodingKey>(forKey key: Key) throws -> RealtimeDataProtocol {
        guard hasChild(key.stringValue) else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(
                codingPath: compactMap({ $0.key.flatMap(_RealtimeCodingKey.init) }),
                debugDescription: debugDescription
            ))
        }
        return child(forPath: key.stringValue)
    }
}

fileprivate struct DataSnapshotUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    let snapshot: RealtimeDataProtocol
    let iterator: AnyIterator<RealtimeDataProtocol>

    init(snapshot: RealtimeDataProtocol & Decoder) {
        self.snapshot = snapshot
        self.iterator = snapshot.makeIterator()
        self.currentIndex = 0
    }

    var codingPath: [CodingKey] { return snapshot.codingPath }
    var count: Int? { return Int(snapshot.childrenCount) }
    var isAtEnd: Bool { return currentIndex >= count! }
    var currentIndex: Int

    mutating func decodeNil() throws -> Bool {
        return try nextDecoder().decodeNil()
    }

    private mutating func nextDecoder() throws -> RealtimeDataProtocol {
        guard let next = iterator.next() else {
            throw DecodingError.dataCorruptedError(in: self, debugDescription: snapshot.debugDescription)
        }
        currentIndex += 1
        return next
    }

    private mutating func _decode<T: Decodable>(_ type: T.Type) throws -> T {
        return try nextDecoder().decode(T.self)
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
    let snapshot: RealtimeDataProtocol

    var codingPath: [CodingKey] { return snapshot.node?.map({ _RealtimeCodingKey(stringValue: $0.key)! }) ?? [] }
    var allKeys: [Key] { return snapshot.compactMap { $0.node.flatMap { Key(stringValue: $0.key) } } }

    private func _decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let child = try snapshot.childDecoder(forKey: key)
        return try child.decode(T.self)
    }

    func contains(_ key: Key) -> Bool { return snapshot.hasChild(key.stringValue) }

    func decodeNil(forKey key: Key) throws -> Bool { return try !snapshot.hasChild(key.stringValue) || snapshot.childDecoder(forKey: key).decodeNil() }
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
        return try T(from: snapshot.childDecoder(forKey: key))
    }
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        return try snapshot.childDecoder(forKey: key).container(keyedBy: type)
    }
    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        return try snapshot.childDecoder(forKey: key).unkeyedContainer()
    }
    func superDecoder() throws -> Decoder { return snapshot }
    func superDecoder(forKey key: Key) throws -> Decoder { return snapshot }
}

protocol TransactionEncoderProtocol: Encoder {
    func boxNil()
    func box<T: ExpressibleByRealtimeDatabaseValue>(_ value: T)
    func boxNil(for key: String)
    func box<T: ExpressibleByRealtimeDatabaseValue>(_ value: T, key: String)
    func child(for key: String) -> TransactionEncoderProtocol
}
class DatabaseValueEncoder: TransactionEncoderProtocol {
    var codingPath: [CodingKey] { return [] }
    var userInfo: [CodingUserInfoKey : Any] { return [:] }

    var single: RealtimeDatabaseValue?
    var builder: RealtimeDatabaseValue.Dictionary = .init()
    var children: [String: DatabaseValueEncoder] = [:]

    init() {}

    func boxNil(for key: String) {}
    func boxNil() {}
    func box<T>(_ value: T) where T : ExpressibleByRealtimeDatabaseValue {
        self.single = RealtimeDatabaseValue(value)
    }
    func box<T>(_ value: T, key: String) where T : ExpressibleByRealtimeDatabaseValue {
        builder.setValue(value, forKey: key)
    }
    func child(for key: String) -> TransactionEncoderProtocol {
        let childStorage = DatabaseValueEncoder()
        children[key] = childStorage
        return childStorage
    }

    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
        return KeyedEncodingContainer<Key>(TransactionEncoder.KeyedContainer(storage: self))
    }
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        return TransactionEncoder.UnkeyedContainer(storage: self, count: 0)
    }
    func singleValueContainer() -> SingleValueEncodingContainer {
        return TransactionEncoder.SingleValueContainer(storage: self)
    }

    func build() -> RealtimeDatabaseValue {
        guard let single = self.single else {
            children.forEach { (key, child) in
                builder.setValue(child.build(), forKey: key)
            }
            return builder.build()
        }
        return single
    }
}
struct TransactionEncoder: TransactionEncoderProtocol {
    let node: Node
    let transaction: Transaction
    public var codingPath: [CodingKey] { return [] }

    public var userInfo: [CodingUserInfoKey : Any] {
        return [CodingUserInfoKey(rawValue: "transaction")!: transaction]
    }

    public func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
        return KeyedEncodingContainer(KeyedContainer(storage: self))
    }

    public func unkeyedContainer() -> UnkeyedEncodingContainer {
        return UnkeyedContainer(storage: self, count: 0)
    }

    public func singleValueContainer() -> SingleValueEncodingContainer {
        return SingleValueContainer(storage: self)
    }

    func boxNil() {
        transaction.removeValue(by: node)
    }

    func box<T>(_ value: T) where T : ExpressibleByRealtimeDatabaseValue {
        transaction.addValue(value, by: node)
    }

    func boxNil(for key: String) {
        transaction.removeValue(by: node.child(with: key))
    }

    func box<T>(_ value: T, key: String) where T : ExpressibleByRealtimeDatabaseValue {
        transaction.addValue(value, by: node.child(with: key))
    }

    func child(for key: String) -> TransactionEncoderProtocol {
        return TransactionEncoder(node: node.child(with: key), transaction: transaction)
    }

    struct SingleValueContainer: SingleValueEncodingContainer {
        typealias Encode<T: ExpressibleByRealtimeDatabaseValue> = (T) throws -> Void
        var storage: TransactionEncoderProtocol
        var codingPath: [CodingKey] { return [] }

        init(storage: TransactionEncoderProtocol) {
            self.storage = storage
        }

        mutating func encodeNil() throws { storage.boxNil() }
        mutating func encode(_ value: Bool) throws { storage.box(value) }
        mutating func encode(_ value: String) throws { storage.box(value) }
        mutating func encode(_ value: Double) throws { storage.box(value) }
        mutating func encode(_ value: Float) throws { storage.box(value) }
        mutating func encode(_ value: Int) throws { storage.box(Int64(value)) }
        mutating func encode(_ value: Int8) throws { storage.box(value) }
        mutating func encode(_ value: Int16) throws { storage.box(value) }
        mutating func encode(_ value: Int32) throws { storage.box(value) }
        mutating func encode(_ value: Int64) throws { storage.box(value) }
        mutating func encode(_ value: UInt) throws { storage.box(UInt64(value)) }
        mutating func encode(_ value: UInt8) throws { storage.box(value) }
        mutating func encode(_ value: UInt16) throws { storage.box(value) }
        mutating func encode(_ value: UInt32) throws { storage.box(value) }
        mutating func encode(_ value: UInt64) throws { storage.box(value) }
        mutating func encode<T>(_ value: T) throws where T : Encodable {
            try value.encode(to: storage)
        }
    }

    struct UnkeyedContainer: UnkeyedEncodingContainer {
        var storage: TransactionEncoderProtocol

        var codingPath: [CodingKey] { return [] }
        var count: Int = 0

        mutating func _encode<T: ExpressibleByRealtimeDatabaseValue>(_ value: T) {
            storage.box(value, key: String(count))
            count += 1
        }
        mutating func encodeNil() throws {
            storage.boxNil(for: String(count))
            count += 1
        }
        mutating func encode(_ value: Bool) throws { _encode(value) }
        mutating func encode(_ value: Int) throws { _encode(Int64(value)) }
        mutating func encode(_ value: String) throws { _encode(value) }
        mutating func encode(_ value: Double) throws { _encode(value) }
        mutating func encode(_ value: Float) throws { _encode(value) }
        mutating func encode(_ value: Int8) throws { _encode(value) }
        mutating func encode(_ value: Int16) throws { _encode(value) }
        mutating func encode(_ value: Int32) throws { _encode(value) }
        mutating func encode(_ value: Int64) throws { _encode(value) }
        mutating func encode(_ value: UInt) throws { _encode(UInt64(value)) }
        mutating func encode(_ value: UInt8) throws { _encode(value) }
        mutating func encode(_ value: UInt16) throws { _encode(value) }
        mutating func encode(_ value: UInt32) throws { _encode(value) }
        mutating func encode(_ value: UInt64) throws { _encode(value) }
        mutating func encode<T>(_ value: T) throws where T : Encodable {
            try value.encode(to: storage.child(for: String(count)))
        }
        mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
            return KeyedEncodingContainer(KeyedContainer(storage: storage.child(for: String(count))))
        }
        mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
            return UnkeyedContainer(storage: storage.child(for: String(count)), count: 0)
        }
        mutating func superEncoder() -> Encoder {
            return storage
        }
    }

    struct KeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
        var storage: TransactionEncoderProtocol
        var codingPath: [CodingKey] { return [] }

        mutating func encodeNil(forKey key: Key) throws { storage.boxNil(for: key.stringValue) }
        mutating func encode(_ value: Bool, forKey key: Key) throws { storage.box(value, key: key.stringValue) }
        mutating func encode(_ value: String, forKey key: Key) throws { storage.box(value, key: key.stringValue) }
        mutating func encode(_ value: Double, forKey key: Key) throws { storage.box(value, key: key.stringValue) }
        mutating func encode(_ value: Float, forKey key: Key) throws { storage.box(value, key: key.stringValue) }
        mutating func encode(_ value: Int, forKey key: Key) throws { storage.box(Int64(value), key: key.stringValue) }
        mutating func encode(_ value: Int8, forKey key: Key) throws { storage.box(value, key: key.stringValue) }
        mutating func encode(_ value: Int16, forKey key: Key) throws { storage.box(value, key: key.stringValue) }
        mutating func encode(_ value: Int32, forKey key: Key) throws { storage.box(value, key: key.stringValue) }
        mutating func encode(_ value: Int64, forKey key: Key) throws { storage.box(value, key: key.stringValue) }
        mutating func encode(_ value: UInt, forKey key: Key) throws { storage.box(UInt64(value), key: key.stringValue) }
        mutating func encode(_ value: UInt8, forKey key: Key) throws { storage.box(value, key: key.stringValue) }
        mutating func encode(_ value: UInt16, forKey key: Key) throws { storage.box(value, key: key.stringValue) }
        mutating func encode(_ value: UInt32, forKey key: Key) throws { storage.box(value, key: key.stringValue) }
        mutating func encode(_ value: UInt64, forKey key: Key) throws { storage.box(value, key: key.stringValue) }
        mutating func encode<T>(_ value: T, forKey key: Key) throws where T : Encodable {
            try value.encode(to: storage.child(for: key.stringValue))
        }
        mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
            return KeyedEncodingContainer(KeyedContainer<NestedKey>(storage: storage.child(for: key.stringValue)))
        }
        mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
            return UnkeyedContainer(storage: storage.child(for: key.stringValue), count: 0)
        }
        mutating func superEncoder() -> Encoder {
            return storage
        }
        mutating func superEncoder(forKey key: Key) -> Encoder {
            return storage
        }
    }
}


/// A type that represented someone value of Realtime database
public protocol RealtimeDataRepresented {
    /// Creates a new instance by decoding from the given data.
    ///
    /// This initializer throws an error if data does not correspond
    /// requirements of this type
    ///
    /// - Parameters:
    ///   - data: Realtime database data
    ///   - exactly: Indicates that data should be applied as is (for example, empty values will be set to `nil`).
    init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws

    /// Applies value of data snapshot
    ///
    /// - Parameters:
    ///   - data: Realtime database data
    ///   - exactly: Indicates that data should be applied as is (for example, empty values will be set to `nil`).
    ///               Pass `false` if data represents part of data (for example filtered list).
    mutating func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws
}
public extension RealtimeDataRepresented {
    init(data: RealtimeDataProtocol) throws {
        try self.init(data: data, event: .value)
    }
    mutating func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        self = try Self.init(data: data, event: event)
    }
    mutating func apply(_ data: RealtimeDataProtocol) throws {
        try apply(data, event: .value)
    }
}
public extension RealtimeDataRepresented where Self: Decodable {
    init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        try self.init(from: data)
    }
}

public protocol ExpressibleBySequence {
    associatedtype SequenceElement
    init<S: Sequence>(_ sequence: S) where S.Element == SequenceElement
}
extension Array: ExpressibleBySequence {
    public typealias SequenceElement = Element
}

// MARK: RealtimeDataValue ------------------------------------------------------------------

/// A type that can be initialized using with nothing.
public protocol HasDefaultLiteral {
    init()
}
/// Internal protocol to compare HasDefaultLiteral type.
public protocol _ComparableWithDefaultLiteral {
    /// Checks that argument is default.
    ///
    /// - Parameter lhs: Value is conformed HasDefaultLiteral
    /// - Returns: Comparison result
    static func _isDefaultLiteral(_ lhs: Self) -> Bool
}
extension _ComparableWithDefaultLiteral where Self: HasDefaultLiteral & Equatable {
    public static func _isDefaultLiteral(_ lhs: Self) -> Bool {
        return lhs == Self()
    }
}

public extension KeyedEncodingContainer {
    mutating func encodeNilIfDefault<T: HasDefaultLiteral & _ComparableWithDefaultLiteral & Encodable>(_ value: T, forKey key: K) throws {
        try T._isDefaultLiteral(value) ? encodeNil(forKey: key) : encode(value, forKey: key)
    }
    mutating func encodeIfNotDefault<T: HasDefaultLiteral & _ComparableWithDefaultLiteral & Encodable>(_ value: T, forKey key: K) throws {
        if !T._isDefaultLiteral(value) {
            try encode(value, forKey: key)
        }
    }
}
public extension UnkeyedEncodingContainer {
    mutating func encodeNilIfDefault<T: HasDefaultLiteral & _ComparableWithDefaultLiteral & Encodable>(_ value: T) throws {
        try T._isDefaultLiteral(value) ? encodeNil() : encode(value)
    }
    mutating func encodeIfNotDefault<T: HasDefaultLiteral & _ComparableWithDefaultLiteral & Encodable>(_ value: T) throws {
        if !T._isDefaultLiteral(value) {
            try encode(value)
        }
    }
}
public extension SingleValueEncodingContainer {
    mutating func encodeNilIfDefault<T: HasDefaultLiteral & _ComparableWithDefaultLiteral & Encodable>(_ value: T) throws {
        try T._isDefaultLiteral(value) ? encodeNil() : encode(value)
    }
    mutating func encodeIfNotDefault<T: HasDefaultLiteral & _ComparableWithDefaultLiteral & Encodable>(_ value: T) throws {
        if !T._isDefaultLiteral(value) {
            try encode(value)
        }
    }
}

extension Bool      : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataRepresented {}
extension Int       : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataRepresented {}
extension Double    : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataRepresented {}
extension Float     : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataRepresented {}
extension Int8      : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataRepresented {}
extension Int16     : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataRepresented {}
extension Int32     : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataRepresented {}
extension Int64     : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataRepresented {}
extension UInt      : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataRepresented {}
extension UInt8     : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataRepresented {}
extension UInt16    : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataRepresented {}
extension UInt32    : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataRepresented {}
extension UInt64    : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataRepresented {}
extension CGFloat   : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataRepresented {}
extension String    : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataRepresented {}
extension Data      : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataRepresented {
    public init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        self = try data.decode(Data.self)
    }
}
extension Array     : HasDefaultLiteral, _ComparableWithDefaultLiteral {
    public static func _isDefaultLiteral(_ lhs: Array<Element>) -> Bool {
        return lhs.isEmpty
    }
}
extension Dictionary: HasDefaultLiteral, _ComparableWithDefaultLiteral {
    public static func _isDefaultLiteral(_ lhs: Dictionary<Key, Value>) -> Bool {
        return lhs.isEmpty
    }
}
extension Optional  : HasDefaultLiteral, _ComparableWithDefaultLiteral {
    public init() { self = .none }
    public static func _isDefaultLiteral(_ lhs: Optional<Wrapped>) -> Bool {
        return lhs == nil
    }
}
#if os(macOS) || os(iOS)
extension NSNull    : HasDefaultLiteral, _ComparableWithDefaultLiteral {}
extension NSValue   : HasDefaultLiteral, _ComparableWithDefaultLiteral {}
extension NSString  : HasDefaultLiteral, _ComparableWithDefaultLiteral {}
extension NSArray   : HasDefaultLiteral, _ComparableWithDefaultLiteral {
    public static func _isDefaultLiteral(_ lhs: NSArray) -> Bool {
        return lhs.count == 0
    }
}
extension NSDictionary: HasDefaultLiteral, _ComparableWithDefaultLiteral {
    public static func _isDefaultLiteral(_ lhs: NSDictionary) -> Bool {
        return lhs.count == 0
    }
}
#endif

//extension Optional  : HasDefaultLiteral, _ComparableWithDefaultLiteral where Wrapped: HasDefaultLiteral & _ComparableWithDefaultLiteral {
//    public init() { self = .none }
//    public static func _isDefaultLiteral(_ lhs: Optional<Wrapped>) -> Bool {
//        return lhs.map(Wrapped._isDefaultLiteral) ?? lhs == nil
//    }
//}

public struct RealtimeDatabaseValue {
    internal let backend: Backend

    public var debug: Any {
        switch backend {
        case .bool(let v as Any),
            .int8(let v as Any),
            .int16(let v as Any),
            .int32(let v as Any),
            .int64(let v as Any),
            .uint8(let v as Any),
            .uint16(let v as Any),
            .uint32(let v as Any),
            .uint64(let v as Any),
            .double(let v as Any),
            .float(let v as Any),
            .string(let v as Any),
            .data(let v as Any):
            return v
        case .pair(let k, let v): return (k.debug, v.debug)
        case .unkeyed(let values): return values.map({ $0.debug })
        }
    }

    indirect enum Backend {
        case bool(Bool)
        case int8(Int8)
        case int16(Int16)
        case int32(Int32)
        case int64(Int64)
        case uint8(UInt8)
        case uint16(UInt16)
        case uint32(UInt32)
        case uint64(UInt64)
        case double(Double)
        case float(Float)
        case string(String)
        case data(Data)
        case pair(RealtimeDatabaseValue, RealtimeDatabaseValue)
        case unkeyed([RealtimeDatabaseValue])
    }

    init(_ value: RealtimeDatabaseValue) {
        self.backend = value.backend
    }
    public init(_ value: (RealtimeDatabaseValue, RealtimeDatabaseValue)) {
        self.backend = .pair(value.0, value.1)
    }
    public init(_ values: [RealtimeDatabaseValue]) {
        self.backend = .unkeyed(values)
    }

    public func extract<T>(
        bool: (Bool) throws -> T,
        int8: (Int8) throws -> T,
        int16: (Int16) throws -> T,
        int32: (Int32) throws -> T,
        int64: (Int64) throws -> T,
        uint8: (UInt8) throws -> T,
        uint16: (UInt16) throws -> T,
        uint32: (UInt32) throws -> T,
        uint64: (UInt64) throws -> T,
        double: (Double) throws -> T,
        float: (Float) throws -> T,
        string: (String) throws -> T,
        data: (Data) throws -> T,
        pair: (RealtimeDatabaseValue, RealtimeDatabaseValue) throws -> T,
        collection: ([RealtimeDatabaseValue]) throws -> T
        ) rethrows -> T {
        switch backend {
        case .bool(let v): return try bool(v)
        case .int8(let v): return try int8(v)
        case .int16(let v): return try int16(v)
        case .int32(let v): return try int32(v)
        case .int64(let v): return try int64(v)
        case .uint8(let v): return try uint8(v)
        case .uint16(let v): return try uint16(v)
        case .uint32(let v): return try uint32(v)
        case .uint64(let v): return try uint64(v)
        case .double(let v): return try double(v)
        case .float(let v): return try float(v)
        case .string(let v): return try string(v)
        case .data(let v): return try data(v)
        case .pair(let k, let v):
            return try pair(k, v)
        case .unkeyed(let values):
            return try collection(values)
        }
    }
}
extension RealtimeDatabaseValue: Equatable {
    public static func ==(lhs: RealtimeDatabaseValue, rhs: RealtimeDatabaseValue) -> Bool {
        switch (lhs.backend, rhs.backend) {
        case (.bool(let v1), .bool(let v2)): return v1 == v2
        case (.int8(let v1), .int8(let v2)): return v1 == v2
        case (.int16(let v1), .int16(let v2)): return v1 == v2
        case (.int32(let v1), .int32(let v2)): return v1 == v2
        case (.int64(let v1), .int64(let v2)): return v1 == v2
        case (.uint8(let v1), .uint8(let v2)): return v1 == v2
        case (.uint16(let v1), .uint16(let v2)): return v1 == v2
        case (.uint32(let v1), .uint32(let v2)): return v1 == v2
        case (.uint64(let v1), .uint64(let v2)): return v1 == v2
        case (.double(let v1), .double(let v2)): return v1 == v2
        case (.float(let v1), .float(let v2)): return v1 == v2
        case (.string(let v1), .string(let v2)): return v1 == v2
        case (.data(let v1), .data(let v2)): return v1 == v2
        case (.pair(let k1, let v1), .pair(let k2, let v2)): return k1 == k2 && v1 == v2
        case (.unkeyed(let values1), .unkeyed(let values2)): return values1 == values2
        default: return false
        }
    }
}
extension RealtimeDatabaseValue: ExpressibleByStringLiteral {
    public typealias StringLiteralType = String
    public init(stringLiteral value: StringLiteralType) {
        self.init(value)
    }
}
extension RealtimeDatabaseValue: ExpressibleByFloatLiteral {
    public typealias FloatLiteralType = Float
    public init(floatLiteral value: FloatLiteralType) {
        self.init(value)
    }
}
extension RealtimeDatabaseValue: ExpressibleByBooleanLiteral {
    public typealias BooleanLiteralType = Bool
    public init(booleanLiteral value: BooleanLiteralType) {
        self.init(value)
    }
}
extension RealtimeDatabaseValue {
    #if os(iOS) || os(macOS)
    public init(_ value: NSString) { self.init(value as String) }
    #endif
}
extension RealtimeDatabaseValue {
    public struct Dictionary {
        var properties: [(RealtimeDatabaseValue, RealtimeDatabaseValue)] = []
        public var isEmpty: Bool { return properties.isEmpty }

        public init() {}

        public mutating func setValue<T: ExpressibleByRealtimeDatabaseValue>(_ value: T, forKey key: String) {
            properties.append((RealtimeDatabaseValue(key), RealtimeDatabaseValue(value)))
        }

        public func build() -> RealtimeDatabaseValue {
            return RealtimeDatabaseValue(properties.map(RealtimeDatabaseValue.init))
        }
    }

    public init<T: ExpressibleByRealtimeDatabaseValue>(_ value: T) {
        self = T.RDBConvertor.map(value)
    }

    public func losslessMap<T: FixedWidthInteger>(to type: T.Type) -> T? {
        switch backend {
        case .int8(let v): return T(exactly: v)
        case .int16(let v): return T(exactly: v)
        case .int32(let v): return T(exactly: v)
        case .int64(let v): return T(exactly: v)
        case .uint8(let v): return T(exactly: v)
        case .uint16(let v): return T(exactly: v)
        case .uint32(let v): return T(exactly: v)
        case .uint64(let v): return T(exactly: v)
        case .string(let v): return T(v)
        default: return nil
        }
    }
    public func losslessMap(to type: String.Type) -> String? {
        switch backend {
        case .string(let v): return v
        case .int8(let v): return String(v)
        case .int16(let v): return String(v)
        case .int32(let v): return String(v)
        case .int64(let v): return String(v)
        case .uint8(let v): return String(v)
        case .uint16(let v): return String(v)
        case .uint32(let v): return String(v)
        case .uint64(let v): return String(v)
        case .float(let v): return String(v)
        case .double(let v): return String(v)
        default: return nil
        }
    }
    public func lossyMap<T: FixedWidthInteger>(to type: T.Type) -> T? {
        switch backend {
        case .int8(let v): return T(truncatingIfNeeded: v)
        case .int16(let v): return T(truncatingIfNeeded: v)
        case .int32(let v): return T(truncatingIfNeeded: v)
        case .int64(let v): return T(truncatingIfNeeded: v)
        case .uint8(let v): return T(truncatingIfNeeded: v)
        case .uint16(let v): return T(truncatingIfNeeded: v)
        case .uint32(let v): return T(truncatingIfNeeded: v)
        case .uint64(let v): return T(truncatingIfNeeded: v)
        case .string(let v): return T(v)
        case .float(let v): return T(v)
        case .double(let v): return T(v)
        default: return nil
        }
    }

    func lossyMap(to type: Bool.Type) -> Bool? {
        switch backend {
        case .string(let v): return !(v.isEmpty || v == "0")
        case .int8(let v): return v > 0
        case .int16(let v): return v > 0
        case .int32(let v): return v > 0
        case .int64(let v): return v > 0
        case .uint8(let v): return v > 0
        case .uint16(let v): return v > 0
        case .uint32(let v): return v > 0
        case .uint64(let v): return v > 0
        case .float(let v): return v > 0
        case .double(let v): return v > 0
        case .data(let v): return !v.isEmpty
        default: return nil
        }
    }
}

// MARK: Representer --------------------------------------------------------------------------

//protocol Representable {
//    associatedtype Represented
//    var representer: Representer<Represented> { get }
//}
//extension Representable {
//    var customRepresenter: Representer<Self> {
//        return representer
//    }
//}
//
//public protocol CustomRepresentable {
//    associatedtype Represented
//    var customRepresenter: Representer<Represented> { get }
//}

/// A type that can convert itself into and out of an external representation.
public protocol RepresenterProtocol {
    associatedtype V
    /// Encodes this value to untyped value
    ///
    /// - Parameter value:
    /// - Returns: Untyped value
    func encode(_ value: V) throws -> RealtimeDatabaseValue?
    /// Decodes a data of Realtime database to defined type.
    ///
    /// - Parameter data: A data of database.
    /// - Returns: Value of defined type.
    func decode(_ data: RealtimeDataProtocol) throws -> V
}
public extension RepresenterProtocol {
    /// Representer that no throws error on empty data
    ///
    /// - Returns: Wrapped representer
    func optional() -> Representer<V?> {
        return Representer(optional: self)
    }
    /// Representer that convert data to collection
    /// where element of collection is type of base representer
    ///
    /// - Returns: Wrapped representer
    func collection<T>() -> Representer<T> where T: Collection & ExpressibleBySequence, T.Element == V, T.SequenceElement == V {
        return Representer(collection: self)
    }
    /// Representer that convert data to array
    /// where element of collection is type of base representer
    ///
    /// - Returns: Wrapped representer
    func array() -> Representer<[V]> {
        return Representer(collection: self)
    }
}
extension RepresenterProtocol where V: HasDefaultLiteral & _ComparableWithDefaultLiteral {
    /// Representer that convert empty data as default literal
    ///
    /// - Returns: Wrapped representer
    func defaultOnEmpty() -> Representer<V> {
        return Representer(defaultOnEmpty: self)
    }
}
public extension Representer {
    /// Encodes optional wrapped value if exists
    /// else returns nil
    ///
    /// - Parameter value: Optional of base value
    /// - Returns: Encoding result
    func encode<T>(_ value: V) throws -> RealtimeDatabaseValue? where V == Optional<T> {
        return try value.flatMap(encode)
    }
    /// Decodes a data of Realtime database to defined type.
    /// If data is empty return nil.
    ///
    /// - Parameter data: A data of database.
    /// - Returns: Value of defined type.
    func decode<T>(_ data: RealtimeDataProtocol) throws -> V where V == Optional<T> {
        guard data.exists() else { return nil }
        return try decode(data)
    }
}

/// Any representer
public struct Representer<V>: RepresenterProtocol {
    fileprivate let encoding: (V) throws -> RealtimeDatabaseValue?
    fileprivate let decoding: (RealtimeDataProtocol) throws -> V
    public func decode(_ data: RealtimeDataProtocol) throws -> V {
        return try decoding(data)
    }
    public func encode(_ value: V) throws -> RealtimeDatabaseValue? {
        return try encoding(value)
    }
    public init(encoding: @escaping (V) throws -> RealtimeDatabaseValue?, decoding: @escaping (RealtimeDataProtocol) throws -> V) {
        self.encoding = encoding
        self.decoding = decoding
    }
    public init<T>(encoding: @escaping (T) throws -> RealtimeDatabaseValue?, decoding: @escaping (RealtimeDataProtocol) throws -> T) where V == Optional<T> {
        self.encoding = { v -> RealtimeDatabaseValue? in
            return try v.flatMap(encoding)
        }
        self.decoding = { d -> V.Wrapped? in
            guard d.exists() else { return nil }
            return try decoding(d)
        }
    }
}
public extension Representer {
    init<R: RepresenterProtocol>(_ base: R) where V == R.V {
        self.encoding = base.encode
        self.decoding = base.decode
    }
    init<R: RepresenterProtocol>(optional base: R) where V == R.V? {
        self.encoding = { (v) -> RealtimeDatabaseValue? in
            return try v.flatMap(base.encode)
        }
        self.decoding = { (data) in
            guard data.exists() else { return nil }
            return try base.decode(data)
        }
    }
    init<R: RepresenterProtocol>(collection base: R) where V: Collection, V.Element == R.V, V: ExpressibleBySequence, V.SequenceElement == V.Element {
        self.encoding = { (v) -> RealtimeDatabaseValue? in
            return RealtimeDatabaseValue(try v.compactMap(base.encode))
        }
        self.decoding = { (data) -> V in
            return try V(data.map(base.decode))
        }
    }
    init<R: RepresenterProtocol>(defaultOnEmpty base: R) where R.V: HasDefaultLiteral & _ComparableWithDefaultLiteral, V == R.V {
        self.encoding = { (v) -> RealtimeDatabaseValue? in
            if V._isDefaultLiteral(v) {
                return nil
            } else {
                return try base.encode(v)
            }
        }
        self.decoding = { (data) -> V in
            guard data.exists() else { return V() }
            return try base.decode(data)
        }
    }
    init<R: RepresenterProtocol, T>(defaultOnEmpty base: R) where T: HasDefaultLiteral & _ComparableWithDefaultLiteral, Optional<T> == R.V, Optional<T> == V {
        self.encoding = { (v) -> RealtimeDatabaseValue? in
            if v.map(T._isDefaultLiteral) ?? true {
                return nil
            } else {
                return try base.encode(v)
            }
        }
        self.decoding = { (data) -> T? in
            guard data.exists() else { return T() }
            return try base.decode(data) ?? T()
        }
    }
}
public extension Representer where V: Collection {
    func sorting<Element>(_ descriptor: @escaping (Element, Element) -> Bool) -> Representer<[Element]> where Array<Element> == V {
        return Representer(collection: self, sorting: descriptor)
    }
    init<E>(collection base: Representer<[E]>, sorting: @escaping (E, E) throws -> Bool) where V == [E] {
        self.init(
            encoding: { (collection) -> RealtimeDatabaseValue? in
                return try base.encode(collection.sorted(by: sorting))
            },
            decoding: { (data) -> [E] in
                return try base.decode(data).sorted(by: sorting)
            }
        )
    }
}
public extension Representer where V: RealtimeValue {
    /// Representer that convert `RealtimeValue` as database relation.
    ///
    /// - Parameters:
    ///   - mode: Relation type
    ///   - rootLevelsUp: Level of root node to do relation path
    ///   - ownerNode: Database node of relation owner
    /// - Returns: Relation representer
    static func relation(_ mode: RelationProperty, rootLevelsUp: UInt?, ownerNode: ValueStorage<Node?>, database: RealtimeDatabase?, builder: @escaping RCElementBuilder<RealtimeValueOptions, V>) -> Representer<V> {
        return Representer<V>(
            encoding: { v in
                guard let owner = ownerNode.value else { throw RealtimeError(encoding: V.self, reason: "Can`t get relation owner node") }
                guard let node = v.node else { throw RealtimeError(encoding: V.self, reason: "Can`t get relation value node.") }
                let anchorNode = try rootLevelsUp.map { level -> Node in
                    if let ancestor = owner.ancestor(onLevelUp: level) {
                        return ancestor
                    } else {
                        throw RealtimeError(encoding: V.self, reason: "Couldn`t get root node")
                    }
                }

                return try RelationRepresentation(
                    path: node.path(from: anchorNode ?? .root),
                    property: mode.path(for: owner),
                    payload: (v.raw, v.payload)
                ).defaultRepresentation()
            },
            decoding: { d in
                guard let owner = ownerNode.value
                else { throw RealtimeError(decoding: V.self, d, reason: "Can`t get relation owner node") }
                let anchorNode = try rootLevelsUp.map { level -> Node in
                    if let ancestor = owner.ancestor(onLevelUp: level) {
                        return ancestor
                    } else {
                        throw RealtimeError(decoding: V.self, d, reason: "Couldn`t get root node")
                    }
                }
                let relation = try RelationRepresentation(data: d)
                return builder((anchorNode ?? .root).child(with: relation.targetPath), database, relation.options(database))
            }
        )
    }
    /// Representer that convert `RealtimeValue` as database reference.
    ///
    /// - Parameter mode: Representation mode
    /// - Returns: Reference representer
    static func reference(_ mode: ReferenceMode, database: RealtimeDatabase?, builder: @escaping RCElementBuilder<RealtimeValueOptions, V>) -> Representer<V> {
        return Representer<V>(
            encoding: { v in
                guard let node = v.node else {
                    throw RealtimeError(source: .coding, description: "Can`t get reference from value \(v), using mode \(mode)")
                }
                let ref: String
                switch mode {
                case .fullPath: ref = node.absolutePath
                case .path(from: let n): ref = node.path(from: n)
                }
                return try ReferenceRepresentation(
                    ref: ref,
                    payload: (raw: v.raw, user: v.payload)
                ).defaultRepresentation()
            },
            decoding: { (data) in
                let reference = try ReferenceRepresentation(data: data)
                switch mode {
                case .fullPath: return builder(.root(reference.source), database, reference.options(database))
                case .path(from: let n): return builder(n.child(with: reference.source), database, reference.options(database))
                }
            }
        )
    }
}

extension Representer {
    public func requiredProperty() -> Representer<V?> {
        return Representer<V?>(required: self)
    }

    init<R: RepresenterProtocol>(required base: R) where V == R.V? {
        self.encoding = { (value) -> RealtimeDatabaseValue? in
            switch value {
            case .none: throw RealtimeError(encoding: R.V.self, reason: "Required property has not been set")
            case .some(let v): return try base.encode(v)
            }
        }
        self.decoding = { data -> V in
            guard data.exists() else {
                throw RealtimeError(decoding: R.V.self, data, reason: "Required property is not exists")
            }
            return .some(try base.decode(data))
        }
    }

    public func optionalProperty() -> Representer<V??> {
        return Representer<V??>(optionalProperty: self)
    }

    init<R: RepresenterProtocol>(optionalProperty base: R) where V == R.V?? {
        self.encoding = { (value) -> RealtimeDatabaseValue? in
            switch value {
            case .none, .some(nil): return nil
            case .some(.some(let v)): return try base.encode(v)
            }
        }
        self.decoding = { data -> V in
            guard data.exists() else {
                return .some(nil)
            }

            return .some(try base.decode(data))
        }
    }

    public func writeRequiredProperty() -> Representer<V??> {
        return Representer<V??>(writeRequiredProperty: self)
    }

    init<R: RepresenterProtocol>(writeRequiredProperty base: R) where V == R.V?? {
        self.encoding = { (value) -> RealtimeDatabaseValue? in
            switch value {
            case .none, .some(nil): throw RealtimeError(encoding: R.V.self, reason: "Required property has not been set")
            case .some(.some(let v)): return try base.encode(v)
            }
        }
        self.decoding = { data -> V in
            guard data.exists() else {
                return .some(nil)
            }

            return .some(try base.decode(data))
        }
    }
}

public extension Representer where V: RealtimeDataRepresented {
    static func realtimeData(encoding: @escaping (V) throws -> RealtimeDatabaseValue?) -> Representer<V> {
        return Representer(encoding: encoding, decoding: V.init(data:))
    }
}

public extension Representer where V: ExpressibleByRealtimeDatabaseValue & RealtimeDataRepresented {
    static var realtimeDataValue: Representer<V> {
        return Representer<V>(encoding: RealtimeDatabaseValue.init(_:), decoding: V.init(data:))
    }
}

public extension Representer where V: RawRepresentable, V.RawValue: ExpressibleByRealtimeDatabaseValue & RealtimeDataRepresented {
    static var rawRepresentable: Representer<V> {
        return self.default(Representer<V.RawValue>.realtimeDataValue)
    }
}

public extension Representer where V: RawRepresentable {
    static func `default`<R: RepresenterProtocol>(_ rawRepresenter: R) -> Representer<V> where R.V == V.RawValue {
        return Representer(
            encoding: { try rawRepresenter.encode($0.rawValue) },
            decoding: { d in
                let raw = try rawRepresenter.decode(d)
                guard let v = V(rawValue: raw) else {
                    throw RealtimeError(decoding: V.self, d, reason: "Can`t get value using raw value: \(raw), using initializer: .init(rawValue:)")
                }
                return v
            }
        )
    }
}

public extension Representer where V == URL {
    static var `default`: Representer<URL> {
        return Representer(
            encoding: { RealtimeDatabaseValue($0.absoluteString) },
            decoding: URL.init
        )
    }
}

public extension Representer where V: Codable {
    static var codable: Representer<V> {
        return Representer(
            encoding: { (v) -> RealtimeDatabaseValue? in
                let encoder = DatabaseValueEncoder()
                try v.encode(to: encoder)
                return encoder.build()
            },
            decoding: V.init
        )
    }
}

public enum DateCodingStrategy {
    case secondsSince1970
    case millisecondsSince1970
    @available(iOS 10.0, macOS 10.12, *)
    case iso8601(ISO8601DateFormatter)
    case formatted(DateFormatter)
}
public extension Representer where V == Date {
    static func date(_ strategy: DateCodingStrategy) -> Representer<Date> {
        return Representer<Date>(
            encoding: { date -> RealtimeDatabaseValue? in
                switch strategy {
                case .secondsSince1970:
                    return RealtimeDatabaseValue(date.timeIntervalSince1970)
                case .millisecondsSince1970:
                    return RealtimeDatabaseValue(1000.0 * date.timeIntervalSince1970)
                case .iso8601(let formatter):
                    return RealtimeDatabaseValue(formatter.string(from: date))
                case .formatted(let formatter):
                    return RealtimeDatabaseValue(formatter.string(from: date))
                }
            },
            decoding: { (data) in
                let container = try data.singleValueContainer()
                switch strategy {
                case .secondsSince1970:
                    let double = try container.decode(TimeInterval.self)
                    return Date(timeIntervalSince1970: double)
                case .millisecondsSince1970:
                    let double = try container.decode(Double.self)
                    return Date(timeIntervalSince1970: double / 1000.0)
                case .iso8601(let formatter):
                    let string = try container.decode(String.self)
                    guard let date = formatter.date(from: string) else {
                        throw RealtimeError(decoding: V.self, string, reason: "Expected date string to be ISO8601-formatted.")
                    }
                    return date
                case .formatted(let formatter):
                    let string = try container.decode(String.self)
                    guard let date = formatter.date(from: string) else {
                        throw RealtimeError(decoding: V.self, string, reason: "Date string does not match format expected by formatter.")
                    }
                    return date
                }
            }
        )
    }
}

#if os(iOS)

import UIKit.UIImage

public extension Representer where V: UIImage {
    static var png: Representer<UIImage> {
        let base = Representer<Data>.realtimeDataValue
        return Representer<UIImage>(
            encoding: { img -> RealtimeDatabaseValue? in
                guard let data = img.pngData() else {
                    throw RealtimeError(encoding: V.self, reason: "Can`t get image data in .png representation")
                }
                return RealtimeDatabaseValue(data)
            },
            decoding: { d in
                let data = try base.decode(d)
                guard let img = UIImage(data: data) else {
                    throw RealtimeError(decoding: V.self, d, reason: "Can`t get UIImage object, using initializer .init(data:)")
                }
                return img
            }
        )
    }
    static func jpeg(quality: CGFloat = 1.0) -> Representer<UIImage> {
        let base = Representer<Data>.realtimeDataValue
        return Representer<UIImage>(
            encoding: { img -> RealtimeDatabaseValue? in
                guard let data = img.jpegData(compressionQuality: quality) else {
                    throw RealtimeError(encoding: V.self, reason: "Can`t get image data in .jpeg representation with compression quality: \(quality)")
                }
                return RealtimeDatabaseValue(data)
            },
            decoding: { d in
                guard let img = UIImage(data: try base.decode(d)) else {
                    throw RealtimeError(decoding: V.self, d, reason: "Can`t get UIImage object, using initializer .init(data:)")
                }
                return img
            }
        )
    }
}
#endif
