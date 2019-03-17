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
                    try event(v, ResultPromise(receiver: { assign(.value($0)) }, error: { assign(.error($0)) }))
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
    init(event: @escaping (O, Promise) throws -> Void) {
        self.init(bridge: { e, assign in
            switch e {
            case .value(let v):
                do {
                    try event(v, Promise(action: { assign(.value(v)) }, error: { assign(.error($0)) }))
                } catch let e {
                    assign(.error(e))
                }
            case .error: assign(e)
            }
        })
    }
}

public struct Preprocessor<I, O>: Listenable {
    let listenable: AnyListenable<I>
    let bridgeMaker: Bridge<I, O>

    public func listening(_ assign: Assign<ListenEvent<O>>) -> Disposable {
        return listenable.listening(bridgeMaker.wrapAssign(assign))
    }
    public func listeningItem(_ assign: Assign<ListenEvent<O>>) -> ListeningItem {
        return listenable.listeningItem(bridgeMaker.wrapAssign(assign))
    }
}

public extension Listenable {
    /// Returns listenable that filters value events
    ///
    /// - Parameter predicate: Closure to evaluate value
    public func filter(_ predicate: @escaping (Out) -> Bool) -> Preprocessor<Out, Out> {
        return Preprocessor(listenable: AnyListenable(self.listening, self.listeningItem),
                            bridgeMaker: Bridge(predicate: predicate))
    }

    /// Returns listenable that transforms value events
    ///
    /// - Parameter transform: Closure to transform value
    public func map<U>(_ transform: @escaping (Out) throws -> U) -> Preprocessor<Out, U> {
        return Preprocessor(listenable: AnyListenable(self.listening, self.listeningItem),
                            bridgeMaker: Bridge(transform: transform))
    }

    /// transforms value if it's not `nil`, otherwise skips value
    func compactMap<U>(_ transform: @escaping (Out) throws -> U?) -> Preprocessor<U?, U> {
        return self.map(transform).compactMap()
    }

