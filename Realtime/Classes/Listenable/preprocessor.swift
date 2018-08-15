//
//  Preprocessor.swift
//  GoogleToolboxForMac
//
//  Created by Denis Koryttsev on 31/01/2018.
//

import Foundation

// MARK: Map, filter

internal struct AnyFilter<I> {
    static func wrap<O>(predicate: @escaping (O) -> Bool, on assign: @escaping (O) -> Void) -> (O) -> Void {
        return { val in
            if predicate(val) {
                assign(val)
            }
        }
    }

    static func wrap(predicate: @escaping (I) -> Bool) -> (_ value: I, _ assign: (I) -> Void) -> Void {
        return { (val: I, assign: (I) -> Void) -> Void in
            if predicate(val) {
                assign(val)
            }
        }
    }

    static func wrap(predicate: @escaping (I) -> Bool, on filter: @escaping (_ value: I, _ assign: (I) -> Void) -> Void) -> (_ value: I, _ assign: (I) -> Void) -> Void {
        return { (val: I, assign: (I) -> Void) -> Void in
            if predicate(val) {
                filter(val, assign)
            }
        }
    }

    static func wrap<O>(predicate: @escaping (I) -> Bool, on filterModificator: @escaping (_ value: I, _ assign: @escaping (O) -> Void) -> Void) -> (_ value: I, _ assign: @escaping (O) -> Void) -> Void {
        return { val, assign in
            if predicate(val) {
                filterModificator(val, assign)
            }
        }
    }

    static func wrap<O>(predicate: @escaping (O) -> Bool, on filterModificator: @escaping (_ value: I, _ assign: @escaping (O) -> Void) -> Void) -> (_ value: I, _ assign: @escaping (O) -> Void) -> Void {
        return { val, assign in
            let newAssign = wrap(predicate: predicate, on: assign)
            filterModificator(val, newAssign)
        }
    }
}

internal struct AnyModificator<I, O> {
    static func make(modificator: @escaping (I) -> O, with original: @escaping () -> I) -> () -> O {
        return { return modificator(original()) }
    }

    static func make<I, O>(modificator: @escaping (I) -> O, with assign: @escaping (O) -> Void) -> (I) -> Void {
        return { input in
            assign(modificator(input))
        }
    }

    static func make(modificator: @escaping (I) -> O, with filtered: @escaping (_ value: I, _ assign: (I) -> Void) -> Void) -> (_ value: I, _ assign: @escaping (O) -> Void) -> Void {
        let newAssignMaker: (@escaping (I) -> O, @escaping (O) -> Void) -> (I) -> Void = AnyModificator.make
        return { value, assign in
            let newAssign = newAssignMaker(modificator, assign)
            filtered(value, newAssign)
        }
    }

