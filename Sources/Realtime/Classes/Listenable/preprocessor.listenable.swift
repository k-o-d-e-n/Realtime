//
//  Preprocessor.swift
//  GoogleToolboxForMac
//
//  Created by Denis Koryttsev on 31/01/2018.
//

import Foundation

// MARK: Map, filter

typealias BridgeBlank<I, O> = (_ value: I, _ assign: @escaping (O) -> Void) -> Void

struct Bridge<I, O> {
    let bridge: BridgeBlank<ListenEvent<I>, ListenEvent<O>>

    func wrapAssign(_ assign: Assign<ListenEvent<O>>) -> Assign<ListenEvent<I>> {
        return .just({ i in self.bridge(i, assign.assign) })
    }

    init(bridge: @escaping BridgeBlank<ListenEvent<I>, ListenEvent<O>>) {
        self.bridge = bridge
    }

    init(transform: @escaping (I) throws -> O) {
        self.init(bridge: { value, assign in
            do {
                let transformed = try value.map(transform)
                assign(transformed)
            } catch let e {
                assign(.error(e))
            }
        })
    }
    init(event: @escaping (I, ResultPromise<O>) throws -> Void) {
        self.init(bridge: { (e, assign) in
            switch e {
            case .value(let v):
                do {
                    let promise: ResultPromise<O> = ResultPromise()
                    promise.do({ assign(.value($0)) }).resolve({ assign(.error($0)) })
                    try event(v, promise)
                } catch let e {
                    assign(.error(e))
                }
            case .error(let e): assign(.error(e))
            }
        })
    }
}
extension Bridge where I == O {
    init(predicate: @escaping (O) -> Bool) {
        self.init(bridge: { (e, assign) in
            switch e {
            case .value(let v):
                if predicate(v) {
                    assign(.value(v))
                }
            case .error(let e): assign(.error(e))
            }
        })
    }
    init(event: @escaping (O, PromiseVoid) throws -> Void) {
        self.init(bridge: { e, assign in
            switch e {
            case .value(let v):
                do {
                    let promise = PromiseVoid()
                    promise.do({ assign(.value(v)) }).resolve({ assign(.error($0)) })
                    try event(v, promise)
                } catch let e {
                    assign(.error(e))
                }
            case .error: assign(e)
            }
        })
    }
}

public struct Preprocessor<I: Listenable, O>: Listenable {
    let listenable: I
    let bridgeMaker: Bridge<I.Out, O>

    public func listening(_ assign: Assign<ListenEvent<O>>) -> Disposable {
        return listenable.listening(bridgeMaker.wrapAssign(assign))
    }
}

public extension Listenable {
    /// Returns listenable that filters value events
    ///
    /// - Parameter predicate: Closure to evaluate value
    func filter(_ predicate: @escaping (Out) -> Bool) -> Preprocessor<Self, Out> {
        return Preprocessor(listenable: self,
                            bridgeMaker: Bridge(predicate: predicate))
    }

    /// Returns listenable that transforms value events
    ///
    /// - Parameter transform: Closure to transform value
    func map<U>(_ transform: @escaping (Out) throws -> U) -> Preprocessor<Self, U> {
        return Preprocessor(listenable: self,
                            bridgeMaker: Bridge(transform: transform))
    }

    typealias CompactMap<U> = Preprocessor<Preprocessor<Preprocessor<Self, U?>, U?>, U>
    /// transforms value if it's not `nil`, otherwise skips value
    func compactMap<U>(_ transform: @escaping (Out) throws -> U?) -> CompactMap<U> {
        return self.map(transform).compactMap()
    }

    /// Returns listenable that on receive value event calls the passed closure
    /// and waits when is received signal in `Promise`
    ///
    /// - Warning: This does not preserve the sequence of events
    ///
    /// - Parameter event: Closure to run async work.
    func doAsync(_ event: @escaping (Out, PromiseVoid) throws -> Void) -> Preprocessor<Self, Out> {
        return Preprocessor(listenable: self,
                            bridgeMaker: Bridge(event: event))
    }
    /// Returns listenable that on receive value event calls the passed closure
    /// and waits when is received signal in `ResultPromise`
    ///
    /// - Parameter event: Closure to run async work.
    func mapAsync<Result>(_ event: @escaping (Out, ResultPromise<Result>) throws -> Void) -> Preprocessor<Self, Result> {
        return Preprocessor(listenable: self,
                            bridgeMaker: Bridge(event: event))
    }

    func forEach(_ closure: @escaping (Out) throws -> Void) -> Preprocessor<Self, Out> {
        return map { v -> Out in
            try closure(v)
            return v
        }
    }
}

public struct EventMap<I, O>: Listenable {
    fileprivate let listenable: AnyListenable<I>
    let transform: (ListenEvent<I>) throws -> ListenEvent<O>

