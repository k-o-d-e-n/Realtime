//
//  Preprocessor.swift
//  GoogleToolboxForMac
//
//  Created by Denis Koryttsev on 31/01/2018.
//

import Foundation

// MARK: Map, filter

fileprivate struct AnyFilter<I> {
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

fileprivate struct AnyModificator<I, O> {
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
        return distinctUntilChanged(def, comparer: { $0 != $1 })
    }

    /// blocks updates with the same values
    func distinctUntilChanged() -> Filtered {
        return distinctUntilChanged(comparer: { $0 != $1 })
    }
}

// TODO: May be has possible use TransformedFilteredPreprocessor only
// TODO: Avoid to use copy of simple preprocessor with owner property
// TODO: Can be removed, because immediately transformed
// TODO: Add flatMap, default value.
// TODO: Make preprocessor type with private access and create filter-map protocol
public struct Preprocessor<V>: FilteringEntity, _ListeningMaker, PublicPreprocessor {
    public typealias OutData = V
    typealias Data = V
    internal let dataSource: () -> V
    internal let bridgeMaker = SimpleBridgeMaker<V>()

    public func filter(_ predicate: @escaping (V) -> Bool) -> FilteredPreprocessor<V> {
        return FilteredPreprocessor(dataSource: dataSource, bridgeMaker: .init(bridge: AnyFilter.wrap(predicate: predicate)))
    }

    public func map<U>(_ transform: @escaping (V) -> U) -> TransformedPreprocessor<U> {
        return TransformedPreprocessor(dataSource: AnyModificator.make(modificator: transform, with: dataSource))
    }

    public func onReceive(_ event: @escaping (V, Promise) -> Void) -> OnReceivePreprocessor<V, V> {
        return OnReceivePreprocessor(dataSource: dataSource, bridgeMaker: OnReceiveBridge(event: event, bridge: { i, assign in assign(i) }))
    }

    public func onReceiveMap<O>(_ event: @escaping (V, ResultPromise<O>) -> Void) -> OnReceiveMapPreprocessor<O, V, V> {
        return OnReceiveMapPreprocessor(dataSource: dataSource, bridgeMaker: OnReceiveMapBridge(event: event, bridge: { i, assign in assign(i) }))
    }

    public func wrap(_ assign: @escaping (V) -> Void) -> AnyListening {
        return makeListening(assign)
    }
}

public struct OwnedOnReceivePreprocessor<Owner: InsiderOwner, I, O>: InsiderAccessor, _ListeningMaker, Listenable {
    public typealias OutData = O
    typealias Data = I
    internal typealias Bridge = OnReceiveBridge<I, O>
    internal weak var insiderOwner: Owner!
    internal let dataSource: () -> I
    internal let bridgeMaker: Bridge

    public func filter(_ predicate: @escaping (O) -> Bool) -> OwnedTransformedFilteredPreprocessor<Owner, I, O> {
        let bridge = AnyFilter.wrap(predicate: predicate, on: AnyOnReceive.wrap(bridgeBlank: bridgeMaker.bridge, to: bridgeMaker.event))
        return OwnedTransformedFilteredPreprocessor(insiderOwner: insiderOwner,
                                                    dataSource: dataSource,
                                                    bridgeMaker: .init(bridge: bridge))
    }

    public func map<U>(_ transform: @escaping (O) -> U) -> OwnedTransformedFilteredPreprocessor<Owner, I, U> {
        let bridge = AnyModificator.make(modificator: transform, with: AnyOnReceive.wrap(bridgeBlank: bridgeMaker.bridge, to: bridgeMaker.event))
        return OwnedTransformedFilteredPreprocessor<Owner, I, U>(insiderOwner: insiderOwner,
                                                                 dataSource: dataSource,
                                                                 bridgeMaker: .init(bridge: bridge))
    }

