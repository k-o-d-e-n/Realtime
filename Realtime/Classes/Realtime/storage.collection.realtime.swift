//
//  storage.collection.realtime.swift
//  Realtime
//
//  Created by Denis Koryttsev on 21/11/2018.
//

import Foundation

/// A type that stores collection values and responsible for lazy initialization elements
protocol RealtimeCollectionStorage {
    associatedtype Value
}
protocol RCStorage: RealtimeCollectionStorage {
    associatedtype Key: Hashable, DatabaseKeyRepresentable
    var sourceNode: Node! { get }
    func storedValue(by key: Key) -> Value?
}
protocol MutableRCStorage: RCStorage {
    mutating func store(value: Value, by key: Key)
    mutating func remove(for key: Key)
}

/// Type-erased Realtime collection storage
struct AnyRCStorage: RealtimeCollectionStorage {
    public typealias Value = Any
}

public typealias RCElementBuilder<Element> = (Node, [ValueOption: Any]) -> Element
struct RCArrayStorage<K, V>: MutableRCStorage where V: RealtimeValue, K: RCViewItem {
    public typealias Value = V
    typealias Key = K
    var sourceNode: Node!
    let elementBuilder: RCElementBuilder<V>
    var elements: [String: Value] = [:]

    func storedValue(by key: K) -> Value? { return elements[for: key.dbKey] }

    mutating func store(value: Value, by key: K) { elements[for: key.dbKey] = value }
    mutating func remove(for key: K) {
        elements.removeValue(forKey: key.dbKey)
    }

    func buildElement(with key: K) -> V {
        return elementBuilder(sourceNode.child(with: key.dbKey), [.systemPayload: key.payload.system,
                                                                  .userPayload: key.payload.user as Any])
    }

    internal mutating func object(for key: Key) -> Value {
        guard let element = storedValue(by: key) else {
            let value = buildElement(with: key)
            store(value: value, by: key)

            return value
        }

        return element
    }
}

struct RCDictionaryStorage<K, V>: MutableRCStorage where K: HashableValue, V: RealtimeValue {
    public typealias Value = V
    var sourceNode: Node!
    let keysNode: Node
    let elementBuilder: (Node, [ValueOption: Any]) -> Value
    let keyBuilder: (Node, [ValueOption: Any]) -> Key
    var elements: [K: Value] = [:]

    func buildElement(with item: RDItem) -> V {
        return elementBuilder(sourceNode.child(with: item.dbKey), [.systemPayload: item.rcItem.payload.system,
                                                                   .userPayload: item.rcItem.payload.user as Any])
    }

    func buildKey(with item: RDItem) -> K {
        return keyBuilder(keysNode.child(with: item.dbKey), [.systemPayload: item.payload.system,
                                                             .userPayload: item.payload.user as Any])
    }

    func storedValue(by key: K) -> Value? { return elements[for: key] }

    mutating func store(value: Value, by key: K) { elements[for: key] = value }
    mutating func remove(for key: K) {
        elements.removeValue(forKey: key)
    }

    internal mutating func element(by key: RDItem) -> (Key, Value) {
        guard let element = storedElement(by: key.dbKey) else {
            let storeKey = buildKey(with: key)
            let value = buildElement(with: key)
            store(value: value, by: storeKey)

            return (storeKey, value)
        }

        return element
    }
    fileprivate func storedElement(by key: String) -> (Key, Value)? {
        return elements.first(where: { $0.key.dbKey == key })
    }
}
