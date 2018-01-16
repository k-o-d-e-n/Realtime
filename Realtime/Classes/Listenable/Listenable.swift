//
//  Observable.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 10/01/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation

/// -------------------------------------------------------------------

// MARK: Listening stores, disposes and items

public struct Promise {
    fileprivate let action: () -> Void

    public func fulfill() {
        action()
    }
}
public struct ResultPromise<T> {
    fileprivate let receiver: (T) -> Void

    public func fulfill(_ result: T) {
        receiver(result)
    }
}

public struct ListeningDisposeStore {
    private var disposes = [Disposable]()
    private var listeningItems = [ListeningItem]()

    public init() {}

    public mutating func add(_ stop: Disposable) {
        disposes.append(stop)
    }
    
    public mutating func add(_ item: ListeningItem) {
        listeningItems.append(item)
    }
    
    public mutating func dispose() {
        disposes.forEach { $0.dispose() }
        disposes.removeAll()
        listeningItems.forEach { $0.stop() }
        listeningItems.removeAll()
    }
    
    public func pause() {
        listeningItems.forEach { $0.stop() }
    }
    
    public func resume(_ needNotify: Bool = true) {
        listeningItems.forEach { $0.start(needNotify) }
    }

    func `deinit`() {
        disposes.forEach { $0.dispose() }
        listeningItems.forEach { $0.stop() }
    }
}

public protocol Disposable {
    var dispose: () -> Void { get }
}

struct ListeningDispose: Disposable {
    let dispose: () -> Void
    init(_ dispose: @escaping () -> Void) {
        self.dispose = dispose
    }
}

public struct ListeningItem {
    private let start: () -> Void
    public let stop: () -> Void
    let notify: () -> Void
    let isListen: () -> Bool
    
    init<Token>(start: @escaping () -> Token?, stop: @escaping (Token) -> Void, notify: @escaping () -> Void, token: Token?) {
        var tkn = token
        self.notify = notify
        self.isListen = { tkn != nil }
        self.start = {
            guard tkn == nil else { return }
            tkn = start()
        }
        self.stop = {
            guard let token = tkn else { return }
            stop(token)
            tkn = nil
        }
    }
    
    public func start(_ needNotify: Bool = true) {
        start()
        if needNotify { notify() }
    }
}
extension ListeningItem: Disposable {
    public var dispose: () -> Void { return stop }
}
public extension ListeningItem {
    init<Token>(start: @escaping (AnyListening) -> Token?, stop: @escaping (Token) -> Void, listeningToken: (Token, AnyListening)) {
        self.init(start: { return start(listeningToken.1) },
                  stop: stop,
                  notify: { listeningToken.1.sendData() },
                  token: listeningToken.0)
    }
}

public extension ListeningItem {
    @discardableResult
    func add(to store: inout ListeningDisposeStore) -> ListeningItem {
        store.add(self); return self
    }
}

public extension Disposable {
    func add(to store: inout ListeningDisposeStore) {
        store.add(self)
    }
}

// MARK: Connections

public struct Assign<A> {
    fileprivate let assign: (A) -> Void
    static public func just(_ assign: @escaping (A) -> Void) -> Assign<A> {
        return Assign(assign: assign)
    }
    static public func weak<Owner: AnyObject>(_ owner: Owner, assign: @escaping (A, Owner?) -> Void) -> Assign<A> {
        return Assign(assign: { [weak owner] v in assign(v, owner) })
    }
    static public func unowned<Owner: AnyObject>(_ owner: Owner, assign: @escaping (A, Owner) -> Void) -> Assign<A> {
        return Assign(assign: { [unowned owner] v in assign(v, owner) })
    }
    static public func guarded<Owner: AnyObject>(_ owner: Owner, assign: @escaping (A, Owner) -> Void) -> Assign<A> {
        return weak(owner) { if let o = $1 { assign($0, o) } }
    }
    static public func on(_ queue: DispatchQueue, assign: @escaping (A) -> Void) -> Assign<A> {
        return Assign(assign: { v in queue.async { assign(v) } })
    }

