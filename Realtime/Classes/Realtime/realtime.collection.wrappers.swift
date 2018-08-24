//
//  RealtimeCollectionWrappers.swift
//  Realtime
//
//  Created by Denis Koryttsev on 16/03/2018.
//

import Foundation

// MARK: Type erased realtime collection

struct AnyCollectionKey: Hashable, DatabaseKeyRepresentable {
    let dbKey: String!
    var hashValue: Int { return dbKey.hashValue }

    init<Base: DatabaseKeyRepresentable>(_ key: Base) {
        self.dbKey = key.dbKey
    }
    //    init<Base: RealtimeCollectionContainerKey>(_ key: Base) where Base.Key == String {
    //        self.key = key.key
    //    }
    static func ==(lhs: AnyCollectionKey, rhs: AnyCollectionKey) -> Bool {
        return lhs.dbKey == rhs.dbKey
    }
}

internal class _AnyRealtimeCollectionBase<Element>: Collection {
    var node: Node? { fatalError() }
    var version: Int? { fatalError() }
    var raw: FireDataValue? { fatalError() }
    var payload: [String : FireDataValue]? { fatalError() }
    var view: RealtimeCollectionView { fatalError() }
    var isPrepared: Bool { fatalError() }
    func makeIterator() -> AnyIterator<Element> { fatalError() }
    var startIndex: Int { fatalError() }
    var endIndex: Int { fatalError() }
    func index(after i: Int) -> Int { fatalError() }
    func index(before i: Int) -> Int { fatalError() }
    subscript(position: Int) -> Element { fatalError() }
    func apply(_ data: FireDataProtocol, exactly: Bool) throws { fatalError() }
    func runObserving() -> Bool { fatalError() }
    func stopObserving() { fatalError() }
    func listening(changes handler: @escaping () -> Void) -> ListeningItem { fatalError() }
    public func prepare(forUse completion: Assign<Error?>) { fatalError() }
    var debugDescription: String { return "" }
    func load(completion: Assign<Error?>?) { fatalError() }
    var canObserve: Bool { fatalError() }
}

internal final class __AnyRealtimeCollection<C: RealtimeCollection>: _AnyRealtimeCollectionBase<C.Iterator.Element>
where C.Index == Int {
    var base: C
    required init(base: C) {
        self.base = base
    }

    convenience required init(fireData: FireDataProtocol) throws {
        let base = try C(fireData: fireData)
        self.init(base: base)
    }

    convenience required init(in node: Node) {
        self.init(base: C(in: node))
    }

    override var node: Node? { return base.node }
    override var payload: [String : FireDataValue]? { return base.payload }
    override var view: RealtimeCollectionView { return base.view }
    override var isPrepared: Bool { return base.isPrepared }

    override func makeIterator() -> AnyIterator<C.Iterator.Element> { return AnyIterator(base.makeIterator()) }
    override var startIndex: Int { return base.startIndex }
    override var endIndex: Int { return base.endIndex }
    override func index(after i: Int) -> Int { return base.index(after: i) }
    override func index(before i: Int) -> Int { return base.index(before: i) }
    override subscript(position: Int) -> C.Iterator.Element { return base[position] }

    override func apply(_ data: FireDataProtocol, exactly: Bool) throws { try base.apply(data, exactly: exactly) }
    override func prepare(forUse completion: Assign<Error?>) { base.prepare(forUse: completion) }
    override func listening(changes handler: @escaping () -> Void) -> ListeningItem { return base.listening(changes: handler) }
    override func runObserving() -> Bool { return base.runObserving() }
    override func stopObserving() { base.stopObserving() }
    override func load(completion: Assign<Error?>?) { base.load(completion: completion) }
    /// Indicates that value can observe. It is true when object has rooted node, otherwise false.
    override var canObserve: Bool { return base.canObserve }
}

public final class AnyRealtimeCollection<Element>: RealtimeCollection {
    private let base: _AnyRealtimeCollectionBase<Element>

    public init<C: RealtimeCollection>(_ base: C) where C.Iterator.Element == Element, C.Index == Int {
        self.base = __AnyRealtimeCollection<C>(base: base)
    }

    public convenience init(in node: Node?, options: [RealtimeValueOption: Any]) {
        fatalError("Cannot use this initializer")
    }