    public func listening(as config: (AnyListening) -> AnyListening, _ assign: Assign<O>) -> Disposable {
        return _listening(as: config, assign)
    }
    public func listeningItem(as config: (AnyListening) -> AnyListening, _ assign: Assign<O>) -> ListeningItem {
        return _listeningItem(as: config, assign)
    }
}
struct OnReceiveBridge<I, O>: BridgeMaker {
    let event: (O, Promise) -> Void
    let bridge: (_ value: I, _ assign: @escaping (O) -> Void) -> Void
    internal func makeBridge(with assign: @escaping (O) -> Void, source: @escaping () -> I) -> () -> Void {
        return AnyOnReceive.wrap(assign: assign, to: event, with: source, bridgeBlank: bridge)
    }
}
struct OnReceiveMapBridge<I, O, R>: BridgeMaker {
    let event: (O, ResultPromise<R>) -> Void
    let bridge: (_ value: I, _ assign: @escaping (O) -> Void) -> Void
    internal func makeBridge(with assign: @escaping (R) -> Void, source: @escaping () -> I) -> () -> Void {
        return AnyOnReceive.wrap(assign: assign, to: event, with: source, bridgeBlank: bridge)
    }
}
public struct OnReceivePreprocessor<I, O>: _ListeningMaker, PublicPreprocessor {
    public typealias OutData = O
    typealias Data = I
    internal typealias Bridge = OnReceiveBridge<I, O>
    internal let dataSource: () -> I
    internal let bridgeMaker: Bridge

    public func filter(_ predicate: @escaping (O) -> Bool) -> TransformedFilteredPreprocessor<I, O> {
        let bridge = AnyFilter.wrap(predicate: predicate, on: AnyOnReceive.wrap(bridgeBlank: bridgeMaker.bridge, to: bridgeMaker.event))
        return TransformedFilteredPreprocessor(dataSource: dataSource, bridgeMaker: .init(bridge: bridge))
    }

    public func map<U>(_ transform: @escaping (O) -> U) -> TransformedFilteredPreprocessor<I, U> {
        let bridge = AnyModificator.make(modificator: transform, with: AnyOnReceive.wrap(bridgeBlank: bridgeMaker.bridge, to: bridgeMaker.event))
        return TransformedFilteredPreprocessor(dataSource: dataSource, bridgeMaker: .init(bridge: bridge))
    }

    public func wrap(_ assign: @escaping (O) -> Void) -> AnyListening {
        return makeListening(assign)
    }
}
public struct OnReceiveMapPreprocessor<Result, I, O>: _ListeningMaker, PublicPreprocessor {
    public typealias OutData = Result
    typealias Data = I
    internal let dataSource: () -> I
    internal let bridgeMaker: OnReceiveMapBridge<I, O, Result>

    public func filter(_ predicate: @escaping (Result) -> Bool) -> TransformedFilteredPreprocessor<I, Result> {
        let bridge = AnyFilter.wrap(predicate: predicate, on: AnyOnReceive.wrap(bridgeBlank: bridgeMaker.bridge, to: bridgeMaker.event))
        return TransformedFilteredPreprocessor(dataSource: dataSource, bridgeMaker: .init(bridge: bridge))
    }

    public func map<U>(_ transform: @escaping (Result) -> U) -> TransformedFilteredPreprocessor<I, U> {
        let bridge = AnyModificator.make(modificator: transform, with: AnyOnReceive.wrap(bridgeBlank: bridgeMaker.bridge, to: bridgeMaker.event))
        return TransformedFilteredPreprocessor(dataSource: dataSource, bridgeMaker: .init(bridge: bridge))
    }

    public func wrap(_ assign: @escaping (Result) -> Void) -> AnyListening {
        return makeListening(assign)
    }
}
public struct OwnedOnReceiveMapPreprocessor<Owner: InsiderOwner, Result, I, O>: InsiderAccessor, _ListeningMaker, Listenable {
    public typealias OutData = Result
    typealias Data = I
    weak var insiderOwner: Owner!
    internal let dataSource: () -> I
    internal let bridgeMaker: OnReceiveMapBridge<I, O, Result>

    public func filter(_ predicate: @escaping (Result) -> Bool) -> TransformedFilteredPreprocessor<I, Result> {
        let bridge = AnyFilter.wrap(predicate: predicate, on: AnyOnReceive.wrap(bridgeBlank: bridgeMaker.bridge, to: bridgeMaker.event))
        return TransformedFilteredPreprocessor(dataSource: dataSource, bridgeMaker: .init(bridge: bridge))
    }

