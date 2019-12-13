//
//  RealtimeCollectionWrappers.swift
//  Realtime
//
//  Created by Denis Koryttsev on 16/03/2018.
//

import Foundation

// MARK: Index

internal protocol _AnyIndexBox: class {
    var _typeID: ObjectIdentifier { get }

    func _unbox<T : Comparable>() -> T?
    func _isEqual(to rhs: _AnyIndexBox) -> Bool
    func _isLess(than rhs: _AnyIndexBox) -> Bool
}
internal final class _IndexBox<BaseIndex: Comparable>: _AnyIndexBox {
    internal var _base: BaseIndex
    internal init(_base: BaseIndex) {
        self._base = _base
    }
    internal func _unsafeUnbox(_ other: _AnyIndexBox) -> BaseIndex {
        return unsafeDowncast(other, to: _IndexBox.self)._base
    }
    internal var _typeID: ObjectIdentifier {
        return ObjectIdentifier(type(of: self))
    }
    internal func _unbox<T : Comparable>() -> T? {
        return (self as _AnyIndexBox as? _IndexBox<T>)?._base
    }
    internal func _isEqual(to rhs: _AnyIndexBox) -> Bool {
        return _base == _unsafeUnbox(rhs)
    }
    internal func _isLess(than rhs: _AnyIndexBox) -> Bool {
        return _base < _unsafeUnbox(rhs)
    }
}
internal extension Collection {
    func _unbox(
        _ position: _AnyIndexBox, file: StaticString = #file, line: UInt = #line
        ) -> Index {
        if let i = position._unbox() as Index? {
            return i
        }
        fatalError("Index type mismatch!", file: file, line: line)
    }
}

public struct RealtimeCollectionIndex {
    internal var _box: _AnyIndexBox
    public init<BaseIndex : Comparable>(_ base: BaseIndex) { self._box = _IndexBox(_base: base) }
    internal init(_box: _AnyIndexBox) { self._box = _box }
    internal var _typeID: ObjectIdentifier { return _box._typeID }
}

extension RealtimeCollectionIndex : Comparable {
    public static func == (lhs: RealtimeCollectionIndex, rhs: RealtimeCollectionIndex) -> Bool {
        precondition(lhs._typeID == rhs._typeID, "Base index types differ")
        return lhs._box._isEqual(to: rhs._box)
    }
    public static func < (lhs: RealtimeCollectionIndex, rhs: RealtimeCollectionIndex) -> Bool {
        precondition(lhs._typeID == rhs._typeID, "Base index types differ")
        return lhs._box._isLess(than: rhs._box)
    }
}

// MARK: Type erased realtime collection

internal class _AnyRealtimeCollectionBase<Element>: Collection {
    typealias Index = RealtimeCollectionIndex
    var node: Node? { fatalError() }
    var raw: RealtimeDatabaseValue? { fatalError() }
    var payload: RealtimeDatabaseValue? { fatalError() }
    var view: AnyRealtimeCollectionView { fatalError() }
    var isSynced: Bool { fatalError() }
    var isObserved: Bool { fatalError() }
    var keepSynced: Bool { set { fatalError() } get { fatalError() } }
    var dataExplorer: RCDataExplorer { set { fatalError() } get { fatalError() } }
    var changes: AnyListenable<RCEvent> { fatalError() }
    var canObserve: Bool { fatalError() }
    var debugDescription: String { return "" }

    var startIndex: Index { fatalError() }
    var endIndex: Index { fatalError() }
    func makeIterator() -> AnyIterator<Element> { fatalError() }
    func index(after i: Index) -> Index { fatalError() }
    func index(before i: Index) -> Index { fatalError() }
    subscript(position: Index) -> Element { fatalError() }

    func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws { fatalError() }
    func runObserving() -> Bool { fatalError() }
    func stopObserving() { fatalError() }
    func load(timeout: DispatchTimeInterval) -> RealtimeTask { fatalError() }
}

internal final class _AnyRealtimeCollection<C: RealtimeCollection>: _AnyRealtimeCollectionBase<C.Iterator.Element>
where C.View.Element: DatabaseKeyRepresentable {
    var base: C

    override var node: Node? { return base.node }
    override var payload: RealtimeDatabaseValue? { return base.payload }
    override var view: AnyRealtimeCollectionView { return AnyRealtimeCollectionView(base.view) }
    override var isSynced: Bool { return base.isSynced }
    override var isObserved: Bool { return base.isObserved }
    override var canObserve: Bool { return base.canObserve }
    override var changes: AnyListenable<RCEvent> { return base.changes }
    override var keepSynced: Bool {
        get { return base.keepSynced }
        set { base.keepSynced = newValue }
    }
    override var dataExplorer: RCDataExplorer {
        set { base.dataExplorer = newValue }
        get { return base.dataExplorer }
    }

    required init(base: C) {
        self.base = base
    }

    required convenience init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        let base = try C(data: data, event: event)
        self.init(base: base)
    }

    override func makeIterator() -> AnyIterator<C.Iterator.Element> { return AnyIterator(base.makeIterator()) }
    override var startIndex: Index { return Index(base.startIndex) }
    override var endIndex: Index { return Index(base.endIndex) }
    override func index(after i: Index) -> Index { return Index(base.index(after: base._unbox(i._box))) }
    override func index(before i: Index) -> Index { return Index(base.index(before: base._unbox(i._box))) }
    override subscript(position: Index) -> C.Iterator.Element { return base[base._unbox(position._box)] }

    override func runObserving() -> Bool { return base.runObserving() }
    override func stopObserving() { base.stopObserving() }
    override func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws { try base.apply(data, event: event) }
    override func load(timeout: DispatchTimeInterval) -> RealtimeTask { return base.load(timeout: timeout) }
}