    static func make<U>(modificator: @escaping (O) -> U, with filterModificator: @escaping (_ value: I, _ assign: @escaping (O) -> Void) -> Void) -> (_ value: I, _ assign: @escaping (U) -> Void) -> Void {
        return { value, assign in
            let newAssign = make(modificator: modificator, with: assign)
            filterModificator(value, newAssign)
        }
    }
}
fileprivate struct AnyOnReceive<I, O> {
    static func wrap(assign: @escaping (O) -> Void,
                     to event: @escaping (O, Promise) -> Void,
                     with source: @escaping () -> I,
                     bridgeBlank: @escaping (_ value: I, _ assign: @escaping (O) -> Void) -> Void) -> () -> Void {
        let wrappedAssign = { o in
            event(o, Promise(action: { assign(o) }))
        }
        return { bridgeBlank(source(), wrappedAssign) }
    }

    static func wrap(assign: @escaping (O) -> Void,
                     to event: @escaping (O, Promise) -> Void,
                     bridgeBlank: @escaping (_ value: I, _ assign: @escaping (O) -> Void) -> Void) -> (I) -> Void {
        let wrappedAssign = { o in
            event(o, Promise(action: { assign(o) }))
        }
        return { i in
            bridgeBlank(i, wrappedAssign)
        }
    }

    static func wrap(bridgeBlank: @escaping (_ value: I, _ assign: @escaping (O) -> Void) -> Void, to event: @escaping (O, Promise) -> Void) -> (_ value: I, _ assign: @escaping (O) -> Void) -> Void {
        return { i, a in
            let wrappedAssign = { o in
                event(o, Promise(action: { a(o) }))
            }

            bridgeBlank(i, wrappedAssign)
        }
    }
    static func wrap<Result>(assign: @escaping (Result) -> Void,
                             to event: @escaping (O, ResultPromise<Result>) -> Void,
                             with source: @escaping () -> I,
                             bridgeBlank: @escaping (_ value: I, _ assign: @escaping (O) -> Void) -> Void) -> () -> Void {
        let wrappedAssign = { o in
            event(o, ResultPromise(receiver: assign))
        }
        return { bridgeBlank(source(), wrappedAssign) }
    }

    static func wrap<Result>(assign: @escaping (Result) -> Void,
                             to event: @escaping (O, ResultPromise<Result>) -> Void,
                             bridgeBlank: @escaping (_ value: I, _ assign: @escaping (O) -> Void) -> Void) -> (I) -> Void {
        let wrappedAssign = { o in
            event(o, ResultPromise(receiver: assign))
        }
        return { i in
            bridgeBlank(i, wrappedAssign)
        }
    }

    static func wrap<Result>(bridgeBlank: @escaping (_ value: I, _ assign: @escaping (O) -> Void) -> Void, to event: @escaping (O, ResultPromise<Result>) -> Void) -> (_ value: I, _ assign: @escaping (Result) -> Void) -> Void {
        return { i, a in
            let wrappedAssign = { o in
                event(o, ResultPromise(receiver: a))
            }

            bridgeBlank(i, wrappedAssign)
        }
    }
}

/// Data source that can be applied filter
public protocol FilteringEntity {
    associatedtype Value
    associatedtype Filtered
    func filter(_ predicate: @escaping (Value) -> Bool) -> Filtered
}
public extension FilteringEntity {
    fileprivate func _distinctUntilChanged(_ def: Value?, comparer: @escaping (Value, Value) -> Bool) -> Filtered {
        var oldValue: Value? = def
        return filter { newValue in
            defer { oldValue = newValue }
            return oldValue.map { comparer($0, newValue) } ?? true
        }
    }

    /// blocks updates with the same values, using specific comparer. Defines initial value.
    func distinctUntilChanged(_ def: Value, comparer: @escaping (Value, Value) -> Bool) -> Filtered {
        return _distinctUntilChanged(def, comparer: comparer)
    }

    /// blocks updates with the same values, using specific comparer
    func distinctUntilChanged(comparer: @escaping (Value, Value) -> Bool) -> Filtered {
        return _distinctUntilChanged(nil, comparer: comparer)
    }
}
public extension FilteringEntity where Value: Equatable {
	/// blocks updates with the same values with defined initial value.
    func distinctUntilChanged(_ def: Value) -> Filtered {
        return distinctUntilChanged(def, comparer: !=)
    }

    /// blocks updates with the same values
    func distinctUntilChanged() -> Filtered {
        return distinctUntilChanged(comparer: !=)
    }
}