    public func on(queue: DispatchQueue) -> Assign<A> {
        return Assign.on(queue, assign: assign)
    }
}

fileprivate protocol BridgeMaker {
    associatedtype Data
    associatedtype OutData
    func makeBridge(with assign: @escaping (OutData) -> Void, source: @escaping () -> Data) -> () -> Void
}

extension BridgeMaker where Data == OutData {
    fileprivate func makeBridge(with assign: @escaping (OutData) -> Void, source: @escaping () -> Data) -> () -> Void {
        return { assign(source()) }
    }
    fileprivate func makeBridge(on event: @escaping (OutData, Promise) -> Void, with assign: @escaping (OutData) -> Void, source: @escaping () -> Data) -> () -> Void {
        let realBridge = makeBridge(with: assign, source: source)
        return makeBridge(on: event, bridge: realBridge, source: source)
    }
    fileprivate func makeBridge(on event: @escaping (OutData, Promise) -> Void, bridge: @escaping () -> Void, source: @escaping () -> Data) -> () -> Void {
        return { event(source(), Promise(action: bridge)) }
    }
}

fileprivate protocol ListeningMaker {
    associatedtype OutData
    associatedtype Data
    func makeListening(_ assign: @escaping (OutData) -> Void) -> AnyListening
}

struct SimpleBridgeMaker<Data>: BridgeMaker {
    typealias OutData = Data
}
fileprivate protocol _ListeningMaker: ListeningMaker {
    associatedtype Bridge: BridgeMaker
    var bridgeMaker: Bridge { get }
    var dataSource: () -> Data { get }
}
extension _ListeningMaker where Bridge.Data == Self.Data, Bridge.OutData == Self.OutData {
    fileprivate func makeListening(_ assign: @escaping (OutData) -> Void) -> AnyListening {
        return Listening(bridge: bridgeMaker.makeBridge(with: assign, source: dataSource))
    }
    fileprivate func makeListening(on event: @escaping (Data, Promise) -> Void, _ assign: @escaping (OutData) -> Void) -> AnyListening {
        let source = dataSource
        let realBridge = bridgeMaker.makeBridge(with: assign, source: source)
        return Listening(bridge: { event(source(), Promise(action: realBridge)) })
    }
}

public protocol Listenable {
    associatedtype OutData
    func listening(as config: (AnyListening) -> AnyListening, _ assign: Assign<OutData>) -> Disposable
    func listeningItem(as config: (AnyListening) -> AnyListening, _ assign: Assign<OutData>) -> ListeningItem
}
public extension Listenable {
    func listening(_ assign: Assign<OutData>) -> Disposable {
        return listening(as: { $0 }, assign)
    }
    func listeningItem(_ assign: Assign<OutData>) -> ListeningItem {
        return listeningItem(as: { $0 }, assign)
    }
    func listening(_ assign: @escaping (OutData) -> Void) -> Disposable {
        return listening(.just(assign))
    }
    func listeningItem(_ assign: @escaping (OutData) -> Void) -> ListeningItem {
        return listeningItem(.just(assign))
    }
}

extension Insider: _ListeningMaker {
    typealias OutData = D
    public typealias Data = D
    var bridgeMaker: SimpleBridgeMaker<D> { return SimpleBridgeMaker<D>() } // TODO: Avoid permanent reallocation
    public typealias ListeningToken = (token: Token, listening: AnyListening)
    fileprivate mutating func addListening(_ listening: AnyListening) -> ListeningToken {
        return (connect(with: listening), listening)
    }

    mutating public func listen(as config: (AnyListening) -> AnyListening = { $0 }, onReceive: @escaping (D, Promise) -> Void, _ assign: Assign<D>) -> ListeningToken {
        return addListening(config(makeListening(on: onReceive, assign.assign)))
    }
    mutating public func listen(as config: (AnyListening) -> AnyListening = { $0 }, _ assign: Assign<D>) -> ListeningToken {
        return addListening(config(makeListening(assign.assign)))
    }
}

