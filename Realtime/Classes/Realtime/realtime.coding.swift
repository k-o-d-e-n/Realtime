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
    var dataKey: String? { get }
    var dataRef: DatabaseReference? { get }
    var childrenCount: UInt { get }
    func makeIterator() -> AnyIterator<FireDataProtocol>
    func exists() -> Bool
    func hasChildren() -> Bool
    func hasChild(_ childPathString: String) -> Bool
    func child(forPath path: String) -> FireDataProtocol
    func map<T>(_ transform: (FireDataProtocol) throws -> T) rethrows -> [T]
    func compactMap<ElementOfResult>(_ transform: (FireDataProtocol) throws -> ElementOfResult?) rethrows -> [ElementOfResult]
    func forEach(_ body: (FireDataProtocol) throws -> Swift.Void) rethrows
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

    public func makeIterator() -> AnyIterator<FireDataProtocol> {
        let childs = children
        return AnyIterator {
            return childs.nextObject() as? DataSnapshot
        }
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

    public func makeIterator() -> AnyIterator<FireDataProtocol> {
        let childs = children
        return AnyIterator {
            return childs.nextObject() as? MutableData
        }
    }
}

public protocol FireDataRepresented {
    init(fireData: FireDataProtocol) throws // TODO: May be need remove from protocol declaration and add as extension.

    /// Applies value of data snapshot
    ///
    /// - Parameters:
    ///   - snapshot: Snapshot value
    ///   - strongly: Indicates that snapshot should be applied as is (for example, empty values will be set to `nil`).
    ///               Pass `false` if snapshot represents part of data (for example filtered list).
    mutating func apply(_ data: FireDataProtocol, strongly: Bool) throws
}
extension FireDataRepresented {
    mutating public func apply(_ data: FireDataProtocol, strongly: Bool) throws {
        self = try Self.init(fireData: data)
    }
    mutating func apply(_ data: FireDataProtocol) throws {
        try apply(data, strongly: true)
    }
}
public protocol FireDataValueRepresented {
    var fireValue: FireDataValue { get } // TODO: Instead add variable that will return representer, or method `func represented()`
}

// MARK: FireDataValue ------------------------------------------------------------------

public protocol HasDefaultLiteral {
    init()
}
public protocol _ComparableWithDefaultLiteral {
    static func _isDefaultLiteral(_ lhs: Self) -> Bool
}
extension _ComparableWithDefaultLiteral where Self: HasDefaultLiteral & Equatable {
    public static func _isDefaultLiteral(_ lhs: Self) -> Bool {
        return lhs == Self()
    }
}

/// Protocol for values that only valid for Realtime Database, e.g. `(NS)Array`, `(NS)Dictionary` and etc.
/// You shouldn't apply for some custom values.
public protocol FireDataValue: FireDataRepresented {}
extension FireDataValue {
    public init(fireData: FireDataProtocol) throws {
        guard let v = fireData.value as? Self else {
            throw RealtimeError(initialization: Self.self, fireData.value as Any)
        }

        self = v
    }
}

//extension Optional: FireDataValue where Wrapped: FireDataValue {
//    public init(fireData: FireDataProtocol) throws {
//        if fireData.exists() {
//            self = try Wrapped(fireData: fireData)
//        } else {
//            self = .none
//        }
//    }
//}
extension Array: FireDataValue, FireDataRepresented where Element: FireDataValue {
    public init(fireData: FireDataProtocol) throws {
        guard let v = fireData.value as? Array<Element> else {
            throw RealtimeError(initialization: Array<Element>.self, fireData.value as Any)
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
            throw RealtimeError(initialization: [Key: Value].self, fireData.value as Any)
        }

        self = v
    }
}