internal struct FilteredBridge<V>: BridgeMaker {
    typealias OutData = V
    let bridge: (_ value: V, _ assign: (V) -> Void) -> Void
    func makeBridge(with assign: @escaping (FilteredBridge<V>.OutData) -> Void, source: @escaping () -> FilteredBridge<V>.Data) -> () -> Void {
        return { self.bridge(source(), assign) }
    }
    func filtered(_ predicate: @escaping (V) -> Bool) -> FilteredBridge<V> {
        return .init(bridge: AnyFilter.wrap(predicate: predicate, on: bridge))
    }
    func transformed<U>(_ transform: @escaping (V) -> U) -> TransformedFilteredBridgeMaker<V, U> {
        return .init(bridge: AnyModificator.make(modificator: transform, with: bridge))
    }
    func wrapAssign(_ assign: Assign<V>) -> Assign<V> {
        return .just({ i in self.bridge(i, assign.assign) })
    }
}
struct TransformedFilteredBridgeMaker<I, O>: BridgeMaker {
    let bridge: (_ value: I, _ assign: @escaping (O) -> Void) -> Void
    func makeBridge(with assign: @escaping (O) -> Void, source: @escaping () -> I) -> () -> Void {
        return { self.bridge(source(), assign) }
    }
    func filtered(_ predicate: @escaping (O) -> Bool) -> TransformedFilteredBridgeMaker<I, O> {
        return .init(bridge: AnyFilter.wrap(predicate: predicate, on: bridge))
    }
    func transformed<U>(_ transform: @escaping (O) -> U) -> TransformedFilteredBridgeMaker<I, U> {
        return .init(bridge: AnyModificator.make(modificator: transform, with: bridge))
    }
    func wrapAssign(_ assign: Assign<O>) -> Assign<I> {
        return .just({ i in self.bridge(i, assign.assign) })
    }
}
struct OnReceiveBridge<I, O>: BridgeMaker {
    let event: (O, Promise) -> Void
    let bridge: (_ value: I, _ assign: @escaping (O) -> Void) -> Void
    internal func makeBridge(with assign: @escaping (O) -> Void, source: @escaping () -> I) -> () -> Void {
        return AnyOnReceive.wrap(assign: assign, to: event, with: source, bridgeBlank: bridge)
    }
    func wrapAssign(_ assign: Assign<O>) -> Assign<I> {
        return .just(AnyOnReceive.wrap(assign: assign.assign, to: event, bridgeBlank: bridge))
    }
}
struct OnReceiveMapBridge<I, O, R>: BridgeMaker {
    let event: (O, ResultPromise<R>) -> Void
    let bridge: (_ value: I, _ assign: @escaping (O) -> Void) -> Void
    internal func makeBridge(with assign: @escaping (R) -> Void, source: @escaping () -> I) -> () -> Void {
        return AnyOnReceive.wrap(assign: assign, to: event, with: source, bridgeBlank: bridge)
    }
    func wrapAssign(_ assign: Assign<R>) -> Assign<I> {
        return .just(AnyOnReceive.wrap(assign: assign.assign, to: event, bridgeBlank: bridge))
    }
}

public struct Preprocessor<V>: FilteringEntity, Listenable {
    typealias Data = V
    public typealias OutData = V
    let listenable: AnyListenable<V>
    internal let bridgeMaker = SimpleBridgeMaker<V>()

    public func filter(_ predicate: @escaping (V) -> Bool) -> FilteredPreprocessor<V> {
        return FilteredPreprocessor(listenable: listenable, bridgeMaker: bridgeMaker.filtered(predicate))
    }

    public func map<U>(_ transform: @escaping (V) -> U) -> TransformedPreprocessor<V, U> {
        return TransformedPreprocessor<V, U>(listenable: listenable, bridgeMaker: bridgeMaker.transformed(transform))
    }

    public func onReceive(_ event: @escaping (V, Promise) -> Void) -> OnReceivePreprocessor<V, V> {
        return OnReceivePreprocessor(listenable: listenable, bridgeMaker: OnReceiveBridge(event: event, bridge: { i, assign in assign(i) }))
    }

    public func onReceiveMap<O>(_ event: @escaping (V, ResultPromise<O>) -> Void) -> OnReceiveMapPreprocessor<O, V, V> {
        return OnReceiveMapPreprocessor(listenable: listenable, bridgeMaker: OnReceiveMapBridge(event: event, bridge: { i, assign in assign(i) }))
    }

    public func listening(as config: (AnyListening) -> AnyListening, _ assign: Assign<V>) -> Disposable {
        return listenable.listening(as: config, bridgeMaker.wrapAssign(assign))
    }
    public func listeningItem(as config: (AnyListening) -> AnyListening, _ assign: Assign<V>) -> ListeningItem {
        return listenable.listeningItem(as: config, bridgeMaker.wrapAssign(assign))
    }
}
public struct FilteredPreprocessor<O>: FilteringEntity, Listenable {
    typealias Data = O
    public typealias OutData = O
    let listenable: AnyListenable<O>
    internal let bridgeMaker: FilteredBridge<O>