/// A type-erased Realtime database collection.
public final class AnyRealtimeCollection<Element>: RealtimeCollection {
    private let base: _AnyRealtimeCollectionBase<Element>

    public var node: Node? { return base.node }
    public var raw: RealtimeDatabaseValue? { return base.raw }
    public var payload: RealtimeDatabaseValue? { return base.payload }
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
    public var dataExplorer: RCDataExplorer {
        set { base.dataExplorer = newValue }
        get { return base.dataExplorer }
    }

    public init<C: RealtimeCollection>(_ base: C) where C.Element == Element, C.View.Element: DatabaseKeyRepresentable {
        self.base = _AnyRealtimeCollection<C>(base: base)
    }

    public convenience required init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws { fatalError() }

    public typealias Index = RealtimeCollectionIndex
    public var startIndex: Index { return base.startIndex }
    public var endIndex: Index { return base.endIndex }
    public func index(after i: Index) -> Index { return base.index(after: i) }
    public func index(before i: Index) -> Index { return base.index(before: i) }
    public subscript(position: Index) -> Element { return base[position] }

    public func load(timeout: DispatchTimeInterval) -> RealtimeTask { return base.load(timeout: timeout) }
    @discardableResult
    public func runObserving() -> Bool { return base.runObserving() }
    public func stopObserving() { base.stopObserving() }
    public func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws { try base.apply(data, event: event) }
}

class _AnyShareCollectionBase<Element>: Collection {
    var startIndex: RealtimeCollectionIndex { fatalError() }
    var endIndex: RealtimeCollectionIndex { fatalError() }
    func index(after i: RealtimeCollectionIndex) -> RealtimeCollectionIndex { fatalError() }
    public subscript(position: RealtimeCollectionIndex) -> Element { fatalError() }
}

class _AnyShareCollection<C: Collection>: _AnyShareCollectionBase<C.Element> {
    let base: C
    init(_ base: C) { self.base = base }
    typealias Index = RealtimeCollectionIndex
    override var startIndex: Index { return Index(base.startIndex) }
    override var endIndex: Index { return Index(base.endIndex) }
    override func index(after i: Index) -> Index { return Index(base.index(after: base._unbox(i._box))) }
    public override subscript(position: RealtimeCollectionIndex) -> Element { return base[base._unbox(position._box)] }
}

struct AnySharedCollection<Element>: Collection {
    let base: _AnyShareCollectionBase<Element>
    init<Base: Collection>(_ base: Base) where Base.Iterator.Element == Element {
        self.base = _AnyShareCollection(base)
    }
    typealias Index = RealtimeCollectionIndex
    public var startIndex: Index { return base.startIndex }
    public var endIndex: Index { return base.endIndex }
    public func index(after i: Index) -> Index { return base.index(after: i) }
    public subscript(position: Index) -> Element { return base[position] }
    public subscript(offset: Int) -> Element { return base[base.index(base.startIndex, offsetBy: offset)] }
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

    func lazyFlatMap<SegmentOfResult>(
        _ transform: @escaping (Element) -> SegmentOfResult
        ) -> FlattenRealtimeCollection<MapRealtimeCollection<SegmentOfResult, Self>>
        where SegmentOfResult: RealtimeCollection {
            return FlattenRealtimeCollection(base: self.lazyMap(transform))
    }
}

/// A immutable Realtime database collection whose elements consist of those in a `Base Collection`
/// passed through a transform function returning `Element`.
/// These elements are computed lazily, each time they’re read,
/// by calling the transform function on a base element.
///
/// This is the result of `x.lazyMap(_ transform:)` method, where `x` is any RealtimeCollection.
public final class MapRealtimeCollection<Element, Base: RealtimeCollection>: RealtimeCollection
where Base.View.Element: DatabaseKeyRepresentable {
    private let transform: (Base.Element) -> Element
    private let base: _AnyRealtimeCollectionBase<Base.Element>

    public var node: Node? { return base.node }
    public var raw: RealtimeDatabaseValue? { return base.raw }
    public var payload: RealtimeDatabaseValue? { return base.payload }
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
    public var dataExplorer: RCDataExplorer {
        set { base.dataExplorer = newValue }
        get { return base.dataExplorer }
    }

    public required init(base: Base, transform: @escaping (Base.Element) -> Element) {
        guard base.isRooted else { fatalError("Only rooted collections can use in map collection") }
        self.base = _AnyRealtimeCollection<Base>(base: base)
        self.transform = transform
    }

    public convenience required init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        fatalError("Cannot use this initializer")
    }

    public typealias Index = RealtimeCollectionIndex
    public var startIndex: Index { return base.startIndex }
    public var endIndex: Index { return base.endIndex }
    public func index(after i: Index) -> Index { return base.index(after: i) }
    public func index(before i: Index) -> Index { return base.index(before: i) }
    public subscript(position: Index) -> Element { return transform(base[position]) }

    public func load(timeout: DispatchTimeInterval) -> RealtimeTask { return base.load(timeout: timeout) }
    @discardableResult public func runObserving() -> Bool { return base.runObserving() }
    public func stopObserving() { base.stopObserving() }
    public func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws { try base.apply(data, event: event) }
}

