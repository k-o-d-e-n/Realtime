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
}

public final class __Promise<T>: Listenable {
    public typealias Dispatcher = Repeater<T>.Dispatcher

    var disposes: [Disposable] = []
    var _result: ListenEvent<T>? = .none
    var _dispatcher: _Dispatcher

    init(result: ListenEvent<T>? = .none, dispatcher: _Dispatcher) {
        self._result = result
        self._dispatcher = dispatcher
    }

    enum _Dispatcher {
        case direct
        case repeater(NSLocking, Repeater<T>)
    }

    public convenience init() {
        self.init(lock: NSRecursiveLock(), dispatcher: .default)
    }

    public convenience init(_ value: T) {
        self.init(unsafe: .value(value))
    }

    public convenience init(_ error: Error) {
        self.init(unsafe: .error(error))
    }

    /// Creates new instance with `strong` reference that has no thread-safe working context
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - dispatcher: Closure that implements method of dispatch events to listeners.
    public convenience init(unsafe value: ListenEvent<T>) {
        self.init(result: value, dispatcher: .direct)
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
        self.init(dispatcher: .repeater(lock, repeater))
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
        ) -> __Promise {
        return __Promise(lock: lock, dispatcher: dispatcher)
    }

    public func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
        switch _dispatcher {
        case .repeater(let lock, let repeater):
            switch _result {
            case .none:
                lock.lock()
                let d = repeater.listening(assign)
                lock.unlock()
                return ListeningDispose {
                    lock.lock()
                    d.dispose()
                    lock.unlock()
                }
            case .some(let v):
                assign.call(v)
                return EmptyDispose()
            }
        case .direct:
            assign.call(_result!)
            return EmptyDispose()
        }
    }
}
public extension __Promise {
    func fulfill(_ value: T) {
        _resolve(.value(value))
    }
    func reject(_ error: Error) {
        _resolve(.error(error))
    }

    internal func _resolve(_ result: ListenEvent<T>) {
        switch _dispatcher {
        case .direct: break
        case .repeater(let lock, let repeater):
            lock.lock()
            disposes.forEach { $0.dispose() }
            disposes.removeAll()
            self._result = .some(result)
            self._dispatcher = .direct
            repeater.send(result)
            lock.unlock()
        }
    }

    typealias Then<Result> = (T) throws -> Result

    @discardableResult
    func then(on queue: DispatchQueue = .main, make it: @escaping Then<Void>) -> __Promise {
        let promise = __Promise(dispatcher: .default)
        self.queue(queue).listening({ (event) in
            switch event {
            case .error(let e): promise.reject(e)
            case .value(let v):
                do {
                    try it(v)
                    promise.fulfill(v)
                } catch let e {
                    promise.reject(e)
                }
            }
        }).add(to: &promise.disposes)
        return promise
    }

    @discardableResult
    func then<Result>(on queue: DispatchQueue = .main, make it: @escaping Then<Result>) -> __Promise<Result> {
        let promise = __Promise<Result>(dispatcher: .default)
        self.queue(queue).listening({ (event) in
            switch event {
            case .error(let e): promise.reject(e)
            case .value(let v):
                do {
                    promise.fulfill(try it(v))
                } catch let e {
                    promise.reject(e)
                }
            }
        }).add(to: &promise.disposes)
        return promise
    }

    @discardableResult
    func then<Result>(on queue: DispatchQueue = .main, make it: @escaping Then<__Promise<Result>>) -> __Promise<Result> {
        let promise = __Promise<Result>(dispatcher: .default)
        self.queue(queue).listening({ (event) in
            switch event {
            case .error(let e): promise.reject(e)
            case .value(let v):
                do {
                    let p = try it(v)
                    p.listening({ (event) in
                        switch event {
                        case .error(let e): promise.reject(e)
                        case .value(let v): promise.fulfill(v)
                        }
                    }).add(to: &promise.disposes)
                } catch let e {
                    promise.reject(e)
                }
            }
        }).add(to: &promise.disposes)
        return promise
    }

    func `catch`(on queue: DispatchQueue = .main, make it: @escaping (Error) -> Void) -> __Promise {
        let promise = __Promise(dispatcher: .default)
        self.queue(queue).listening({ (event) in
            switch event {
            case .error(let e):
                it(e)
                promise.reject(e)
            case .value(let v): promise.fulfill(v)
            }
        }).add(to: &promise.disposes)
        return promise
    }
}

import Promise_swift

public typealias _Promise<T> = DispatchPromise<T>
public typealias PromiseVoid = DispatchPromise<Void>
public typealias ResultPromise<T> = DispatchPromise<T>
extension DispatchPromise where Value == Void {
    func fulfill() {
        self.fulfill(())
    }
}

extension DispatchPromise: Listenable {
    public func listening(_ assign: Closure<ListenEvent<Value>, Void>) -> Disposable {
        self.do(assign.map({ .value($0) }).call)
        self.resolve(assign.map({ .error($0) }).call)
        return EmptyDispose()
    }
}
extension _Promise: RealtimeTask {
    public var completion: AnyListenable<Void> { return AnyListenable(map({ _ in () })) }
}