    public func filter(_ predicate: @escaping (O) -> Bool) -> FilteredPreprocessor<O> {
        return FilteredPreprocessor(listenable: listenable, bridgeMaker: bridgeMaker.filtered(predicate))
    }

    public func map<U>(_ transform: @escaping (O) -> U) -> TransformedFilteredPreprocessor<O, U> {
        return TransformedFilteredPreprocessor(listenable: listenable, bridgeMaker: bridgeMaker.transformed(transform))
    }

    public func onReceive(_ event: @escaping (O, Promise) -> Void) -> OnReceivePreprocessor<O, O> {
        return OnReceivePreprocessor(listenable: listenable, bridgeMaker: OnReceiveBridge(event: event, bridge: bridgeMaker.bridge))
    }
    public func onReceiveMap<Result>(_ event: @escaping (O, ResultPromise<Result>) -> Void) -> OnReceiveMapPreprocessor<Result, O, O> {
        return OnReceiveMapPreprocessor(listenable: listenable, bridgeMaker: OnReceiveMapBridge(event: event, bridge: bridgeMaker.bridge))
    }

    public func listening(as config: (AnyListening) -> AnyListening, _ assign: Assign<O>) -> Disposable {
        return listenable.listening(as: config, bridgeMaker.wrapAssign(assign))
    }
    public func listeningItem(as config: (AnyListening) -> AnyListening, _ assign: Assign<O>) -> ListeningItem {
        return listenable.listeningItem(as: config, bridgeMaker.wrapAssign(assign))
    }
}
public struct TransformedPreprocessor<I, O>: FilteringEntity, Listenable {
    public typealias OutData = O
    typealias Data = O
    let listenable: AnyListenable<I>
    internal let bridgeMaker: TransformedFilteredBridgeMaker<I, O>

    public func filter(_ predicate: @escaping (O) -> Bool) -> TransformedFilteredPreprocessor<I, O> {
        return TransformedFilteredPreprocessor<I, O>(listenable: listenable, bridgeMaker: bridgeMaker.filtered(predicate))
    }

    public func map<U>(_ transform: @escaping (O) -> U) -> TransformedFilteredPreprocessor<I, U> {
        return TransformedFilteredPreprocessor<I, U>(listenable: listenable, bridgeMaker: bridgeMaker.transformed(transform))
    }

    public func onReceive(_ event: @escaping (O, Promise) -> Void) -> OnReceivePreprocessor<I, O> {
        return OnReceivePreprocessor(listenable: listenable, bridgeMaker: OnReceiveBridge(event: event, bridge: bridgeMaker.bridge))
    }
    public func onReceiveMap<U>(_ event: @escaping (O, ResultPromise<U>) -> Void) -> OnReceiveMapPreprocessor<U, I, O> {
        return OnReceiveMapPreprocessor(listenable: listenable, bridgeMaker: OnReceiveMapBridge(event: event, bridge: bridgeMaker.bridge))
    }

    public func listening(as config: (AnyListening) -> AnyListening, _ assign: Assign<O>) -> Disposable {
        return listenable.listening(as: config, bridgeMaker.wrapAssign(assign))
    }
    public func listeningItem(as config: (AnyListening) -> AnyListening, _ assign: Assign<O>) -> ListeningItem {
        return listenable.listeningItem(as: config, bridgeMaker.wrapAssign(assign))
    }
}
public struct TransformedFilteredPreprocessor<I, O>: FilteringEntity, Listenable {
    public typealias OutData = O
    typealias Data = I
    let listenable: AnyListenable<I>
    internal let bridgeMaker: TransformedFilteredBridgeMaker<I, O>

    /// filter for value from this source, but this behavior illogical, therefore it use not recommended
    //    func filter(_ predicate: @escaping (I) -> Bool) -> OwnedTransformedFilteredPreprocessor<Owner, I, O> {
    //        return OwnedTransformedFilteredPreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, bridge: AnyFilter.wrap(predicate: predicate, on: bridge))
    //    }

    public func filter(_ predicate: @escaping (O) -> Bool) -> TransformedFilteredPreprocessor<I, O> {
        return TransformedFilteredPreprocessor(listenable: listenable, bridgeMaker: bridgeMaker.filtered(predicate))
    }