    public func map<U>(_ transform: @escaping (Result) -> U) -> TransformedFilteredPreprocessor<I, U> {
        let bridge = AnyModificator.make(modificator: transform, with: AnyOnReceive.wrap(bridgeBlank: bridgeMaker.bridge, to: bridgeMaker.event))
        return TransformedFilteredPreprocessor(dataSource: dataSource, bridgeMaker: .init(bridge: bridge))
    }

    public func listening(as config: (AnyListening) -> AnyListening, _ assign: Assign<Result>) -> Disposable {
        return _listening(as: config, assign)
    }
    public func listeningItem(as config: (AnyListening) -> AnyListening, _ assign: Assign<Result>) -> ListeningItem {
        return _listeningItem(as: config, assign)
    }
}
public struct OwnedPreprocessor<Owner: InsiderOwner>: InsiderAccessor, FilteringEntity, _ListeningMaker, Listenable {
    typealias Data = Owner.T
    public typealias OutData = Owner.T
    weak var insiderOwner: Owner!
    internal var dataSource: () -> Owner.T {
        return insiderOwner.insider.dataSource
    }
    internal let bridgeMaker = SimpleBridgeMaker<Owner.T>()

    public func filter(_ predicate: @escaping (Owner.T) -> Bool) -> OwnedFilteredPreprocessor<Owner, Owner.T> {
        return OwnedFilteredPreprocessor(insiderOwner: insiderOwner, dataSource: insiderOwner.insider.dataSource, bridgeMaker: .init(bridge: AnyFilter.wrap(predicate: predicate)))
    }

    public func map<U>(_ transform: @escaping (Owner.T) -> U) -> OwnedTransformedPreprocessor<Owner, U> {
        return OwnedTransformedPreprocessor<Owner, U>(insiderOwner: insiderOwner, dataSource: AnyModificator.make(modificator: transform, with: dataSource))
    }

    public func onReceive(_ event: @escaping (Owner.T, Promise) -> Void) -> OwnedOnReceivePreprocessor<Owner, Owner.T, Owner.T> {
        return OwnedOnReceivePreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, bridgeMaker: OnReceiveBridge(event: event, bridge: { i, assign in assign(i) }))
    }

    public func onReceiveMap<O>(_ event: @escaping (Owner.T, ResultPromise<O>) -> Void) -> OwnedOnReceiveMapPreprocessor<Owner, O, Owner.T, Owner.T> {
        return OwnedOnReceiveMapPreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, bridgeMaker: OnReceiveMapBridge(event: event, bridge: { i, assign in assign(i) }))
    }

    public func listening(as config: (AnyListening) -> AnyListening, _ assign: Assign<Owner.T>) -> Disposable {
        return _listening(as: config, assign)
    }
    public func listeningItem(as config: (AnyListening) -> AnyListening, _ assign: Assign<Owner.T>) -> ListeningItem {
        return _listeningItem(as: config, assign)
    }
}

public struct TransformedPreprocessor<V>: FilteringEntity, _ListeningMaker, PublicPreprocessor {
    public typealias OutData = V
    typealias Data = V
    internal let dataSource: () -> V
    internal let bridgeMaker = SimpleBridgeMaker<V>()

    public func filter(_ predicate: @escaping (V) -> Bool) -> FilteredPreprocessor<V> {
        return FilteredPreprocessor(dataSource: dataSource, bridgeMaker: .init(bridge: AnyFilter.wrap(predicate: predicate)))
    }

    public func map<U>(_ transform: @escaping (V) -> U) -> TransformedPreprocessor<U> {
        return TransformedPreprocessor<U>(dataSource: AnyModificator.make(modificator: transform, with: dataSource))
    }

    public func onReceive(_ event: @escaping (V, Promise) -> Void) -> OnReceivePreprocessor<V, V> {
        return OnReceivePreprocessor(dataSource: dataSource, bridgeMaker: OnReceiveBridge(event: event, bridge: { i, assign in assign(i) }))
    }

