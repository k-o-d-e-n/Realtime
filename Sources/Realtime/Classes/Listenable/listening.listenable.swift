//
//  Listening.swift
//  GoogleToolboxForMac
//
//  Created by Denis Koryttsev on 31/01/2018.
//

import Foundation
#if os(Linux)
import Atomics

extension AtomicBool {
    var isTrue: Bool {
        mutating get { return value }
    }

    mutating func swapAndResult() -> Bool {
        guard !load() else { return false }
        store(true)
        return true
    }

    static func initialize(_ value: Bool) -> AtomicBool {
        var value = AtomicBool()
        value.initialize(false)
        return value
    }
}

#else
struct AtomicBool {
    var _invalidated: Int32

    private init(_ value: Bool) {
        self._invalidated = value ? 1 : 0
    }

    static func initialize(_ value: Bool) -> AtomicBool {
        return AtomicBool(value)
    }

    var isTrue: Bool { return _invalidated == 1 }

    mutating func swapAndResult() -> Bool {
        return OSAtomicCompareAndSwap32Barrier(0, 1, &_invalidated)
    }
}
#endif

// MARK: Cancellable listenings

/// Disposes existing connection
public protocol Disposable {
    func dispose()
}

public struct EmptyDispose: Disposable {
    public init() {}
    public func dispose() {}
}

public final class SingleDispose: Disposable {
    var storage: ValueStorage<AnyObject?>?
    public var isDisposed: Bool { return storage == nil }

    init(storage: ValueStorage<AnyObject?>) {
        self.storage = storage
    }
    deinit { dispose() }

    public convenience init(strong value: AnyObject?) {
        self.init(storage: .unsafe(strong: value))
    }
    public convenience init(weak value: AnyObject?) {
        self.init(storage: .unsafe(weak: value))
    }
//    public convenience init(unowned value: AnyObject) {
//        self.init(storage: .unsafe(unowned: value))
//    }
    public func dispose() {
        storage?.wrappedValue = nil
        storage = nil
    }
    public func replace(with newDispose: AnyObject) {
        storage?.wrappedValue = newDispose
    }
}

public final class ListeningDispose: Disposable {
    let _dispose: () -> Void
    var invalidated: AtomicBool = AtomicBool.initialize(false)
    public var isDisposed: Bool { return invalidated.isTrue }
    public init(_ dispose: @escaping () -> Void) {
        self._dispose = dispose
    }
    public func dispose() {
        if invalidated.swapAndResult() {
            _dispose()
        }
    }
    deinit {
        dispose()
    }
}
extension ListeningDispose {
    convenience init(_ base: Disposable) {
        self.init(base.dispose)
    }
}

public extension Disposable {
    func add(to store: ListeningDisposeStore) {
        store.add(self)
    }
    func add(to disposes: inout [Disposable]) {
        disposes.append(self)
    }
}

/// Stores connections
public final class ListeningDisposeStore: Disposable, CustomStringConvertible {
    private var disposes = [Disposable]()

    var isEmpty: Bool { return disposes.isEmpty }

    public init() {}

    deinit {
        dispose()
    }

    public func add(_ stop: Disposable) {
        disposes.append(stop)
    }

    public func dispose() {
        disposes.forEach({ $0.dispose() })
    }

    public var description: String {
        return """
            disposes: \(disposes.count)
        """
    }
}
