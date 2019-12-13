//
//  listenables.listenable.swift
//  Realtime
//
//  Created by Denis Koryttsev on 18/11/2018.
//

import Foundation

/// Provides subscribing and delivering events to listeners
public struct Repeater<T>: Listenable {
    let sender: (ListenEvent<T>) -> Void
    let _remove: (UInt) -> Void
    let _add: (Assign<ListenEvent<T>>) -> UInt

    public enum Dispatcher {
        case `default`
        case queue(DispatchQueue)
        case custom((Assign<ListenEvent<T>>, ListenEvent<T>) -> Void)

        fileprivate var implentation: (Assign<ListenEvent<T>>, ListenEvent<T>) -> Void {
            switch self {
            case .default: return { $0.call($1) }
            case .queue(let q): return { a, e in q.async { a.call(e) } }
            case .custom(let impl): return impl
            }
        }
    }

    /// Returns repeater that has no thread-safe context
    ///
    /// - Parameter dispatcher: Closure that implements method of dispatch events to listeners
    public static func unsafe(with dispatcher: Dispatcher = .default) -> Repeater<T> {
        return Repeater(dispatcher: dispatcher)
    }
    /// Creates new instance that has no thread-safe working context
    ///
    /// - Parameter dispatcher: Closure that implements method of dispatch events to listeners
    public init(dispatcher: Dispatcher) {
        let dispatch = dispatcher.implentation
        var nextToken = UInt.min
        var listeners: [UInt: Assign<ListenEvent<T>>] = [:]

        self.sender = { e in
            listeners.forEach({ (listener) in
                dispatch(listener.value, e)
            })
        }

        self._add = { assign in
            defer { nextToken += 1 }

            let token = nextToken
            listeners[token] = assign

            return token
        }

        self._remove = { token in
            listeners.removeValue(forKey: token)
        }
    }

    public static func locked(by lock: NSLocking = NSRecursiveLock(), dispatcher: Dispatcher = .default) -> Repeater<T> {
        return Repeater(lockedBy: lock, dispatcher: dispatcher)
    }

    /// Creates new instance that has thread-safe implementation using lock object.
    ///
    /// - Parameters:
    ///   - lock: Lock object.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners
    public init(lockedBy lock: NSLocking, dispatcher: Dispatcher) {
        let dispatch = dispatcher.implentation
        var nextToken = UInt.min
        var listeners: [UInt: Assign<ListenEvent<T>>] = [:]

        self.sender = { e in
            lock.lock(); defer { lock.unlock() }
            listeners.forEach({ (listener) in
                dispatch(listener.value, e)
            })
        }

        self._add = { assign in
            lock.lock()
            defer {
                nextToken += 1
                lock.unlock()
            }

            let token = nextToken
            listeners[token] = assign

            return token
        }
        self._remove = { token in
            lock.lock(); defer { lock.unlock() }
            listeners.removeValue(forKey: token)
        }
    }

    func add(_ assign: Assign<ListenEvent<T>>) -> UInt {
        return _add(assign)
    }

    func remove(_ token: UInt) {
        _remove(token)
    }
    
    /// Sends passed event to listeners
    ///
    /// - Parameter event: Event type with associated value
    public func send(_ event: ListenEvent<T>) {
        sender(event)
    }

    public func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
        let token = _add(assign)
        return ListeningDispose({
            self._remove(token)
        })
    }
}
extension Repeater {
    func send(_ input: Out) {
        self.send(.value(input))
    }
}

/// Stores value and sends event on his change
public struct ValueStorage<T>: ValueWrapper {
    let get: () -> T
    let mutate: ((inout T) -> Void) -> Void
    var repeater: Repeater<T>?

    /// Stored value
    @available(*, deprecated, renamed: "wrappedValue")
    public var value: T {
        get { return get() }
        nonmutating set {
            mutate({ $0 = newValue })
            repeater?.send(.value(newValue))
        }
    }
    public var wrappedValue: T {
        get { return get() }
        nonmutating set {
            mutate({ $0 = newValue })
            repeater?.send(.value(newValue))
        }
    }

    init(get: @escaping () -> T, set: @escaping ((inout T) -> Void) -> Void) {
        self.get = get
        self.mutate = set
    }

    /// Creates new instance with `strong` reference that has no thread-safe working context
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    init(unsafeStrong value: T) {
        var val: T = value

        self.init(get: { val }, set: { $0(&val) })
    }

    /// Creates new instance with `strong` reference that has thread-safe implementation
    /// using lock object.
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - lock: Lock object.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    init(strong value: T, lock: NSLocking) {
        var val: T = value

        self.init(
            get: {
                lock.lock(); defer { lock.unlock() }
                return val
            },
            set: {
                lock.lock()
                $0(&val)
                lock.unlock()
            }
        )
    }

    /// Creates new instance with `weak` reference that has no thread-safe working context
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    init<O: AnyObject>(unsafeWeak value: O?) where Optional<O> == T {
        weak var val = value
        self.init(get: { val }, set: { $0(&val) })
    }

