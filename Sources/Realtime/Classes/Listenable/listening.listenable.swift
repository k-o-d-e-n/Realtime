//
//  Listening.swift
//  GoogleToolboxForMac
//
//  Created by Denis Koryttsev on 31/01/2018.
//

import Foundation
#if os(Linux)
import SE0282_Experimental

final class AtomicBool {
    private let _value: UnsafeAtomic<Int>

    init(bool value: Bool) {
        self._value = .create(initialValue: value ? 1 : 0)
    }

    deinit {
        _value.destroy()
    }

    var boolValue: Bool {
        _value.load(ordering: .relaxed) == 1
    }

    func swap(to value: Bool) -> Bool {
        _value.compareExchange(expected: value ? 0 : 1, desired: value ? 1 : 0, ordering: .relaxed).exchanged
    }

    static func initialize(_ value: Bool) -> AtomicBool {
        AtomicBool(bool: value)
    }
}
#else
struct AtomicBool {
    var _invalidated: Int32

    private init(_ value: Bool) {
        self._invalidated = value ? 1 : 0
    }

    static func initialize(_ value: Bool) -> AtomicBool {
        AtomicBool(value)
    }

    var boolValue: Bool { _invalidated == 1 }

    mutating func swap(to value: Bool) -> Bool {
        OSAtomicCompareAndSwap32Barrier(0, 1, &_invalidated)
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

public final class SingleDispose<T: Disposable>: Disposable {
    var storage: ValueStorage<T?>?
    public var isDisposed: Bool { return storage == nil }

    init(storage: ValueStorage<T?>) {
        self.storage = storage
    }
    deinit { dispose() }

    public convenience init(strong value: T?) {
        self.init(storage: .unsafe(strong: value))
    }
//    public convenience init(unowned value: AnyObject) {
//        self.init(storage: .unsafe(unowned: value))
//    }
    public func dispose() {
        storage?.wrappedValue?.dispose()
        storage?.wrappedValue = nil
        storage = nil
    }
    public func replace(with newDispose: T) {
        storage?.wrappedValue = newDispose
    }
}
extension SingleDispose where T: AnyObject {
    public convenience init(weak value: T?) {
        self.init(storage: .unsafe(weak: value))
    }
}

public final class ListeningDispose: Disposable {
    let _dispose: () -> Void
    var invalidated: AtomicBool = .initialize(false)
    public var isDisposed: Bool { invalidated.boolValue }
    public init(_ dispose: @escaping () -> Void) {
        self._dispose = dispose
    }
    public func dispose() {
        if invalidated.swap(to: true) {
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