    public func listening(_ assign: Closure<ListenEvent<O>, Void>) -> Disposable {
        return listenable.listening(assign.mapIn({ event in
            do {
                return try self.transform(event)
            } catch let e {
                return .error(e)
            }
        }))
    }
}
extension Listenable {
    public func mapEvent<T>(_ transform: @escaping (ListenEvent<Out>) throws -> ListenEvent<T>) -> EventMap<Out, T> {
        return EventMap(listenable: AnyListenable(self), transform: transform)
    }
    public func anywayValue() -> EventMap<Out, ListenEvent<Out>> {
        return mapEvent({ .value($0) })
    }
    public func mapError(_ transform: @escaping (Error) -> Error) -> EventMap<Out, Out> {
        return mapEvent({ (event) -> ListenEvent<Out> in
            switch event {
            case .error(let e): return .error(transform(e))
            default: return event
            }
        })
    }
    public func resolved(with transform: @escaping (Error) throws -> Out) -> EventMap<Out, Out> {
        return mapEvent({ (event) -> ListenEvent<Out> in
            switch event {
            case .error(let e): return .value(try transform(e))
            default: return event
            }
        })
    }
    public func resolved(with value: @escaping @autoclosure () -> Out) -> EventMap<Out, Out> {
        return mapEvent({ (event) -> ListenEvent<Out> in
            switch event {
            case .error: return .value(value())
            default: return event
            }
        })
    }
    public func resolved(with transform: @escaping (Error) throws -> Out?) -> EventMap<Out, Out?> {
        return mapEvent({ (event) -> ListenEvent<Out?> in
            switch event {
            case .error(let e): return .value(try transform(e))
            case .value(let v): return .value(v)
            }
        })
    }
    public func resolved(with value: @escaping @autoclosure () -> Out?) -> EventMap<Out, Out?> {
        return mapEvent({ (event) -> ListenEvent<Out?> in
            switch event {
            case .error: return .value(value())
            case .value(let v): return .value(v)
            }
        })
    }
}

/// Fires if disposes use his Disposable. Else if has previous dispose behaviors like as once(), livetime(_:) and others, will not called.
/// Can calls before last event.
public struct OnFire<T: Listenable>: Listenable {
    fileprivate let listenable: T
    fileprivate let onFire: () -> Void

    public func listening(_ assign: Assign<ListenEvent<T.Out>>) -> Disposable {
        let disposable = listenable.listening(assign)
        return ListeningDispose({
            disposable.dispose()
            self.onFire()
        })
    }
}
public extension Listenable {
    /// calls closure on disconnect
    func onFire(_ todo: @escaping () -> Void) -> OnFire<Self> {
        return OnFire(listenable: self, onFire: todo)
    }
}

public struct Do<T: Listenable>: Listenable {
    fileprivate let listenable: T
    fileprivate let doit: (ListenEvent<T.Out>) -> Void

    public func listening(_ assign: Assign<ListenEvent<T.Out>>) -> Disposable {
        return listenable.listening(assign.with(work: doit))
    }
}
public extension Listenable {
    /// calls closure on receive next value
    func `do`(_ something: @escaping (ListenEvent<Out>) -> Void) -> Do<Self> {
        return Do(listenable: self, doit: something)
    }

    func `do`(onValue something: @escaping (Out) -> Void) -> Do<Self> {
        return self.do({ event in
            switch event {
            case .value(let v): something(v)
            default: break
            }
        })
    }
    func `do`(onError something: @escaping (Error) -> Void) -> Do<Self> {
        return self.do({ event in
            switch event {
            case .error(let e): something(e)
            default: break
            }
        })
    }

    func always(_ doit: @escaping () -> Void) -> Do<Self> {
        return self.do({ _ in doit() })
    }
}

public struct Once<T: Listenable>: Listenable {
    private let listenable: T

    init(_ base: T) {
        self.listenable = base
    }

    public func listening(_ assign: Assign<ListenEvent<T.Out>>) -> Disposable {
        let disposable: SingleDispose = SingleDispose(weak: nil)
        let dispose = ListeningDispose(
            listenable
                .filter({ _ in disposable.isDisposed == false })
                .listening(assign.with(work: { (_) in
                    disposable.dispose()
                }))
        )
        disposable.replace(with: dispose)
        return dispose
    }
}
public extension Listenable {
    /// Connection to receive single value
    /// - Warning: Disposable must be retained anyway,
    /// otherwise connection will be disposed immediately
    func once() -> Once<Self> {
        return Once(self)
    }
}

extension Bridge where I == O {
    init(queue: DispatchQueue) {
        self.init(bridge: { (value, assign) in
            queue.async {
                assign(value)
            }
        })
    }
}
public extension Listenable {
    /// calls connection on specific queue
    func queue(_ queue: DispatchQueue) -> Preprocessor<Self, Out> {
        return Preprocessor(listenable: self, bridgeMaker: Bridge(queue: queue))
    }
}

public struct Deadline<T: Listenable>: Listenable {
    private let listenable: T
    private let deadline: DispatchTime

    init(_ base: T, deadline: DispatchTime) {
        self.listenable = base
        self.deadline = deadline
    }