    /// Creates new instance with `weak` reference that has thread-safe implementation
    /// using lock object.
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - lock: Lock object.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    init<O: AnyObject>(weak value: O?, lock: NSLocking) where Optional<O> == T {
        weak var val = value

        self.init(
            get: {
                lock.lock(); defer { lock.unlock() }
                return val
            },
            set: {
                lock.lock()
                $0(&val)
                lock.unlock()
            }
        )
    }

    /// Sends error event to listeners
    ///
    /// - Parameter error: Error instance
    public func sendError(_ error: Error) {
        repeater?.sender(.error(error))
    }

    /// Replaces stored value with new value without emitting change event
    public func replace(with value: T) {
        mutate({ $0 = value })
    }

    /// Method to change value using mutation block
    func mutate(with mutator: (inout T) -> Void) {
        self.mutate(mutator)
    }
}
extension ValueStorage {
    /// Returns storage with `strong` reference that has no thread-safe working context
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    public static func unsafe(strong value: T, repeater: Repeater<T>? = nil) -> ValueStorage {
        var storage = ValueStorage(unsafeStrong: value)
        storage.repeater = repeater
        return storage
    }
    public static func unsafe<Wrapped>(strong value: T, repeater: Repeater<T>? = nil) -> ValueStorage where Optional<Wrapped> == T {
        var storage = ValueStorage(unsafeStrong: value)
        storage.repeater = repeater
        return storage
    }

    /// Returns storage with `strong` reference that has thread-safe implementation
    /// using lock object.
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - lock: Lock object.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    public static func locked(
        strong value: T,
        lock: NSLocking = NSRecursiveLock(),
        repeater: Repeater<T>? = nil
    ) -> ValueStorage {
        var storage = ValueStorage(strong: value, lock: lock)
        storage.repeater = repeater
        return storage
    }
    public static func locked<Wrapped>(
        strong value: T,
        lock: NSLocking = NSRecursiveLock(),
        repeater: Repeater<T>? = nil
    ) -> ValueStorage where Optional<Wrapped> == T {
        var storage = ValueStorage(strong: value, lock: lock)
        storage.repeater = repeater
        return storage
    }

    /// Returns storage with `weak` reference that has no thread-safe working context
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    public static func unsafe<O: AnyObject>(
        weak value: O?, repeater: Repeater<T>? = nil
    ) -> ValueStorage where Optional<O> == T {
        var storage = ValueStorage(unsafeWeak: value)
        storage.repeater = repeater
        return storage
    }
    /// Returns storage with `weak` reference that has thread-safe implementation
    /// using lock object.
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - lock: Lock object.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    public static func locked<O: AnyObject>(
        weak value: O?,
        lock: NSLocking = NSRecursiveLock(),
        repeater: Repeater<T>? = nil
    ) -> ValueStorage where Optional<O> == T {
        var storage = ValueStorage(weak: value, lock: lock)
        storage.repeater = repeater
        return storage
    }
}
extension ValueStorage where T: AnyObject {
    /// Creates new instance with `unowned` reference that has no thread-safe working context
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    init(unsafeUnowned value: T) {
        unowned var val = value

        self.init(get: { val }, set: { $0(&val) })
    }

    /// Creates new instance with `unowned` reference that has thread-safe implementation
    /// using lock object.
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - lock: Lock object.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    init(unowned value: T, lock: NSLocking) {
        unowned var val = value

        self.init(
            get: {
                lock.lock(); defer { lock.unlock() }
                return val
            },
            set: {
                lock.lock()
                $0(&val)
                lock.unlock()
            }
        )
    }

    /// Returns storage with `unowned` reference that has no thread-safe working context
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    public static func unsafe(
        unowned value: T, repeater: Repeater<T>? = nil
    ) -> ValueStorage {
        var storage = ValueStorage(unsafeUnowned: value)
        storage.repeater = repeater
        return storage
    }
    /// Returns storage with `unowned` reference that has thread-safe implementation
    /// using lock object.
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - lock: Lock object.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    public static func locked(
        unowned value: T,
        lock: NSLocking = NSRecursiveLock(),
        repeater: Repeater<T>? = nil
    ) -> ValueStorage {
        var storage = ValueStorage(unowned: value, lock: lock)
        storage.repeater = repeater
        return storage
    }
}

public struct Constant<T>: Listenable {
    let value: T
    public init(_ value: T) {
        self.value = value
    }
    public func listening(_ assign: Closure<ListenEvent<T>, Void>) -> Disposable {
        assign.call(.value(value))
        return EmptyDispose()
    }
}
public struct SequenceListenable<Element>: Listenable {
    let value: AnySequence<Element>
    public init<S: Sequence>(_ value: S) where S.Element == Element {
        self.value = AnySequence(value)
    }
    public func listening(_ assign: Closure<ListenEvent<Element>, Void>) -> Disposable {
        value.forEach({ assign.call(.value($0)) })
        return EmptyDispose()
    }
}
