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

    public func listeningItem(_ assign: Assign<ListenEvent<T>>) -> ListeningItem {
        return ListeningItem(resume: { self._add(assign) }, pause: _remove, token: _add(assign))
    }
}

/// Stores value and sends event on his change
public struct ValueStorage<T>: Listenable, ValueWrapper {
    public typealias Dispatcher = Repeater<T>.Dispatcher

    let get: () -> T
    let set: (T) -> Void
    let attachBehavior: AttachBehavior
    let repeater: Repeater<T>

    enum AttachBehavior {
        case unsafe
        case locked(NSLocking)
    }

    /// Stored value
    public var value: T {
        get { return get() }
        nonmutating set { set(newValue) }
    }

    init(repeater: Repeater<T>,
         get: @escaping () -> T, set: @escaping (T) -> Void,
         attachBehavior: AttachBehavior) {
        self.get = get
        self.set = set
        self.attachBehavior = attachBehavior
        self.repeater = repeater
    }

    /// Creates new instance with `strong` reference that has no thread-safe working context
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    public init(unsafeStrong value: T?, dispatcher: Dispatcher) {
        let repeater = Repeater(dispatcher: dispatcher)
        var val: T! = value {
            didSet {
                repeater.send(.value(val))
            }
        }

        self.init(
            repeater: repeater,
            get: { val }, set: { val = $0 },
            attachBehavior: .unsafe
        )
    }

    /// Creates new instance with `strong` reference that has thread-safe implementation
    /// using lock object.
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - lock: Lock object.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    public init(strong value: T?, lock: NSLocking, dispatcher: Dispatcher) {
        let repeater = Repeater(dispatcher: dispatcher)
        var val: T! = value {
            didSet {
                repeater.send(.value(val))
            }
        }

        self.init(
            repeater: repeater,
            get: {
                lock.lock(); defer { lock.unlock() }
                return val
            },
            set: {
                lock.lock()
                val = $0
                lock.unlock()
            },
            attachBehavior: .locked(lock)
        )
    }

    /// Creates new instance with `weak` reference that has no thread-safe working context
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    public init<O: AnyObject>(unsafeWeak value: O?, dispatcher: Dispatcher) where Optional<O> == T {
        let repeater = Repeater(dispatcher: dispatcher)
        weak var val = value {
            didSet {
                repeater.send(.value(val))
            }
        }

        self.init(
            repeater: repeater,
            get: { val }, set: { val = $0 },
            attachBehavior: .unsafe
        )
    }

    /// Creates new instance with `weak` reference that has thread-safe implementation
    /// using lock object.
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - lock: Lock object.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    public init<O: AnyObject>(weak value: O?, lock: NSLocking, dispatcher: Dispatcher) where Optional<O> == T {
        let repeater = Repeater(dispatcher: dispatcher)
        weak var val = value {
            didSet {
                repeater.send(.value(val))
            }
        }

        self.init(
            repeater: repeater,
            get: {
                lock.lock(); defer { lock.unlock() }
                return val
            },
            set: {
                lock.lock()
                val = $0
                lock.unlock()
            },
            attachBehavior: .locked(lock)
        )
    }

    /// Returns storage with `strong` reference that has no thread-safe working context
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    public static func unsafe(
        strong value: T?,
        dispatcher: Dispatcher = .default
        ) -> ValueStorage {
        return ValueStorage(unsafeStrong: value, dispatcher: dispatcher)
    }

    /// Returns storage with `weak` reference that has no thread-safe working context
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    public static func unsafe<O: AnyObject>(
        weak value: O?,
        dispatcher: Dispatcher = .default
        ) -> ValueStorage where Optional<O> == T {
        return ValueStorage(unsafeWeak: value, dispatcher: dispatcher)
    }

    /// Returns storage with `strong` reference that has thread-safe implementation
    /// using lock object.
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - lock: Lock object.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    public static func locked(
        strong value: T?,
        lock: NSLocking = NSRecursiveLock(),
        dispatcher: Dispatcher = .default
        ) -> ValueStorage {
        return ValueStorage(strong: value, lock: lock, dispatcher: dispatcher)
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
        dispatcher: Dispatcher = .default
        ) -> ValueStorage where Optional<O> == T {
        return ValueStorage(weak: value, lock: lock, dispatcher: dispatcher)
    }

    /// Sends error event to listeners
    ///
    /// - Parameter error: Error instance
    public func sendError(_ error: Error) {
        repeater.sender(.error(error))
    }

    public func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
        switch attachBehavior {
        case .unsafe: return repeater.listening(assign)
        case .locked(let lock):
            lock.lock(); defer { lock.unlock() }

            let d = repeater.listening(assign)
            return ListeningDispose {
                lock.lock()
                d.dispose()
                lock.unlock()
            }
        }
    }

    public func listeningItem(_ assign: Assign<ListenEvent<T>>) -> ListeningItem {
        return ListeningItem(resume: { self.listening(assign) }, pause: { $0.dispose() }, token: listening(assign))
    }
}
extension ValueStorage where T: AnyObject {
    /// Creates new instance with `unowned` reference that has no thread-safe working context
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    public init(unsafeUnowned value: T, dispatcher: Dispatcher) {
        let repeater = Repeater(dispatcher: dispatcher)
        unowned var val = value {
            didSet {
                repeater.send(.value(val))
            }
        }

        self.init(
            repeater: repeater,
            get: { val }, set: { val = $0 },
            attachBehavior: .unsafe
        )
    }

    /// Creates new instance with `unowned` reference that has thread-safe implementation
    /// using lock object.
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - lock: Lock object.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    public init(unowned value: T, lock: NSLocking, dispatcher: Dispatcher) {
        let repeater = Repeater(dispatcher: dispatcher)
        unowned var val = value {
            didSet {
                repeater.send(.value(val))
            }
        }

        self.init(
            repeater: repeater,
            get: {
                lock.lock(); defer { lock.unlock() }
                return val
            },
            set: {
                lock.lock()
                val = $0
                lock.unlock()
            },
            attachBehavior: .locked(lock)
        )
    }

    /// Returns storage with `unowned` reference that has no thread-safe working context
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    public static func unsafe(
        unowned value: T,
        dispatcher: Dispatcher = .default
        ) -> ValueStorage {
        return ValueStorage(unsafeUnowned: value, dispatcher: dispatcher)
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
        dispatcher: Dispatcher = .default
        ) -> ValueStorage {
        return ValueStorage(unowned: value, lock: lock, dispatcher: dispatcher)
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
    public func listeningItem(_ assign: Closure<ListenEvent<T>, Void>) -> ListeningItem {
        return ListeningItem(
            resume: { assign.call(.value(self.value)) },
            pause: { _ in },
            token: assign.call(.value(value))
        )
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
    public func listeningItem(_ assign: Closure<ListenEvent<Element>, Void>) -> ListeningItem {
        return ListeningItem(
            resume: { self.value.forEach({ assign.call(.value($0)) }) },
            pause: { _ in },
            token: value.forEach({ assign.call(.value($0)) })
        )
    }
}