    public func map<U>(_ transform: @escaping (O) -> U) -> TransformedFilteredPreprocessor<I, U> {
        return TransformedFilteredPreprocessor<I, U>(listenable: listenable, bridgeMaker: bridgeMaker.transformed(transform))
    }

    public func onReceive(_ event: @escaping (O, Promise) -> Void) -> OnReceivePreprocessor<I, O> {
        return OnReceivePreprocessor(listenable: listenable, bridgeMaker: OnReceiveBridge(event: event, bridge: bridgeMaker.bridge))
    }
    public func onReceiveMap<Result>(_ event: @escaping (O, ResultPromise<Result>) -> Void) -> OnReceiveMapPreprocessor<Result, I, O> {
        return OnReceiveMapPreprocessor(listenable: listenable, bridgeMaker: OnReceiveMapBridge(event: event, bridge: bridgeMaker.bridge))
    }

    public func listening(as config: (AnyListening) -> AnyListening, _ assign: Assign<O>) -> Disposable {
        return listenable.listening(as: config, bridgeMaker.wrapAssign(assign))
    }
    public func listeningItem(as config: (AnyListening) -> AnyListening, _ assign: Assign<O>) -> ListeningItem {
        return listenable.listeningItem(as: config, bridgeMaker.wrapAssign(assign))
    }
}
public struct OnReceivePreprocessor<I, O>: FilteringEntity, Listenable {
    public typealias OutData = O
    typealias Data = I
    internal typealias Bridge = OnReceiveBridge<I, O>
    internal let listenable: AnyListenable<I>
    internal let bridgeMaker: Bridge

    public func filter(_ predicate: @escaping (O) -> Bool) -> TransformedFilteredPreprocessor<I, O> {
        let bridge = AnyFilter.wrap(predicate: predicate, on: AnyOnReceive.wrap(bridgeBlank: bridgeMaker.bridge, to: bridgeMaker.event))
        return TransformedFilteredPreprocessor(listenable: listenable,
                                                    bridgeMaker: .init(bridge: bridge))
    }

    public func map<U>(_ transform: @escaping (O) -> U) -> TransformedFilteredPreprocessor<I, U> {
        let bridge = AnyModificator.make(modificator: transform, with: AnyOnReceive.wrap(bridgeBlank: bridgeMaker.bridge, to: bridgeMaker.event))
        return TransformedFilteredPreprocessor<I, U>(listenable: listenable,
                                                          bridgeMaker: .init(bridge: bridge))
    }

    public func listening(as config: (AnyListening) -> AnyListening, _ assign: Assign<O>) -> Disposable {
        return listenable.listening(as: config, bridgeMaker.wrapAssign(assign))
    }
    public func listeningItem(as config: (AnyListening) -> AnyListening, _ assign: Assign<O>) -> ListeningItem {
        return listenable.listeningItem(as: config, bridgeMaker.wrapAssign(assign))
    }
}
public struct OnReceiveMapPreprocessor<Result, I, O>: FilteringEntity, Listenable {
    public typealias OutData = Result
    typealias Data = I
    let listenable: AnyListenable<I>
    internal let bridgeMaker: OnReceiveMapBridge<I, O, Result>

    public func filter(_ predicate: @escaping (Result) -> Bool) -> TransformedFilteredPreprocessor<I, Result> {
        let bridge = AnyFilter.wrap(predicate: predicate, on: AnyOnReceive.wrap(bridgeBlank: bridgeMaker.bridge, to: bridgeMaker.event))
        return TransformedFilteredPreprocessor(listenable: listenable, bridgeMaker: .init(bridge: bridge))
    }

    public func map<U>(_ transform: @escaping (Result) -> U) -> TransformedFilteredPreprocessor<I, U> {
        let bridge = AnyModificator.make(modificator: transform, with: AnyOnReceive.wrap(bridgeBlank: bridgeMaker.bridge, to: bridgeMaker.event))
        return TransformedFilteredPreprocessor(listenable: listenable, bridgeMaker: .init(bridge: bridge))
    }

