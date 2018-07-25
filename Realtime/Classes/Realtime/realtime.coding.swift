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
    var fireValue: FireDataValue { get }
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

public protocol RealtimeValueRepresenter {
    associatedtype V
    func encode(_ value: V) throws -> Any?
    func decode(_ data: FireDataProtocol) throws -> V
}
extension RealtimeValueRepresenter {
    func optional() -> AnyRVRepresenter<V?> {
        return AnyRVRepresenter(optional: self)
    }
}

public struct AnyRVRepresenter<V>: RealtimeValueRepresenter {
    fileprivate let encoding: (V) throws -> Any?
    fileprivate let decoding: (FireDataProtocol) throws -> V
    public func decode(_ data: FireDataProtocol) throws -> V {
        return try decoding(data)
    }
    public func encode(_ value: V) throws -> Any? {
        return try encoding(value)
    }
}
public extension AnyRVRepresenter {
    init<R: RealtimeValueRepresenter>(_ base: R) where V == R.V {
        self.encoding = base.encode
        self.decoding = base.decode
    }
    init<R: RealtimeValueRepresenter>(optional base: R) where V == R.V? {
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
public extension AnyRVRepresenter where V: RealtimeValue {
    static func relation(_ property: String) -> AnyRVRepresenter<V?> {
        return AnyRVRepresenter<V?>(
            encoding: { v in
                guard let node = v?.node else { return nil }

                return Relation(path: node.rootPath, property: property).fireValue
        },
            decoding: { d in
                guard d.exists() else { return nil }

                let relation = try Relation(fireData: d)
                return V(in: Node.root.child(with: relation.targetPath))
        })
    }

    static func key(by rootedNode: Node) -> AnyRVRepresenter<V?> {
        let stringRepresenter: AnyRVRepresenter<String> = .default
        return AnyRVRepresenter<V?>(
            encoding: { $0?.dbKey },
            decoding: { (data) in
                guard data.exists() else { return nil }

                return V(in: Node(key: try stringRepresenter.decode(data), parent: rootedNode))
        }
        )
    }
}
public extension AnyRVRepresenter {
    static var `default`: AnyRVRepresenter<V> {
        return AnyRVRepresenter<V>(encoding: { $0 }, decoding: { d in
            guard let v = d.value as? V else { throw RealtimeError("Fail") }

            return v
        })
    }
}
