//
//  _concepts_.swift
//  Pods
//
//  Created by Denis Koryttsev on 31/01/2018.
//

import Foundation

public struct Repeater<T>: Listenable {
    let sender: (ListenEvent<T>) -> Void
    let listen: (Assign<ListenEvent<T>>) -> Disposable
    let dispatcher: (ListenEvent<T>, Assign<ListenEvent<T>>) -> Void

    public static func unsafe(with dispatcher: @escaping (ListenEvent<T>, Assign<ListenEvent<T>>) -> Void = { $1.call($0) }) -> Repeater<T> {
        return Repeater(dispatcher: dispatcher)
    }

    public init(dispatcher: @escaping (ListenEvent<T>, Assign<ListenEvent<T>>) -> Void) {
        self.dispatcher = dispatcher
        var nextToken = UInt.min
        var listeners: [UInt: Assign<ListenEvent<T>>] = [:]

        self.sender = { e in
            listeners.forEach({ (listener) in
                dispatcher(e, listener.value)
            })
        }

        self.listen = { assign in
            defer { nextToken += 1 }

            let token = nextToken
            listeners[token] = assign

            return ListeningDispose {
                listeners.removeValue(forKey: token)
            }
        }
    }

    public init(queue: DispatchQueue) {
        self.init { (e, a) in
            queue.async { a.assign(e) }
        }
    }

    public static func locked(by lock: NSLocking = NSRecursiveLock(), dispatcher: @escaping (ListenEvent<T>, Assign<ListenEvent<T>>) -> Void = { $1.call($0) }) -> Repeater<T> {
        return Repeater(lockedBy: lock, dispatcher: dispatcher)
    }

    public init(lockedBy lock: NSLocking, dispatcher: @escaping (ListenEvent<T>, Assign<ListenEvent<T>>) -> Void) {
        self.dispatcher = dispatcher
        var nextToken = UInt.min
        var listeners: [UInt: Assign<ListenEvent<T>>] = [:]

        self.sender = { e in
            lock.lock(); defer { lock.unlock() }
            listeners.forEach({ (listener) in
                dispatcher(e, listener.value)
            })
        }

        self.listen = { assign in
            lock.lock()
            defer {
                nextToken += 1
                lock.unlock()
            }

            let token = nextToken
            listeners[token] = assign

            return ListeningDispose {
                lock.lock(); defer { lock.unlock() }
                listeners.removeValue(forKey: token)
            }
        }
    }

    public init(lockedBy lock: NSLocking, queue: DispatchQueue) {
        self.init(lockedBy: lock) { (e, a) in
            queue.async { a.assign(e) }
        }
    }

    public func send(_ event: ListenEvent<T>) {
        sender(event)
    }

    public func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
        return listen(assign)
    }
}

public struct ValueStorage<T>: Listenable, ValueWrapper {
    let get: () -> T
    let set: (T) -> Void
    let listen: (Assign<ListenEvent<T>>) -> Disposable
    let repeater: Repeater<T>

    public var value: T {
        get { return get() }
        nonmutating set { set(newValue) }
    }

    init(repeater: Repeater<T>,
         get: @escaping () -> T, set: @escaping (T) -> Void,
         listen: @escaping (Assign<ListenEvent<T>>) -> Disposable) {
        self.get = get
        self.set = set
        self.listen = listen
        self.repeater = repeater
    }

    public init(unsafeStrong value: T, dispatcher: @escaping (ListenEvent<T>, Assign<ListenEvent<T>>) -> Void) {
        let repeater = Repeater(dispatcher: dispatcher)
        var val = value {
            didSet {
                repeater.send(.value(val))
            }
        }

        self.init(
            repeater: repeater,
            get: { val }, set: { val = $0 },
            listen: repeater.listen
        )
    }

    public init(lockedStrong value: T, lock: NSLocking, dispatcher: @escaping (ListenEvent<T>, Assign<ListenEvent<T>>) -> Void) {
        let repeater = Repeater(dispatcher: dispatcher)
        var val = value {
            didSet {
                repeater.send(.value(val))
            }
        }

        let safeGet: () -> T = {
            lock.lock(); defer { lock.unlock() }
            return val
        }

        self.init(
            repeater: repeater,
            get: safeGet,
            set: {
                lock.lock()
                val = $0
                lock.unlock()
            },
            listen: ValueStorage.disposed(lock, repeater: repeater)
        )
    }

    public init<O: AnyObject>(unsafeWeak value: O?, dispatcher: @escaping (ListenEvent<T>, Assign<ListenEvent<T>>) -> Void) where Optional<O> == T {
        let repeater = Repeater(dispatcher: dispatcher)
        weak var val = value {
            didSet {
                repeater.send(.value(val))
            }
        }

        self.init(
            repeater: repeater,
            get: { val }, set: { val = $0 },
            listen: repeater.listen
        )
    }

