//
//  realtime.coding.swift
//  Realtime
//
//  Created by Denis Koryttsev on 25/07/2018.
//

import Foundation

// MARK: RealtimeDataProtocol ---------------------------------------------------------------

/// A type that contains data associated with database node.
public protocol RealtimeDataProtocol: Decoder, CustomDebugStringConvertible, CustomStringConvertible {
    var database: RealtimeDatabase? { get }
    var storage: RealtimeStorage? { get }
    var node: Node? { get }
    var key: String? { get }
    var priority: Any? { get }
    var childrenCount: UInt { get }
    func makeIterator() -> AnyIterator<RealtimeDataProtocol>
    func exists() -> Bool
    func hasChildren() -> Bool
    func hasChild(_ childPathString: String) -> Bool
    func child(forPath path: String) -> RealtimeDataProtocol

    func asSingleValue() -> Any?
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
    public func reduce<Result>(into result: inout Result, updateAccumulatingResult: (inout Result, RealtimeDataProtocol) throws -> Void) rethrows -> Result {
        return try makeIterator().reduce(into: result, updateAccumulatingResult)
    }
}
public extension RealtimeDataProtocol {
    func unbox<T>(as type: T.Type) throws -> T {
        guard case let v as T = asSingleValue() else {
            throw RealtimeError(decoding: T.self, self, reason: "Mismatch type")
        }
        return v
    }
    func unboxIfPresent<T>(as type: T.Type) throws -> T? {
        guard exists() else { return nil }
        return try unbox(as: type)
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
        return []
    }