    public func listening(as config: (AnyListening) -> AnyListening, _ assign: Assign<Result>) -> Disposable {
        return listenable.listening(as: config, bridgeMaker.wrapAssign(assign))
    }
    public func listeningItem(as config: (AnyListening) -> AnyListening, _ assign: Assign<Result>) -> ListeningItem {
        return listenable.listeningItem(as: config, bridgeMaker.wrapAssign(assign))
    }
}

public extension Listenable {
    func filter(_ predicate: @escaping (OutData) -> Bool) -> FilteredPreprocessor<OutData> {
        let out = Preprocessor<OutData>(listenable: AnyListenable(self.listening, self.listeningItem))
        return out.filter(predicate)
    }
    func map<U>(_ transform: @escaping (OutData) -> U) -> TransformedPreprocessor<OutData, U> {
        let out = Preprocessor<OutData>(listenable: AnyListenable(self.listening, self.listeningItem))
        return out.map(transform)
    }
    func onReceive(_ event: @escaping (OutData, Promise) -> Void) -> OnReceivePreprocessor<OutData, OutData> {
        let out = Preprocessor<OutData>(listenable: AnyListenable(self.listening, self.listeningItem))
        return out.onReceive(event)
    }
    func onReceiveMap<Result>(_ event: @escaping (OutData, ResultPromise<Result>) -> Void) -> OnReceiveMapPreprocessor<Result, OutData, OutData> {
        let out = Preprocessor<OutData>(listenable: AnyListenable(self.listening, self.listeningItem))
        return out.onReceiveMap(event)
    }
}

//protocol _Preprocessor: PublicPreprocessor {
//    associatedtype Input
//    associatedtype Output
//    associatedtype Filtered: PublicPreprocessor
//    func filter(_ predicate: @escaping (Input) -> Bool) -> Filtered
//    associatedtype Transformed: PublicPreprocessor
//    func map<U>(_ transform: @escaping (Input) -> U) -> Transformed
//    associatedtype OnReceive: PublicPreprocessor
//    func onReceive(_ event: @escaping (Input, Promise) -> Void) -> OnReceive
//    associatedtype OnReceiveMap: PublicPreprocessor
//    func onReceiveMap<Result>(_ event: @escaping (Input, ResultPromise<Result>) -> Void) -> OnReceiveMap
//}
public protocol PublicPreprocessor {
    associatedtype OutData
    func wrap(_ assign: @escaping (OutData) -> Void) -> AnyListening
}

public struct InsiderPreprocessor<V>: FilteringEntity, _ListeningMaker, PublicPreprocessor {
    public typealias OutData = V
    typealias Data = V
    internal let dataSource: () -> V
    internal let bridgeMaker = SimpleBridgeMaker<V>()

    public func filter(_ predicate: @escaping (V) -> Bool) -> InsiderFilteredPreprocessor<V> {
        return InsiderFilteredPreprocessor(dataSource: dataSource, bridgeMaker: .init(bridge: AnyFilter.wrap(predicate: predicate)))
    }

    public func map<U>(_ transform: @escaping (V) -> U) -> InsiderTransformedPreprocessor<U> {
        return InsiderTransformedPreprocessor(dataSource: AnyModificator.make(modificator: transform, with: dataSource))
    }

    public func onReceive(_ event: @escaping (V, Promise) -> Void) -> InsiderOnReceivePreprocessor<V, V> {
        return InsiderOnReceivePreprocessor(dataSource: dataSource, bridgeMaker: OnReceiveBridge(event: event, bridge: { i, assign in assign(i) }))
    }

    public func onReceiveMap<O>(_ event: @escaping (V, ResultPromise<O>) -> Void) -> InsiderOnReceiveMapPreprocessor<O, V, V> {
        return InsiderOnReceiveMapPreprocessor(dataSource: dataSource, bridgeMaker: OnReceiveMapBridge(event: event, bridge: { i, assign in assign(i) }))
    }

    public func wrap(_ assign: @escaping (V) -> Void) -> AnyListening {
        return makeListening(assign)
    }
}
public struct InsiderTransformedPreprocessor<V>: FilteringEntity, _ListeningMaker, PublicPreprocessor {
    public typealias OutData = V
    typealias Data = V
    internal let dataSource: () -> V
    internal let bridgeMaker = SimpleBridgeMaker<V>()

