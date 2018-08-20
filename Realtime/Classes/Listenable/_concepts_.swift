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

struct P<T>: Listenable, ValueWrapper {
    let get: () -> T
    let set: (T) -> Void
    let listen: (Assign<ListenEvent<T>>) -> Disposable
    let listenItem: (Assign<ListenEvent<T>>) -> ListeningItem

    var value: T {
        get { return get() }
        set { set(newValue) }
    }

    init(_ value: T) {
        var nextToken = UInt.min
        var listeners: [UInt: Assign<ListenEvent<T>>] = [:]
        var val = value {
            didSet {
                listeners.forEach { (assign) in
                    assign.value.assign(.value(val))
                }
            }
        }
        get = { val }
        set = { val = $0 }
        listen = { assign in
            defer { nextToken += 1 }

            let token = nextToken
            listeners[token] = assign

            return ListeningDispose {
                listeners.removeValue(forKey: token)
            }
        }

        listenItem = { assign in
            defer { nextToken += 1 }

            listeners[nextToken] = assign

            return ListeningItem(start: { () -> UInt? in
                defer { nextToken += 1 }
                listeners[nextToken] = assign
                return nextToken
            }, stop: { (t) in
                listeners.removeValue(forKey: t)
            }, notify: {
                assign.assign(.value(val))
            }, token: nextToken)
        }
    }

    func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
        return listen(assign)
    }

    func listeningItem(_ assign: Assign<ListenEvent<T>>) -> ListeningItem {
        return listenItem(assign)
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
    func threadSafe(use serialQueue: DispatchQueue) -> QueueSafe<OutData> {
        return QueueSafe(base: AnyListenable(self.listening, self.listeningItem), queue: serialQueue)
    }
}

///// Attempt create primitive value, property where value will be copied

struct Primitive<T> {
    let get: () -> T
    let set: (T) -> Void

    init(_ value: T) {
        var val = value
        let pointer = UnsafeMutablePointer(&val)
        get = { val }
        set = { pointer.pointee = $0 }
    }
}

struct PrimitiveValue<T> {
    fileprivate var getter: (_ owner: PrimitiveValue<T>) -> T
    private var setter: (_ owner: inout PrimitiveValue<T>, _ value: T) -> Void
    private var value: T

    func get() -> T {
        return getter(self)
    }

    mutating func set(_ val: T) {
        setter(&self, val)
    }

    init(_ value: T) {
        self.value = value
        setter = { $0.value = $1 }
        //        let pointer = UnsafeMutablePointer<PrimitiveValue<V>>(&self)
        getter = { $0.value }
    }

    func `deinit`() {
        // hidden possibillity
    }
}

struct PrimitiveProperty<Value>: ValueWrapper {
    lazy var insider: Insider<Value> = Insider(source: self.concreteValue.get) // 'get' implicitly took concreteValue, and returned always one value
    private var concreteValue: PrimitiveValue<Value>
    var value: Value {
        get { return concreteValue.get() }
        set { concreteValue.set(newValue); insider.dataDidChange() }
    }

    init(value: Value) {
        concreteValue = PrimitiveValue(value)
    }
}

// MARK: Not used yet or unsuccessful attempts

protocol AnyInsider {
    associatedtype Data
    associatedtype Token
//    var dataSource: () -> Data { get }
    mutating func connect(with listening: AnyListening) -> Token
    mutating func disconnect(with token: Token)
}
