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

    func satisfy<T>(to type: T.Type) -> Bool
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
public extension RealtimeDataProtocol {
    func extract<T>(
        bool: (Bool) throws -> T,
        int: (Int) throws -> T,
        int8: (Int8) throws -> T,
        int16: (Int16) throws -> T,
        int32: (Int32) throws -> T,
        int64: (Int64) throws -> T,
        uint: (UInt) throws -> T,
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
        ) throws -> T {
        guard childrenCount == 0 else {
            let result = try reduce(into: (result: [(Node, RealtimeDatabaseValue)](), array: true), updateAccumulatingResult: { (res, data) in
                guard let node = data.node, let dbValue = try data.asDatabaseValue() else { return }
                res.array = res.array && data.node.flatMap({ Int($0.key) }) != nil
                res.result.append((node, dbValue))
            })
            
            return try collection(
                result.array ? result.result.map({ $1 }) : result.result.map({ RealtimeDatabaseValue((RealtimeDatabaseValue($0.key), $1)) })
            )
        }
        let container = self
        if satisfy(to: Bool.self) {
            return try bool(try container.decode(Bool.self))
        } else if satisfy(to: Int.self) {
            return try int(try container.decode(Int.self))
        } else if satisfy(to: Int8.self) {
            return try int8(try container.decode(Int8.self))
        } else if satisfy(to: Int16.self) {
            return try int16(try container.decode(Int16.self))
        } else if satisfy(to: Int32.self) {
            return try int32(try container.decode(Int32.self))
        } else if satisfy(to: Int64.self) {
            return try int64(try container.decode(Int64.self))
        } else if satisfy(to: UInt.self) {
            return try uint(try container.decode(UInt.self))
        } else if satisfy(to: UInt8.self) {
            return try uint8(try container.decode(UInt8.self))
        } else if satisfy(to: UInt16.self) {
            return try uint16(try container.decode(UInt16.self))
        } else if satisfy(to: UInt32.self) {
            return try uint32(try container.decode(UInt32.self))
        } else if satisfy(to: UInt64.self) {
            return try uint64(try container.decode(UInt64.self))
        } else if satisfy(to: Double.self) {
            return try double(try container.decode(Double.self))
        } else if satisfy(to: Float.self) {
            return try float(try container.decode(Float.self))
        } else if satisfy(to: String.self) {
            return try string(try container.decode(String.self))
        } else if satisfy(to: Data.self) {
            return try data(try container.decode(Data.self))
        } else {
            throw RealtimeError(source: .coding, description: "Cannot extract value from database value. Reason: Undefined type")
        }
    }