    public var node: Node? { return base.node }
    public var version: Int? { return base.version }
    public var raw: FireDataValue? { return base.raw }
    public var payload: [String : FireDataValue]? { return base.payload }
    public var storage: AnyArrayStorage = AnyArrayStorage()
    public var view: RealtimeCollectionView { return base.view }
    public var isPrepared: Bool { return base.isPrepared }
    public var startIndex: Int { return base.startIndex }
    public var endIndex: Int { return base.endIndex }
    public func index(after i: Index) -> Int { return base.index(after: i) }
    public func index(before i: Int) -> Int { return base.index(before: i) }
    public subscript(position: Int) -> Element { return base[position] }
    public var debugDescription: String { return base.debugDescription }
    public func prepare(forUse completion: Assign<(Error?)>) { base.prepare(forUse: completion) }
    public func didPrepare() {}
    public func load(completion: Assign<Error?>?) { base.load(completion: completion) }
    public func listening(changes handler: @escaping () -> Void) -> ListeningItem { return base.listening(changes: handler) }
    public var canObserve: Bool { return base.canObserve }
    public func runObserving() -> Bool { return base.runObserving() }
    public func stopObserving() { base.stopObserving() }
    public convenience required init(fireData: FireDataProtocol, exactly: Bool) throws { fatalError() }
    public func apply(_ data: FireDataProtocol, exactly: Bool) throws { try base.apply(data, exactly: exactly) }
}

// TODO: Create wrapper that would sort array (sorting by default) (example array from tournament table)
// 1) Sorting performs before save prototype (storing sorted array)
// 2) Sorting performs after load prototype (runtime sorting)

public extension RealtimeArray {
    func keyed<Keyed: RealtimeValue, Key: RawRepresentable>(by key: Key, elementBuilder: @escaping (Node) -> Keyed = Keyed.init)
        -> KeyedRealtimeCollection<Keyed, Element> where Key.RawValue == String {
            return KeyedRealtimeCollection(base: self, key: key, elementBuilder: elementBuilder)
    }
}
public extension LinkedRealtimeArray {
    func keyed<Keyed: RealtimeValue, Key: RawRepresentable>(by key: Key, elementBuilder: @escaping (Node) -> Keyed = Keyed.init)
        -> KeyedRealtimeCollection<Keyed, Element> where Key.RawValue == String {
            return KeyedRealtimeCollection(base: self, key: key, elementBuilder: elementBuilder)
    }
}
public extension RealtimeDictionary {
    func keyed<Keyed: RealtimeValue, Key: RawRepresentable>(by key: Key, elementBuilder: @escaping (Node) -> Keyed = Keyed.init)
        -> KeyedRealtimeCollection<Keyed, Element> where Key.RawValue == String {
            return KeyedRealtimeCollection(base: self, key: key, elementBuilder: elementBuilder)
    }
}

struct AnySharedCollection<Element>: Collection {
    let _startIndex: () -> Int
    let _endIndex: () -> Int
    let _indexAfter: (Int) -> Int
    let _subscript: (Int) -> Element

    init<Base: Collection>(_ base: Base) where Base.Iterator.Element == Element, Base.Index: SignedInteger {
        self._startIndex = { return base.startIndex.toOther() }
        self._endIndex = { return base.endIndex.toOther() }
        self._indexAfter = { return base.index(after: $0.toOther()).toOther() }
        self._subscript = { return base[$0.toOther()] }
    }

    public var startIndex: Int { return _startIndex() }
    public var endIndex: Int { return _endIndex() }
    public func index(after i: Int) -> Int { return _indexAfter(i) }
    public subscript(position: Int) -> Element { return _subscript(position) }
}

public struct KeyedCollectionStorage<V>: MutableRCStorage {
    public typealias Value = V
    let key: String
    let sourceNode: Node!
    let elementBuilder: (Node) -> Value
    var elements: [AnyCollectionKey: Value] = [:]

    init<Source: RCStorage>(_ base: Source, key: String, builder: @escaping (Node) -> Value) {
        self.key = key
        self.elementBuilder = builder
        self.sourceNode = base.sourceNode
    }

    mutating func store(value: Value, by key: AnyCollectionKey) { elements[for: key] = value }
    func storedValue(by key: AnyCollectionKey) -> Value? { return elements[for: key] }

    func buildElement(with key: AnyCollectionKey) -> V {
        return elementBuilder(sourceNode.child(with: key.dbKey).child(with: self.key))
    }
}