    public func listening(_ assign: Assign<ListenEvent<T.Out>>) -> Disposable {
        var disposable: Disposable! = nil
        disposable = listenable.listening(assign.filter({ _ -> Bool in
            guard self.deadline >= .now() else {
                disposable.dispose()
                return false
            }
            return true
        }))
        return disposable
    }
}
public extension Listenable {
    /// works until time has not reached deadline
    /// - Warning: can lead to memory leaks
    @available(*, deprecated, message: "has unsafe behavior")
    func deadline(_ time: DispatchTime) -> Deadline<Self> {
        return Deadline(self, deadline: time)
    }
}

public struct Livetime<T: Listenable>: Listenable {
    private let listenable: T
    private weak var livingItem: AnyObject?

    init(_ base: T, living: AnyObject) {
        self.listenable = base
        self.livingItem = living
    }

    public func listening(_ assign: Assign<ListenEvent<T.Out>>) -> Disposable {
        var disposable: Disposable! = nil
        disposable = listenable.listening(assign.filter({ _ -> Bool in
            guard self.livingItem != nil else {
                disposable.dispose()
                return false
            }
            return true
        }))
        return disposable
    }
}
public extension Listenable {
    /// works until alive specified object
    /// - Warning: can lead to memory leaks
    @available(*, deprecated, message: "has unsafe behavior")
    func livetime(of object: AnyObject) -> Livetime<Self> {
        return Livetime(self, living: object)
    }
}

extension Bridge where I == O {
    init(debounce time: DispatchTimeInterval) {
        var isNeedSend = true
        var fireDate: DispatchTime = .now()
        var next: ListenEvent<I>?

        func debounce(_ event: ListenEvent<I>, _ assign: @escaping (ListenEvent<O>) -> Void) {
            switch event {
            case .error: return assign(event)
            case .value:
                next = event
                guard fireDate <= .now() else { isNeedSend = true; return }

                isNeedSend = false
                next.map(assign)
                fireDate = .now() + time
                DispatchQueue.main.asyncAfter(deadline: fireDate, execute: {
                    if isNeedSend, let n = next {
                        debounce(n, assign)
                    }
                })
            }
        }

        self.init(bridge: debounce)
    }
}
public extension Listenable {
    /// each next event are calling not earlier a specified period
    func debounce(_ time: DispatchTimeInterval) -> Preprocessor<Self, Out> {
        return Preprocessor(listenable: self, bridgeMaker: Bridge(debounce: time))
    }
}

public struct Accumulator<T>: Listenable {
    let repeater: Repeater<T>
    let store: ListeningDisposeStore = ListeningDisposeStore()

    public init<L: Listenable>(repeater: Repeater<T>, _ inputs: L...) where L.Out == T {
        self.repeater = repeater
        self._first = _First()
        inputs.forEach { l in
            repeater.depends(on: l).add(to: store)
        }
    }

    public init<L: Listenable>(repeater: Repeater<T>, _ inputs: [L]) where L.Out == T {
        self.repeater = repeater
        self._first = _First()
        inputs.forEach { l in
            repeater.depends(on: l).add(to: store)
        }
    }

    public init<L1: Listenable, L2: Listenable>(repeater: Repeater<T>, _ one: L1, _ two: L2) where T == (L1.Out, L2.Out) {
        self.init(repeater: repeater, one, default: nil, two, default: nil)
    }
    public init<L1: Listenable, L2: Listenable>(repeater: Repeater<T>, _ one: L1, default defOne: L1.Out?, _ two: L2, default defTwo: L2.Out?) where T == (L1.Out, L2.Out) {
        self.repeater = repeater
        let _first = _First()

        var event: (one: ListenEvent<L1.Out>?, two: ListenEvent<L2.Out>?) = (defOne.map({ .value($0) }), defTwo.map({ .value($0) })) {
            didSet {
                if let e = fulfill() {
                    _first._wrapped = nil
                    repeater.send(e)
                }
            }
        }

        func fulfill() -> ListenEvent<T>? {
            switch event {
            case (.some(.value(let v1)), .some(.value(let v2))):
                return .value((v1, v2))
            case (.some(.value), .some(.error(let e2))):
                return .error(e2)
            case (.some(.error(let e1)), .some(.value)):
                return .error(e1)
            case (.some(.error(let e1)), .some(.error(let e2))):
                return
                    .error(
                        RealtimeError(source: .listening, description:
                            """
                            Error #1: \(e1.localizedDescription),
                            Error #2: \(e2.localizedDescription)
                            """
                        )
                    )
            default: return nil
            }
        }

        one.listening({ event.one = $0 }).add(to: store)
        two.listening({ event.two = $0 }).add(to: store)

        _first._wrapped = fulfill()
        self._first = _first
    }

    struct Compound3<V1, V2, V3> {
        var first: ListenEvent<V1>?
        var second: ListenEvent<V2>?
        var third: ListenEvent<V3>?

        init() {}

