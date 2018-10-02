//
//  Preprocessor.swift
//  GoogleToolboxForMac
//
//  Created by Denis Koryttsev on 31/01/2018.
//

import Foundation

// MARK: Map, filter

typealias BridgeBlank<I, O> = (_ value: I, _ assign: @escaping (O) -> Void) -> Void

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
    init(event: @escaping (I, ResultPromise<O>) -> Void) {
        self.init(bridge: { (e, assign) in
            switch e {
            case .value(let v): event(v, ResultPromise(receiver: { assign(.value($0)) }, error: { assign(.error($0)) }))
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
    init(event: @escaping (O, Promise) -> Void) {
        self.init(bridge: { e, assign in
            switch e {
            case .value(let v): event(v, Promise(action: { assign(.value(v)) }, error: { assign(.error($0)) }))
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

    /// Returns listenable that on receive value event calls the passed closure
    /// and waits when is received signal in `Promise`
    ///
    /// - Warning: This does not preserve the sequence of events
    ///
    /// - Parameter event: Closure to run async work.
    public func onReceive(_ event: @escaping (Out, Promise) -> Void) -> Preprocessor<Out, Out> {
        return Preprocessor(listenable: AnyListenable(self.listening, self.listeningItem),
                            bridgeMaker: Bridge(event: event))
    }
    /// Returns listenable that on receive value event calls the passed closure
    /// and waits when is received signal in `ResultPromise`
    ///
    /// - Parameter event: Closure to run async work.
    public func onReceiveMap<Result>(_ event: @escaping (Out, ResultPromise<Result>) -> Void) -> Preprocessor<Out, Result> {
        return Preprocessor(listenable: AnyListenable(self.listening, self.listeningItem),
                            bridgeMaker: Bridge(event: event))
    }
}
public extension Listenable where Out: _Optional {
    /// transforms value if it's not `nil`, otherwise skips value
    func flatMap<U>(_ transform: @escaping (Out.Wrapped) -> U) -> Preprocessor<Out, U> {
        return self
            .filter { $0.map { _ in true } ?? false }
            .map { transform($0.unsafelyUnwrapped) }
    }
    /// transforms value if it's not `nil`, otherwise returns `nil`
    func optionalMap<U>(_ transform: @escaping (Out.Wrapped) -> U?) -> Preprocessor<Out, U?> {
        return map { $0.flatMap(transform) }
    }
    /// skips `nil` values
    func compactMap() -> Preprocessor<Out, Out.Wrapped> {
        return flatMap({ $0 })
    }
}

// MARK:

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
}
public extension Listenable {
    /// calls closure on receive next value
    func `do`(_ something: @escaping (ListenEvent<Out>) -> Void) -> Do<Out> {
        return Do(listenable: AnyListenable(self.listening, self.listeningItem), doit: something)
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
    var store: ListeningDisposeStore = ListeningDisposeStore()

    public init<L: Listenable>(repeater: Repeater<T>, _ inputs: L...) where L.Out == T {
        self.repeater = repeater
        inputs.forEach { l in
            repeater.depends(on: l).add(to: &store)
        }
    }

    public init<L: Listenable>(repeater: Repeater<T>, _ inputs: [L]) where L.Out == T {
        self.repeater = repeater
        inputs.forEach { l in
            repeater.depends(on: l).add(to: &store)
        }
    }

    public init<L1: Listenable, L2: Listenable>(repeater: Repeater<T>, _ one: L1, _ two: L2) where T == (L1.Out, L2.Out) {
        self.repeater = repeater

        var event: (one: ListenEvent<L1.Out>?, two: ListenEvent<L2.Out>?) {
            didSet {
                switch event {
                case (.some(.value(let v1)), .some(.value(let v2))):
                    repeater.send(.value((v1, v2)))
                case (.some(.value), .some(.error(let e2))):
                    repeater.send(.error(e2))
                case (.some(.error(let e1)), .some(.value)):
                    repeater.send(.error(e1))
                case (.some(.error(let e1)), .some(.error(let e2))):
                    repeater.send(
                        .error(
                            RealtimeError(source: .listening, description:
                                """
                                    Error #1: \(e1.localizedDescription),
                                    Error #2: \(e2.localizedDescription)
                                """
                            )
                        )
                    )
                default: break
                }
            }
        }
        one.listening({ event.one = $0 }).add(to: &store)
        two.listening({ event.two = $0 }).add(to: &store)
    }

    public func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
        return repeater.listening(assign)
    }
}
public extension Listenable {
    func join(with others: Self...) -> Accumulator<Out> {
        return Accumulator(repeater: .unsafe(), [self] + others)
    }

    func combine<L: Listenable>(with other: L) -> Accumulator<(Out, L.Out)> {
        return Accumulator(repeater: .unsafe(), self, other)
    }
}

struct Memoize<T>: Listenable {
    let base: AnyListenable<T>
    let maxCount: Int
    let sendOnResume: Bool

    func listening(_ assign: Assign<ListenEvent<[T]>>) -> Disposable {
        var memoized: [T] = []
        return base
            .map({ (v) -> [T] in
                memoized = Array((memoized + [v]).suffix(self.maxCount))
                return memoized
            })
            .listening(assign)
    }

    func listeningItem(_ assign: Assign<ListenEvent<[T]>>) -> ListeningItem {
        var memoized: [T] = []
        let item = base
            .map({ (v) -> [T] in
                memoized = Array((memoized + [v]).suffix(self.maxCount))
                return memoized
            })
            .listeningItem(assign)
        if sendOnResume {
            return ListeningItem(
                resume: {
                    item.resume()
                    assign.call(.value(memoized))
                    return ()
                },
                pause: item.pause,
                token: ()
            )
        } else {
            return item
        }
    }
}

extension Listenable {
    func memoize(maxCount: Int, send: Bool, sendOnResume: Bool) -> Memoize<Out> {
        return Memoize(base: AnyListenable(self.listening, self.listeningItem), maxCount: maxCount, sendOnResume: sendOnResume)
    }
}

