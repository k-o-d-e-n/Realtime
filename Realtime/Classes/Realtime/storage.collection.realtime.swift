//
//  storage.collection.realtime.swift
//  Realtime
//
//  Created by Denis Koryttsev on 21/11/2018.
//

import Foundation

protocol KeyValueAccessableCollection: Collection {
    associatedtype Key
    associatedtype Value
    subscript(for key: Key) -> Value? { get set }
}

extension Array: KeyValueAccessableCollection {
    subscript(for key: Int) -> Element? {
        get { return self[key] }
        set {
            if let v = newValue {
                self[key] = v
            } else {
                self.remove(at: key)
            }
        }
    }
}
extension Dictionary: KeyValueAccessableCollection {
    subscript(for key: Key) -> Value? {
        get { return self[key] }
        set { self[key] = newValue }
    }
}

/// A type that stores collection values and responsible for lazy initialization elements
protocol RealtimeCollectionStorage: KeyValueAccessableCollection {
    associatedtype Value
}
protocol RCStorage: RealtimeCollectionStorage where Key: Hashable & DatabaseKeyRepresentable {
    func value(for key: Key) -> Value?
}
protocol MutableRCStorage: RCStorage {
    mutating func set(value: Value, for key: Key)
    @discardableResult
    mutating func remove(for key: Key) -> Value?
}
protocol RealtimeValueBuilderProtocol {
    associatedtype Value
    func build(with key: String, options: [ValueOption: Any]) -> Value
}
struct RealtimeValueBuilder<Value>: RealtimeValueBuilderProtocol {
    var spaceNode: Node!
    let impl: RCElementBuilder<Value>

    func build(with key: String, options: [ValueOption : Any]) -> Value {
        return impl(spaceNode.child(with: key), options)
    }
}
extension RealtimeValueBuilder {
    func buildValue(with item: RDItem) -> Value {
        return impl(spaceNode.child(with: item.dbKey), item.rcItem.defaultOptions)
    }
    func buildKey(with item: RDItem) -> Value {
        return impl(spaceNode.child(with: item.dbKey), item.defaultOptions)
    }
    func build<T>(with item: T) -> Value where T: RCExplicitElementProtocol {
        return impl(spaceNode.child(with: item.dbKey), item.defaultOptions)
    }
}

/// Type-erased Realtime collection storage
typealias AnyRCStorage = EmptyCollection

public typealias RCElementBuilder<Element> = (Node, [ValueOption: Any]) -> Element
typealias RCKeyValueStorage<V> = Dictionary<String, V>
extension String: DatabaseKeyRepresentable {
    public var dbKey: String! { return self }
}
extension Dictionary: RealtimeCollectionStorage where Key == String {
    func value(for key: Key) -> Value? {
        return self[key]
    }

    mutating func set(value: Value, for key: Key) {
        self[key] = value
    }

    @discardableResult
    mutating func remove(for key: Key) -> Value? {
        return removeValue(forKey: key)
    }
}
extension Dictionary: RCStorage where Key == String {}
extension Dictionary: MutableRCStorage where Key == String {}

struct RCDictionaryStorage<K, V>: MutableRCStorage where K: HashableValue {
    typealias Value = V
    typealias Key = K
    private var elements: [K: Value] = [:]

    func value(for key: K) -> Value? { return elements[for: key] }

    mutating func set(value: Value, for key: K) { elements[for: key] = value }
    @discardableResult
    mutating func remove(for key: K) -> Value? {
        return elements.removeValue(forKey: key)
    }

    subscript(for key: Key) -> Value? {
        get { return self.elements[key] }
        set { self.elements[key] = newValue }
    }

    func element(for key: String) -> (key: Key, value: Value)? {
        return elements.first(where: { $0.key.dbKey == key })
    }

    mutating func removeAll() {
        elements.removeAll()
    }

    func makeIterator() -> DictionaryIterator<K, V> {
        return elements.makeIterator()
    }
    var startIndex: Dictionary<K, V>.Index { return elements.startIndex }
    var endIndex: Dictionary<K, V>.Index { return elements.endIndex }
    func index(after i: Dictionary<K, V>.Index) -> Dictionary<K, V>.Index {
        return elements.index(after: i)
    }
    subscript(position: Dictionary<K, V>.Index) -> (key: Key, value: Value) {
        return elements[position]
    }
}
