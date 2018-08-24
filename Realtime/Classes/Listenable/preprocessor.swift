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
    fileprivate func _distinctUntilChanged(_ def: OutData?, comparer: @escaping (OutData, OutData) -> Bool) -> Preprocessor<OutData, OutData> {
        var oldValue: OutData? = def
        return filter { newValue in
            defer { oldValue = newValue }
            return oldValue.map { comparer($0, newValue) } ?? true
        }
    }

    /// blocks updates with the same values, using specific comparer. Defines initial value.
    func distinctUntilChanged(_ def: OutData, comparer: @escaping (OutData, OutData) -> Bool) -> Preprocessor<OutData, OutData> {
        return _distinctUntilChanged(def, comparer: comparer)
    }

    /// blocks updates with the same values, using specific comparer
    func distinctUntilChanged(comparer: @escaping (OutData, OutData) -> Bool) -> Preprocessor<OutData, OutData> {
        return _distinctUntilChanged(nil, comparer: comparer)
    }
}
public extension Listenable where OutData: Equatable {
	/// blocks updates with the same values with defined initial value.
    func distinctUntilChanged(_ def: OutData) -> Preprocessor<OutData, OutData> {
        return distinctUntilChanged(def, comparer: !=)
    }

    /// blocks updates with the same values
    func distinctUntilChanged() -> Preprocessor<OutData, OutData> {
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
    public func filter(_ predicate: @escaping (OutData) -> Bool) -> Preprocessor<OutData, OutData> {
        return Preprocessor(listenable: AnyListenable(self.listening, self.listeningItem),
                            bridgeMaker: Bridge(predicate: predicate))
    }

    public func map<U>(_ transform: @escaping (OutData) throws -> U) -> Preprocessor<OutData, U> {
        return Preprocessor(listenable: AnyListenable(self.listening, self.listeningItem),
                            bridgeMaker: Bridge(transform: transform))
    }

    public func onReceive(_ event: @escaping (OutData, Promise) -> Void) -> Preprocessor<OutData, OutData> {
        return Preprocessor(listenable: AnyListenable(self.listening, self.listeningItem),
                            bridgeMaker: Bridge(event: event))
    }
    public func onReceiveMap<Result>(_ event: @escaping (OutData, ResultPromise<Result>) -> Void) -> Preprocessor<OutData, Result> {
        return Preprocessor(listenable: AnyListenable(self.listening, self.listeningItem),
                            bridgeMaker: Bridge(event: event))
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
    func onFire(_ todo: @escaping () -> Void) -> OnFire<OutData> {
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
    func `do`(_ something: @escaping (ListenEvent<OutData>) -> Void) -> Do<OutData> {
        return Do(listenable: AnyListenable(self.listening, self.listeningItem), doit: something)
    }
}

public struct Once<T>: Listenable {
    private let listenable: AnyListenable<T>

    init(base: AnyListenable<T>) {
        self.listenable = base
    }

    public func listening(_ assign: Assign<ListenEvent<T>>) -> Disposable {
        var disposable: Disposable! = nil
        var shouldCall = true
        disposable = listenable
            .filter({ _ in shouldCall })
            .listening(
                assign.with(work: { (_) in
                    disposable.dispose()
                    shouldCall = false
                })
        )
        return disposable
    }
}
public extension Listenable {
    /// connection to receive single value
    func once() -> Once<OutData> {
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
    func queue(_ queue: DispatchQueue) -> Preprocessor<OutData, OutData> {
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
    func deadline(_ time: DispatchTime) -> Deadline<OutData> {
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
    func livetime(_ byItem: AnyObject) -> Livetime<OutData> {
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
    func debounce(_ time: DispatchTimeInterval) -> Preprocessor<OutData, OutData> {
        return Preprocessor(listenable: AnyListenable(self.listening, self.listeningItem), bridgeMaker: Bridge(debounce: time))
    }
}

public class Accumulator<T>: Listenable {
    let repeater: Repeater<T>
    var store: ListeningDisposeStore = ListeningDisposeStore()

    public init<L: Listenable>(repeater: Repeater<T>, _ inputs: L...) where L.OutData == T {
        self.repeater = repeater
        inputs.forEach { l in
            repeater.depends(on: l).add(to: &store)
        }
    }

    public init<L1: Listenable, L2: Listenable>(repeater: Repeater<T>, _ one: L1, _ two: L2) where T == (L1.OutData, L2.OutData) {
        self.repeater = repeater

        var event: (one: ListenEvent<L1.OutData>?, two: ListenEvent<L2.OutData>?) {
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
