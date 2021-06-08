//
//  _concepts_.swift
//  Pods
//
//  Created by Denis Koryttsev on 31/01/2018.
//

import Foundation

struct Trivial<T>: Listenable {
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
extension Trivial {
    static func <==(_ prop: inout Self, _ value: T) {
        prop.value = value
    }
    static func <==(_ value: inout T, _ prop: Self) {
        value = prop.value
    }
    static func <==(_ value: inout T?, _ prop: Self) {
        value = prop.value
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

/// New `Repeater` type

protocol CallbackPoint: AnyObject {
    associatedtype Point: CallbackPoint
    var next: Point? { get set }
    var previous: Point? { get set }
}
extension CallbackPoint where Self.Point.Point == Self.Point {
    func collapse() {
        guard let prev = previous else { return }
        self.previous = nil
        guard let next = next else { return }
        prev.next = next
        next.previous = prev
        self.next = nil
    }
}
protocol CallbackProtocol: CallbackPoint {
    associatedtype T
    func call(back event: ListenEvent<T>)
}
#warning("TODO: Add threadsafe callback version with atomic references")
public struct CallbackQueue<T> {
    let head: Head = Head()
    let tail: Tail = Tail()

    public class Point: CallbackProtocol {
        var next: Point?
        weak var previous: Point?

        public func call(back event: ListenEvent<T>) {}
    }

    final class Head: Point {
        override var previous: Point? {
            get { nil }
            set { fatalError("Cannot set previous in head") }
        }
    }
    final class Tail: Point {
        override var next: Point? {
            get { nil }
            set { fatalError("Cannot set next in tail") }
        }
    }

    final class Callback: Point {
        let sink: Assign<ListenEvent<T>>

        init(_ sink: Assign<ListenEvent<T>>) {
            self.sink = sink
        }

        deinit {
            collapse()
        }

        override func call(back event: ListenEvent<T>) {
            sink.call(event)
        }
    }

    func enqueue(_ assign: Assign<ListenEvent<T>>) -> Callback {
        let callback = Callback(assign)
        if let last = tail.previous {
            last.next = callback
            callback.previous = last
        } else {
            head.next = callback
            callback.previous = head
        }
        tail.previous = callback
        callback.next = tail
        return callback
    }

    func dequeue() -> Point? {
        guard head.next !== tail else { return nil }
        return head.next.map { (cb) -> Point in
            cb.collapse()
            return cb
        }
    }
}
extension CallbackQueue: Sequence {
    public typealias Iterator = Array<Point>.Iterator
    public func makeIterator() -> Iterator {
        var currentElements: [Point] = []
        var point: Point = head
        while let next = point.next, tail !== next {
            currentElements.append(next)
            point = next
        }
        return currentElements.makeIterator()
    }
    public struct _Iterator: IteratorProtocol {
        let _last: Point?
        var _next: Point?

        mutating public func next() -> Point? {
            defer {
                _next = _last === _next ? nil : _next?.next
            }
            return _next
        }
    }
}
extension CallbackQueue.Point: Disposable {
    var isCollapsed: Bool { next == nil && previous == nil }
    public func dispose() {
        collapse()
    }
}
extension CallbackQueue {
    func send(_ event: ListenEvent<T>) {
        var point: Point = head
        while let next = point.next {
            next.call(back: event)
            point = next
        }
    }
}
extension CallbackQueue {
    func _validate() -> Bool {
        #if DEBUG
        var point: Point = head
        while let next = point.next {
            guard next.previous === point else { return false }
            guard next !== tail else { return true }
            point = next
        }
        return point === head
        #else
        return true
        #endif
    }
}