    /// Returns listenable that on receive value event calls the passed closure
    /// and waits when is received signal in `Promise`
    ///
    /// - Warning: This does not preserve the sequence of events
    ///
    /// - Parameter event: Closure to run async work.
    public func doAsync(_ event: @escaping (Out, Promise) throws -> Void) -> Preprocessor<Out, Out> {
        return Preprocessor(listenable: AnyListenable(self.listening, self.listeningItem),
                            bridgeMaker: Bridge(event: event))
    }
    /// Returns listenable that on receive value event calls the passed closure
    /// and waits when is received signal in `ResultPromise`
    ///
    /// - Parameter event: Closure to run async work.
    public func mapAsync<Result>(_ event: @escaping (Out, ResultPromise<Result>) throws -> Void) -> Preprocessor<Out, Result> {
        return Preprocessor(listenable: AnyListenable(self.listening, self.listeningItem),
                            bridgeMaker: Bridge(event: event))
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

    public func listeningItem(_ assign: Closure<ListenEvent<O>, Void>) -> ListeningItem {
        return listenable.listeningItem(assign.mapIn({ event in
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
    public func mapError(_ transform: @escaping (Error) -> Error) -> EventMap<Out, Out> {
        return mapEvent({ (event) -> ListenEvent<Out> in
            switch event {
            case .error(let e): return .error(transform(e))
            default: return event
            }
        })
    }
    public func resolve(with transform: @escaping (Error) throws -> Out) -> EventMap<Out, Out> {
        return mapEvent({ (event) -> ListenEvent<Out> in
            switch event {
            case .error(let e): return .value(try transform(e))
            default: return event
            }
        })
    }
    public func resolve(with value: @escaping @autoclosure () -> Out) -> EventMap<Out, Out> {
        return mapEvent({ (event) -> ListenEvent<Out> in
            switch event {
            case .error: return .value(value())
            default: return event
            }
        })
    }
    public func resolve(with transform: @escaping (Error) throws -> Out?) -> EventMap<Out, Out?> {
        return mapEvent({ (event) -> ListenEvent<Out?> in
            switch event {
            case .error(let e): return .value(try transform(e))
            case .value(let v): return .value(v)
            }
        })
    }
    public func resolve(with value: @escaping @autoclosure () -> Out?) -> EventMap<Out, Out?> {
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
public struct OnFire<T>: Listenable {
    fileprivate let listenable: AnyListenable<T>
    fileprivate let onFire: () -> Void

    public func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
        let disposable = listenable.listening(assign)
        return ListeningDispose({
            disposable.dispose()
            self.onFire()
        })
    }

    public func listeningItem(_ assign: Closure<ListenEvent<T>, Void>) -> ListeningItem {
        let base = listenable.listeningItem(assign)
        return ListeningItem(resume: base.resume, pause: base.pause,
                             dispose: { base.dispose(); self.onFire() }, token: ())
    }
}
public extension Listenable {
    /// calls closure on disconnect
    func onFire(_ todo: @escaping () -> Void) -> OnFire<Out> {
        return OnFire(listenable: AnyListenable(self.listening, self.listeningItem), onFire: todo)
    }
}

public struct Do<T>: Listenable {
    fileprivate let listenable: AnyListenable<T>
    fileprivate let doit: (ListenEvent<T>) -> Void

    public func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
        return listenable.listening(assign.with(work: doit))
    }

    public func listeningItem(_ assign: Closure<ListenEvent<T>, Void>) -> ListeningItem {
        return listenable.listeningItem(assign.with(work: doit))
    }
}
public extension Listenable {
    /// calls closure on receive next value
    func `do`(_ something: @escaping (ListenEvent<Out>) -> Void) -> Do<Out> {
        return Do(listenable: AnyListenable(self.listening, self.listeningItem), doit: something)
    }

    func `do`(onValue something: @escaping (Out) -> Void) -> Do<Out> {
        return self.do({ event in
            switch event {
            case .value(let v): something(v)
            default: break
            }
        })
    }
    func `do`(onError something: @escaping (Error) -> Void) -> Do<Out> {
        return self.do({ event in
            switch event {
            case .error(let e): something(e)
            default: break
            }
        })
    }
}

public struct Once<T>: Listenable {
    private let listenable: AnyListenable<T>

    init(base: AnyListenable<T>) {
        self.listenable = base
    }

    public func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
        var shouldCall = true
        var disposable: Disposable? {
            didSet {
                if !shouldCall {
                    disposable?.dispose()
                }
            }
        }
        disposable = listenable
            .filter({ _ in shouldCall })
            .listening(
                assign.with(work: { (_) in
                    disposable?.dispose()
                    shouldCall = false
                })
        )
        return disposable!
    }

    public func listeningItem(_ assign: Assign<ListenEvent<T>>) -> ListeningItem {
        /// calls once and sets to pause, on resume call enabled once event yet
        var shouldCall = true
        var baseItem: ListeningItem?
        var item: ListeningItem?
        baseItem = listenable
            .filter({ _ in shouldCall })
            .listeningItem(
                assign.with(work: { (_) in
                    item?.pause()
                    shouldCall = false
                })
        )
        item = ListeningItem(
            resume: {
                shouldCall = true
                return baseItem!.resume()
            },
            pause: baseItem!.pause,
            dispose: baseItem!.dispose,
            token: ()
        )
        if !shouldCall {
            item?.pause()
        }
        return item!
    }
}
public extension Listenable {
    /// connection to receive single value
    func once() -> Once<Out> {
        return Once(base: AnyListenable(self.listening, self.listeningItem))
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
    func queue(_ queue: DispatchQueue) -> Preprocessor<Out, Out> {
        return Preprocessor(listenable: AnyListenable(self.listening, self.listeningItem), bridgeMaker: Bridge(queue: queue))
    }
}

public struct Deadline<T>: Listenable {
    private let listenable: AnyListenable<T>
    private let deadline: DispatchTime

    init(base: AnyListenable<T>, deadline: DispatchTime) {
        self.listenable = base
        self.deadline = deadline
    }

    public func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
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
    public func listeningItem(_ assign: Closure<ListenEvent<T>, Void>) -> ListeningItem {
        var base: ListeningItem?
        base = listenable.listeningItem(assign.filter({ _ -> Bool in
            guard self.deadline >= .now() else {
                base?.dispose()
                return false
            }
            return true
        }))
        return base!
    }
}
public extension Listenable {
    /// works until time has not reached deadline
    func deadline(_ time: DispatchTime) -> Deadline<Out> {
        return Deadline(base: AnyListenable(self.listening, self.listeningItem), deadline: time)
    }
}

public struct Livetime<T>: Listenable {
    private let listenable: AnyListenable<T>
    private weak var livingItem: AnyObject?

    init(base: AnyListenable<T>, living: AnyObject) {
        self.listenable = base
        self.livingItem = living
    }

    public func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
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

    public func listeningItem(_ assign: Closure<ListenEvent<T>, Void>) -> ListeningItem {
        var base: ListeningItem?
        base = listenable.listeningItem(assign.filter({ _ -> Bool in
            guard self.livingItem != nil else {
                base?.dispose()
                return false
            }
            return true
        }))
        return base!
    }
}
public extension Listenable {
    /// works until alive specified object
    func livetime(_ byItem: AnyObject) -> Livetime<Out> {
        return Livetime(base: AnyListenable(self.listening, self.listeningItem), living: byItem)
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
    func debounce(_ time: DispatchTimeInterval) -> Preprocessor<Out, Out> {
        return Preprocessor(listenable: AnyListenable(self.listening, self.listeningItem), bridgeMaker: Bridge(debounce: time))
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
        self.repeater = repeater
        let _first = _First()

        var event: (one: ListenEvent<L1.Out>?, two: ListenEvent<L2.Out>?) {
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
    public func listeningItem(_ assign: Closure<ListenEvent<T>, Void>) -> ListeningItem {
        defer { sendFirstIfExists(assign) }
        return repeater.listeningItem(assign)
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

    public func listeningItem(_ assign: Closure<ListenEvent<T>, Void>) -> ListeningItem {
        let item = accumulator.listeningItem(assign)
        let unmanaged = Unmanaged.passUnretained(accumulator.store).retain()
        return ListeningItem(
            resume: item.resume,
            pause: item.pause,
            dispose: { item.dispose(); unmanaged.release() },
            token: ()
        )
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
    ///   - size: Storage size
    ///   - sendLast: If true it will be emit existed last
    /// values on each next listening immediately
    /// - Returns: Retained preprocessor object
    func memoize(_ size: Int, waitFulness: Bool = false, sendLast: Bool) -> Memoize<Out> {
        debugFatalError(condition: size <= 0, "`size` must be more than 0")
        return Memoize(
            AnyListenable(self.listening, self.listeningItem),
            storage: .unsafe(strong: ([], waitFulness && sendLast)),
            options: Memoize.Options(count: size, waitFullness: waitFulness, sendLast: sendLast)
        )
    }
    /// See description `func memoize`
    func memoizeOne(sendLast: Bool) -> Preprocessor<[Out], Out> {
        return memoize(1, sendLast: sendLast).map({ $0[0] })
    }

    // TODO: Usage `Memoize` leads to retain both values, but must retains old value only
//    func oldValue() -> Preprocessor<[Out], (old: Out, new: Out)> {
//        return memoize(2, waitFulness: true, sendLast: false).map({ (old: $0[0], new: $0[1]) })
//    }
    func oldValue(_ default: Out?) -> Preprocessor<[Out], (old: Out?, new: Out)> {
        return memoize(2, waitFulness: false, sendLast: false)
            .map({ $0.count == 2 ? (old: $0[0], new: $0[1]) : (old: `default`, new: $0[0]) })
    }
    func oldValue(_ default: Out) -> Preprocessor<[Out], (old: Out, new: Out)> {
        return memoize(2, waitFulness: false, sendLast: false)
            .map({ $0.count == 2 ? (old: $0[0], new: $0[1]) : (old: `default`, new: $0[0]) })
    }
}

/// Added implicit storage in chain with retained listening point
public struct Memoize<T>: Listenable {
    let storage: ValueStorage<([T], Bool)>
    let dispose: ListeningDispose

    struct Options {
        let count: Int
        let waitFullness: Bool
        let sendLast: Bool

        func evaluate(_ current: [T]) -> Bool {
            guard waitFullness else { return true }
            return current.count == count
        }
    }

    init(_ base: AnyListenable<T>, storage: ValueStorage<([T], Bool)>, options: Options) {
        self.dispose = ListeningDispose(base.listening(
            onValue: { (value) in
                let value = Array((storage.value.0 + [value]).suffix(options.count))
                storage.value = (value, options.evaluate(value))
            },
            onError: storage.sendError
        ))
        self.storage = storage
    }

    private func sendLastIfNeeded(_ assign: Closure<ListenEvent<[T]>, Void>) {
        let current = storage.value
        if current.1 {
            assign.call(.value(current.0))
        }
    }

    public func listening(_ assign: Closure<ListenEvent<[T]>, Void>) -> Disposable {
        defer { sendLastIfNeeded(assign) }
        let disposer = storage.map({ $0.0 }).listening(assign)
        let unmanaged = Unmanaged.passUnretained(dispose).retain()
        return ListeningDispose.init({
            unmanaged.release()
            disposer.dispose()
        })
    }

    public func listeningItem(_ assign: Closure<ListenEvent<[T]>, Void>) -> ListeningItem {
        defer { sendLastIfNeeded(assign) }
        let item = storage.map({ $0.0 }).listeningItem(assign)
        let unmanaged = Unmanaged.passUnretained(dispose).retain()
        return ListeningItem(
            resume: {
                defer { self.sendLastIfNeeded(assign) }
                return item.resume()
            },
            pause: item.pause,
            dispose: { item.dispose(); unmanaged.release() },
            token: ()
        )
    }
}

@available(*, deprecated: 0.9, message: "Use memoize preprocessor")
public struct OldValue<T>: Listenable {
    let base: AnyListenable<T>

    public func listening(_ assign: Assign<ListenEvent<(new: T, old: T?)>>) -> Disposable {
        var old: T?
        var current: T? {
            didSet { old = oldValue }
        }
        return base
            .map({ (v) -> (T, T?) in
                current = v
                return (current!, old)
            })
            .listening(assign)
    }
    public func listeningItem(_ assign: Closure<ListenEvent<(new: T, old: T?)>, Void>) -> ListeningItem {
        var old: T?
        var current: T? {
            didSet { old = oldValue }
        }
        return base
            .map({ (v) -> (T, T?) in
                current = v
                return (current!, old)
            })
            .listeningItem(assign)
    }
}
public extension Listenable {
    @available(*, deprecated: 0.9, message: "Use memoize preprocessor")
    func oldValue() -> OldValue<Out> {
        return OldValue(base: AnyListenable(self.listening, self.listeningItem))
    }
}

public struct DoDebug<T>: Listenable {
    fileprivate let listenable: AnyListenable<T>
    fileprivate let doit: (ListenEvent<T>) -> Void

    public func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
        #if DEBUG
        return listenable.listening(assign.with(work: doit))
        #else
        return listenable.listening(assign)
        #endif
    }
    public func listeningItem(_ assign: Closure<ListenEvent<T>, Void>) -> ListeningItem {
        #if DEBUG
        return listenable.listeningItem(assign.with(work: doit))
        #else
        return listenable.listeningItem(assign)
        #endif
    }
}
public extension Listenable {
    /// calls closure on receive next value
    func doOnDebug(_ something: @escaping (ListenEvent<Out>) -> Void) -> Do<Out> {
        return Do(listenable: AnyListenable(self.listening, self.listeningItem), doit: something)
    }
}

/// Creates unretained listening point
public struct Shared<T>: Listenable {
    let repeater: Repeater<T>
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
        case repeatable(AnyListenable<T>, ValueStorage<(UInt, ListeningDispose?)>, ListeningDispose)
    }

    init<L: Listenable>(_ source: L, liveStrategy: ConnectionLiveStrategy, repeater: Repeater<T>) where L.Out == T {
        self.repeater = repeater
        switch liveStrategy {
        case .repeatable:
            let connectionStorage = ValueStorage<(UInt, ListeningDispose?)>.unsafe(strong: (0, nil))
            self.liveStrategy = .repeatable(source.asAny(), connectionStorage, ListeningDispose({
                connectionStorage.value = (connectionStorage.value.0, nil) // disposes when shared deinitialized
            }))
        case .continuous:
            self.liveStrategy = .continuous(source.bind(to: repeater))
        }
    }

    private func increment(_ storage: ValueStorage<(UInt, ListeningDispose?)>, source: AnyListenable<T>) {
        if storage.value.1 == nil {
            storage.value = (1, ListeningDispose(source.bind(to: repeater)))
        } else {
            storage.value.0 += 1
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

    public func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
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
    public func listeningItem(_ assign: Assign<ListenEvent<T>>) -> ListeningItem {
        switch self.liveStrategy {
        case .continuous: return repeater.listeningItem(assign)
        case .repeatable(let source, let disposeStorage, _):
            increment(disposeStorage, source: source)
            let item = repeater.listeningItem(assign)
            return ListeningItem(
                resume: item.resume,
                pause: item.pause,
                dispose: {
                    item.dispose()
                    Shared.decrement(disposeStorage)
                },
                token: ()
            )
        }
    }
}
public extension Listenable {
    /// Creates unretained listening point
    /// Connection with source keeps while current point retained
    func shared(connectionLive strategy: Shared<Out>.ConnectionLiveStrategy, _ repeater: Repeater<Out> = .unsafe()) -> Shared<Out> {
        return Shared(self, liveStrategy: strategy, repeater: repeater)
    }
}

/// Creates retained listening point
public struct Share<T>: Listenable {
    let repeater: Repeater<T>
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
        case repeatable(AnyListenable<T>, ValueStorage<ListeningDispose?>)
    }

    init<L: Listenable>(_ source: L, liveStrategy: ConnectionLiveStrategy, repeater: Repeater<T>) where L.Out == T {
        self.repeater = repeater
        switch liveStrategy {
        case .repeatable:
            self.liveStrategy = .repeatable(source.asAny(), ValueStorage.unsafe(weak: nil))
        case .continuous:
            self.liveStrategy = .continuous(ListeningDispose(source.bind(to: repeater)))
        }
    }

    private func currentDispose() -> ListeningDispose {
        let dispose: ListeningDispose
        switch self.liveStrategy {
        case .continuous(let d): dispose = d
        case .repeatable(let source, let disposeStorage):
            if let disp = disposeStorage.value {
                dispose = disp
            } else {
                dispose = ListeningDispose(source.bind(to: repeater))
                disposeStorage.value = dispose
            }
        }
        return dispose
    }

    public func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
        let connection = currentDispose()
        let disposable = repeater.listening(assign)
        let unmanaged = Unmanaged.passUnretained(connection).retain()
        return ListeningDispose({
            disposable.dispose()
            unmanaged.release()
        })
    }
    public func listeningItem(_ assign: Assign<ListenEvent<T>>) -> ListeningItem {
        let connection = currentDispose()
        let item = repeater.listeningItem(assign)
        let unmanaged = Unmanaged.passUnretained(connection).retain()
        return ListeningItem(
            resume: item.resume,
            pause: item.pause,
            dispose: { item.dispose(); unmanaged.release() },
            token: ()
        )
    }
}
public extension Listenable {
    /// Creates retained listening point.
    /// Connection with source keeps while current point exists listeners.
    func share(connectionLive strategy: Share<Out>.ConnectionLiveStrategy, _ repeater: Repeater<Out> = .unsafe()) -> Share<Out> {
        return Share(self, liveStrategy: strategy, repeater: repeater)
    }
}

// MARK: Conveniences

public extension Listenable {
    fileprivate func _distinctUntilChanged(_ def: Out?, comparer: @escaping (Out, Out) -> Bool) -> Preprocessor<Out, Out> {
        var oldValue: Out? = def
        return filter { newValue in
            defer { oldValue = newValue }
            return oldValue.map { comparer($0, newValue) } ?? true
        }
    }

    /// blocks updates with the same values, using specific comparer. Defines initial value.
    func distinctUntilChanged(_ def: Out, comparer: @escaping (Out, Out) -> Bool) -> Preprocessor<Out, Out> {
        return _distinctUntilChanged(def, comparer: comparer)
    }

    /// blocks updates with the same values, using specific comparer
    func distinctUntilChanged(comparer: @escaping (Out, Out) -> Bool) -> Preprocessor<Out, Out> {
        return _distinctUntilChanged(nil, comparer: comparer)
    }
}
public extension Listenable where Out: Equatable {
    /// blocks updates with the same values with defined initial value.
    func distinctUntilChanged(_ def: Out) -> Preprocessor<Out, Out> {
        return distinctUntilChanged(def, comparer: !=)
    }

    /// blocks updates with the same values
    func distinctUntilChanged() -> Preprocessor<Out, Out> {
        return distinctUntilChanged(comparer: !=)
    }
}

public extension Listenable {
    public func then<L: Listenable>(_ transform: @escaping (Out) throws -> L) -> Preprocessor<Out, L.Out> {
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
    public func then<L: Listenable>(_ transform: @escaping (Out.Wrapped) throws -> L) -> Preprocessor<Out, L.Out?> {
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
    public func then<L: Listenable>(_ transform: @escaping (Out.Wrapped) throws -> L?) -> Preprocessor<Out, L.Out?> {
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
    public func then<L: Listenable>(_ transform: @escaping (Out.Wrapped) throws -> L?) -> Preprocessor<Out, L.Out.Wrapped?> where L.Out: _Optional {
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
    func flatMap<U>(_ transform: @escaping (Out.Wrapped) throws -> U) -> Preprocessor<Out, U?> {
        return map { try $0.map(transform) }
    }
    /// transforms value if it's not `nil`, otherwise returns `nil`
    func flatMap<U>(_ transform: @escaping (Out.Wrapped) throws -> U?) -> Preprocessor<Out, U?> {
        return map { try $0.flatMap(transform) }
    }
    /// unwraps value
    func flatMap() -> Preprocessor<Out, Out.Wrapped?> {
        return flatMap({ $0 })
    }

    public func flatMapAsync<Result>(_ event: @escaping (Out.Wrapped, ResultPromise<Result>) throws -> Void) -> Preprocessor<Out, Result?> {
        return mapAsync({ (out, promise) in
            guard let wrapped = out.wrapped else { return promise.fulfill(nil) }
            let wrappedPromise = ResultPromise<Result>(receiver: promise.fulfill, error: promise.reject)
            try event(wrapped, wrappedPromise)
        })
    }
    public func flatMapAsync<Result>(_ event: @escaping (Out.Wrapped, ResultPromise<Result?>) throws -> Void) -> Preprocessor<Out, Result?> {
        return mapAsync({ (out, promise) in
            guard let wrapped = out.wrapped else { return promise.fulfill(nil) }
            try event(wrapped, promise)
        })
    }

    /// transforms value if it's not `nil`, otherwise skips value
    func filterMap<U>(_ transform: @escaping (Out.Wrapped) throws -> U) -> Preprocessor<Out, U> {
        return self
            .filter { $0.map { _ in true } ?? false }
            .map { try transform($0.unsafelyUnwrapped) }
    }

    /// skips `nil` values
    func compactMap() -> Preprocessor<Out, Out.Wrapped> {
        return filterMap({ $0 })
    }
}
public extension Listenable where Out: _Optional, Out.Wrapped: _Optional {
    /// transforms value if it's not `nil`, otherwise returns `nil`
    func flatMap<U>(_ transform: @escaping (Out.Wrapped) throws -> U?) -> Preprocessor<Out, U?> {
        return map({ try $0.flatMap(transform) })
    }

    /// unwraps value
    func flatMap() -> Preprocessor<Out, Out.Wrapped.Wrapped?> {
        return flatMap({ $0.wrapped })
    }
}

public extension Listenable where Out == Bool {
    func and<L: Listenable>(_ other: L) -> Preprocessor<(Bool, Bool), Bool> where L.Out == Bool {
        return combine(with: other).map({ $0 && $1 })
    }
    func and<L1: Listenable, L2: Listenable>(_ other1: L1, _ other2: L2) -> Preprocessor<(Bool, Bool, Bool), Bool> where L1.Out == Bool, L2.Out == Bool {
        return combine(with: other1, other2).map({ $0 && $1 && $2 })
    }
    func or<L: Listenable>(_ other: L) -> Preprocessor<(Bool, Bool), Bool> where L.Out == Bool {
        return combine(with: other).map({ $0 || $1 })
    }
    func or<L1: Listenable, L2: Listenable>(_ other1: L1, _ other2: L2) -> Preprocessor<(Bool, Bool, Bool), Bool> where L1.Out == Bool, L2.Out == Bool {
        return combine(with: other1, other2).map({ $0 || $1 || $2 })
    }
}

public extension Listenable where Out: Comparable {
    func lessThan<L: Listenable>(_ other: L) -> Preprocessor<(Out, Out), Bool> where L.Out == Out {
        return combine(with: other).map({ $0 < $1 })
    }
    func lessThan<L: Listenable>(orEqual other: L) -> Preprocessor<(Out, Out), Bool> where L.Out == Out {
        return combine(with: other).map({ $0 <= $1 })
    }
    func moreThan<L: Listenable>(_ other: L) -> Preprocessor<(Out, Out), Bool> where L.Out == Out {
        return combine(with: other).map({ $0 > $1 })
    }
    func moreThan<L: Listenable>(orEqual other: L) -> Preprocessor<(Out, Out), Bool> where L.Out == Out {
        return combine(with: other).map({ $0 >= $1 })
    }
}

public extension Listenable where Out: _Optional {
    func `default`(_ defaultValue: Out.Wrapped) -> Preprocessor<Out, Out.Wrapped> {
        return map({ $0.wrapped ?? defaultValue })
    }
}
public extension Listenable where Out: _Optional, Out.Wrapped: HasDefaultLiteral {
    func `default`() -> Preprocessor<Out, Out.Wrapped> {
        return map({ $0.wrapped ?? Out.Wrapped() })
    }
}
