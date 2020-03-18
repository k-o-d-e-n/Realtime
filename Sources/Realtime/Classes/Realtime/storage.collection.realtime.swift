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

/// Type-erased Realtime collection storage
typealias AnyRCStorage = EmptyCollection

public typealias RCElementBuilder<ViewElement, Element> = (Node?, RealtimeDatabase?, ViewElement) -> Element
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

struct SortedDictionary<Key: Hashable & Comparable, Value>: BidirectionalCollection {
    var storage: [Key: Value] = [:]
    var keys: SortedArray<Key> = []

    typealias Element = (key: Key, value: Value)
    typealias Index = SortedArray<Key>.Index
    func makeIterator() -> IndexingIterator<SortedDictionary<Key, Value>> {
        return IndexingIterator(_elements: self)
    }
    var startIndex: Index { return keys.startIndex }
    var endIndex: Index { return keys.endIndex }
    func index(before i: Index) -> Index {
        return keys.index(before: i)
    }
    func index(after i: Index) -> Index {
        return keys.index(after: i)
    }
    subscript(position: Index) -> (key: Key, value: Value) {
        let key = keys[position]
        return (key, storage[key]!)
    }

    subscript(key: Key) -> Value? {
        get { return storage[key] }
        set {
            if let new = newValue {
                if storage.updateValue(new, forKey: key) == nil {
                    keys.insert(key)
                }
            } else {
                storage.removeValue(forKey: key)
                _ = keys.remove(key)
            }
        }
    }

    mutating func removeAll() {
        storage.removeAll()
        keys.removeAll()
    }

    mutating func update(_ value: Value, for key: Key) {
        if storage.updateValue(value, forKey: key) == nil {
            keys.insert(key)
        }
    }

    mutating func removeValue(for key: Key) -> (index: Index, value: Value)? {
        if let value = storage.removeValue(forKey: key), let index = keys.remove(key)?.index {
            return (index, value)
        } else {
            return nil
        }
    }
}
extension SortedDictionary: KeyValueAccessableCollection {
    subscript(for key: Key) -> Value? {
        get { return self[key] }
        set { self[key] = newValue }
    }
}
extension SortedDictionary: ExpressibleByDictionaryLiteral {
    init(dictionaryLiteral elements: (Key, Value)...) {
        let keysStorage: ([Key: Value], [Key]) = elements.reduce(into: ([:], []), { result, keyValue in
            result.0[keyValue.0] = keyValue.1
            result.1.append(keyValue.0)
        })
        self.init(
            storage: keysStorage.0,
            keys: SortedArray(unsorted: keysStorage.1)
        )
    }
}
extension SortedDictionary: RealtimeCollectionStorage {}
extension SortedDictionary: RCStorage where Key: DatabaseKeyRepresentable {
    func value(for key: Key) -> Value? {
        return self[key]
    }
}
extension SortedDictionary: MutableRCStorage where Key: DatabaseKeyRepresentable {
    mutating func set(value: Value, for key: Key) {
        update(value, for: key)
    }
    mutating func remove(for key: Key) -> Value? {
        return removeValue(for: key)?.value
    }
    func element(for key: String) -> (key: Key, value: Value)? {
        return storage.first(where: { $0.key.dbKey == key })
    }
}

typealias RCDictionaryStorage<K, V> = SortedDictionary<K, V> where K: HashableValue & Comparable