    public init<O: AnyObject>(lockedWeak value: O?, lock: NSLocking, dispatcher: @escaping (ListenEvent<T>, Assign<ListenEvent<T>>) -> Void) where Optional<O> == T {
        let repeater = Repeater(dispatcher: dispatcher)
        weak var val = value {
            didSet {
                repeater.send(.value(val))
            }
        }

        let safeGet: () -> T = {
            lock.lock(); defer { lock.unlock() }
            return val
        }

        self.init(
            repeater: repeater,
            get: safeGet,
            set: {
                lock.lock()
                val = $0
                lock.unlock()
            },
            listen: ValueStorage.disposed(lock, repeater: repeater)
        )
    }

    public static func unsafe(
        strong value: T,
        dispatcher: @escaping (ListenEvent<T>, Assign<ListenEvent<T>>) -> Void = { $1.call($0) }
        ) -> ValueStorage {
        return ValueStorage(unsafeStrong: value, dispatcher: dispatcher)
    }

    public static func unsafe<O: AnyObject>(
        weak value: O?,
        dispatcher: @escaping (ListenEvent<T>, Assign<ListenEvent<T>>) -> Void = { $1.call($0) }
        ) -> ValueStorage where Optional<O> == T {
        return ValueStorage(unsafeWeak: value, dispatcher: dispatcher)
    }

    public static func locked(
        strong value: T,
        lock: NSLocking = NSRecursiveLock(),
        dispatcher: @escaping (ListenEvent<T>, Assign<ListenEvent<T>>) -> Void = { $1.call($0) }
        ) -> ValueStorage {
        return ValueStorage(lockedStrong: value, lock: lock, dispatcher: dispatcher)
    }

    public static func locked<O: AnyObject>(
        weak value: O?,
        lock: NSLocking = NSRecursiveLock(),
        dispatcher: @escaping (ListenEvent<T>, Assign<ListenEvent<T>>) -> Void = { $1.call($0) }) -> ValueStorage where Optional<O> == T {
        return ValueStorage(lockedWeak: value, lock: lock, dispatcher: dispatcher)
    }

    public func sendError(_ error: Error) {
        repeater.sender(.error(error))
    }

    public func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
        return repeater.listen(assign)
    }

    private static func disposed(_ lock: NSLocking, repeater: Repeater<T>) -> (Assign<ListenEvent<T>>) -> Disposable {
        return { assign in
            lock.lock(); defer { lock.unlock() }

            let d = repeater.listening(assign)
            return ListeningDispose {
                lock.lock()
                d.dispose()
                lock.unlock()
            }
        }
    }
}
extension ValueStorage where T: AnyObject {
    public init(unsafeUnowned value: T, dispatcher: @escaping (ListenEvent<T>, Assign<ListenEvent<T>>) -> Void) {
        let repeater = Repeater(dispatcher: dispatcher)
        unowned var val = value {
            didSet {
                repeater.send(.value(val))
            }
        }

        self.init(
            repeater: repeater,
            get: { val }, set: { val = $0 },
            listen: repeater.listen
        )
    }

    public init(lockedUnowned value: T, lock: NSLocking, dispatcher: @escaping (ListenEvent<T>, Assign<ListenEvent<T>>) -> Void) {
        let repeater = Repeater(dispatcher: dispatcher)
        unowned var val = value {
            didSet {
                repeater.send(.value(val))
            }
        }

        let safeGet: () -> T = {
            lock.lock(); defer { lock.unlock() }
            return val
        }

        self.init(
            repeater: repeater,
            get: safeGet,
            set: {
                lock.lock()
                val = $0
                lock.unlock()
        },
            listen: ValueStorage.disposed(lock, repeater: repeater)
        )
    }

    public static func unsafe(
        unowned value: T,
        dispatcher: @escaping (ListenEvent<T>, Assign<ListenEvent<T>>) -> Void = { $1.call($0) }
        ) -> ValueStorage {
        return ValueStorage(unsafeUnowned: value, dispatcher: dispatcher)
    }
    public static func locked(
        unowned value: T,
        lock: NSLocking = NSRecursiveLock(),
        dispatcher: @escaping (ListenEvent<T>, Assign<ListenEvent<T>>) -> Void = { $1.call($0) }
        ) -> ValueStorage {
        return ValueStorage(lockedUnowned: value, lock: lock, dispatcher: dispatcher)
    }
}

struct Trivial<T>: Listenable, ValueWrapper {
    let repeater: Repeater<T>

    var value: T {
        didSet {
            repeater.send(.value(value))
        }
    }

    init(_ value: T, repeater: Repeater<T>) {
        self.value = value
        self.repeater = repeater
    }

    init(_ value: T) {
        self.init(value, repeater: Repeater.unsafe())
    }

    func sendError(_ error: Error) {
        repeater.send(.error(error))
    }

    func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
        return repeater.listen(assign)
    }
}
