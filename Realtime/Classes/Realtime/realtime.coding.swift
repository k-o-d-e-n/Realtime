//
//  realtime.coding.swift
//  Realtime
//
//  Created by Denis Koryttsev on 25/07/2018.
//

import Foundation
import FirebaseDatabase

// MARK: FireDataProtocol ---------------------------------------------------------------

public protocol FireDataProtocol: Decoder, CustomDebugStringConvertible, CustomStringConvertible {
    var value: Any? { get }
    var priority: Any? { get }
    var children: NSEnumerator { get }
    var dataKey: String? { get }
    var dataRef: DatabaseReference? { get }
    var childrenCount: UInt { get }
    func exists() -> Bool
    func hasChildren() -> Bool
    func hasChild(_ childPathString: String) -> Bool
    func child(forPath path: String) -> FireDataProtocol
    func map<T>(_ transform: (FireDataProtocol) throws -> T) rethrows -> [T]
    func compactMap<ElementOfResult>(_ transform: (FireDataProtocol) throws -> ElementOfResult?) rethrows -> [ElementOfResult]
    func forEach(_ body: (FireDataProtocol) throws -> Swift.Void) rethrows
}
extension Sequence where Self: FireDataProtocol {
    public func makeIterator() -> AnyIterator<FireDataProtocol> {
        let childs = children
        return AnyIterator {
            return unsafeBitCast(childs.nextObject(), to: FireDataProtocol.self)
        }
    }
}

extension DataSnapshot: FireDataProtocol, Sequence {
    public var dataKey: String? {
        return key
    }

    public var dataRef: DatabaseReference? {
        return ref
    }

    public func child(forPath path: String) -> FireDataProtocol {
        return childSnapshot(forPath: path)
    }
}
extension MutableData: FireDataProtocol, Sequence {
    public var dataKey: String? {
        return key
    }

    public var dataRef: DatabaseReference? {
        return nil
    }

    public func exists() -> Bool {
        return value.map { !($0 is NSNull) } ?? false
    }

    public func child(forPath path: String) -> FireDataProtocol {
        return childData(byAppendingPath: path)
    }

    public func hasChild(_ childPathString: String) -> Bool {
        return hasChild(atPath: childPathString)
    }
}

public protocol FireDataRepresented {
    init(fireData: FireDataProtocol) throws
}
public protocol FireDataValueRepresented {
    var fireValue: FireDataValue { get } // TODO: Instead add variable that will return representer, or method `func represented()`
}

// MARK: FireDataValue ------------------------------------------------------------------

public protocol HasDefaultLiteral {
    init()
}

/// Protocol for values that only valid for Realtime Database, e.g. `(NS)Array`, `(NS)Dictionary` and etc.
/// You shouldn't apply for some custom values.
public protocol FireDataValue: FireDataRepresented {}
extension FireDataValue {
    public init(fireData: FireDataProtocol) throws {
        guard let v = fireData.value as? Self else {
            throw RealtimeError("Failed data for type: \(Self.self)")
        }

        self = v
    }
}

extension Optional: FireDataValue, FireDataRepresented where Wrapped: FireDataValue {
    public init(fireData: FireDataProtocol) throws {
        self = fireData.value as? Wrapped
    }
}
extension Array: FireDataValue, FireDataRepresented where Element: FireDataValue {
    public init(fireData: FireDataProtocol) throws {
        guard let v = fireData.value as? Array<Element> else {
            throw RealtimeError("Failed data for type: \(Array<Element>.self)")
        }

        self = v
    }
}

// TODO: Swift 4.2
//extension Dictionary: FireDataValue, FireDataRepresented where Key: FireDataValue, Value: FireDataValue {
//    public init(fireData: FireDataProtocol) throws {
//        guard let v = fireData.value as? [Key: Value] else {
//            throw RealtimeError("Failed data for type: \([Key: Value].self)")
//        }
//
//        self = v
//    }
//}