extension Optional  : HasDefaultLiteral, _ComparableWithDefaultLiteral {
    public init() { self = .none }
    public static func _isDefaultLiteral(_ lhs: Optional<Wrapped>) -> Bool {
        return lhs == nil
    }
}
extension Bool      : HasDefaultLiteral, _ComparableWithDefaultLiteral, FireDataValue {}
extension Int       : HasDefaultLiteral, _ComparableWithDefaultLiteral, FireDataValue {}
extension Double    : HasDefaultLiteral, _ComparableWithDefaultLiteral, FireDataValue {}
extension Float     : HasDefaultLiteral, _ComparableWithDefaultLiteral, FireDataValue {}
extension Int8      : HasDefaultLiteral, _ComparableWithDefaultLiteral, FireDataValue {}
extension Int16     : HasDefaultLiteral, _ComparableWithDefaultLiteral, FireDataValue {}
extension Int32     : HasDefaultLiteral, _ComparableWithDefaultLiteral, FireDataValue {}
extension Int64     : HasDefaultLiteral, _ComparableWithDefaultLiteral, FireDataValue {}
extension UInt      : HasDefaultLiteral, _ComparableWithDefaultLiteral, FireDataValue {}
extension UInt8     : HasDefaultLiteral, _ComparableWithDefaultLiteral, FireDataValue {}
extension UInt16    : HasDefaultLiteral, _ComparableWithDefaultLiteral, FireDataValue {}
extension UInt32    : HasDefaultLiteral, _ComparableWithDefaultLiteral, FireDataValue {}
extension UInt64    : HasDefaultLiteral, _ComparableWithDefaultLiteral, FireDataValue {}
extension String    : HasDefaultLiteral, _ComparableWithDefaultLiteral, FireDataValue {}
extension Data      : HasDefaultLiteral, _ComparableWithDefaultLiteral {}
extension Array     : HasDefaultLiteral {}
extension Dictionary: HasDefaultLiteral {}
extension Array: _ComparableWithDefaultLiteral {
    public static func _isDefaultLiteral(_ lhs: Array<Element>) -> Bool {
        return lhs.isEmpty
    }
}
extension Dictionary: _ComparableWithDefaultLiteral {
    public static func _isDefaultLiteral(_ lhs: Dictionary<Key, Value>) -> Bool {
        return lhs.isEmpty
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

public protocol RepresenterProtocol {
    associatedtype V
    func encode(_ value: V) throws -> Any?
    func decode(_ data: FireDataProtocol) throws -> V
}
public extension RepresenterProtocol {
    func optional() -> Representer<V?> {
        return Representer(optional: self)
    }
//    func encode(_ value: V?) throws -> Any? {
//        return try value.map(encode)
//    }
//    func decode(_ data: FireDataProtocol) throws -> V? {
//        guard data.exists() else { return nil }
//        return try decode(data)
//    }
}
extension RepresenterProtocol where V: HasDefaultLiteral & _ComparableWithDefaultLiteral {
    func defaultOnEmpty() -> Representer<V> {
        return Representer(defaultOnEmpty: self)
    }
}
public extension Representer {
    func encode<T>(_ value: V) throws -> Any? where V == Optional<T> {
        return try value.map(encode)
    }
    func decode<T>(_ data: FireDataProtocol) throws -> V where V == Optional<T> {
        guard data.exists() else { return nil }
        return try decode(data)
    }
}

public struct Representer<V>: RepresenterProtocol {
    fileprivate let encoding: (V) throws -> Any?
    fileprivate let decoding: (FireDataProtocol) throws -> V
    public func decode(_ data: FireDataProtocol) throws -> V {
        return try decoding(data)
    }
    public func encode(_ value: V) throws -> Any? {
        return try encoding(value)
    }
    public init(_: V.Type = V.self, encoding: @escaping (V) throws -> Any?, decoding: @escaping (FireDataProtocol) throws -> V) {
        self.encoding = encoding
        self.decoding = decoding
    }
    public init<T>(encoding: @escaping (T) throws -> Any?, decoding: @escaping (FireDataProtocol) throws -> T) where V == Optional<T> {
        self.encoding = { v -> Any? in
            return try v.map(encoding)
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
        self.encoding = { (v) -> Any? in
            return try v.map(base.encode)
        }
        self.decoding = { (data) in
            guard data.exists() else { return nil }
            return try base.decode(data)
        }
    }
    init<R: RepresenterProtocol>(collection base: R) where V: Collection, V.Element == R.V, V: ExpressibleByArrayLiteral, V.ArrayLiteralElement == V.Element {
        self.encoding = { (v) -> Any? in
            return try v.map(base.encode)
        }
        self.decoding = { (data) -> V in
            return try data.map(base.decode) as! V
        }
    }
    init<R: RepresenterProtocol>(defaultOnEmpty base: R) where R.V: HasDefaultLiteral & _ComparableWithDefaultLiteral, V == R.V {
        self.encoding = { (v) -> Any? in
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
    init<S: _Serializer>(serializer base: S.Type) where V == S.Entity {
        self.encoding = base.serialize
        self.decoding = base.deserialize
    }
}
public extension Representer where V: RealtimeValue {
    static func relation(_ property: RelationMode, rootLevelsUp: Int?, ownerNode: Property<Node?>) -> Representer<V> {
        return Representer<V>(
            encoding: { v in
                guard let owner = ownerNode.value else { throw RealtimeError(encoding: V.self, reason: "Can`t get relation owner node") }
                guard let node = v.node else { throw RealtimeError(encoding: V.self, reason: "Can`t get relation value node.") }

                return Relation(path: rootLevelsUp.map(node.path) ?? node.rootPath, property: property.path(for: owner)).fireValue
        },
            decoding: { d in
                let relation = try Relation(fireData: d)
                return V(in: Node.root.child(with: relation.targetPath))
        })
    }

    static func reference(_ mode: ReferenceMode) -> Representer<V> {
        return Representer<V>(
            encoding: { v in
                switch mode {
                case .fullPath:
                    if let ref = v.reference() {
                        return ref.fireValue
                    } else {
                        throw RealtimeError(source: .coding, description: "Can`t get reference from value \(v), using mode \(mode)")
                    }
                case .key(from: let n):
                    if let ref = v.reference(from: n) {
                        return ref.fireValue
                    } else {
                        throw RealtimeError(source: .coding, description: "Can`t get reference from value \(v), using mode \(mode)")
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
public extension Representer {
    static var any: Representer<V> {
        return Representer<V>(encoding: { $0 }, decoding: { try $0.unbox(as: V.self) })
    }
}
public extension Representer where V: FireDataRepresented & FireDataValueRepresented {
    static var fireData: Representer<V> {
        return Representer<V>(encoding: { $0.fireValue }, decoding: V.init)
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
            encoding: { $0.absoluteString },
            decoding: URL.init
        )
    }
}

public extension Representer where V: Codable {
    static var json: Representer<V> {
        return Representer(
            encoding: { v -> Any? in
                let data = try JSONEncoder().encode(v)
                return try JSONSerialization.jsonObject(with: data, options: .allowFragments)
            },
            decoding: V.init
        )
    }
}

import UIKit.UIImage

public extension Representer where V: UIImage {
    static var png: Representer<UIImage> {
        let base = Representer<Data>.any
        return Representer<UIImage>(
            encoding: { img -> Any? in
                guard let data = UIImagePNGRepresentation(img) else {
                    throw RealtimeError(encoding: V.self, reason: "Can`t get image data in .png representation")
                }
                return data
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
        let base = Representer<Data>.any
        return Representer<UIImage>(
            encoding: { img -> Any? in
                guard let data = UIImageJPEGRepresentation(img, quality) else {
                    throw RealtimeError(encoding: V.self, reason: "Can`t get image data in .jpeg representation with compression quality: \(quality)")
                }
                return data
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

public enum DateCodingStrategy {
    case secondsSince1970
    case millisecondsSince1970
    @available(iOS 10.0, *)
    case iso8601(ISO8601DateFormatter)
    case formatted(DateFormatter)
}
public extension Representer where V == Date {
    static func date(_ strategy: DateCodingStrategy) -> Representer<Date> {
        return Representer<Date>(
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
                        throw RealtimeError(decoding: V.self, string, reason: "Expected date string to be ISO8601-formatted.")
                    }
                    return date
                case .formatted(let formatter):
                    let string = try data.unbox(as: String.self)
                    guard let date = formatter.date(from: string) else {
                        throw RealtimeError(decoding: V.self, string, reason: "Date string does not match format expected by formatter.")
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
            throw RealtimeError(decoding: T.self, self, reason: "Mismatch type")
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
    let iterator: AnyIterator<FireDataProtocol>

    init(snapshot: FireDataProtocol & Decoder) {
        self.snapshot = snapshot
        self.iterator = snapshot.makeIterator()
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
        guard let next = iterator.next() else {
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