        func fulfill() -> ListenEvent<(V1, V2, V3)>? {
            guard let one = first, let two = second, let third = third else {
                return nil
            }
            guard let val1 = one.value else {
                return .error(error(for: one.error, two.error, third.error))
            }
            guard let val2 = two.value else {
                return .error(error(for: one.error, two.error, third.error))
            }
            guard let val3 = third.value else {
                return .error(error(for: one.error, two.error, third.error))
            }

            return .value((val1, val2, val3))
        }

        func error(for errors: Error? ...) -> RealtimeError {
            var counter = 0
            return RealtimeError(source: .listening, description: errors.reduce(into: "") { (string, error) in
                if let e = error {
                    string.append("\nError #\(counter): \(e.localizedDescription)")
                }
                counter += 1
            })
        }
    }

    public init<L1: Listenable, L2: Listenable, L3: Listenable>(
        repeater: Repeater<T>,
        _ first: L1, _ second: L2, _ third: L3
    ) where T == (L1.Out, L2.Out, L3.Out) {
        self.repeater = repeater
        let _first = _First()

        var event: Compound3<L1.Out, L2.Out, L3.Out> = Compound3() {
            didSet {
                if let e = event.fulfill() {
                    _first._wrapped = nil
                    repeater.send(e)
                }
            }
        }
        first.listening({ event.first = $0 }).add(to: store)
        second.listening({ event.second = $0 }).add(to: store)
        third.listening({ event.third = $0 }).add(to: store)

        _first._wrapped = event.fulfill()
        self._first = _first
    }

    private let _first: _First
    private class _First {
        var _wrapped: ListenEvent<T>?
    }

    private func sendFirstIfExists(_ assign: Assign<ListenEvent<T>>) {
        if let f = _first._wrapped {
            assign.call(f)
            _first._wrapped = nil
        }
    }

    public func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
        defer { sendFirstIfExists(assign) }
        return repeater.listening(assign)
    }
}
public struct Combine<T>: Listenable {
    let accumulator: Accumulator<T>

    public func listening(_ assign: Closure<ListenEvent<T>, Void>) -> Disposable {
        let disposer = accumulator.listening(assign)
        let unmanaged = Unmanaged.passUnretained(accumulator.store).retain()
        return ListeningDispose.init({
            unmanaged.release()
            disposer.dispose()
        })
    }
}

public extension Listenable {
    /// See `func join`.
    /// - Returns: Unretained preprocessor
    func joined(with others: Self...) -> Accumulator<Out> {
        return Accumulator(repeater: .unsafe(), [self] + others)
    }
    /// See `func join`.
    /// - Returns: Unretained preprocessor
    func joined<L: Listenable>(with others: L...) -> Accumulator<Out> where L.Out == Self.Out {
        return Accumulator(repeater: .unsafe(), [self.asAny()] + others.map(AnyListenable.init))
    }
    /// Connects sources to single out
    ///
    /// - Parameter others: Sources that emit the same values
    /// - Returns: Retained preprocessor
    func join(with others: Self...) -> Combine<Out> {
        return Combine(accumulator: Accumulator(repeater: .unsafe(), [self] + others))
    }
    /// See description `func join(with others: Self...)`
    func join<L: Listenable>(with others: L...) -> Combine<Out> where L.Out == Self.Out {
        return Combine(accumulator: Accumulator(repeater: .unsafe(), [self.asAny()] + others.map(AnyListenable.init)))
    }

    /// Returns listenable object that emits event when all sources emit at least one event
    ///
    /// - Parameter other: Other source
    /// - Returns: Unretained accumulator object
    func combined<L: Listenable>(with other: L) -> Accumulator<(Out, L.Out)> {
        return Accumulator(repeater: .unsafe(), self, other)
    }
    /// See description `func combined(with:)`
    func combined<L1: Listenable, L2: Listenable>(with other1: L1, _ other2: L2) -> Accumulator<(Out, L1.Out, L2.Out)> {
        return Accumulator(repeater: .unsafe(), self, other1, other2)
    }
    /// Preprocessor that emits event when all sources emit at least one event
    ///
    /// - Parameter other: Other source
    /// - Returns: Retained preprocessor object
    func combine<L: Listenable>(with other: L) -> Combine<(Out, L.Out)> {
        return Combine(accumulator: combined(with: other))
    }
    /// See description `func combine(with:)`
    func combine<L1: Listenable, L2: Listenable>(with other1: L1, _ other2: L2) -> Combine<(Out, L1.Out, L2.Out)> {
        return Combine(accumulator: Accumulator(repeater: .unsafe(), self, other1, other2))
    }

    /// Creates retained storage that saves last values
    ///
    /// - Parameters:
    ///   - buffer: Buffer behavior implementation
    ///     - continuous: Emits all elements from buffer storage includes new element
    ///         - bufferSize: Storage size
    ///         - waitFullness: If true, emits events when all sources sent at least one value.
    ///         - sendLast: If true it will be emit existed last
    ///     - portionally: Emits elements when buffer fullness and then clears storage
    ///         - bufferSize: Storage size
    ///     - custom: User defined buffer behavior
    /// - Returns: Retained preprocessor object
    func memoize(buffer: Memoize<Self>.Buffer) -> Memoize<Self> {
        return Memoize(
            self,
            storage: .unsafe(strong: ([], false), repeater: .unsafe()),
            buffer: buffer
        )
    }
    /// See description `func memoize`
    func memoizeOne(sendLast: Bool) -> Preprocessor<Memoize<Self>, Out> {
        return memoize(buffer: .continuous(bufferSize: 1, waitFullness: false, sendLast: sendLast)).map({ $0[0] })
    }