public final class FlattenRealtimeCollection<Base: RealtimeCollection>: RealtimeCollection
where Base.View.Element: DatabaseKeyRepresentable, Base.Element: RealtimeCollection {
    public typealias Element = Base.Element.Element

    private let base: _AnyRealtimeCollectionBase<Base.Element>

    public var node: Node? { return base.node }
    public var raw: RealtimeDatabaseValue? { return base.raw }
    public var payload: RealtimeDatabaseValue? { return base.payload }
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
    public var dataExplorer: RCDataExplorer {
        set { base.dataExplorer = newValue }
        get { return base.dataExplorer }
    }

    init(base: Base) {
        guard base.node?.isRooted ?? false else { fatalError("Only rooted collections can use in map collection") }
        self.base = _AnyRealtimeCollection(base: base)
    }

    public convenience required init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        fatalError("Cannot use this initializer")
    }

    public struct Index: Comparable {
        internal let _outer: RealtimeCollectionIndex
        internal let _inner: Base.Element.Index?

        internal init(_ _outer: RealtimeCollectionIndex, _ inner: Base.Element.Index?) {
            self._outer = _outer
            self._inner = inner
        }

        public static func == (
            lhs: FlattenRealtimeCollection<Base>.Index,
            rhs: FlattenRealtimeCollection<Base>.Index
            ) -> Bool {
            return lhs._outer == rhs._outer && lhs._inner == rhs._inner
        }

        public static func < (
            lhs: FlattenRealtimeCollection<Base>.Index,
            rhs: FlattenRealtimeCollection<Base>.Index
            ) -> Bool {
            if lhs._outer != rhs._outer {
                return lhs._outer < rhs._outer
            }

            if let lhsInner = lhs._inner, let rhsInner = rhs._inner {
                return lhsInner < rhsInner
            }

            // When combined, the two conditions above guarantee that both
            // `_outer` indices are `_base.endIndex` and both `_inner` indices
            // are `nil`, since `_inner` is `nil` iff `_outer == base.endIndex`.
            precondition(lhs._inner == nil && rhs._inner == nil)

            return false
        }
    }

    public var startIndex: Index {
        let end = base.endIndex
        var outer = base.startIndex
        while outer != end {
            let innerCollection = base[outer]
            if !innerCollection.isEmpty {
                return Index(outer, innerCollection.startIndex)
            }
            base.formIndex(after: &outer)
        }

        return endIndex
    }
    public var endIndex: Index { return Index(base.endIndex, nil) }
    public func index(after i: Index) -> Index {
        let innerCollection = base[i._outer]
        let nextInner = innerCollection.index(after: i._inner!)
        if _fastPath(nextInner != innerCollection.endIndex) {
            return Index(i._outer, nextInner)
        }

        var nextOuter = base.index(after: i._outer)
        while nextOuter != base.endIndex {
            let nextInnerCollection = base[nextOuter]
            if !nextInnerCollection.isEmpty {
                return Index(nextOuter, nextInnerCollection.startIndex)
            }
            base.formIndex(after: &nextOuter)
        }

        return endIndex
    }
    public func index(before i: Index) -> Index {
        var prevOuter = i._outer
        if prevOuter == base.endIndex {
            prevOuter = base.index(prevOuter, offsetBy: -1)
        }
        var prevInnerCollection = base[prevOuter]
        var prevInner = i._inner ?? prevInnerCollection.endIndex

        while prevInner == prevInnerCollection.startIndex {
            prevOuter = base.index(prevOuter, offsetBy: -1)
            prevInnerCollection = base[prevOuter]
            prevInner = prevInnerCollection.endIndex
        }

        return Index(prevOuter, prevInnerCollection.index(prevInner, offsetBy: -1))
    }
    public subscript(position: Index) -> Element {
        return base[position._outer][position._inner!]
    }

    public func load(timeout: DispatchTimeInterval) -> RealtimeTask { return base.load(timeout: timeout) }
    @discardableResult public func runObserving() -> Bool { return base.runObserving() }
    public func stopObserving() { base.stopObserving() }
    public func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws { try base.apply(data, event: event) }
}