    public func onReceiveMap<Result>(_ event: @escaping (V, ResultPromise<Result>) -> Void) -> OnReceiveMapPreprocessor<Result, V, V> {
        return OnReceiveMapPreprocessor(dataSource: dataSource, bridgeMaker: OnReceiveMapBridge(event: event, bridge: { i, assign in assign(i) }))
    }

    public func wrap(_ assign: @escaping (V) -> Void) -> AnyListening {
        return makeListening(assign)
    }
}
public struct OwnedTransformedPreprocessor<Owner: InsiderOwner, V>: InsiderAccessor, FilteringEntity, _ListeningMaker, Listenable {
    public typealias OutData = V
    typealias Data = V
    weak var insiderOwner: Owner!
    internal let dataSource: () -> V
    internal let bridgeMaker = SimpleBridgeMaker<V>()

    public func filter(_ predicate: @escaping (V) -> Bool) -> OwnedFilteredPreprocessor<Owner, V> {
        return OwnedFilteredPreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, bridgeMaker: .init(bridge: AnyFilter.wrap(predicate: predicate)))
    }

    public func map<U>(_ transform: @escaping (V) -> U) -> OwnedTransformedPreprocessor<Owner, U> {
        return OwnedTransformedPreprocessor<Owner, U>(insiderOwner: insiderOwner, dataSource: AnyModificator.make(modificator: transform, with: dataSource))
    }

    public func onReceive(_ event: @escaping (V, Promise) -> Void) -> OwnedOnReceivePreprocessor<Owner, V, V> {
        return OwnedOnReceivePreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, bridgeMaker: OnReceiveBridge(event: event, bridge: { i, assign in assign(i) }))
    }
    public func onReceiveMap<O>(_ event: @escaping (V, ResultPromise<O>) -> Void) -> OwnedOnReceiveMapPreprocessor<Owner, O, V, V> {
        return OwnedOnReceiveMapPreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, bridgeMaker: OnReceiveMapBridge(event: event, bridge: { i, assign in assign(i) }))
    }

    public func listening(as config: (AnyListening) -> AnyListening, _ assign: Assign<V>) -> Disposable {
        return _listening(as: config, assign)
    }
    public func listeningItem(as config: (AnyListening) -> AnyListening, _ assign: Assign<V>) -> ListeningItem {
        return _listeningItem(as: config, assign)
    }
}

public struct TransformedFilteredPreprocessor<I, O>: FilteringEntity, _ListeningMaker, PublicPreprocessor {
    public typealias OutData = O
    typealias Data = I
    internal let dataSource: () -> I
    internal let bridgeMaker: TransformedFilteredBridgeMaker<I, O>

    /// filter for value from this source, but this behavior illogical, therefore it use not recommended
    //    func filter(_ predicate: @escaping (I) -> Bool) -> TransformedFilteredPreprocessor<I, O> {
    //        return TransformedFilteredPreprocessor(dataSource: dataSource, bridge: AnyFilter.wrap(predicate: predicate, on: bridge))
    //    }

    public func filter(_ predicate: @escaping (O) -> Bool) -> TransformedFilteredPreprocessor<I, O> {
        return TransformedFilteredPreprocessor(dataSource: dataSource, bridgeMaker: bridgeMaker.filtered(predicate))
    }

    public func map<U>(_ transform: @escaping (O) -> U) -> TransformedFilteredPreprocessor<I, U> {
        return TransformedFilteredPreprocessor<I, U>(dataSource: dataSource, bridgeMaker: bridgeMaker.transformed(transform))
    }

    public func onReceive(_ event: @escaping (O, Promise) -> Void) -> OnReceivePreprocessor<I, O> {
        return OnReceivePreprocessor(dataSource: dataSource, bridgeMaker: OnReceiveBridge(event: event, bridge: bridgeMaker.bridge))
    }

    public func onReceiveMap<Result>(_ event: @escaping (O, ResultPromise<Result>) -> Void) -> OnReceiveMapPreprocessor<Result, I, O> {
        return OnReceiveMapPreprocessor(dataSource: dataSource, bridgeMaker: OnReceiveMapBridge(event: event, bridge: bridgeMaker.bridge))
    }