extension Dictionary: FireDataValue, FireDataRepresented where Key: FireDataValue, Value == FireDataValue {
    public init(fireData: FireDataProtocol) throws {
        guard let v = fireData.value as? [Key: Value] else {
            throw RealtimeError("Failed data for type: \([Key: Value].self)")
        }

        self = v
    }
}

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


// MARK: Representer --------------------------------------------------------------------------

public protocol Representer {
    associatedtype V
    func encode(_ value: V) throws -> Any?
    func decode(_ data: FireDataProtocol) throws -> V
}
extension Representer {
    func optional() -> AnyRepresenter<V?> {
        return AnyRepresenter(optional: self)
    }
}

public struct AnyRepresenter<V>: Representer {
    fileprivate let encoding: (V) throws -> Any?
    fileprivate let decoding: (FireDataProtocol) throws -> V
    public func decode(_ data: FireDataProtocol) throws -> V {
        return try decoding(data)
    }
    public func encode(_ value: V) throws -> Any? {
        return try encoding(value)
    }
    public init(encoding: @escaping (V) throws -> Any?, decoding: @escaping (FireDataProtocol) throws -> V) {
        self.encoding = encoding
        self.decoding = decoding
    }
}
public extension AnyRepresenter {
    init<R: Representer>(_ base: R) where V == R.V {
        self.encoding = base.encode
        self.decoding = base.decode
    }
    init<R: Representer>(optional base: R) where V == R.V? {
        self.encoding = { (v) -> Any? in
            return try v.map(base.encode)
        }
        self.decoding = { (data) -> R.V? in
            guard data.exists() else { return nil }
            return try base.decode(data)
        }
    }
    init<S: _Serializer>(serializer base: S.Type) where V == S.Entity {
        self.encoding = base.serialize
        self.decoding = base.deserialize
    }
}
public extension AnyRepresenter where V: RealtimeValue {
    static func relation(_ property: String) -> AnyRepresenter<V> {
        return AnyRepresenter<V>(
            encoding: { v in
                guard let node = v.node else { return nil }

                return Relation(path: node.rootPath, property: property).fireValue
        },
            decoding: { d in
                let relation = try Relation(fireData: d)
                return V(in: Node.root.child(with: relation.targetPath))
        })
    }

    static func reference(_ mode: RealtimeReference<V>.Mode) -> AnyRepresenter<V> {
        return AnyRepresenter<V>(
            encoding: { v in
                switch mode {
                case .fullPath:
                    if let ref = v.reference() {
                        return ref.fireValue
                    } else {
                        throw RealtimeError("Fail")
                    }
                case .key(from: let n):
                    if let ref = v.reference(from: n) {
                        return ref.fireValue
                    } else {
                        throw RealtimeError("Fail")
                    }
                }
        },
            decoding: { (data) in
                let reference = try Reference(fireData: data)
                let options: [RealtimeValueOption: Any] = [.internalPayload: InternalPayload(data.version, data.rawValue)]
                switch mode {
                case .fullPath: return reference.make(options: options)
                case .key(from: let n): return reference.make(in: n, options: options)
                }
        }
        )
    }
}
public extension AnyRepresenter {
    static var any: AnyRepresenter<V> {
        return AnyRepresenter<V>(encoding: { $0 }, decoding: { try $0.unbox(as: V.self) })
    }
}

public extension AnyRepresenter where V: RawRepresentable {
    static func `default`<R: Representer>(_ rawRepresenter: R) -> AnyRepresenter<V> where R.V == V.RawValue {
        return AnyRepresenter(
            encoding: { try rawRepresenter.encode($0.rawValue) },
            decoding: { d in
                guard let v = V(rawValue: try rawRepresenter.decode(d)) else {
                    throw RealtimeError("Fail")
                }
                return v
            }
        )
    }
}

public extension AnyRepresenter where V == URL {
    static var `default`: AnyRepresenter<URL> {
        return AnyRepresenter(
            encoding: { $0.absoluteString },
            decoding: URL.init
        )
    }
}