    func asDatabaseValue() throws -> RealtimeDatabaseValue? {
        guard exists() else { return nil }
        return try extract(
            bool: { RealtimeDatabaseValue($0) },
            int: { RealtimeDatabaseValue(Int64($0)) },
            int8: { RealtimeDatabaseValue($0) },
            int16: { RealtimeDatabaseValue($0) },
            int32: { RealtimeDatabaseValue($0) },
            int64: { RealtimeDatabaseValue($0) },
            uint: { RealtimeDatabaseValue(UInt64($0)) },
            uint8: { RealtimeDatabaseValue($0) },
            uint16: { RealtimeDatabaseValue($0) },
            uint32: { RealtimeDatabaseValue($0) },
            uint64: { RealtimeDatabaseValue($0) },
            double: { RealtimeDatabaseValue($0) },
            float: { RealtimeDatabaseValue($0) },
            string: { RealtimeDatabaseValue($0) },
            data: { RealtimeDatabaseValue($0) },
            pair: { RealtimeDatabaseValue(($0, $1)) },
            collection: { RealtimeDatabaseValue($0) }
        )
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
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: [key], debugDescription: debugDescription))
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

    @available(*, deprecated, message: "Use `extract` or similar methods, because value can have unexpected type")
    public var untyped: Any {
        switch backend {
        case ._untyped(let v),
            .bool(let v as Any),
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
        case .pair(let k, let v): return (k.untyped, v.untyped)
        case .unkeyed(let values): return values.map({ $0.untyped })
        }
    }

    indirect enum Backend {
        @available(*, deprecated, message: "Untyped values no more supported")
        case _untyped(Any)
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

    @available(*, deprecated, message: "Untyped values no more supported")
    init(untyped val: Any) {
        self.backend = ._untyped(val)
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
        ) throws -> T { // TODO: rethrows
        switch backend {
        case ._untyped: throw RealtimeError(source: .coding, description: "Untyped values no more supported")
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
//    public init(_ value: NSNumber) {
//        let numberType = CFNumberGetType(value)
//        switch numberType {
//        case .charType: self.init(value.boolValue)
//        case .sInt8Type: self.init(value.int8Value)
//        case .sInt16Type: self.init(value.int16Value)
//        case .sInt32Type: self.init(value.int32Value)
//        case .sInt64Type: self.init(value.int64Value)
//        case .shortType, .intType, .longType, .longLongType, .cfIndexType, .nsIntegerType:
//            self.init(value.intValue)
//        case .float32Type, .float64Type, .floatType, .doubleType, .cgFloatType:
//            self.init(value.floatValue)
//        }
//    }
    public init(_ value: NSString) { self.init(value as String) }
    #endif
}
extension RealtimeDatabaseValue {
    public struct Dictionary {
        var properties: [(RealtimeDatabaseValue, RealtimeDatabaseValue)] = []

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
    static func relation(_ mode: RelationProperty, rootLevelsUp: UInt?, ownerNode: ValueStorage<Node?>) -> Representer<V> {
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

                return RealtimeDatabaseValue(try RelationRepresentation(
                    path: node.path(from: anchorNode ?? .root),
                    property: mode.path(for: owner),
                    payload: (v.raw, v.payload)
                ).defaultRepresentation())
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
                return relation.make(fromAnchor: anchorNode ?? .root, options: [:])
            }
        )
    }

    /// Representer that convert `RealtimeValue` as database reference.
    ///
    /// - Parameter mode: Representation mode
    /// - Returns: Reference representer
    static func reference(_ mode: ReferenceMode, options: [ValueOption: Any]) -> Representer<V> {
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
                return RealtimeDatabaseValue(try ReferenceRepresentation(
                    ref: ref,
                    payload: (raw: v.raw, user: v.payload)
                ).defaultRepresentation())
            },
            decoding: { (data) in
                let reference = try ReferenceRepresentation(data: data)
                switch mode {
                case .fullPath: return reference.make(options: options)
                case .path(from: let n): return reference.make(fromAnchor: n, options: options)
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

    public func writeRequiredProperty() -> Representer<V!?> {
        return Representer<V!?>(writeRequiredProperty: self)
    }

    init<R: RepresenterProtocol>(writeRequiredProperty base: R) where V == R.V!? {
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

#if os(macOS) || os(iOS)
public extension Representer where V: Codable {
    @available(*, deprecated, message: "Unavailable after move to strong types")
    static func json(
        dateEncodingStrategy: JSONEncoder.DateEncodingStrategy = .secondsSince1970,
        keyEncodingStrategy: JSONEncoder.KeyEncodingStrategy = .useDefaultKeys
    ) -> Representer<V> {
        return Representer(
            encoding: { v -> RealtimeDatabaseValue? in
                let e = JSONEncoder()
                e.dateEncodingStrategy = dateEncodingStrategy
                #if os(macOS) || os(iOS)
                e.keyEncodingStrategy = keyEncodingStrategy
                #endif
                e.outputFormatting = .prettyPrinted
                let data = try e.encode(v)
                return RealtimeDatabaseValue(untyped: try JSONSerialization.jsonObject(with: data, options: .allowFragments))
            },
            decoding: V.init
        )
    }
}
#endif

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