    public func wrap(_ assign: @escaping (O) -> Void) -> AnyListening {
        return makeListening(assign)
    }
}
internal struct TransformedFilteredBridgeMaker<I, O>: BridgeMaker {
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
}
public struct OwnedTransformedFilteredPreprocessor<Owner: InsiderOwner, I, O>: InsiderAccessor, FilteringEntity, _ListeningMaker, Listenable {
    public typealias OutData = O
    typealias Data = I
    weak var insiderOwner: Owner!
    internal let dataSource: () -> I
    internal let bridgeMaker: TransformedFilteredBridgeMaker<I, O>

    /// filter for value from this source, but this behavior illogical, therefore it use not recommended
    //    func filter(_ predicate: @escaping (I) -> Bool) -> OwnedTransformedFilteredPreprocessor<Owner, I, O> {
    //        return OwnedTransformedFilteredPreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, bridge: AnyFilter.wrap(predicate: predicate, on: bridge))
    //    }

    public func filter(_ predicate: @escaping (O) -> Bool) -> OwnedTransformedFilteredPreprocessor<Owner, I, O> {
        return OwnedTransformedFilteredPreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, bridgeMaker: bridgeMaker.filtered(predicate))
    }

    public func map<U>(_ transform: @escaping (O) -> U) -> OwnedTransformedFilteredPreprocessor<Owner, I, U> {
        return OwnedTransformedFilteredPreprocessor<Owner, I, U>(insiderOwner: insiderOwner, dataSource: dataSource, bridgeMaker: bridgeMaker.transformed(transform))
    }

    public func onReceive(_ event: @escaping (O, Promise) -> Void) -> OwnedOnReceivePreprocessor<Owner, I, O> {
        return OwnedOnReceivePreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, bridgeMaker: OnReceiveBridge(event: event, bridge: bridgeMaker.bridge))
    }
    public func onReceiveMap<Result>(_ event: @escaping (O, ResultPromise<Result>) -> Void) -> OwnedOnReceiveMapPreprocessor<Owner, Result, I, O> {
        return OwnedOnReceiveMapPreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, bridgeMaker: OnReceiveMapBridge(event: event, bridge: bridgeMaker.bridge))
    }

    public func listening(as config: (AnyListening) -> AnyListening, _ assign: Assign<O>) -> Disposable {
        return _listening(as: config, assign)
    }
    public func listeningItem(as config: (AnyListening) -> AnyListening, _ assign: Assign<O>) -> ListeningItem {
        return _listeningItem(as: config, assign)
    }
}

internal struct FilteredBridge<V>: BridgeMaker {
    typealias OutData = V
    fileprivate let bridge: (_ value: V, _ assign: (V) -> Void) -> Void
    func makeBridge(with assign: @escaping (FilteredBridge<V>.OutData) -> Void, source: @escaping () -> FilteredBridge<V>.Data) -> () -> Void {
        return { self.bridge(source(), assign) }
    }
    func filtered(_ predicate: @escaping (V) -> Bool) -> FilteredBridge<V> {
        return .init(bridge: AnyFilter.wrap(predicate: predicate, on: bridge))
    }
    func transformed<U>(_ transform: @escaping (V) -> U) -> TransformedFilteredBridgeMaker<V, U> {
        return .init(bridge: AnyModificator.make(modificator: transform, with: bridge))
    }
}
public struct FilteredPreprocessor<V>: FilteringEntity, _ListeningMaker, PublicPreprocessor {
    public typealias OutData = V
    typealias Data = V
    internal let dataSource: () -> V
    internal let bridgeMaker: FilteredBridge<V>

    public func filter(_ predicate: @escaping (V) -> Bool) -> FilteredPreprocessor<V> {
        return FilteredPreprocessor(dataSource: dataSource, bridgeMaker: bridgeMaker.filtered(predicate))
    }