    func oldValue(_ default: Out? = nil) -> Preprocessor<Memoize<Self>, (old: Out?, new: Out)> {
        return memoize(buffer: .oldValue())
            .map({ $0.count == 2 ? (old: $0[0], new: $0[1]) : (old: `default`, new: $0[0]) })
    }
    func oldValue(_ default: Out) -> Preprocessor<Memoize<Self>, (old: Out, new: Out)> {
        return memoize(buffer: .oldValue())
            .map({ $0.count == 2 ? (old: $0[0], new: $0[1]) : (old: `default`, new: $0[0]) })
    }
}

/// Added implicit storage in chain with retained listening point
public struct Memoize<T: Listenable>: Listenable {
    let storage: ValueStorage<([T.Out], Bool)>
    let dispose: ListeningDispose

    public struct Buffer {
        public typealias Iterator = (inout ([T.Out], Bool), T.Out) -> [T.Out]?
        let mapper: Iterator

        public static func continuous(bufferSize: Int, waitFullness: Bool, sendLast: Bool) -> Buffer {
            debugFatalError(condition: bufferSize <= 0, "`size` must be more than 0")
            if waitFullness {
                return Buffer(mapper: { (storage, last) -> [T.Out]? in
                    storage.1 = sendLast
                    storage.0.append(last)
                    if storage.0.count >= bufferSize {
                        storage.0.removeFirst(storage.0.count - bufferSize)
                        return storage.0
                    } else {
                        return nil
                    }
                })
            } else {
                return Buffer(mapper: { (storage, last) -> [T.Out]? in
                    storage.1 = sendLast
                    storage.0.append(last)
                    if storage.0.count > bufferSize {
                        storage.0.removeFirst(storage.0.count - bufferSize)
                    }
                    return storage.0
                })
            }
        }
        public static func portionally(bufferSize: Int) -> Buffer {
            debugFatalError(condition: bufferSize <= 0, "`size` must be more than 0")
            return Buffer(mapper: { (storage, last) -> [T.Out]? in
                if storage.0.count < bufferSize {
                    storage.0.append(last)
                    return nil
                } else {
                    defer { storage.0.removeAll() }
                    return storage.0
                }
            })
        }
        public static func custom(_ mapper: @escaping Iterator) -> Buffer {
            return Buffer(mapper: mapper)
        }

        static func oldValue() -> Buffer {
            return Buffer(mapper: { (storage, last) -> [T.Out]? in
                defer { storage.0.isEmpty ? storage.0.append(last) : (storage.0[0] = last) }
                return storage.0.isEmpty ? [last] : [storage.0[0], last]
            })
        }
        static func distinctUntilChanged(comparer: @escaping (T.Out, T.Out) -> Bool) -> Buffer {
            return Buffer(mapper: { (stores, last) -> [T.Out]? in
                if stores.0.isEmpty || comparer(stores.0[0], last) {
                    stores.1 = false
                    return [last]
                } else {
                    stores.1 = true
                    return nil
                }
            })
        }
    }

    init(_ base: T, storage: ValueStorage<([T.Out], Bool)>, buffer: Buffer) {
        precondition(storage.repeater != nil, "Storage must have repeater")
        self.dispose = ListeningDispose(base.listening(
            onValue: { (value) in
                var result: [T.Out]?
                storage.mutate { (currentValue) in
                    result = buffer.mapper(&currentValue, value)
                }
                if let toSend = result {
                    storage.repeater?.send(.value((toSend, true)))
                }
            },
            onError: storage.sendError
        ))
        self.storage = storage
    }

    private func sendLastIfNeeded(_ assign: Closure<ListenEvent<[T.Out]>, Void>) {
        let current = storage.value
        if current.1 {
            assign.call(.value(current.0))
        }
    }

    public func listening(_ assign: Closure<ListenEvent<[T.Out]>, Void>) -> Disposable {
        defer { sendLastIfNeeded(assign) }
        let disposer = storage.repeater!.map({ $0.0 }).listening(assign)
        let unmanaged = Unmanaged.passUnretained(dispose).retain()
        return ListeningDispose.init({
            unmanaged.release()
            disposer.dispose()
        })
    }
}

public struct DoDebug<T: Listenable>: Listenable {
    fileprivate let listenable: T
    fileprivate let doit: (ListenEvent<T.Out>) -> Void

    public func listening(_ assign: Assign<ListenEvent<T.Out>>) -> Disposable {
        #if DEBUG
        return listenable.listening(assign.with(work: doit))
        #else
        return listenable.listening(assign)
        #endif
    }
}
public extension Listenable {
    /// calls closure on receive next value
    func doOnDebug(_ something: @escaping (ListenEvent<Out>) -> Void) -> DoDebug<Self> {
        return DoDebug(listenable: self, doit: something)
    }
    func print(_ labels: Any...) -> DoDebug<Self> {
        return doOnDebug({ Swift.print(labels + [$0]) })
    }
}

