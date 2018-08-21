//
//  _concepts_.swift
//  Pods
//
//  Created by Denis Koryttsev on 31/01/2018.
//

import Foundation

struct ListenableValue<T> {
    let get: () -> T
    let set: (T) -> Void
    let setWithoutNotify: (T) -> Void
    let getInsider: () -> Insider<T>
    let setInsider: (Insider<T>) -> Void

    init(_ value: T) {
        var val = value
        get = { val }
        var insider = Insider(source: get)
        set = { val = $0; insider.dataDidChange(); }
        setWithoutNotify = { val = $0 }
        getInsider = { insider }
        setInsider = { insider = $0 }
    }
}

extension ListenableValue {
    var insider: Insider<T> {
        get { return getInsider() }
        set { setInsider(newValue) }
    }
}

struct Repeater<T>: Listenable {
    let sender: (ListenEvent<T>) -> Void
    let listen: (Assign<ListenEvent<T>>) -> Disposable
    let listenItem: (Assign<ListenEvent<T>>) -> ListeningItem

    static func unmanaged(with dispatcher: @escaping (ListenEvent<T>, Assign<ListenEvent<T>>) -> Void = { $1.assign($0) }) -> Repeater<T> {
        return Repeater(dispatcher: dispatcher)
    }

    init(dispatcher: @escaping (ListenEvent<T>, Assign<ListenEvent<T>>) -> Void) {
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

        self.listenItem = { assign in
            defer { nextToken += 1 }

            listeners[nextToken] = assign

            return ListeningItem(start: { () -> UInt? in
                defer { nextToken += 1 }
                listeners[nextToken] = assign
                return nextToken
            }, stop: { (t) in
                listeners.removeValue(forKey: t)
            }, notify: {
                assign.assign(.error(RealtimeError(source: .listening, description: "No value to notify")))
            }, token: nextToken)
        }
    }

    init(queue: DispatchQueue) {
        self.init { (e, a) in
            queue.async { a.assign(e) }
        }
    }

    static func locked(by lock: NSLocking, dispatcher: @escaping (ListenEvent<T>, Assign<ListenEvent<T>>) -> Void = { $1.assign($0) }) -> Repeater<T> {
        return Repeater(lockedBy: lock, dispatcher: dispatcher)
    }

    init(lockedBy lock: NSLocking, dispatcher: @escaping (ListenEvent<T>, Assign<ListenEvent<T>>) -> Void = { $1.assign($0) }) {
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

        self.listenItem = { assign in
            lock.lock()
            defer {
                nextToken += 1
                lock.unlock()
            }

            let token = nextToken
            listeners[token] = assign

            return ListeningItem(start: { () -> UInt? in
                lock.lock(); defer { lock.unlock() }
                listeners[token] = assign
                return token
            }, stop: { (t) in
                lock.lock(); defer { lock.unlock() }
                listeners.removeValue(forKey: t)
            }, notify: {
                assign.assign(.error(RealtimeError(source: .listening, description: "No value to notify")))
            }, token: token)
        }
    }

    init(lockedBy lock: NSLocking, queue: DispatchQueue) {
        self.init(lockedBy: lock) { (e, a) in
            queue.async { a.assign(e) }
        }
    }

    func send(_ event: ListenEvent<T>) {
        sender(event)
    }

    func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
        return listen(assign)
    }

    func listeningItem(_ assign: Assign<ListenEvent<T>>) -> ListeningItem {
        return listenItem(assign)
    }
}

struct P<T>: Listenable, ValueWrapper {
    let get: () -> T
    let set: (T) -> Void
    let listenItem: (Assign<ListenEvent<T>>) -> ListeningItem
    let repeater: Repeater<T>

    var value: T {
        get { return get() }
        nonmutating set { set(newValue) }
    }

    init(_ value: T, repeater: Repeater<T>) {
        var val = value {
            didSet {
                repeater.sender(.value(val))
            }
        }

        self.repeater = repeater
        self.get = { val }
        self.set = { val = $0 }
        self.listenItem = { assign in
            let item = repeater.listeningItem(assign)
            return ListeningItem(
                start: item.start,
                stop: item.stop,
                notify: { assign.assign(.value(val)) },
                token: ()
            )
        }
    }

    init(_ value: T) {
        self.init(value, repeater: Repeater<T>.unmanaged())
    }

    func sendError(_ error: Error) {
        repeater.sender(.error(error))
    }

    func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
        return repeater.listen(assign)
    }

    func listeningItem(_ assign: Assign<ListenEvent<T>>) -> ListeningItem {
        return listenItem(assign)
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
        self.init(value, repeater: Repeater.unmanaged())
    }

    func sendError(_ error: Error) {
        repeater.send(.error(error))
    }

    func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
        return repeater.listen(assign)
    }

    func listeningItem(_ assign: Assign<ListenEvent<T>>) -> ListeningItem {
        return repeater.listeningItem(assign)
    }
}

public struct ThreadSafe<T>: Listenable {
    let base: AnyListenable<T>
    let lock: NSLock = NSLock()

    public func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
        lock.lock(); defer { lock.unlock() }
        return base.listening(assign)
    }

    public func listeningItem(_ assign: Assign<ListenEvent<T>>) -> ListeningItem {
        lock.lock(); defer { lock.unlock() }
        return base.listeningItem(assign)
    }
}

public struct QueueSafe<T>: Listenable {
    let base: AnyListenable<T>
    let queue: DispatchQueue
    let lock: NSLock = NSLock()

    public func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
        return queue.sync {
            return base.listening(assign)
        }
    }

    public func listeningItem(_ assign: Assign<ListenEvent<T>>) -> ListeningItem {
        return queue.sync {
            return base.listeningItem(assign)
        }
    }
}

public extension Listenable {
    func threadSafe() -> ThreadSafe<OutData> {
        return ThreadSafe(base: AnyListenable(self.listening, self.listeningItem))
    }
    func queueSafe(use serialQueue: DispatchQueue) -> QueueSafe<OutData> {
        return QueueSafe(base: AnyListenable(self.listening, self.listeningItem), queue: serialQueue)
    }
}
