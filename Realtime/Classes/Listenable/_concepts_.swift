//
//  _concepts_.swift
//  Pods
//
//  Created by Denis Koryttsev on 31/01/2018.
//

import Foundation

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
        return repeater.listening(assign)
    }

    public func listeningItem(_ assign: Assign<ListenEvent<T>>) -> ListeningItem {
        return repeater.listeningItem(assign)
    }
}

/// Stores value and sends event on his change
public final class _Promise<T>: Listenable {
    public typealias Dispatcher = Repeater<T>.Dispatcher

    var disposes: ListeningDisposeStore = ListeningDisposeStore()
    let _get: () -> ListenEvent<T>?
    let _fulfill: (ListenEvent<T>) -> Void
    let _listen: (Assign<ListenEvent<T>>) -> Disposable

    init(get: @escaping () -> ListenEvent<T>?,
         set: @escaping (ListenEvent<T>) -> Void,
         listen: @escaping (Assign<ListenEvent<T>>) -> Disposable) {
        self._get = get
        self._fulfill = set
        self._listen = listen
    }

    public convenience init() {
        self.init(lock: NSRecursiveLock(), dispatcher: .default)
    }

    public convenience init(_ value: T) {
        self.init(unsafe: .value(value), dispatcher: .default)
    }

    public convenience init(_ error: Error) {
        self.init(unsafe: .error(error), dispatcher: .default)
    }

    /// Creates new instance with `strong` reference that has no thread-safe working context
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    public convenience init(unsafe value: ListenEvent<T>?, dispatcher: Dispatcher) {
        let repeater = Repeater(dispatcher: dispatcher)
        var val: ListenEvent<T>! = value {
            didSet {
                repeater.send(val)
            }
        }

        self.init(
            get: { val }, set: { val = $0 },
            listen: repeater.listening
        )
    }

    /// Creates new instance with `strong` reference that has thread-safe implementation
    /// using lock object.
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - lock: Lock object.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    public convenience init(lock: NSLocking = NSRecursiveLock(), dispatcher: Dispatcher) {
        let repeater = Repeater(dispatcher: dispatcher)
        var val: ListenEvent<T>! = nil {
            didSet {
                repeater.send(val)
            }
        }

        let safeGet: () -> ListenEvent<T>? = {
            lock.lock(); defer { lock.unlock() }
            return val
        }

        self.init(
            get: safeGet,
            set: {
                lock.lock()
                val = $0
                lock.unlock()
            },
            listen: _Promise.disposed(lock, repeater: repeater)
        )
    }

    /// Returns storage with `strong` reference that has no thread-safe working context
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    public static func unsafe(
        strong value: T?,
        dispatcher: Dispatcher
        ) -> _Promise {
        return _Promise(unsafe: value.map { .value($0) }, dispatcher: dispatcher)
    }

    /// Returns storage with `strong` reference that has thread-safe implementation
    /// using lock object.
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - lock: Lock object.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    public static func locked(
        lock: NSLocking = NSRecursiveLock(),
        dispatcher: Dispatcher
        ) -> _Promise {
        return _Promise(lock: lock, dispatcher: dispatcher)
    }

    public func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
        switch _get() {
        case .none:
            return _listen(assign)
        case .some(let v):
            assign.call(v)
            return EmptyDispose()
        }
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
public extension _Promise {
    func fulfill(_ value: T) {
        switch _get() {
        case .some: break
        case .none:
            unsafeFulfill(value)
        }
    }
    func reject(_ error: Error) {
        switch _get() {
        case .some: break
        case .none:
            unsafeReject(error)
        }
    }

    fileprivate func unsafeFulfill(_ value: T) {
        disposes.dispose()
        _fulfill(.value(value))
    }
    fileprivate func unsafeReject(_ error: Error) {
        disposes.dispose()
        _fulfill(.error(error))
    }

    typealias Then<Result> = (T) throws -> Result

    @discardableResult
    func then(on queue: DispatchQueue = .main, make it: @escaping Then<Void>) -> _Promise {
        let promise = _Promise(lock: NSRecursiveLock(), dispatcher: .default)
        self.queue(queue).listening({ (event) in
            switch event {
            case .error(let e): promise.unsafeReject(e)
            case .value(let v):
                do {
                    try it(v)
                    promise.unsafeFulfill(v)
                } catch let e {
                    promise.unsafeReject(e)
                }
            }
        }).add(to: promise.disposes)
        return promise
    }

    @discardableResult
    public func then<Result>(on queue: DispatchQueue = .main, make it: @escaping Then<Result>) -> _Promise<Result> {
        let promise = _Promise<Result>(lock: NSRecursiveLock(), dispatcher: .default)
        self.queue(queue).listening({ (event) in
            switch event {
            case .error(let e): promise.unsafeReject(e)
            case .value(let v):
                do {
                    promise.unsafeFulfill(try it(v))
                } catch let e {
                    promise.unsafeReject(e)
                }
            }
        }).add(to: promise.disposes)
        return promise
    }

    @discardableResult
    public func then<Result>(on queue: DispatchQueue = .main, make it: @escaping Then<_Promise<Result>>) -> _Promise<Result> {
        let promise = _Promise<Result>(dispatcher: .default)
        self.queue(queue).listening({ (event) in
            switch event {
            case .error(let e): promise.reject(e)
            case .value(let v):
                do {
                    let p = try it(v)
                    p.listening({ (event) in
                        switch event {
                        case .error(let e): promise.unsafeReject(e)
                        case .value(let v): promise.unsafeFulfill(v)
                        }
                    }).add(to: promise.disposes)
                } catch let e {
                    promise.unsafeReject(e)
                }
            }
        }).add(to: promise.disposes)
        return promise
    }

    func `catch`(on queue: DispatchQueue = .main, make it: @escaping (Error) -> Void) -> _Promise {
        let promise = _Promise.locked(dispatcher: .default)
        self.queue(queue).listening({ (event) in
            switch event {
            case .error(let e):
                it(e)
                promise.unsafeReject(e)
            case .value(let v): promise.unsafeFulfill(v)
            }
        }).add(to: promise.disposes)
        return promise
    }
}