/// Creates unretained listening point
public struct Shared<T: Listenable>: Listenable {
    let repeater: Repeater<T.Out>
    let liveStrategy: InternalLiveStrategy

    /// Defines intermediate connection live strategy
    ///
    /// - continuous: Connection lives for all the time while current point alive
    /// - repeatable: Connection lives if at least one listener exists
    public enum ConnectionLiveStrategy {
        case continuous
        case repeatable
    }

    enum InternalLiveStrategy {
        case continuous(Disposable)
        case repeatable(T, ValueStorage<(UInt, ListeningDispose?)>, ListeningDispose)
    }

    init(_ source: T, liveStrategy: ConnectionLiveStrategy, repeater: Repeater<T.Out>) {
        self.repeater = repeater
        switch liveStrategy {
        case .repeatable:
            let connectionStorage = ValueStorage<(UInt, ListeningDispose?)>.unsafe(strong: (0, nil))
            self.liveStrategy = .repeatable(source, connectionStorage, ListeningDispose({
                connectionStorage.value = (connectionStorage.value.0, nil) // disposes when shared deinitialized
            }))
        case .continuous:
            self.liveStrategy = .continuous(source.bind(to: repeater))
        }
    }

    private func increment(_ storage: ValueStorage<(UInt, ListeningDispose?)>, source: T) {
        if storage.value.1 == nil {
            storage.value = (1, ListeningDispose(source.bind(to: repeater)))
        } else {
            storage.value = (storage.value.0 + 1, storage.value.1)
        }
    }

    private static func decrement(_ storage: ValueStorage<(UInt, ListeningDispose?)>) {
        let current = storage.value
        if current.0 == 1 {
            storage.value = (0, nil)
        } else {
            storage.value = (current.0 - 1, current.1)
        }
    }

    public func listening(_ assign: Assign<ListenEvent<T.Out>>) -> Disposable {
        switch self.liveStrategy {
        case .continuous: return repeater.listening(assign)
        case .repeatable(let source, let disposeStorage, _):
            increment(disposeStorage, source: source)
            let dispose = repeater.listening(assign)
            return ListeningDispose({
                dispose.dispose()
                Shared.decrement(disposeStorage)
            })
        }
    }
}
public extension Listenable {
    /// Creates unretained listening point
    /// Connection with source keeps while current point retained
    func shared(connectionLive strategy: Shared<Self>.ConnectionLiveStrategy, _ repeater: Repeater<Out> = .unsafe()) -> Shared<Self> {
        return Shared(self, liveStrategy: strategy, repeater: repeater)
    }
}

/// Creates retained listening point
public struct Share<T: Listenable>: Listenable {
    let repeater: Repeater<T.Out>
    let liveStrategy: InternalLiveStrategy

    /// Defines intermediate connection live strategy
    ///
    /// - continuous: Connection lives for all the time while current point alive
    /// - repeatable: Connection lives if at least one listener exists
    /// This retains source, therefore be careful to avoid retain cycle.
    public enum ConnectionLiveStrategy {
        case continuous
        case repeatable
    }

    enum InternalLiveStrategy {
        case continuous(ListeningDispose)
        case repeatable(T, ValueStorage<ListeningDispose?>)
    }

    init(_ source: T, liveStrategy: ConnectionLiveStrategy, repeater: Repeater<T.Out>) {
        self.repeater = repeater
        switch liveStrategy {
        case .repeatable:
            self.liveStrategy = .repeatable(source, ValueStorage.unsafe(weak: nil))
        case .continuous:
            self.liveStrategy = .continuous(ListeningDispose(source.bind(to: repeater)))
        }
    }

    private func currentDispose() -> ListeningDispose {
        let dispose: ListeningDispose
        switch self.liveStrategy {
        case .continuous(let d): dispose = d
        case .repeatable(let source, let disposeStorage):
            if let disp = disposeStorage.value, !disp.isDisposed {
                dispose = disp
            } else {
                dispose = ListeningDispose(source.bind(to: repeater))
                disposeStorage.value = dispose
            }
        }
        return dispose
    }

    public func listening(_ assign: Assign<ListenEvent<T.Out>>) -> Disposable {
        let connection = currentDispose()
        let disposable = repeater.listening(assign)
        let unmanaged = Unmanaged.passUnretained(connection).retain()
        return ListeningDispose({
            disposable.dispose()
            unmanaged.release()
        })
    }
}
public extension Listenable {
    /// Creates retained listening point.
    /// Connection with source keeps while current point exists listeners.
    func share(connectionLive strategy: Share<Self>.ConnectionLiveStrategy, _ repeater: Repeater<Out> = .unsafe()) -> Share<Self> {
        return Share(self, liveStrategy: strategy, repeater: repeater)
    }
}

// MARK: Conveniences