    public var userInfo: [CodingUserInfoKey : Any] {
        return [CodingUserInfoKey(rawValue: "node")!: node as Any]
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

    fileprivate func childDecoder<Key: CodingKey>(forKey key: Key) throws -> RealtimeDataProtocol {
        guard hasChild(key.stringValue) else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: [key], debugDescription: debugDescription))
        }
        return child(forPath: key.stringValue)
    }
}
fileprivate struct DataSnapshotSingleValueContainer: SingleValueDecodingContainer {
    let snapshot: RealtimeDataProtocol
    var codingPath: [CodingKey] { return snapshot.codingPath }

    func decodeNil() -> Bool {
        if let v = snapshot.asSingleValue() {
            return v is NSNull
        }
        return true
    }

    private func _decode<T>(_ type: T.Type) throws -> T {
        guard case let v as T = snapshot.asSingleValue() else {
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
        if let value = try nextDecoder().asSingleValue() {
            return value is NSNull
        }
        return true
    }

    private mutating func nextDecoder() throws -> RealtimeDataProtocol {
        guard let next = iterator.next() else {
            throw DecodingError.dataCorruptedError(in: self, debugDescription: snapshot.debugDescription)
        }
        currentIndex += 1
        return next
    }

    private mutating func _decode<T>(_ type: T.Type) throws -> T {
        let next = try nextDecoder()
        guard case let v as T = next.asSingleValue() else {
            throw DecodingError.valueNotFound(T.self, DecodingError.Context(codingPath: [_RealtimeCodingKey(intValue: currentIndex)!], debugDescription: next.debugDescription))
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
    let snapshot: RealtimeDataProtocol

    var codingPath: [CodingKey] { return [] }
    var allKeys: [Key] { return snapshot.compactMap { $0.node.flatMap { Key(stringValue: $0.key) } } }

    private func _decode<T>(_ type: T.Type, forKey key: Key) throws -> T {
        let child = try snapshot.childDecoder(forKey: key)
        guard case let v as T = child.asSingleValue() else {
            throw DecodingError.valueNotFound(T.self, DecodingError.Context(codingPath: [key], debugDescription: child.debugDescription))
        }
        return v
    }

    func contains(_ key: Key) -> Bool {
        return snapshot.hasChild(key.stringValue)
    }

    func decodeNil(forKey key: Key) throws -> Bool { return try snapshot.childDecoder(forKey: key).asSingleValue() is NSNull }
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

/// Protocol for values that only valid for Realtime Database, e.g. `(NS)Array`, `(NS)Dictionary` and etc.
/// You shouldn't apply for some custom values.
public protocol RealtimeDataValue: RealtimeDataRepresented {} // TODO: Rename to `ExplicitlyRealtimeDatabaseCompatible`
extension RealtimeDataValue {
    public init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        let value = data.asSingleValue()
        guard let v = value as? Self else {
            throw RealtimeError(initialization: Self.self, value as Any)
        }

        self = v
    }
}

extension Bool      : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataValue {}
extension Int       : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataValue {}
extension Double    : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataValue {}
extension Float     : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataValue {}
extension Int8      : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataValue {}
extension Int16     : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataValue {}
extension Int32     : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataValue {}
extension Int64     : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataValue {}
extension UInt      : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataValue {}
extension UInt8     : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataValue {}
extension UInt16    : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataValue {}
extension UInt32    : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataValue {}
extension UInt64    : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataValue {}
extension CGFloat   : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataValue {}
extension String    : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataValue {}
extension Data      : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataValue {}
extension Array     : HasDefaultLiteral, _ComparableWithDefaultLiteral {
    public static func _isDefaultLiteral(_ lhs: Array<Element>) -> Bool {
        return lhs.isEmpty
    }
}
extension Array: RealtimeDataValue, RealtimeDataRepresented where Element: RealtimeDataValue {
    public init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        guard data.exists() else { throw RealtimeError(initialization: Array<Element>.self, data) }

        let iterator = data.makeIterator()
        var arr: [Element] = []
        while let next = iterator.next() {
            try arr.append(Element(data: next))
        }
        self = arr
    }
}
extension Dictionary: HasDefaultLiteral, _ComparableWithDefaultLiteral {
    public static func _isDefaultLiteral(_ lhs: Dictionary<Key, Value>) -> Bool {
        return lhs.isEmpty
    }
}
extension Dictionary: RealtimeDataValue, RealtimeDataRepresented where Key: RealtimeDataValue, Value == RealtimeDataValue {
    public init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        let value = data.asSingleValue()
        guard let v = value as? [Key: Value] else {
            throw RealtimeError(initialization: [Key: Value].self, value as Any)
        }

        self = v
//        guard data.exists() else { throw RealtimeError(initialization: Dictionary<Key, Value>.self, data) }
//
//        let iterator = data.makeIterator()
//        var dict: [Key: Value] = [:]
//        while let next = iterator.next() {
//            guard let key = next.key.flatMap(Key.init) else {
//                throw RealtimeError(initialization: Dictionary<Key, Value>.self, data)
//            }
//            dict[key] = try Value(data: next)
//        }
//        self = dict
    }
}
extension Optional  : HasDefaultLiteral, _ComparableWithDefaultLiteral {
    public init() { self = .none }
    public static func _isDefaultLiteral(_ lhs: Optional<Wrapped>) -> Bool {
        return lhs == nil
    }
}
#if os(macOS) || os(iOS)
extension NSNull    : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataValue {}
extension NSValue   : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataValue {}
extension NSString  : HasDefaultLiteral, _ComparableWithDefaultLiteral, RealtimeDataValue {}
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

//extension Optional: RealtimeDataValue where Wrapped: RealtimeDataValue {
//    public init(data: RealtimeDataProtocol) throws {
//        if data.exists() {
//            self = try Wrapped(data: data)
//        } else {
//            self = .none
//        }
//    }
//}

//extension Dictionary: RealtimeDataValue, RealtimeDataRepresented where Key: RealtimeDataValue, Value: RealtimeDataValue {
//    public init(data: RealtimeDataProtocol) throws {
//        guard let v = data.value as? [Key: Value] else {
//            throw RealtimeError(initialization: [Key: Value].self, data.value as Any)
//        }
//
//        self = v
//    }
//}

//extension Optional  : HasDefaultLiteral, _ComparableWithDefaultLiteral where Wrapped: HasDefaultLiteral & _ComparableWithDefaultLiteral {
//    public init() { self = .none }
//    public static func _isDefaultLiteral(_ lhs: Optional<Wrapped>) -> Bool {
//        return lhs.map(Wrapped._isDefaultLiteral) ?? lhs == nil
//    }
//}

// TODO: Implement Expressible protocols where if can https://developer.apple.com/documentation/swift/swift_standard_library/initialization_with_literals
public struct RealtimeDatabaseValue {
    private let backend: Backend

    public var untyped: Any {
        switch backend {
        case ._untyped(let v): return v
        case .single(_, let v): return v
        case .pair(let k, let v): return (k.untyped, v.untyped) // TODO: Invalid for Firebase
        case .unkeyed(let values): return values.map({ $0.untyped })
        }
    }

    indirect enum Backend {
        @available(*, deprecated, message: "Untyped values no more supported")
        case _untyped(Any)
        case single(Any.Type, Any)
        case pair(RealtimeDatabaseValue, RealtimeDatabaseValue)
        case unkeyed([RealtimeDatabaseValue])
    }

    internal init<T: RealtimeDataValue>(value: T) {
        self.backend = .single(T.self, value)
    }

    // TODO: Remove this invalid initializer, used when access to child node in ValueNode
    internal init(dbVal: RealtimeDataValue) {
        self.backend = .single(RealtimeDataValue.self, dbVal)
    }

    public init(_ value: Bool) { self.init(value: value) }
    public init(_ value: Int) { self.init(value: value) }
    public init(_ value: Double) { self.init(value: value) }
    public init(_ value: Float) { self.init(value: value) }
    public init(_ value: Int8) { self.init(value: value) }
    public init(_ value: Int16) { self.init(value: value) }
    public init(_ value: Int32) { self.init(value: value) }
    public init(_ value: Int64) { self.init(value: value) }
    public init(_ value: UInt) { self.init(value: value) }
    public init(_ value: UInt8) { self.init(value: value) }
    public init(_ value: UInt16) { self.init(value: value) }
    public init(_ value: UInt32) { self.init(value: value) }
    public init(_ value: UInt64) { self.init(value: value) }
    public init(_ value: String) { self.init(value: value) }
    public init(_ value: Data) { self.init(value: value) }

    // TODO: Remove both below
    public init<E: RealtimeDataValue>(_ value: Array<E>) {
        self.init(value: value)
    }
    public init<K: RealtimeDataValue>(_ value: Dictionary<K, RealtimeDataValue>) {
        self.init(value: value)
    }

    #if os(iOS) || os(macOS)
    public init(_ value: NSNull) { self.init(value: value) }
    public init(_ value: NSValue) { self.init(value: value) }
    public init(_ value: NSString) { self.init(value: value) }
//    init(_ value: NSArray) { self.init(value: value) }
//    init(_ value: NSDictionary) { self.init(value: value) }
    #endif

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

//    func satisfy<T>(to type: T.Type) -> Bool where T: RealtimeDataValue {
//        switch backend {
//        case ._untyped(let v): return (v as? T) != nil
//        case .single(let t, let v):
//            return type == t || (v as? T) != nil
//        case .pair(let k, let v):
//            return (k.type, v.type) == type
//        case .unkeyed:
//            return type == NSArray.self || type == Array<Any>.self
//        }
//    }

    func typed<T>(as type: T.Type) throws -> T where T: RealtimeDataValue {
        switch backend {
        case ._untyped(let v):
            guard let typed = v as? T else {
                throw RealtimeError(source: .value, description: "Type casting fails")
            }
            return typed
        case .single(_, let v):
            guard let typed = v as? T else {
                throw RealtimeError(source: .value, description: "Type casting fails")
            }
            return typed
        case .pair(let k, let v):
            guard let typed = (k.untyped, v.untyped) as? T else {
                throw RealtimeError(source: .value, description: "Type casting fails")
            }
            return typed
        case .unkeyed(let values):
            guard let typed = values.map({ $0.untyped }) as? T else {
                throw RealtimeError(source: .value, description: "Type casting fails")
            }
            return typed
        }
    }

    public func extract<T>(
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
        switch backend {
        case ._untyped: throw RealtimeError(source: .value, description: "Unexpected database value to extract")
        case .single(let t, let v):
            func load<T>(_ p: UnsafeRawBufferPointer) -> T { return p.load(as: T.self) }
            if t == Bool.self {
                return try bool(withUnsafeBytes(of: v, load))
            } else if t == Int.self {
                return try int(withUnsafeBytes(of: v, load))
            } else if t == Int8.self {
                return try int8(withUnsafeBytes(of: v, load))
            } else if t == Int16.self {
                return try int16(withUnsafeBytes(of: v, load))
            } else if t == Int32.self {
                return try int32(withUnsafeBytes(of: v, load))
            } else if t == Int64.self {
                return try int64(withUnsafeBytes(of: v, load))
            } else if t == UInt.self {
                return try uint(withUnsafeBytes(of: v, load))
            } else if t == UInt8.self {
                return try uint8(withUnsafeBytes(of: v, load))
            } else if t == UInt16.self {
                return try uint16(withUnsafeBytes(of: v, load))
            } else if t == UInt32.self {
                return try uint32(withUnsafeBytes(of: v, load))
            } else if t == UInt64.self {
                return try uint64(withUnsafeBytes(of: v, load))
            } else if t == Double.self {
                return try double(withUnsafeBytes(of: v, load))
            } else if t == Float.self {
                return try float(withUnsafeBytes(of: v, load))
            } else if t == String.self {
                return try string(withUnsafeBytes(of: v, load))
            } else if t == Data.self {
                return try data(withUnsafeBytes(of: v, load))
            } else {
                throw RealtimeError(source: .value, description: "Cannot extract value from database value. Reason: Unexpected type")
            }
        case .pair(let k, let v):
            return try pair(k, v)
        case .unkeyed(let values):
            return try collection(values)
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
public extension Representer where V: RealtimeDataValue {
    static var realtimeDataValue: Representer<V> {
        return Representer<V>(encoding: RealtimeDatabaseValue.init, decoding: V.init)
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
public extension Representer where V: RawRepresentable, V.RawValue: RealtimeDataValue {
    static var rawRepresentable: Representer<V> {
        return self.default(Representer<V.RawValue>.realtimeDataValue)
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