public protocol InsiderOwner: class, Listenable {
    associatedtype T
    var insider: Insider<T> { get set }
}

protocol InsiderAccessor {
    associatedtype Owner: InsiderOwner
    weak var insiderOwner: Owner! { get }
}

extension InsiderAccessor where Self: _ListeningMaker {
    fileprivate func _listening(as config: (AnyListening) -> AnyListening, _ assign: Assign<OutData>) -> Disposable {
        return insiderOwner.connect(disposed: config(makeListening(assign.assign)))
    }
    fileprivate func _listeningItem(as config: (AnyListening) -> AnyListening, _ assign: Assign<OutData>) -> ListeningItem {
        return insiderOwner.connect(item: config(makeListening(assign.assign)))
    }
}

extension InsiderOwner {
    private func makeDispose(for token: Insider<T>.Token) -> ListeningDispose {
        return ListeningDispose({ [weak self] in self?.insider.disconnect(with: token) })
    }
    private func makeListeningItem(token: Insider<T>.Token, listening: AnyListening) -> ListeningItem {
        return ListeningItem(start: { [weak self] in return self?.insider.connect(with: listening) },
                             stop: { [weak self] in self?.insider.disconnect(with: $0) },
                             notify: { listening.sendData() },
                             token: token)
    }
    func connect(disposed listening: AnyListening) -> ListeningDispose {
        return makeDispose(for: insider.connect(with: listening))
    }
    func connect(item listening: AnyListening) -> ListeningItem {
        return makeListeningItem(token: insider.connect(with: listening), listening: listening)
    }