public extension Listenable {
    // TODO: Move to memoize
    fileprivate func _distinctUntilChanged(_ def: Out?, comparer: @escaping (Out, Out) -> Bool) -> Preprocessor<Self, Out> {
        var oldValue: Out? = def
        return filter { newValue in
            defer { oldValue = newValue }
            return oldValue.map { comparer($0, newValue) } ?? true
        }
    }

    /// blocks updates with the same values, using specific comparer. Defines initial value.
    func distinctUntilChanged(_ def: Out, comparer: @escaping (Out, Out) -> Bool) -> Preprocessor<Self, Out> {
        return _distinctUntilChanged(def, comparer: comparer)
    }

    /// blocks updates with the same values, using specific comparer
    func distinctUntilChanged(comparer: @escaping (Out, Out) -> Bool) -> Preprocessor<Self, Out> {
        return _distinctUntilChanged(nil, comparer: comparer)
    }
}
public extension Listenable where Out: Equatable {
    /// blocks updates with the same values with defined initial value.
    func distinctUntilChanged(_ def: Out) -> Preprocessor<Self, Out> {
        return distinctUntilChanged(def, comparer: !=)
    }

    /// blocks updates with the same values
    func distinctUntilChanged() -> Preprocessor<Self, Out> {
        return distinctUntilChanged(comparer: !=)
    }
}

public extension Listenable {
    func then<L: Listenable>(_ transform: @escaping (Out) throws -> L) -> Preprocessor<Self, L.Out> {
        var disposable: Disposable? {
            didSet { oldValue?.dispose() }
        }
        return mapAsync { (event, promise: ResultPromise<L.Out>) in
            let next = try transform(event)
            disposable = next.listening({ (out) in
                switch out {
                case .error(let e): promise.reject(e)
                case .value(let v): promise.fulfill(v)
                }
            })
        }
    }
}
public extension Listenable where Out: _Optional {
    func then<L: Listenable>(_ transform: @escaping (Out.Wrapped) throws -> L) -> Preprocessor<Self, L.Out?> {
        var disposable: Disposable? {
            didSet { oldValue?.dispose() }
        }
        return flatMapAsync { (event, promise: ResultPromise<L.Out>) in
            let next = try transform(event)
            disposable = next.listening({ (out) in
                switch out {
                case .error(let e): promise.reject(e)
                case .value(let v): promise.fulfill(v)
                }
            })
        }
    }
    func then<L: Listenable>(_ transform: @escaping (Out.Wrapped) throws -> L?) -> Preprocessor<Self, L.Out?> {
        var disposable: Disposable? {
            didSet { oldValue?.dispose() }
        }
        return flatMapAsync { (event, promise: ResultPromise<L.Out?>) in
            guard let next = try transform(event) else { return promise.fulfill(nil) }
            disposable = next.listening({ (out) in
                switch out {
                case .error(let e): promise.reject(e)
                case .value(let v): promise.fulfill(v)
                }
            })
        }
    }
    func then<L: Listenable>(_ transform: @escaping (Out.Wrapped) throws -> L?) -> Preprocessor<Self, L.Out.Wrapped?> where L.Out: _Optional {
        var disposable: Disposable? {
            didSet { oldValue?.dispose() }
        }
        return flatMapAsync { (event, promise: ResultPromise<L.Out.Wrapped?>) in
            guard let next = try transform(event) else { return promise.fulfill(nil) }
            disposable = next.listening({ (out) in
                switch out {
                case .error(let e): promise.reject(e)
                case .value(let v): promise.fulfill(v.wrapped)
                }
            })
        }
    }
}

public extension Listenable where Out: _Optional {
    /// transforms value if it's not `nil`, otherwise returns `nil`
    func flatMap<U>(_ transform: @escaping (Out.Wrapped) throws -> U) -> Preprocessor<Self, U?> {
        return map { try $0.map(transform) }
    }
    /// transforms value if it's not `nil`, otherwise returns `nil`
    func flatMap<U>(_ transform: @escaping (Out.Wrapped) throws -> U?) -> Preprocessor<Self, U?> {
        return map { try $0.flatMap(transform) }
    }
    /// unwraps value
    func flatMap() -> Preprocessor<Self, Out.Wrapped?> {
        return flatMap({ $0 })
    }

    func flatMapAsync<Result>(_ event: @escaping (Out.Wrapped, ResultPromise<Result>) throws -> Void) -> Preprocessor<Self, Result?> {
        return mapAsync({ (out, promise) in
            guard let wrapped = out.wrapped else { return promise.fulfill(nil) }
            let wrappedPromise = ResultPromise<Result>()
            wrappedPromise.do(promise.fulfill).resolve(promise.reject(_:))
            try event(wrapped, wrappedPromise)
        })
    }
    func flatMapAsync<Result>(_ event: @escaping (Out.Wrapped, ResultPromise<Result?>) throws -> Void) -> Preprocessor<Self, Result?> {
        return mapAsync({ (out, promise) in
            guard let wrapped = out.wrapped else { return promise.fulfill(nil) }
            try event(wrapped, promise)
        })
    }