    public func filter(_ predicate: @escaping (V) -> Bool) -> InsiderFilteredPreprocessor<V> {
        return InsiderFilteredPreprocessor(dataSource: dataSource, bridgeMaker: .init(bridge: AnyFilter.wrap(predicate: predicate)))
    }

    public func map<U>(_ transform: @escaping (V) -> U) -> InsiderTransformedPreprocessor<U> {
        return InsiderTransformedPreprocessor<U>(dataSource: AnyModificator.make(modificator: transform, with: dataSource))
    }

    public func onReceive(_ event: @escaping (V, Promise) -> Void) -> InsiderOnReceivePreprocessor<V, V> {
        return InsiderOnReceivePreprocessor(dataSource: dataSource, bridgeMaker: OnReceiveBridge(event: event, bridge: { i, assign in assign(i) }))
    }

    public func onReceiveMap<Result>(_ event: @escaping (V, ResultPromise<Result>) -> Void) -> InsiderOnReceiveMapPreprocessor<Result, V, V> {
        return InsiderOnReceiveMapPreprocessor(dataSource: dataSource, bridgeMaker: OnReceiveMapBridge(event: event, bridge: { i, assign in assign(i) }))
    }

    public func wrap(_ assign: @escaping (V) -> Void) -> AnyListening {
        return makeListening(assign)
    }
}
public struct InsiderFilteredPreprocessor<V>: FilteringEntity, _ListeningMaker, PublicPreprocessor {
    public typealias OutData = V
    typealias Data = V
    internal let dataSource: () -> V
    internal let bridgeMaker: FilteredBridge<V>

    public func filter(_ predicate: @escaping (V) -> Bool) -> InsiderFilteredPreprocessor<V> {
        return InsiderFilteredPreprocessor(dataSource: dataSource, bridgeMaker: bridgeMaker.filtered(predicate))
    }

    public func map<U>(_ transform: @escaping (V) -> U) -> InsiderTransformedFilteredPreprocessor<V, U> {
        return InsiderTransformedFilteredPreprocessor(dataSource: dataSource, bridgeMaker: bridgeMaker.transformed(transform))
    }

    func onReceive(_ event: @escaping (V, Promise) -> Void) -> InsiderOnReceivePreprocessor<V, V> {
        return InsiderOnReceivePreprocessor(dataSource: dataSource, bridgeMaker: OnReceiveBridge(event: event, bridge: bridgeMaker.bridge))
    }

    func onReceiveMap<Result>(_ event: @escaping (V, ResultPromise<Result>) -> Void) -> InsiderOnReceiveMapPreprocessor<Result, V, V> {
        return InsiderOnReceiveMapPreprocessor(dataSource: dataSource, bridgeMaker: OnReceiveMapBridge(event: event, bridge: { i, assign in assign(i) }))
    }

    public func wrap(_ assign: @escaping (V) -> Void) -> AnyListening {
        return makeListening(assign)
    }
}
public struct InsiderTransformedFilteredPreprocessor<I, O>: FilteringEntity, _ListeningMaker, PublicPreprocessor {
    public typealias OutData = O
    typealias Data = I
    internal let dataSource: () -> I
    internal let bridgeMaker: TransformedFilteredBridgeMaker<I, O>

    /// filter for value from this source, but this behavior illogical, therefore it use not recommended
    //    func filter(_ predicate: @escaping (I) -> Bool) -> TransformedFilteredPreprocessor<I, O> {
    //        return TransformedFilteredPreprocessor(dataSource: dataSource, bridge: AnyFilter.wrap(predicate: predicate, on: bridge))
    //    }

    public func filter(_ predicate: @escaping (O) -> Bool) -> InsiderTransformedFilteredPreprocessor<I, O> {
        return InsiderTransformedFilteredPreprocessor(dataSource: dataSource, bridgeMaker: bridgeMaker.filtered(predicate))
    }