public extension AnyRepresenter where V: Codable {
    static var json: AnyRepresenter<V> {
        return AnyRepresenter(
            encoding: { v -> Any? in
                let data = try JSONEncoder().encode(v)
                return try JSONSerialization.jsonObject(with: data, options: .allowFragments)
            },
            decoding: V.init
        )
    }
}

public enum DateCodingStrategy {
    case secondsSince1970
    case millisecondsSince1970
    @available(iOS 10.0, *)
    case iso8601(ISO8601DateFormatter)
    case formatted(DateFormatter)
}
public extension AnyRepresenter where V == Date {
    static func date(_ strategy: DateCodingStrategy) -> AnyRepresenter<Date> {
        return AnyRepresenter<Date>(
            encoding: { date -> Any? in
                switch strategy {
                case .secondsSince1970:
                    return date.timeIntervalSince1970
                case .millisecondsSince1970:
                    return 1000.0 * date.timeIntervalSince1970
                case .iso8601(let formatter):
                    return formatter.string(from: date)
                case .formatted(let formatter):
                    return formatter.string(from: date)
                }
        },
            decoding: { (data) in
                switch strategy {
                case .secondsSince1970:
                    let double = try data.unbox(as: TimeInterval.self)
                    return Date(timeIntervalSince1970: double)
                case .millisecondsSince1970:
                    let double = try data.unbox(as: Double.self)
                    return Date(timeIntervalSince1970: double / 1000.0)
                case .iso8601(let formatter):
                    let string = try data.unbox(as: String.self)
                    guard let date = formatter.date(from: string) else {
                        throw RealtimeError("Expected date string to be ISO8601-formatted.")
                    }
                    return date
                case .formatted(let formatter):
                    let string = try data.unbox(as: String.self)
                    guard let date = formatter.date(from: string) else {
                        throw RealtimeError("Date string does not match format expected by formatter.")
                    }
                    return date
                }
        }
        )
    }
}

/// --------------------------- DataSnapshot Decoder ------------------------------

public extension FireDataProtocol {
    func unbox<T>(as type: T.Type) throws -> T {
        guard case let v as T = value else {
            throw RealtimeError("Fail")
        }
        return v
    }
}

extension Decoder where Self: FireDataProtocol {
    public var codingPath: [CodingKey] {
        return []
    }

    public var userInfo: [CodingUserInfoKey : Any] {
        return [CodingUserInfoKey(rawValue: "ref")!: dataRef as Any]
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

    fileprivate func childDecoder<Key: CodingKey>(forKey key: Key) throws -> FireDataProtocol {
        guard hasChild(key.stringValue) else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: [key], debugDescription: debugDescription))
        }
        return child(forPath: key.stringValue)
    }
}
extension DataSnapshot: Decoder {}
extension MutableData: Decoder {}

fileprivate struct DataSnapshotSingleValueContainer: SingleValueDecodingContainer {
    let snapshot: FireDataProtocol
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
    let snapshot: FireDataProtocol
    let enumerator: NSEnumerator

    init(snapshot: FireDataProtocol & Decoder) {
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

    private mutating func nextDecoder() throws -> FireDataProtocol {
        guard case let next as FireDataProtocol = enumerator.nextObject() else {
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
    let snapshot: FireDataProtocol

    var codingPath: [CodingKey] { return [] }
    var allKeys: [Key] { return snapshot.compactMap { $0.dataKey.flatMap(Key.init) } }

    private func _decode<T>(_ type: T.Type, forKey key: Key) throws -> T {
        let child = try snapshot.childDecoder(forKey: key)
        guard case let v as T = child.value else {
            throw DecodingError.valueNotFound(T.self, DecodingError.Context(codingPath: [key], debugDescription: child.debugDescription))
        }
        return v
    }

    func contains(_ key: Key) -> Bool {
        return snapshot.hasChild(key.stringValue)
    }

    func decodeNil(forKey key: Key) throws -> Bool { return try snapshot.childDecoder(forKey: key).value is NSNull }
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