    public func listening(as config: (AnyListening) -> AnyListening, _ assign: Assign<T>) -> Disposable {
        return makeDispose(for: insider.listen(as: config, assign).token)
    }
    public func listeningItem(as config: (AnyListening) -> AnyListening, _ assign: Assign<T>) -> ListeningItem {
        let item = insider.listen(as: config, assign)
        return makeListeningItem(token: item.token, listening: item.listening)
    }
}

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
    func distinctUntilChanged(_ def: Value, comparer: @escaping (Value, Value) -> Bool) -> Filtered {
        return _distinctUntilChanged(def, comparer: comparer)
    }
    func distinctUntilChanged(comparer: @escaping (Value, Value) -> Bool) -> Filtered {
        return _distinctUntilChanged(nil, comparer: comparer)
    }
}
public extension FilteringEntity where Value: Equatable {
    func distinctUntilChanged(_ def: Value) -> Filtered {
        return distinctUntilChanged(def, comparer: { $0 != $1 })
    }
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
    fileprivate let dataSource: () -> V
    fileprivate let bridgeMaker = SimpleBridgeMaker<V>()
    
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
    fileprivate typealias Bridge = OnReceiveBridge<I, O>
    internal weak var insiderOwner: Owner!
    fileprivate let dataSource: () -> I
    fileprivate let bridgeMaker: Bridge

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
fileprivate struct OnReceiveBridge<I, O>: BridgeMaker {
    let event: (O, Promise) -> Void
    let bridge: (_ value: I, _ assign: @escaping (O) -> Void) -> Void
    fileprivate func makeBridge(with assign: @escaping (O) -> Void, source: @escaping () -> I) -> () -> Void {
        return AnyOnReceive.wrap(assign: assign, to: event, with: source, bridgeBlank: bridge)
    }
}
fileprivate struct OnReceiveMapBridge<I, O, R>: BridgeMaker {
    let event: (O, ResultPromise<R>) -> Void
    let bridge: (_ value: I, _ assign: @escaping (O) -> Void) -> Void
    fileprivate func makeBridge(with assign: @escaping (R) -> Void, source: @escaping () -> I) -> () -> Void {
        return AnyOnReceive.wrap(assign: assign, to: event, with: source, bridgeBlank: bridge)
    }
}
public struct OnReceivePreprocessor<I, O>: _ListeningMaker, PublicPreprocessor {
    public typealias OutData = O
    typealias Data = I
    fileprivate typealias Bridge = OnReceiveBridge<I, O>
    fileprivate let dataSource: () -> I
    fileprivate let bridgeMaker: Bridge

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
    fileprivate let dataSource: () -> I
    fileprivate let bridgeMaker: OnReceiveMapBridge<I, O, Result>

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
    fileprivate let dataSource: () -> I
    fileprivate let bridgeMaker: OnReceiveMapBridge<I, O, Result>

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
    fileprivate var dataSource: () -> Owner.T {
        return insiderOwner.insider.dataSource
    }
    fileprivate let bridgeMaker = SimpleBridgeMaker<Owner.T>()
    
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
    fileprivate let dataSource: () -> V
    fileprivate let bridgeMaker = SimpleBridgeMaker<V>()
    
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
    fileprivate let dataSource: () -> V
    fileprivate let bridgeMaker = SimpleBridgeMaker<V>()
    
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
    fileprivate let dataSource: () -> I
    fileprivate let bridgeMaker: TransformedFilteredBridgeMaker<I, O>
    
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
fileprivate struct TransformedFilteredBridgeMaker<I, O>: BridgeMaker {
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
    fileprivate let dataSource: () -> I
    fileprivate let bridgeMaker: TransformedFilteredBridgeMaker<I, O>
    
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

fileprivate struct FilteredBridge<V>: BridgeMaker {
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
    fileprivate let dataSource: () -> V
    fileprivate let bridgeMaker: FilteredBridge<V>
    
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
    fileprivate let dataSource: () -> V
    fileprivate let bridgeMaker: FilteredBridge<V>
    
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
    mutating func listen<Maker: PublicPreprocessor>(
        as config: (AnyListening) -> AnyListening = { $0 },
        preprocessor: (Preprocessor<Data>) -> Maker,
        _ assign: Assign<Maker.OutData>
    ) -> ListeningToken {
        return addListening(config(preprocessor(Preprocessor(dataSource: dataSource)).wrap(assign.assign)))
    }
}


// MARK: Listenings

// TODO: sendData, onStop should be private
public protocol AnyListening {
    var isInvalidated: Bool { get }
    func sendData()
    func onStop() // TODO: is not used now
}
public extension AnyListening {
    func onFire(_ todo: @escaping () -> Void) -> AnyListening {
        return OnFireListening(base: self, onFire: todo)
    }
    func once() -> AnyListening {
        return OnceListening(base: self)
    }
    func queue(_ queue: DispatchQueue) -> AnyListening {
        return ConcurrencyListening(base: self, queue: queue)
    }
    func deadline(_ time: DispatchTime) -> AnyListening {
        return DeadlineListening(base: self, deadline: time)
    }
    func livetime(_ byItem: AnyObject) -> AnyListening {
        return LivetimeListening(base: self, living: byItem)
    }
}

// TODO: Add possible to make depended listenings
struct Listening: AnyListening {
    private let bridge: () -> Void
    var isInvalidated: Bool { return false }
    init(bridge: @escaping () -> Void) {
        self.bridge = bridge
    }
    
    func sendData() {
        bridge()
    }
    
    func onStop() {}
}

struct OnFireListening: AnyListening {
    private let listening: AnyListening
    private let onFire: () -> Void
    var isInvalidated: Bool { return listening.isInvalidated }

    init(base: AnyListening, onFire: @escaping () -> Void) {
        self.listening = base
        self.onFire = onFire
    }

    func sendData() {
        listening.sendData()
    }

    func onStop() {
        listening.onStop()
        onFire()
    }
}

struct OnceListening: AnyListening {
    private let listening: AnyListening
    var isInvalidated: Bool { return true }
    init(base: AnyListening) {
        self.listening = base
    }
    
    func sendData() {
        listening.sendData()
    }
    
    func onStop() {
        listening.onStop()
    }
}

// TODO: Only value sent in specific queue, but assigning can happened in other queue (when use `onReceive` preprocessor)
struct ConcurrencyListening: AnyListening {
    private let listening: AnyListening
    private let queue: DispatchQueue
    var isInvalidated: Bool { return listening.isInvalidated }
    
    init(base: AnyListening, queue: DispatchQueue) {
        self.listening = base
        self.queue = queue
    }
    
    func sendData() {
        queue.async { self.listening.sendData() }
    }
    
    func onStop() {
        listening.onStop()
    }
}

struct DeadlineListening: AnyListening {
    private let listening: AnyListening
    private let deadline: DispatchTime
    private var _isInvalidated: Bool { return deadline <= .now() }
    var isInvalidated: Bool { return listening.isInvalidated || _isInvalidated }

    init(base: AnyListening, deadline: DispatchTime) {
        self.listening = base
        self.deadline = deadline
    }

    func sendData() {
        guard !isInvalidated else { return }

        listening.sendData()
    }

    func onStop() {
        listening.onStop()
    }
}

struct LivetimeListening: AnyListening {
    private let listening: AnyListening
    private weak var livingItem: AnyObject?
    private var _isInvalidated: Bool { return livingItem == nil }
    var isInvalidated: Bool { return listening.isInvalidated || _isInvalidated }

    init(base: AnyListening, living: AnyObject) {
        self.listening = base
        self.livingItem = living
    }

    func sendData() {
        guard !isInvalidated else { return }

        listening.sendData()
    }

    func onStop() {
        listening.onStop()
    }
}

public struct Insider<D> {
    public typealias Token = Int
    fileprivate let dataSource: () -> D
    private var listeners = [Token: AnyListening]()
    private var nextToken: Token = Token.min
    
    public init(source: @escaping () -> D) {
        dataSource = source
    }

    mutating func dataDidChange() {
        let lstnrs = listeners
        lstnrs.forEach { (key: Token, value: AnyListening) in
            value.sendData()
            guard value.isInvalidated else { return }
            
            disconnect(with: key)
        }
    }
    
    public mutating func connect<L: AnyListening>(with listening: L) -> Token {
        return connect(with: listening)
    }
    
    public mutating func connect(with listening: AnyListening) -> Token {
        defer { nextToken += 1 }
        
        listeners[nextToken] = listening
        
        return nextToken
    }
    
    public func has(token: Token) -> Bool {
        return listeners.contains { $0.key == token }
    }
    
    public mutating func disconnect(with token: Token, callOnStop call: Bool = true) {
        if let listener = listeners.removeValue(forKey: token), call {
            listener.onStop()
        }
    }
}

public extension Insider {
    func mapped<Other>(_ map: @escaping (D) -> Other) -> Insider<Other> {
        let source = dataSource
        return Insider<Other>(source: { map(source()) })
    }
}

public struct ReadonlyProperty<Value> {
    public lazy var insider: Insider<Value> = Insider(source: self.concreteValue.get)
    fileprivate let concreteValue: PropertyValue<Value>
    fileprivate(set) var value: Value {
        get { return concreteValue.get() }
        set { concreteValue.set(newValue); insider.dataDidChange() }
    }
    private let getter: () -> Value
    
    init(value: Value, getter: @escaping () -> Value) {
        self.getter = getter
        concreteValue = PropertyValue(value)
    }
    
    public init(getter: @escaping () -> Value) {
        self.init(value: getter(), getter: getter)
    }
    
    mutating func fetch() {
        value = getter()
    }
}

public struct AsyncReadonlyProperty<Value> {
    public var insider: Insider<Value> {
        get { return concreteValue.getInsider() }
        set { concreteValue.setInsider(newValue) }
    }
    private let concreteValue: ListenableValue<Value>
    private(set) var value: Value {
        get { return concreteValue.get() }
        set { concreteValue.set(newValue); }
    }
    private let getter: (@escaping (Value) -> Void) -> Void
    
    public init(value: Value, getter: @escaping (@escaping (Value) -> Void) -> Void) {
        self.getter = getter
        concreteValue = ListenableValue(value)
    }
    
    public mutating func fetch() {
        getter(concreteValue.set)
    }
}

public extension AsyncReadonlyProperty {
    @discardableResult
    mutating func fetch(`if` itRight: (Value) -> Bool) -> AsyncReadonlyProperty {
        guard itRight(value) else { return self }
        
        fetch()
        
        return self
    }
}

struct PropertyValue<T> {
    let get: () -> T
    let set: (T) -> Void
    
    init(_ value: T) {
        var val = value// {
//            didSet {
//                print(oldValue)
//            }
//        }
        get = { val }
        set = { val = $0 }
    }

    init<O: AnyObject>(unowned owner: O, getter: @escaping (O) -> T, setter: @escaping (O, T) -> Void) {
        get = { [unowned owner] in return getter(owner) }
        set = { [unowned owner] in setter(owner, $0) }
    }
}

struct WeakPropertyValue<T> where T: AnyObject {
    let get: () -> T?
    let set: (T?) -> Void

    init(_ value: T?) {
        weak var val = value// {
        //            didSet {
        //                print(oldValue)
        //            }
        //        }
        get = { val }
        set = { val = $0 }
    }
}

//struct _NativeListenableValue<T> {
//    let get: () -> T
//    let set: (T) -> Void
//
//    var insider: Insider<T> {
//        get { return getInsider() }
//        set { setInsider(newValue) }
//    }
//    let getInsider: () -> Insider<T>
//    let setInsider: (Insider<T>) -> Void
//
//    init(_ value: T) {
//        var val = value {
//            didSet { self.insider.dataDidChanged() }
//        }
//        self.get = { val }
//        self.set = { val = $0 }
//
//        var insider = Insider(source: get)
//        getInsider = { insider }
//        setInsider = { insider = $0 }
//    }
//}
struct NativeListenableValue<T> {
    let get: () -> T
    let set: (T) -> Void
    //    var insider: Insider<T>

    init(_ value: T, _ observer: @escaping (T, T) -> Void) {
        var val = value {
            didSet { observer(oldValue, val) }
        }
        self.get = { val }
        //        self.insider = Insider(source: get)
        self.set = { val = $0 }
    }

    private func dataDidChange() {
        
    }
}

struct ListenableValue<T> {
    let get: () -> T
    let set: (T) -> Void
//    let setWithoutNotify: (T) -> Void
    let getInsider: () -> Insider<T>
    let setInsider: (Insider<T>) -> Void
    
    init(_ value: T) {
        var val = value
        get = { val }
        var insider = Insider(source: get)
        set = { val = $0; insider.dataDidChange(); }
//        setWithoutNotify = { val = $0 }
        getInsider = { insider }
        setInsider = { insider = $0 }
    }
}

extension ListenableValue {
    var insider: Insider<T> {
        get { return getInsider() }
        set { setInsider(newValue) }
    }
}

public protocol ValueWrapper {
    associatedtype T
    var value: T { get set }
}

postfix operator ~
public extension ValueWrapper {
    static func <=(_ prop: inout Self, _ value: T) {
        prop.value = value
    }
    static func <=(_ value: inout T, _ prop: Self) {
        value = prop.value
    }
    postfix static func ~(_ prop: inout Self) -> T {
        return prop.value
    }
}

public struct Property<Value>: ValueWrapper {
    lazy public var insider: Insider<Value> = Insider(source: self.concreteValue.get)
    fileprivate let concreteValue: PropertyValue<Value>
    public var value: Value {
        get { return concreteValue.get() }
        set { concreteValue.set(newValue); insider.dataDidChange() }
    }
    
    public init(value: Value) {
        self.init(PropertyValue(value))
    }

    init(_ value: PropertyValue<Value>) {
        self.concreteValue = value
    }
}

// TODO: Create common protocol for Properties
public extension Property {
    /// Subscribing to values from other property
    ///
    /// - Parameter other: Property as source values
    /// - Returns: Listening token
    func bind(to other: inout Property<Value>) -> Insider<Value>.ListeningToken { // TODO: Not notify subscribers about receiving new value.
        return other.insider.listen(.just(concreteValue.set))
    }
}

public extension ReadonlyProperty {
    mutating func setter(_ value: Value) -> Void { self.value = value }

    mutating func bind(to other: inout Property<Value>) -> Insider<Value>.ListeningToken { // TODO: Not notify subscribers about receiving new value.
        return other.insider.listen(.just(concreteValue.set))
    }
}

public extension InsiderOwner {
    /// Makes notification depending
    ///
    /// - Parameter other: Insider owner that will be invoke notifications himself listenings
    /// - Returns: Listening token
    @discardableResult
    func depends<Other: InsiderOwner>(on other: Other) -> Disposable {
        return other.listening(as: { $0.livetime(self) }, .weak(self) { _, owner in owner?.insider.dataDidChange() })
    }

    /// Binds values new values to value wrapper
    ///
    /// - Parameter other: Insider owner that will be invoke notifications himself listenings
    /// - Returns: Listening token
    @discardableResult
    func bind<Other: AnyObject & ValueWrapper>(to other: Other) -> Disposable where Other.T == Self.T {
        return listening(as: { $0.livetime(other) }, .just { [weak other] v in other?.value = v })
    }
}

///// Attempt create primitive value, property where value will be copied

struct Primitive<T> {
    let get: () -> T
    let set: (T) -> Void
    
    init(_ value: T) {
        var val = value
        let pointer = UnsafeMutablePointer(&val)
        get = { val }
        set = { pointer.pointee = $0 }
    }
}

struct PrimitiveValue<T> {
    fileprivate var getter: (_ owner: PrimitiveValue<T>) -> T
    private var setter: (_ owner: inout PrimitiveValue<T>, _ value: T) -> Void
    private var value: T
    
    func get() -> T {
        return getter(self)
    }
    
    mutating func set(_ val: T) {
        setter(&self, val)
    }
    
    init(_ value: T) {
        self.value = value
        setter = { $0.value = $1 }
//        let pointer = UnsafeMutablePointer<PrimitiveValue<T>>(&self)
        getter = { $0.value }
    }
    
    func `deinit`() {
        // hidden possibillity
    }
}

struct PrimitiveProperty<Value>: ValueWrapper {
    lazy var insider: Insider<Value> = Insider(source: self.concreteValue.get) // 'get' implicitly took concreteValue, and returned always one value
    private var concreteValue: PrimitiveValue<Value>
    var value: Value {
        get { return concreteValue.get() }
        set { concreteValue.set(newValue); insider.dataDidChange() }
    }
    
    init(value: Value) {
        concreteValue = PrimitiveValue(value)
    }
}

// MARK: System type extensions

// TODO: Add extension for all types with var asProperty, asRealtimeProperty
extension String {
    var asProperty: Property<String> { return Property(value: self) }
}

// MARK: Not used yet or unsuccessful attempts

protocol AnyInsider {
    associatedtype Data
    associatedtype Token
    var dataSource: () -> Data { get }
    mutating func connect(with listening: AnyListening) -> Token
}

protocol Modificator {
    associatedtype In
    associatedtype Out
    func make(with original: @escaping () -> In) -> () -> Out
    func make(with assign: @escaping (Out) -> Void) -> (In) -> Void
}

protocol Filter {
    associatedtype Evaluated
    func wrap(receiver: @escaping (Evaluated) -> Void) -> (Evaluated) -> Void
    func wrap(source: @escaping () -> Evaluated) -> ((Evaluated) -> Void) -> Void
}

enum Packet<Value> {
    case value(Value)
}