    public func map<U>(_ transform: @escaping (O) -> U) -> InsiderTransformedFilteredPreprocessor<I, U> {
        return InsiderTransformedFilteredPreprocessor<I, U>(dataSource: dataSource, bridgeMaker: bridgeMaker.transformed(transform))
    }

    public func onReceive(_ event: @escaping (O, Promise) -> Void) -> InsiderOnReceivePreprocessor<I, O> {
        return InsiderOnReceivePreprocessor(dataSource: dataSource, bridgeMaker: OnReceiveBridge(event: event, bridge: bridgeMaker.bridge))
    }

    public func onReceiveMap<Result>(_ event: @escaping (O, ResultPromise<Result>) -> Void) -> InsiderOnReceiveMapPreprocessor<Result, I, O> {
        return InsiderOnReceiveMapPreprocessor(dataSource: dataSource, bridgeMaker: OnReceiveMapBridge(event: event, bridge: bridgeMaker.bridge))
    }

    public func wrap(_ assign: @escaping (O) -> Void) -> AnyListening {
        return makeListening(assign)
    }
}
public struct InsiderOnReceivePreprocessor<I, O>: _ListeningMaker, PublicPreprocessor {
    public typealias OutData = O
    typealias Data = I
    internal typealias Bridge = OnReceiveBridge<I, O>
    internal let dataSource: () -> I
    internal let bridgeMaker: Bridge

    public func filter(_ predicate: @escaping (O) -> Bool) -> InsiderTransformedFilteredPreprocessor<I, O> {
        let bridge = AnyFilter.wrap(predicate: predicate, on: AnyOnReceive.wrap(bridgeBlank: bridgeMaker.bridge, to: bridgeMaker.event))
        return InsiderTransformedFilteredPreprocessor(dataSource: dataSource, bridgeMaker: .init(bridge: bridge))
    }

    public func map<U>(_ transform: @escaping (O) -> U) -> InsiderTransformedFilteredPreprocessor<I, U> {
        let bridge = AnyModificator.make(modificator: transform, with: AnyOnReceive.wrap(bridgeBlank: bridgeMaker.bridge, to: bridgeMaker.event))
        return InsiderTransformedFilteredPreprocessor(dataSource: dataSource, bridgeMaker: .init(bridge: bridge))
    }

    public func wrap(_ assign: @escaping (O) -> Void) -> AnyListening {
        return makeListening(assign)
    }
}
public struct InsiderOnReceiveMapPreprocessor<Result, I, O>: _ListeningMaker, PublicPreprocessor {
    public typealias OutData = Result
    typealias Data = I
    internal let dataSource: () -> I
    internal let bridgeMaker: OnReceiveMapBridge<I, O, Result>

    public func filter(_ predicate: @escaping (Result) -> Bool) -> InsiderTransformedFilteredPreprocessor<I, Result> {
        let bridge = AnyFilter.wrap(predicate: predicate, on: AnyOnReceive.wrap(bridgeBlank: bridgeMaker.bridge, to: bridgeMaker.event))
        return InsiderTransformedFilteredPreprocessor(dataSource: dataSource, bridgeMaker: .init(bridge: bridge))
    }

    public func map<U>(_ transform: @escaping (Result) -> U) -> InsiderTransformedFilteredPreprocessor<I, U> {
        let bridge = AnyModificator.make(modificator: transform, with: AnyOnReceive.wrap(bridgeBlank: bridgeMaker.bridge, to: bridgeMaker.event))
        return InsiderTransformedFilteredPreprocessor(dataSource: dataSource, bridgeMaker: .init(bridge: bridge))
    }

    public func wrap(_ assign: @escaping (Result) -> Void) -> AnyListening {
        return makeListening(assign)
    }
}

public extension Insider {
	/// connects to insider of data source using specific connection
    mutating func listen<Maker: PublicPreprocessor>(
        as config: (AnyListening) -> AnyListening = { $0 },
        preprocessor: (InsiderPreprocessor<Data>) -> Maker,
        _ assign: Assign<Maker.OutData>
        ) -> ListeningToken {
        return addListening(config(preprocessor(InsiderPreprocessor(dataSource: dataSource)).wrap(assign.assign)))
    }
}
