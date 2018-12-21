//
//  realtime.coding.swift
//  Realtime
//
//  Created by Denis Koryttsev on 25/07/2018.
//

import Foundation
import FirebaseDatabase

// MARK: RealtimeDataProtocol ---------------------------------------------------------------

/// A type that contains data associated with database node.
public protocol RealtimeDataProtocol: Decoder, CustomDebugStringConvertible, CustomStringConvertible {
    var database: RealtimeDatabase? { get }
    var storage: RealtimeStorage? { get }
    var node: Node? { get }
    var key: String? { get }
    var value: Any? { get }
    var priority: Any? { get }
    var childrenCount: UInt { get }
    func makeIterator() -> AnyIterator<RealtimeDataProtocol>
    func exists() -> Bool
    func hasChildren() -> Bool
    func hasChild(_ childPathString: String) -> Bool
    func child(forPath path: String) -> RealtimeDataProtocol
    func map<T>(_ transform: (RealtimeDataProtocol) throws -> T) rethrows -> [T]
    func compactMap<ElementOfResult>(_ transform: (RealtimeDataProtocol) throws -> ElementOfResult?) rethrows -> [ElementOfResult]
    func forEach(_ body: (RealtimeDataProtocol) throws -> Swift.Void) rethrows
}

extension DataSnapshot: RealtimeDataProtocol, Sequence {
    public var key: String? {
        return self.ref.key
    }

    public var database: RealtimeDatabase? { return ref.database }
    public var storage: RealtimeStorage? { return nil }
    public var node: Node? { return Node.from(ref) }

    public func child(forPath path: String) -> RealtimeDataProtocol {
        return childSnapshot(forPath: path)
    }

    public func makeIterator() -> AnyIterator<RealtimeDataProtocol> {
        let childs = children
        return AnyIterator {
            return childs.nextObject() as? DataSnapshot
        }
    }
}
extension MutableData: RealtimeDataProtocol, Sequence {
    public var database: RealtimeDatabase? { return nil }
    public var storage: RealtimeStorage? { return nil }
    public var node: Node? { return key.map(Node.init) }

    public func exists() -> Bool {
        return value.map { !($0 is NSNull) } ?? false
    }

    public func child(forPath path: String) -> RealtimeDataProtocol {
        return childData(byAppendingPath: path)
    }

    public func hasChild(_ childPathString: String) -> Bool {
        return hasChild(atPath: childPathString)
    }

