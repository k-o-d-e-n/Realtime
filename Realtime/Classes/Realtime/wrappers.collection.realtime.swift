//
//  RealtimeCollectionWrappers.swift
//  Realtime
//
//  Created by Denis Koryttsev on 16/03/2018.
//

import Foundation

// MARK: Type erased realtime collection

internal class _AnyRealtimeCollectionBase<Element>: Collection {
    var node: Node? { fatalError() }
    var raw: RealtimeDataValue? { fatalError() }
    var payload: [String : RealtimeDataValue]? { fatalError() }
    var view: AnyRealtimeCollectionView { fatalError() }
    var isSynced: Bool { fatalError() }
    var isObserved: Bool { fatalError() }
    var keepSynced: Bool { set { fatalError() } get { fatalError() } }
    var changes: AnyListenable<RCEvent> { fatalError() }
    var canObserve: Bool { fatalError() }
    var debugDescription: String { return "" }

    var startIndex: Int { fatalError() }
    var endIndex: Int { fatalError() }
    func makeIterator() -> AnyIterator<Element> { fatalError() }
    func index(after i: Int) -> Int { fatalError() }
    func index(before i: Int) -> Int { fatalError() }
    subscript(position: Int) -> Element { fatalError() }

    func apply(_ data: RealtimeDataProtocol, exactly: Bool) throws { fatalError() }
    func runObserving() -> Bool { fatalError() }
    func stopObserving() { fatalError() }
    func load(timeout: DispatchTimeInterval, completion: Assign<Error?>?) { fatalError() }
}

internal final class _AnyRealtimeCollection<C: RealtimeCollection>: _AnyRealtimeCollectionBase<C.Iterator.Element>
where C.Index == Int, C.View.Element: DatabaseKeyRepresentable {
    var base: C

    override var node: Node? { return base.node }
    override var payload: [String : RealtimeDataValue]? { return base.payload }
    override var view: AnyRealtimeCollectionView { return AnyRealtimeCollectionView(base.view) }
    override var isSynced: Bool { return base.isSynced }
    override var isObserved: Bool { return base.isObserved }
    override var canObserve: Bool { return base.canObserve }
    override var changes: AnyListenable<RCEvent> { return base.changes }
    override var keepSynced: Bool {
        get { return base.keepSynced }
        set { base.keepSynced = newValue }
    }

    required init(base: C) {
        self.base = base
    }

    required convenience init(data: RealtimeDataProtocol, exactly: Bool) throws {
        let base = try C(data: data, exactly: exactly)
        self.init(base: base)
    }

    convenience required init(in node: Node, options: [ValueOption: Any]) {
        self.init(base: C(in: node, options: options))
    }

    override func makeIterator() -> AnyIterator<C.Iterator.Element> { return AnyIterator(base.makeIterator()) }
    override var startIndex: Int { return base.startIndex }
    override var endIndex: Int { return base.endIndex }
    override func index(after i: Int) -> Int { return base.index(after: i) }
    override func index(before i: Int) -> Int { return base.index(before: i) }
    override subscript(position: Int) -> C.Iterator.Element { return base[position] }

    override func runObserving() -> Bool { return base.runObserving() }
    override func stopObserving() { base.stopObserving() }
    override func apply(_ data: RealtimeDataProtocol, exactly: Bool) throws { try base.apply(data, exactly: exactly) }
    override func load(timeout: DispatchTimeInterval, completion: Assign<Error?>?) { base.load(timeout: timeout, completion: completion) }
}

/// A type-erased Realtime database collection.
public final class AnyRealtimeCollection<Element>: RealtimeCollection {
    private let base: _AnyRealtimeCollectionBase<Element>

    public var node: Node? { return base.node }
    public var raw: RealtimeDataValue? { return base.raw }
    public var payload: [String : RealtimeDataValue]? { return base.payload }
    public var view: AnyRealtimeCollectionView { return base.view }
    public var isSynced: Bool { return base.isSynced }
    public var isObserved: Bool { return base.isObserved }
    public var debugDescription: String { return base.debugDescription }
    public var canObserve: Bool { return base.canObserve }
    public var keepSynced: Bool {
        get { return base.keepSynced }
        set { base.keepSynced = newValue }
    }
    public var changes: AnyListenable<RCEvent> { return base.changes }