    /// transforms value if it's not `nil`, otherwise skips value
    func filterMap<U>(_ transform: @escaping (Out.Wrapped) throws -> U) -> Preprocessor<Preprocessor<Self, Out>, U> {
        return self
            .filter { $0.map { _ in true } ?? false }
            .map { try transform($0.unsafelyUnwrapped) }
    }

    /// skips `nil` values
    func compactMap() -> Preprocessor<Preprocessor<Self, Out>, Out.Wrapped> {
        return filterMap({ $0 })
    }
}
public extension Listenable where Out: _Optional, Out.Wrapped: _Optional {
    /// transforms value if it's not `nil`, otherwise returns `nil`
    func flatMap<U>(_ transform: @escaping (Out.Wrapped) throws -> U?) -> Preprocessor<Self, U?> {
        return map({ try $0.flatMap(transform) })
    }

    /// unwraps value
    func flatMap() -> Preprocessor<Self, Out.Wrapped.Wrapped?> {
        return flatMap({ $0.wrapped })
    }
}

public extension Listenable where Out == Bool {
    func and<L: Listenable>(_ other: L) -> Preprocessor<Combine<(Bool, Bool)>, Bool>
        where L.Out == Bool {
        return combine(with: other).map({ $0 && $1 })
    }
    func and<L1: Listenable, L2: Listenable>(_ other1: L1, _ other2: L2) -> Preprocessor<Combine<(Bool, Bool, Bool)>, Bool>
        where L1.Out == Bool, L2.Out == Bool {
        return combine(with: other1, other2).map({ $0 && $1 && $2 })
    }
    func or<L: Listenable>(_ other: L) -> Preprocessor<Combine<(Bool, Bool)>, Bool> where L.Out == Bool {
        return combine(with: other).map({ $0 || $1 })
    }
    func or<L1: Listenable, L2: Listenable>(_ other1: L1, _ other2: L2) -> Preprocessor<Combine<(Bool, Bool, Bool)>, Bool>
        where L1.Out == Bool, L2.Out == Bool {
        return combine(with: other1, other2).map({ $0 || $1 || $2 })
    }
}

public extension Listenable where Out: Comparable {
    func lessThan<L: Listenable>(_ other: L) -> Preprocessor<Combine<(Out, Out)>, Bool> where L.Out == Out {
        return combine(with: other).map({ $0 < $1 })
    }
    func lessThan<L: Listenable>(orEqual other: L) -> Preprocessor<Combine<(Out, Out)>, Bool> where L.Out == Out {
        return combine(with: other).map({ $0 <= $1 })
    }
    func moreThan<L: Listenable>(_ other: L) -> Preprocessor<Combine<(Out, Out)>, Bool> where L.Out == Out {
        return combine(with: other).map({ $0 > $1 })
    }
    func moreThan<L: Listenable>(orEqual other: L) -> Preprocessor<Combine<(Out, Out)>, Bool> where L.Out == Out {
        return combine(with: other).map({ $0 >= $1 })
    }
}

public extension Listenable where Out: _Optional {
    func `default`(_ defaultValue: Out.Wrapped) -> Preprocessor<Self, Out.Wrapped> {
        return map({ $0.wrapped ?? defaultValue })
    }
}
public extension Listenable where Out: _Optional, Out.Wrapped: HasDefaultLiteral {
    func `default`() -> Preprocessor<Self, Out.Wrapped> {
        return map({ $0.wrapped ?? Out.Wrapped() })
    }
}

public extension Listenable {
    /// Creates retained storage that saves last values, but emits result conditionally.
    ///
    /// - Parameters:
    ///   - controller: Source of emitting control
    ///   - maxBufferSize: Maximum elements that can store in storage
    ///   - initially: Initial state.
    /// - Returns: Retained preprocessor object
    typealias Suspend = Preprocessor<Memoize<Combine<(Self.Out, Bool)>>, [Self.Out]>
    func suspend<L: Listenable>(controller: L, maxBufferSize: Int = .max, initially: Bool = true) -> Suspend where L.Out == Bool {
        debugFatalError(condition: maxBufferSize <= 0, "`size` must be more than 0")
        return Combine(accumulator: Accumulator(repeater: .unsafe(), self, default: nil, controller, default: initially))
            .memoize(buffer: .custom({ (storage, last) -> [(Self.Out, Bool)]? in
                if last.1 {
                    if storage.0.count > 1 {
                        defer { storage.0 = [(storage.0[storage.0.count - 1].0, true)] }
                        return storage.0
                    } else {
                        storage = ([last], false)
                        return [last]
                    }
                } else {
                    if storage.0.isEmpty || !storage.0[storage.0.count - 1].1 {
                        storage.0.append(last)
                        if storage.0.count > maxBufferSize {
                            storage.0.removeFirst(storage.0.count - maxBufferSize)
                        }
                        return nil
                    } else {
                        storage = ([], false)
                        return nil
                    }
                }
            }))
            .map({ $0.map({ $0.0 }) })
    }
}
