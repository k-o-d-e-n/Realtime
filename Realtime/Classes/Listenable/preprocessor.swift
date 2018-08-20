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
    public func listeningItem(_ assign: Assign<ListenEvent<O>>) -> ListeningItem {
        return listenable.listeningItem(bridgeMaker.wrapAssign(assign))
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