    public func map<U>(_ transform: @escaping (V) -> U) -> TransformedFilteredPreprocessor<V, U> {
        return TransformedFilteredPreprocessor(dataSource: dataSource, bridgeMaker: bridgeMaker.transformed(transform))
    }

    func onReceive(_ event: @escaping (V, Promise) -> Void) -> OnReceivePreprocessor<V, V> {
        return OnReceivePreprocessor(dataSource: dataSource, bridgeMaker: OnReceiveBridge(event: event, bridge: bridgeMaker.bridge))
    }

    func onReceiveMap<Result>(_ event: @escaping (V, ResultPromise<Result>) -> Void) -> OnReceiveMapPreprocessor<Result, V, V> {
        return OnReceiveMapPreprocessor(dataSource: dataSource, bridgeMaker: OnReceiveMapBridge(event: event, bridge: { i, assign in assign(i) }))
    }

    public func wrap(_ assign: @escaping (V) -> Void) -> AnyListening {
        return makeListening(assign)
    }
}
public struct OwnedFilteredPreprocessor<Owner: InsiderOwner, V>: InsiderAccessor, FilteringEntity, _ListeningMaker, Listenable {
    typealias Data = V
    public typealias OutData = V
    weak var insiderOwner: Owner!
    internal let dataSource: () -> V
    internal let bridgeMaker: FilteredBridge<V>

    public func filter(_ predicate: @escaping (V) -> Bool) -> OwnedFilteredPreprocessor<Owner, V> {
        return OwnedFilteredPreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, bridgeMaker: bridgeMaker.filtered(predicate))
    }

    public func map<U>(_ transform: @escaping (V) -> U) -> OwnedTransformedFilteredPreprocessor<Owner, V, U> {
        return OwnedTransformedFilteredPreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, bridgeMaker: bridgeMaker.transformed(transform))
    }

    public func onReceive(_ event: @escaping (V, Promise) -> Void) -> OwnedOnReceivePreprocessor<Owner, V, V> {
        return OwnedOnReceivePreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, bridgeMaker: OnReceiveBridge(event: event, bridge: bridgeMaker.bridge))
    }
    public func onReceiveMap<Result>(_ event: @escaping (V, ResultPromise<Result>) -> Void) -> OwnedOnReceiveMapPreprocessor<Owner, Result, V, V> {
        return OwnedOnReceiveMapPreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, bridgeMaker: OnReceiveMapBridge(event: event, bridge: bridgeMaker.bridge))
    }

    public func listening(as config: (AnyListening) -> AnyListening, _ assign: Assign<V>) -> Disposable {
        return _listening(as: config, assign)
    }
    public func listeningItem(as config: (AnyListening) -> AnyListening, _ assign: Assign<V>) -> ListeningItem {
        return _listeningItem(as: config, assign)
    }
}

public extension InsiderOwner {
    func filter(_ predicate: @escaping (T) -> Bool) -> OwnedFilteredPreprocessor<Self, T> {
        let out = OwnedPreprocessor(insiderOwner: self)
        return out.filter(predicate)
    }
    func map<U>(_ transform: @escaping (T) -> U) -> OwnedTransformedPreprocessor<Self, U> {
        let out = OwnedPreprocessor(insiderOwner: self)
        return out.map(transform)
    }
    func onReceive(_ event: @escaping (T, Promise) -> Void) -> OwnedOnReceivePreprocessor<Self, T, T> {
        let out = OwnedPreprocessor(insiderOwner: self)
        return out.onReceive(event)
    }
    func onReceiveMap<Result>(_ event: @escaping (T, ResultPromise<Result>) -> Void) -> OwnedOnReceiveMapPreprocessor<Self, Result, T, T> {
        let out = OwnedPreprocessor(insiderOwner: self)
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

public extension Insider {
	/// connects to insider of data source using specific connection
    mutating func listen<Maker: PublicPreprocessor>(
        as config: (AnyListening) -> AnyListening = { $0 },
        preprocessor: (Preprocessor<Data>) -> Maker,
        _ assign: Assign<Maker.OutData>
        ) -> ListeningToken {
        return addListening(config(preprocessor(Preprocessor(dataSource: dataSource)).wrap(assign.assign)))
    }
}