    public func makeIterator() -> AnyIterator<RealtimeDataProtocol> {
        let childs = children
        return AnyIterator {
            return childs.nextObject() as? MutableData
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
    init(data: RealtimeDataProtocol, exactly: Bool) throws

    /// Applies value of data snapshot
    ///
    /// - Parameters:
    ///   - data: Realtime database data
    ///   - exactly: Indicates that data should be applied as is (for example, empty values will be set to `nil`).
    ///               Pass `false` if data represents part of data (for example filtered list).
    mutating func apply(_ data: RealtimeDataProtocol, exactly: Bool) throws
}
extension RealtimeDataRepresented {
    init(data: RealtimeDataProtocol) throws {
        try self.init(data: data, exactly: true)
    }
    mutating public func apply(_ data: RealtimeDataProtocol, exactly: Bool) throws {
        self = try Self.init(data: data)
    }
    mutating func apply(_ data: RealtimeDataProtocol) throws {
        try apply(data, exactly: true)
    }
}

/// A type that can represented to an adopted Realtime database value
public protocol RealtimeDataValueRepresented {
    /// Value adopted for Realtime database
    var rdbValue: RealtimeDataValue { get } // TODO: Instead add variable that will return representer, or method `func represented()`
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

/// Protocol for values that only valid for Realtime Database, e.g. `(NS)Array`, `(NS)Dictionary` and etc.
/// You shouldn't apply for some custom values.
public protocol RealtimeDataValue: RealtimeDataRepresented {}
extension RealtimeDataValue {
    public init(data: RealtimeDataProtocol, exactly: Bool) throws {
        guard let v = data.value as? Self else {
            throw RealtimeError(initialization: Self.self, data.value as Any)
        }

        self = v
    }
}

//extension Optional: RealtimeDataValue where Wrapped: RealtimeDataValue {
//    public init(data: RealtimeDataProtocol) throws {
//        if data.exists() {
//            self = try Wrapped(data: data)
//        } else {
//            self = .none
//        }
//    }
//}
extension Array: RealtimeDataValue, RealtimeDataRepresented where Element: RealtimeDataValue {
    public init(data: RealtimeDataProtocol, exactly: Bool) throws {
        guard let v = data.value as? Array<Element> else {
            throw RealtimeError(initialization: Array<Element>.self, data.value as Any)
        }

        self = v
    }
}

// TODO: Swift 4.2
//extension Dictionary: RealtimeDataValue, FireDataRepresented where Key: RealtimeDataValue, Value: RealtimeDataValue {
//    public init(data: RealtimeDataProtocol) throws {
//        guard let v = data.value as? [Key: Value] else {
//            throw RealtimeError("Failed data for type: \([Key: Value].self)")
//        }
//
//        self = v
//    }
//}
extension Dictionary: RealtimeDataValue, RealtimeDataRepresented where Key: RealtimeDataValue, Value == RealtimeDataValue {
    public init(data: RealtimeDataProtocol, exactly: Bool) throws {
        guard let v = data.value as? [Key: Value] else {
            throw RealtimeError(initialization: [Key: Value].self, data.value as Any)
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
//extension Optional  : HasDefaultLiteral, _ComparableWithDefaultLiteral where Wrapped: HasDefaultLiteral & _ComparableWithDefaultLiteral {
//    public init() { self = .none }
//    public static func _isDefaultLiteral(_ lhs: Optional<Wrapped>) -> Bool {
//        return lhs.map(Wrapped._isDefaultLiteral) ?? lhs == nil
//    }
//}
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

/// A type that can convert itself into and out of an external representation.
public protocol RepresenterProtocol {
    associatedtype V
    /// Encodes this value to untyped value
    ///
    /// - Parameter value:
    /// - Returns: Untyped value
    func encode(_ value: V) throws -> Any?
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
    func encode<T>(_ value: V) throws -> Any? where V == Optional<T> {
        return try value.map(encode)
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
    fileprivate let encoding: (V) throws -> Any?
    fileprivate let decoding: (RealtimeDataProtocol) throws -> V
    public func decode(_ data: RealtimeDataProtocol) throws -> V {
        return try decoding(data)
    }
    public func encode(_ value: V) throws -> Any? {
        return try encoding(value)
    }
    public init(encoding: @escaping (V) throws -> Any?, decoding: @escaping (RealtimeDataProtocol) throws -> V) {
        self.encoding = encoding
        self.decoding = decoding
    }
    public init<T>(encoding: @escaping (T) throws -> Any?, decoding: @escaping (RealtimeDataProtocol) throws -> T) where V == Optional<T> {
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
    public init<R: RepresenterProtocol>(_ base: R) where V == R.V {
        self.encoding = base.encode
        self.decoding = base.decode
    }
    public init<R: RepresenterProtocol>(optional base: R) where V == R.V? {
        self.encoding = { (v) -> Any? in
            return try v.map(base.encode)
        }
        self.decoding = { (data) in
            guard data.exists() else { return nil }
            return try base.decode(data)
        }
    }
    public init<R: RepresenterProtocol>(collection base: R) where V: Collection, V.Element == R.V, V: ExpressibleBySequence, V.SequenceElement == V.Element {
        self.encoding = { (v) -> Any? in
            return try v.map(base.encode)
        }
        self.decoding = { (data) -> V in
            return try V(data.map(base.decode))
        }
    }
    public init<R: RepresenterProtocol>(defaultOnEmpty base: R) where R.V: HasDefaultLiteral & _ComparableWithDefaultLiteral, V == R.V {
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
    init<R: RepresenterProtocol, T>(defaultOnEmpty base: R) where T: HasDefaultLiteral & _ComparableWithDefaultLiteral, Optional<T> == R.V, Optional<T> == V {
        self.encoding = { (v) -> Any? in
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
            encoding: { (collection) -> Any? in
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
    static func relation(_ mode: RelationMode, rootLevelsUp: Int?, ownerNode: ValueStorage<Node?>) -> Representer<V> {
        return Representer<V>(
            encoding: { v in
                guard let owner = ownerNode.value else { throw RealtimeError(encoding: V.self, reason: "Can`t get relation owner node") }
                guard let node = v.node else { throw RealtimeError(encoding: V.self, reason: "Can`t get relation value node.") }
                let rootNode = try rootLevelsUp.map { level -> Node in
                    if let ancestor = owner.ancestor(onLevelUp: level) {
                        return ancestor
                    } else {
                        throw RealtimeError(encoding: V.self, reason: "Couldn`t get root node")
                    }
                }

                return RelationRepresentation(path: node.path(from: rootNode ?? .root), property: mode.path(for: owner)).rdbValue
        },
            decoding: { d in
                let relation = try RelationRepresentation(data: d)
                return V(in: Node.root.child(with: relation.targetPath), options: [:])
        })
    }

    /// Representer that convert `RealtimeValue` as database reference.
    ///
    /// - Parameter mode: Representation mode
    /// - Returns: Reference representer
    static func reference(_ mode: ReferenceMode, options: [ValueOption: Any]) -> Representer<V> {
        return Representer<V>(
            encoding: { v in
                switch mode {
                case .fullPath:
                    if let ref = v.reference() {
                        return ref.rdbValue
                    } else {
                        throw RealtimeError(source: .coding, description: "Can`t get reference from value \(v), using mode \(mode)")
                    }
                case .path(from: let n):
                    if let ref = v.reference(from: n) {
                        return ref.rdbValue
                    } else {
                        throw RealtimeError(source: .coding, description: "Can`t get reference from value \(v), using mode \(mode)")
                    }
                }
        },
            decoding: { (data) in
                let reference = try ReferenceRepresentation(data: data)
                switch mode {
                case .fullPath: return reference.make(options: options)
                case .path(from: let n): return reference.make(in: n, options: options)
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
public extension Representer where V: RealtimeDataRepresented & RealtimeDataValueRepresented {
    static var realtimeData: Representer<V> {
        return Representer<V>(encoding: { $0.rdbValue }, decoding: V.init)
    }
}

extension Representer {
    public func requiredProperty() -> Representer<V?> {
        return Representer<V?>(required: self)
    }

    init<R: RepresenterProtocol>(required base: R) where V == R.V? {
        self.encoding = { (value) -> Any? in
            switch value {
            case .none: throw RealtimeError(encoding: R.V.self, reason: "Required property has not been set")
            case .some(let v): return try base.encode(v)
            }
        }
        self.decoding = { data -> V in
            guard data.exists() else {
                return nil
            }
            return .some(try base.decode(data))
        }
    }

    public func optionalProperty() -> Representer<V??> {
        return Representer<V??>(optionalProperty: self)
    }

    init<R: RepresenterProtocol>(optionalProperty base: R) where V == R.V?? {
        self.encoding = { (value) -> Any? in
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
        self.encoding = { (value) -> Any? in
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
        return self.default(Representer<V.RawValue>.any)
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
    static func json(dateEncodingStrategy: JSONEncoder.DateEncodingStrategy = .secondsSince1970,
                     keyEncodingStrategy: JSONEncoder.KeyEncodingStrategy = .useDefaultKeys) -> Representer<V> {
        return Representer(
            encoding: { v -> Any? in
                let e = JSONEncoder()
                e.dateEncodingStrategy = dateEncodingStrategy
                e.keyEncodingStrategy = keyEncodingStrategy
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
                guard let data = img.pngData() else {
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
                guard let data = img.jpegData(compressionQuality: quality) else {
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

public extension RealtimeDataProtocol {
    func unbox<T>(as type: T.Type) throws -> T {
        guard case let v as T = value else {
            throw RealtimeError(decoding: T.self, self, reason: "Mismatch type")
        }
        return v
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
extension DataSnapshot: Decoder {}
extension MutableData: Decoder {}

fileprivate struct DataSnapshotSingleValueContainer: SingleValueDecodingContainer {
    let snapshot: RealtimeDataProtocol
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
        if let value = try nextDecoder().value {
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
    let snapshot: RealtimeDataProtocol

    var codingPath: [CodingKey] { return [] }
    var allKeys: [Key] { return snapshot.compactMap { $0.node.flatMap { Key(stringValue: $0.key) } } }

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