    public init<C: RealtimeCollection>(_ base: C) where C.Iterator.Element == Element, C.Index == Int, C.View.Element: DatabaseKeyRepresentable {
        self.base = _AnyRealtimeCollection<C>(base: base)
    }

    /// Currently no available
    public convenience init(in node: Node?, options: [ValueOption: Any]) {
        fatalError("Cannot use this initializer")
    }

    public convenience required init(data: RealtimeDataProtocol, exactly: Bool) throws { fatalError() }

    public var startIndex: Int { return base.startIndex }
    public var endIndex: Int { return base.endIndex }
    public func index(after i: Index) -> Int { return base.index(after: i) }
    public func index(before i: Int) -> Int { return base.index(before: i) }
    public subscript(position: Int) -> Element { return base[position] }

    public func load(timeout: DispatchTimeInterval, completion: Assign<Error?>?) { base.load(timeout: timeout, completion: completion) }
    @discardableResult
    public func runObserving() -> Bool { return base.runObserving() }
    public func stopObserving() { base.stopObserving() }
    public func apply(_ data: RealtimeDataProtocol, exactly: Bool) throws { try base.apply(data, exactly: exactly) }
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

public extension RealtimeCollection {
    /// Returns `MapRealtimeCollection` over this collection.
    ///
    /// The elements of the result are computed lazily, each time they are read,
    /// by calling transform function on a base element.
    ///
    /// - Parameter transform: Closure to read element
    /// - Returns: `MapRealtimeCollection` collection.
    func lazyMap<Mapped>(_ transform: @escaping (Element) -> Mapped) -> MapRealtimeCollection<Mapped, Self> {
        return MapRealtimeCollection(base: self, transform: transform)
    }
}

/// A immutable Realtime database collection whose elements consist of those in a `Base Collection`
/// passed through a transform function returning `Element`.
/// These elements are computed lazily, each time they’re read,
/// by calling the transform function on a base element.
///
/// This is the result of `x.lazyMap(_ transform:)` method, where `x` is any RealtimeCollection.
public final class MapRealtimeCollection<Element, Base: RealtimeCollection>: RealtimeCollection
where Base.Index == Int, Base.View.Element: DatabaseKeyRepresentable {
    public typealias Index = Int

    private let transform: (Base.Element) -> Element
    private let base: _AnyRealtimeCollectionBase<Base.Element>

    public var node: Node? { return base.node }
    public var raw: RealtimeDataValue? { return base.raw }
    public var payload: [String : RealtimeDataValue]? { return base.payload }
    public var view: AnyRealtimeCollectionView { return base.view }
    public var isSynced: Bool { return base.isSynced }
    public var isObserved: Bool { return base.isObserved }
    public var changes: AnyListenable<RCEvent> { return base.changes }
    public var debugDescription: String { return base.debugDescription }
    public var canObserve: Bool { return base.canObserve }
    public var keepSynced: Bool {
        set { base.keepSynced = newValue }
        get { return base.keepSynced }
    }

    public required init(base: Base, transform: @escaping (Base.Element) -> Element) {
        guard base.isRooted else { fatalError("Only rooted collections can use in map collection") }
        self.base = _AnyRealtimeCollection<Base>(base: base)
        self.transform = transform
    }

    public init(in node: Node?, options: [ValueOption: Any]) {
        fatalError()
    }

    public convenience required init(data: RealtimeDataProtocol, exactly: Bool) throws {
        fatalError("Cannot use this initializer")
    }

    public var startIndex: Index { return base.startIndex }
    public var endIndex: Index { return base.endIndex }
    public func index(after i: Index) -> Index { return base.index(after: i) }
    public func index(before i: Int) -> Int { return base.index(before: i) }
    public subscript(position: Int) -> Element { return transform(base[position]) }

    public func load(timeout: DispatchTimeInterval, completion: Assign<Error?>?) { base.load(timeout: timeout, completion: completion) }
    @discardableResult public func runObserving() -> Bool { return base.runObserving() }
    public func stopObserving() { base.stopObserving() }
    public func apply(_ data: RealtimeDataProtocol, exactly: Bool) throws {
        try base.apply(data, exactly: exactly)
    }
}