@available(*, deprecated: 0.3.7, message: "Use MapRealtimeCollection instead")
public final class KeyedRealtimeCollection<Element, BaseElement>: RealtimeCollection
where Element: RealtimeValue {
    public typealias Index = Int
    private let base: _AnyRealtimeCollectionBase<BaseElement>
    private let baseView: AnySharedCollection<AnyCollectionKey>

    init<B: RC, Key: RawRepresentable>(base: B, key: Key, elementBuilder: @escaping (Node) -> Element = Element.init)
        where B.View.Iterator.Element: DatabaseKeyRepresentable,
        B.View.Index: SignedInteger, B.Iterator.Element == BaseElement, B.Index == Int, Key.RawValue == String {
            guard base.isRooted else { fatalError("Only rooted collections can use in keyed collection") }
            self.base = __AnyRealtimeCollection(base: base)
            self.storage = KeyedCollectionStorage(base.storage, key: key.rawValue, builder: elementBuilder)
            self.baseView = AnySharedCollection(base._view.lazy.map(AnyCollectionKey.init))
    }

    public init(in node: Node?, options: [RealtimeValueOption: Any]) {
        fatalError()
    }

    public var node: Node? { return base.node }
    public var version: Int? { return base.version }
    public var raw: FireDataValue? { return base.raw }
    public var payload: [String : FireDataValue]? { return base.payload }
    public var view: RealtimeCollectionView { return base.view }
    public var storage: KeyedCollectionStorage<Element>
    public var isPrepared: Bool { return base.isPrepared }

    public var startIndex: Index { return base.startIndex }
    public var endIndex: Index { return base.endIndex }
    public func index(after i: Index) -> Index { return base.index(after: i) }
    public func index(before i: Int) -> Int { return base.index(before: i) }
    public subscript(position: Int) -> Element { return storage.object(for: baseView[position]) }
    public var debugDescription: String { return base.debugDescription }
    public func prepare(forUse completion: Assign<(Error?)>) { base.prepare(forUse: completion) }

    public func load(completion: Assign<Error?>?) { base.load(completion: completion) }
    public var canObserve: Bool { return base.canObserve }

    public func listening(changes handler: @escaping () -> Void) -> ListeningItem {
        return base.listening(changes: handler)
    }
    public func runObserving() -> Bool {
        return base.runObserving()
    }
    public func stopObserving() {
        base.stopObserving()
    }

    public convenience required init(fireData: FireDataProtocol, exactly: Bool) throws {
        fatalError("Cannot use this initializer")
    }

    public func apply(_ data: FireDataProtocol, exactly: Bool) throws {
        try base.apply(data, exactly: exactly)
    }

    public func didPrepare() { fatalError() }
}

public extension RealtimeCollection {
    func lazyMap<Mapped>(_ transform: @escaping (Element) -> Mapped) -> MapRealtimeCollection<Mapped, Self> {
        return MapRealtimeCollection(base: self, transform: transform)
    }
}

public final class MapRealtimeCollection<Element, Base: RealtimeCollection>: RealtimeCollection
where Base.Index == Int {
    public typealias Index = Int
    private let transform: (Base.Element) -> Element
    private let base: _AnyRealtimeCollectionBase<Base.Element>

    public required init(base: Base, transform: @escaping (Base.Element) -> Element) {
        guard base.isRooted else { fatalError("Only rooted collections can use in map collection") }
        self.base = __AnyRealtimeCollection<Base>(base: base)
        self.storage = AnyArrayStorage()
        self.transform = transform
    }

    public init(in node: Node?, options: [RealtimeValueOption: Any]) {
        fatalError()
    }

    public var node: Node? { return base.node }
    public var version: Int? { return base.version }
    public var raw: FireDataValue? { return base.raw }
    public var payload: [String : FireDataValue]? { return base.payload }
    public var view: RealtimeCollectionView { return base.view }
    public var storage: AnyArrayStorage
    public var isPrepared: Bool { return base.isPrepared }

    public var startIndex: Index { return base.startIndex }
    public var endIndex: Index { return base.endIndex }
    public func index(after i: Index) -> Index { return base.index(after: i) }
    public func index(before i: Int) -> Int { return base.index(before: i) }
    public subscript(position: Int) -> Element { return transform(base[position]) }
    public var debugDescription: String { return base.debugDescription }
    public func prepare(forUse completion: Assign<(Error?)>) { base.prepare(forUse: completion) }

    public func load(completion: Assign<Error?>?) { base.load(completion: completion) }
    public var canObserve: Bool { return base.canObserve }

    public func listening(changes handler: @escaping () -> Void) -> ListeningItem {
        return base.listening(changes: handler)
    }
    public func runObserving() -> Bool {
        return base.runObserving()
    }
    public func stopObserving() {
        base.stopObserving()
    }

    public convenience required init(fireData: FireDataProtocol, exactly: Bool) throws {
        fatalError("Cannot use this initializer")
    }

    public func apply(_ data: FireDataProtocol, exactly: Bool) throws {
        try base.apply(data, exactly: exactly)
    }

    public func didPrepare() {
        fatalError()
    }
}
