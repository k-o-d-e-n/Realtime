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

struct Promise {
    fileprivate let action: () -> Void

    func fulfill() {
        action()
    }
}
struct ResultPromise<T> {
    fileprivate let receiver: (T) -> Void

    func fulfill(_ result: T) {
        receiver(result)
    }
}

struct ListeningDisposeStore {
    private var disposes = [Disposable]()
    private var listeningItems = [ListeningItem]()
    
    mutating func add(_ stop: Disposable) {
        disposes.append(stop)
    }
    
    mutating func add(_ item: ListeningItem) {
        listeningItems.append(item)
    }
    
    mutating func dispose() {
        disposes.forEach { $0.dispose() }
        disposes.removeAll()
        listeningItems.forEach { $0.stop() }
        listeningItems.removeAll()
    }
    
    func pause() {
        listeningItems.forEach { $0.stop() }
    }
    
    func resume(_ needNotify: Bool = true) {
        listeningItems.forEach { $0.start(needNotify) }
    }

    func `deinit`() {
        disposes.forEach { $0.dispose() }
        listeningItems.forEach { $0.stop() }
    }
}

protocol Disposable {
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
    let stop: () -> Void
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
    
    func start(_ needNotify: Bool = true) {
        start()
        if needNotify { notify() }
    }
}
extension ListeningItem: Disposable {
    var dispose: () -> Void { return stop }
}
extension ListeningItem {
    init<Token>(start: @escaping (AnyListening) -> Token?, stop: @escaping (Token) -> Void, listeningToken: (Token, AnyListening)) {
        self.init(start: { return start(listeningToken.1) },
                  stop: stop,
                  notify: { listeningToken.1.sendData() },
                  token: listeningToken.0)
    }
}

extension ListeningItem {
    @discardableResult
    func add(to store: inout ListeningDisposeStore) -> ListeningItem {
        store.add(self); return self
    }
}

extension ListeningDispose {
    @discardableResult
    func add(to store: inout ListeningDisposeStore) -> ListeningDispose {
        store.add(self); return self
    }
}

// MARK: Connections

//fileprivate protocol LOwner {
//    associatedtype Assigned
//    func makeBridge<T>(with assign: @escaping (T, Assigned) -> Void, source: @escaping () -> T) -> () -> Void
//    func wrap<T>(assign: @escaping (T, Assigned) -> Void) -> (T) -> Void
//}
//struct ListeningOwner<O: AnyObject, Assigned>: LOwner {
//    struct AnyOwner<Assigned>: LOwner {
//        let base: Base
//
//        func makeBridge<T>(with assign: @escaping (T, Assigned) -> Void, source: @escaping () -> T) -> () -> Void {
//            return base.makeBridge(with: assign, source: source)
//        }
//        func wrap<T>(assign: @escaping (T, Assigned) -> Void) -> (T) -> Void {
//            return base.wrap(assign: assign)
//        }
//    }
//    let builder: AnyOwner<>
//
//    func makeBridge<T>(with assign: @escaping (T, Assigned) -> Void, source: @escaping () -> T) -> () -> Void {
//        return bridging(assign, source)
//    }
//    func wrap<T>(assign: @escaping (T, Assigned) -> Void) -> (T) -> Void {
//        return wrap(assign)
//    }
//    static func unowned(_ owner: O) -> ListeningOwner<O, O> { return ListeningOwner(owner: owner, builder: Unowned()) }
//    struct Unowned: LOwner {
//        private var owner: O
//
//        func makeBridge<T>(with assign: @escaping (T, O) -> Void, source: @escaping () -> T) -> () -> Void {
//            return { [unowned owner] in assign(source(), owner) }
//        }
//        func wrap<T>(assign: @escaping (T, O) -> Void) -> (T) -> Void {
//            return { [unowned owner] v in assign(v, owner) }
//        }
//    }
//    static func weak(_ owner: O) -> ListeningOwner<O, O?> { return ListeningOwner(owner: owner, builder: Weak()) }
//    struct Weak: LOwner {
//        private var owner: O
//
//        func makeBridge<T>(with assign: @escaping (T, O?) -> Void, source: @escaping () -> T) -> () -> Void {
//            return { [weak owner] in assign(source(), owner) }
//        }
//        func wrap<T>(assign: @escaping (T, O?) -> Void) -> (T) -> Void {
//            return { [weak owner] v in assign(v, owner) }
//        }
//    }
//}

enum ListeningOwner<O: AnyObject> {
    //    case none
    case weak(O), unowned(O)
    
    // TODO: For unowned not must have optional wrapper
    func makeBridge<T>(with assign: @escaping (T, O?) -> Void, source: @escaping () -> T) -> () -> Void {
        switch self {
            //        case .none:
        //            return { assign(source(), nil) }
        case .weak(let owner):
            return { [weak owner] in assign(source(), owner) }
        case .unowned(let owner):
            return { [unowned owner] in assign(source(), owner) }
        }
    }
    
    func wrap<T>(assign: @escaping (T, O?) -> Void) -> (T) -> Void {
        switch self {
        case .weak(let owner):
            return { [weak owner] v in assign(v, owner) }
        case .unowned(let owner):
            return { [unowned owner] v in assign(v, owner) }
        }
    }
}

internal protocol BridgeMaker {
    associatedtype Data
    associatedtype OutData
    func makeBridge(with assign: @escaping (OutData) -> Void, source: @escaping () -> Data) -> () -> Void
    func makeBridge<Owner>(owner: ListeningOwner<Owner>, with assign: @escaping (OutData, Owner?) -> Void, source: @escaping () -> Data) -> () -> Void
}

extension BridgeMaker where Data == OutData {
    internal func makeBridge<Owner>(owner: ListeningOwner<Owner>, with assign: @escaping (OutData, Owner?) -> Void, source: @escaping () -> Data) -> () -> Void {
        return owner.makeBridge(with: assign, source: source)
    }
}

internal protocol ListeningMaker: BridgeMaker {
    func makeListening(_ assign: @escaping (OutData) -> Void) -> AnyListening
    func makeListening<O>(owner: ListeningOwner<O>, assign: @escaping (OutData, O?) -> Void) -> AnyListening
}

extension ListeningMaker {
    internal func makeBridge<OutData>(with assign: @escaping (OutData) -> Void, source: @escaping () -> Data) -> () -> Void where OutData == Data {
        return { assign(source()) }
    }
    internal func makeBridge<OutData>(on event: @escaping (OutData, Promise) -> Void, with assign: @escaping (OutData) -> Void, source: @escaping () -> Data) -> () -> Void where OutData == Data {
        let realBridge = makeBridge(with: assign, source: source)
        return makeBridge(on: event, bridge: realBridge, source: source)
    }
    internal func makeBridge<OutData>(on event: @escaping (OutData, Promise) -> Void, bridge: @escaping () -> Void, source: @escaping () -> Data) -> () -> Void where OutData == Data {
        return { event(source(), Promise(action: bridge)) }
    }
}
fileprivate protocol _ListeningMaker: ListeningMaker {
    var dataSource: () -> Data { get }
}
extension _ListeningMaker {
    internal func makeListening(_ assign: @escaping (OutData) -> Void) -> AnyListening {
        return Listening(bridge: makeBridge(with: assign, source: dataSource))
    }
    internal func makeListening(on event: @escaping (Data, Promise) -> Void, _ assign: @escaping (OutData) -> Void) -> AnyListening {
        let source = dataSource
        let realBridge = makeBridge(with: assign, source: source)
        return Listening(bridge: { event(source(), Promise(action: realBridge)) })
    }
    internal func makeListening<O>(owner: ListeningOwner<O>, assign: @escaping (OutData, O?) -> Void) -> AnyListening {
        return Listening(bridge: makeBridge(owner: owner, with: assign, source: dataSource))
    }
}

extension Insider: _ListeningMaker {
    typealias OutData = Data
    typealias ListeningToken = (token: Token, listening: AnyListening)
    fileprivate mutating func addListening(_ listening: AnyListening) -> ListeningToken {
        return (connect(with: listening), listening)
    }

    mutating func listen(as config: (AnyListening) -> AnyListening = { $0 }, onReceive: @escaping (Data, Promise) -> Void, _ assign: @escaping (Data) -> Void) -> ListeningToken {
        return addListening(config(makeListening(on: onReceive, assign)))
    }
    mutating func listen(as config: (AnyListening) -> AnyListening = { $0 }, _ assign: @escaping (Data) -> Void) -> ListeningToken {
        return addListening(config(makeListening(assign)))
    }
    mutating func listen<O>(as config: (AnyListening) -> AnyListening = { $0 }, owner: ListeningOwner<O>, _ assign: @escaping (Data, O?) -> Void) -> ListeningToken {
        return addListening(config(makeListening(owner: owner, assign: assign)))
    }
}

public protocol InsiderOwner: class {
    associatedtype T
    var insider: Insider<T> { get set }
}

protocol InsiderAccessor {
    associatedtype Owner: InsiderOwner
    weak var insiderOwner: Owner! { get }
}

extension InsiderAccessor where Self: ListeningMaker {
    func listening(as config: (AnyListening) -> AnyListening = { $0 }, _ assign: @escaping (OutData) -> Void) -> ListeningDispose {
        return insiderOwner.connect(disposed: config(makeListening(assign)))
    }
    func listening<O>(as config: (AnyListening) -> AnyListening = { $0 }, owner: ListeningOwner<O>, _ assign: @escaping (OutData, O?) -> Void) -> ListeningDispose {
        return insiderOwner.connect(disposed: config(makeListening(owner: owner, assign: assign)))
    }
    func listeningItem(as config: (AnyListening) -> AnyListening = { $0 }, _ assign: @escaping (OutData) -> Void) -> ListeningItem {
        return insiderOwner.connect(item: config(makeListening(assign)))
    }
    func listeningItem<O>(as config: (AnyListening) -> AnyListening = { $0 }, owner: ListeningOwner<O>, _ assign: @escaping (OutData, O?) -> Void) -> ListeningItem {
        return insiderOwner.connect(item: config(makeListening(owner: owner, assign: assign)))
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

    func listening(as config: (AnyListening) -> AnyListening = { $0 }, _ assign: @escaping (T) -> Void) -> ListeningDispose {
        return makeDispose(for: insider.listen(as: config, assign).token)
    }
    func listening<O>(as config: (AnyListening) -> AnyListening = { $0 }, owner: ListeningOwner<O>, _ assign: @escaping (T, O?) -> Void) -> ListeningDispose {
        return makeDispose(for: insider.listen(as: config, owner: owner, assign).token)
    }
    func listeningItem(as config: (AnyListening) -> AnyListening = { $0 }, _ assign: @escaping (T) -> Void) -> ListeningItem {
        let item = insider.listen(as: config, assign)
        return makeListeningItem(token: item.token, listening: item.listening)
    }
    func listeningItem<O>(as config: (AnyListening) -> AnyListening = { $0 }, owner: ListeningOwner<O>, _ assign: @escaping (T, O?) -> Void) -> ListeningItem {
        let item = insider.listen(as: config, owner: owner, assign)
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

protocol FilteringEntity {
    associatedtype Value
    associatedtype Filtered
    func filter(_ predicate: @escaping (Value) -> Bool) -> Filtered
}
extension FilteringEntity {
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
extension FilteringEntity where Value: Equatable {
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
struct Preprocessor<V>: FilteringEntity, _ListeningMaker {
    typealias OutData = V
    fileprivate let dataSource: () -> V
    
    func filter(_ predicate: @escaping (V) -> Bool) -> FilteredPreprocessor<V> {
        return FilteredPreprocessor(dataSource: dataSource, bridge: AnyFilter.wrap(predicate: predicate))
    }
    
    func map<U>(_ transform: @escaping (V) -> U) -> TransformedPreprocessor<U> {
        return TransformedPreprocessor(dataSource: AnyModificator.make(modificator: transform, with: dataSource))
    }

    func onReceive(_ event: @escaping (V, Promise) -> Void) -> OnReceivePreprocessor<V, V> {
        return OnReceivePreprocessor(dataSource: dataSource, event: event, bridge: { i, assign in assign(i) })
    }

    func onReceiveMap<O>(_ event: @escaping (V, ResultPromise<O>) -> Void) -> OnReceiveMapPreprocessor<O, V, V> {
        return OnReceiveMapPreprocessor(dataSource: dataSource, event: event, bridge: { i, assign in assign(i) })
    }
}
// TODO: Add `onReceive` with map value (url -> data)
struct OwnedOnReceivePreprocessor<Owner: InsiderOwner, I, O>: InsiderAccessor, _ListeningMaker {
    typealias OutData = O
    weak var insiderOwner: Owner!
    fileprivate var dataSource: () -> I
    fileprivate let event: (O, Promise) -> Void
    fileprivate let bridge: (_ value: I, _ assign: @escaping (O) -> Void) -> Void


    func filter(_ predicate: @escaping (O) -> Bool) -> OwnedTransformedFilteredPreprocessor<Owner, I, O> {
        let bridge = AnyFilter.wrap(predicate: predicate, on: AnyOnReceive.wrap(bridgeBlank: self.bridge, to: event))
        return OwnedTransformedFilteredPreprocessor(insiderOwner: insiderOwner,
                                                    dataSource: dataSource,
                                                    bridge: bridge)
    }

    func map<U>(_ transform: @escaping (O) -> U) -> OwnedTransformedFilteredPreprocessor<Owner, I, U> {
        let bridge = AnyModificator.make(modificator: transform, with: AnyOnReceive.wrap(bridgeBlank: self.bridge, to: event))
        return OwnedTransformedFilteredPreprocessor<Owner, I, U>(insiderOwner: insiderOwner,
                                                                 dataSource: dataSource,
                                                                 bridge: bridge)
    }

    internal func makeBridge(with assign: @escaping (O) -> Void, source: @escaping () -> I) -> () -> Void {
        return AnyOnReceive.wrap(assign: assign, to: event, with: source, bridgeBlank: bridge)
    }

    internal func makeBridge<Owner>(owner: ListeningOwner<Owner>, with assign: @escaping (O, Owner?) -> Void, source: @escaping () -> I) -> () -> Void {
        return makeBridge(with: owner.wrap(assign: assign), source: source)
    }
}
struct OnReceivePreprocessor<I, O>: _ListeningMaker {
    typealias OutData = O
    fileprivate var dataSource: () -> I
    fileprivate let event: (O, Promise) -> Void
    fileprivate let bridge: (_ value: I, _ assign: @escaping (O) -> Void) -> Void

    func filter(_ predicate: @escaping (O) -> Bool) -> TransformedFilteredPreprocessor<I, O> {
        let bridge = AnyFilter.wrap(predicate: predicate, on: AnyOnReceive.wrap(bridgeBlank: self.bridge, to: event))
        return TransformedFilteredPreprocessor(dataSource: dataSource, bridge: bridge)
    }

    func map<U>(_ transform: @escaping (O) -> U) -> TransformedFilteredPreprocessor<I, U> {
        let bridge = AnyModificator.make(modificator: transform, with: AnyOnReceive.wrap(bridgeBlank: self.bridge, to: event))
        return TransformedFilteredPreprocessor(dataSource: dataSource, bridge: bridge)
    }

    internal func makeBridge(with assign: @escaping (O) -> Void, source: @escaping () -> I) -> () -> Void {
        return AnyOnReceive.wrap(assign: assign, to: event, with: source, bridgeBlank: bridge)
    }

    internal func makeBridge<Owner>(owner: ListeningOwner<Owner>, with assign: @escaping (O, Owner?) -> Void, source: @escaping () -> I) -> () -> Void {
        return makeBridge(with: owner.wrap(assign: assign), source: source)
    }
}
struct OnReceiveMapPreprocessor<Result, I, O>: _ListeningMaker {
    typealias OutData = Result
    fileprivate var dataSource: () -> I
    fileprivate let event: (O, ResultPromise<Result>) -> Void
    fileprivate let bridge: (_ value: I, _ assign: @escaping (O) -> Void) -> Void

    func filter(_ predicate: @escaping (Result) -> Bool) -> TransformedFilteredPreprocessor<I, Result> {
        let bridge = AnyFilter.wrap(predicate: predicate, on: AnyOnReceive.wrap(bridgeBlank: self.bridge, to: event))
        return TransformedFilteredPreprocessor(dataSource: dataSource, bridge: bridge)
    }

    func map<U>(_ transform: @escaping (Result) -> U) -> TransformedFilteredPreprocessor<I, U> {
        let bridge = AnyModificator.make(modificator: transform, with: AnyOnReceive.wrap(bridgeBlank: self.bridge, to: event))
        return TransformedFilteredPreprocessor(dataSource: dataSource, bridge: bridge)
    }

    internal func makeBridge(with assign: @escaping (Result) -> Void, source: @escaping () -> I) -> () -> Void {
        return AnyOnReceive.wrap(assign: assign, to: event, with: source, bridgeBlank: bridge)
    }

    internal func makeBridge<Owner>(owner: ListeningOwner<Owner>, with assign: @escaping (Result, Owner?) -> Void, source: @escaping () -> I) -> () -> Void {
        return makeBridge(with: owner.wrap(assign: assign), source: source)
    }
}
struct OwnedOnReceiveMapPreprocessor<Owner: InsiderOwner, Result, I, O>: InsiderAccessor, _ListeningMaker {
    typealias OutData = Result
    weak var insiderOwner: Owner!
    fileprivate var dataSource: () -> I
    fileprivate let event: (O, ResultPromise<Result>) -> Void
    fileprivate let bridge: (_ value: I, _ assign: @escaping (O) -> Void) -> Void

    func filter(_ predicate: @escaping (Result) -> Bool) -> TransformedFilteredPreprocessor<I, Result> {
        let bridge = AnyFilter.wrap(predicate: predicate, on: AnyOnReceive.wrap(bridgeBlank: self.bridge, to: event))
        return TransformedFilteredPreprocessor(dataSource: dataSource, bridge: bridge)
    }

    func map<U>(_ transform: @escaping (Result) -> U) -> TransformedFilteredPreprocessor<I, U> {
        let bridge = AnyModificator.make(modificator: transform, with: AnyOnReceive.wrap(bridgeBlank: self.bridge, to: event))
        return TransformedFilteredPreprocessor(dataSource: dataSource, bridge: bridge)
    }

    internal func makeBridge(with assign: @escaping (Result) -> Void, source: @escaping () -> I) -> () -> Void {
        return AnyOnReceive.wrap(assign: assign, to: event, with: source, bridgeBlank: bridge)
    }

    internal func makeBridge<Owner>(owner: ListeningOwner<Owner>, with assign: @escaping (Result, Owner?) -> Void, source: @escaping () -> I) -> () -> Void {
        return makeBridge(with: owner.wrap(assign: assign), source: source)
    }
}
struct OwnedPreprocessor<Owner: InsiderOwner>: InsiderAccessor, FilteringEntity, _ListeningMaker {
    typealias Data = Owner.T
    typealias OutData = Owner.T
    weak var insiderOwner: Owner!
    fileprivate var dataSource: () -> Owner.T {
        return insiderOwner.insider.dataSource
    }
    
    func filter(_ predicate: @escaping (Owner.T) -> Bool) -> OwnedFilteredPreprocessor<Owner, Owner.T> {
        return OwnedFilteredPreprocessor(insiderOwner: insiderOwner, dataSource: insiderOwner.insider.dataSource, bridge: AnyFilter.wrap(predicate: predicate))
    }
    
    func map<U>(_ transform: @escaping (Owner.T) -> U) -> OwnedTransformedPreprocessor<Owner, U> {
        return OwnedTransformedPreprocessor<Owner, U>(insiderOwner: insiderOwner, dataSource: AnyModificator.make(modificator: transform, with: dataSource))
    }

    func onReceive(_ event: @escaping (Owner.T, Promise) -> Void) -> OwnedOnReceivePreprocessor<Owner, Owner.T, Owner.T> {
        return OwnedOnReceivePreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, event: event, bridge: { i, assign in assign(i) })
    }

    func onReceiveMap<O>(_ event: @escaping (Owner.T, ResultPromise<O>) -> Void) -> OwnedOnReceiveMapPreprocessor<Owner, O, Owner.T, Owner.T> {
        return OwnedOnReceiveMapPreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, event: event, bridge: { i, assign in assign(i) })
    }
}

struct TransformedPreprocessor<V>: FilteringEntity, _ListeningMaker {
    typealias OutData = V
    fileprivate let dataSource: () -> V
    
    func filter(_ predicate: @escaping (V) -> Bool) -> FilteredPreprocessor<V> {
        return FilteredPreprocessor(dataSource: dataSource, bridge: AnyFilter.wrap(predicate: predicate))
    }
    
    func map<U>(_ transform: @escaping (V) -> U) -> TransformedPreprocessor<U> {
        return TransformedPreprocessor<U>(dataSource: AnyModificator.make(modificator: transform, with: dataSource))
    }

    func onReceive(_ event: @escaping (V, Promise) -> Void) -> OnReceivePreprocessor<V, V> {
        return OnReceivePreprocessor(dataSource: dataSource, event: event, bridge: { i, assign in assign(i) })
    }

    func onReceiveMap<Result>(_ event: @escaping (V, ResultPromise<Result>) -> Void) -> OnReceiveMapPreprocessor<Result, V, V> {
        return OnReceiveMapPreprocessor(dataSource: dataSource, event: event, bridge: { i, assign in assign(i) })
    }
}
struct OwnedTransformedPreprocessor<Owner: InsiderOwner, V>: InsiderAccessor, FilteringEntity, _ListeningMaker {
    typealias OutData = V
    weak var insiderOwner: Owner!
    fileprivate let dataSource: () -> V
    
    func filter(_ predicate: @escaping (V) -> Bool) -> OwnedFilteredPreprocessor<Owner, V> {
        return OwnedFilteredPreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, bridge: AnyFilter.wrap(predicate: predicate))
    }
    
    func map<U>(_ transform: @escaping (V) -> U) -> OwnedTransformedPreprocessor<Owner, U> {
        return OwnedTransformedPreprocessor<Owner, U>(insiderOwner: insiderOwner, dataSource: AnyModificator.make(modificator: transform, with: dataSource))
    }

    func onReceive(_ event: @escaping (V, Promise) -> Void) -> OwnedOnReceivePreprocessor<Owner, V, V> {
        return OwnedOnReceivePreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, event: event, bridge: { i, assign in assign(i) })
    }
    func onReceiveMap<O>(_ event: @escaping (V, ResultPromise<O>) -> Void) -> OwnedOnReceiveMapPreprocessor<Owner, O, V, V> {
        return OwnedOnReceiveMapPreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, event: event, bridge: { i, assign in assign(i) })
    }
}

struct TransformedFilteredPreprocessor<I, O>: FilteringEntity, _ListeningMaker {
    typealias OutData = O
    fileprivate let dataSource: () -> I
    fileprivate let bridge: (_ value: I, _ assign: @escaping (O) -> Void) -> Void
    
    /// filter for value from this source, but this behavior illogical, therefore it use not recommended
//    func filter(_ predicate: @escaping (I) -> Bool) -> TransformedFilteredPreprocessor<I, O> {
//        return TransformedFilteredPreprocessor(dataSource: dataSource, bridge: AnyFilter.wrap(predicate: predicate, on: bridge))
//    }

    func filter(_ predicate: @escaping (O) -> Bool) -> TransformedFilteredPreprocessor<I, O> {
        return TransformedFilteredPreprocessor(dataSource: dataSource, bridge: AnyFilter.wrap(predicate: predicate, on: bridge))
    }
    
    func map<U>(_ transform: @escaping (O) -> U) -> TransformedFilteredPreprocessor<I, U> {
        let bridge = AnyModificator.make(modificator: transform, with: self.bridge)
        return TransformedFilteredPreprocessor<I, U>(dataSource: dataSource, bridge: bridge)
    }

    func onReceive(_ event: @escaping (O, Promise) -> Void) -> OnReceivePreprocessor<I, O> {
        return OnReceivePreprocessor(dataSource: dataSource, event: event, bridge: bridge)
    }

    func onReceiveMap<Result>(_ event: @escaping (O, ResultPromise<Result>) -> Void) -> OnReceiveMapPreprocessor<Result, I, O> {
        return OnReceiveMapPreprocessor(dataSource: dataSource, event: event, bridge: bridge)
    }

    internal func makeBridge(with assign: @escaping (O) -> Void, source: @escaping () -> I) -> () -> Void {
        return { self.bridge(source(), assign) }
    }
    
    internal func makeBridge<Owner>(owner: ListeningOwner<Owner>, with assign: @escaping (O, Owner?) -> Void, source: @escaping () -> I) -> () -> Void {
        return makeBridge(with: owner.wrap(assign: assign), source: source)
    }
}
struct OwnedTransformedFilteredPreprocessor<Owner: InsiderOwner, I, O>: InsiderAccessor, FilteringEntity, _ListeningMaker {
    typealias OutData = O
    weak var insiderOwner: Owner!
    fileprivate let dataSource: () -> I
    fileprivate let bridge: (_ value: I, _ assign: @escaping (O) -> Void) -> Void
    
    /// filter for value from this source, but this behavior illogical, therefore it use not recommended
//    func filter(_ predicate: @escaping (I) -> Bool) -> OwnedTransformedFilteredPreprocessor<Owner, I, O> {
//        return OwnedTransformedFilteredPreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, bridge: AnyFilter.wrap(predicate: predicate, on: bridge))
//    }

    func filter(_ predicate: @escaping (O) -> Bool) -> OwnedTransformedFilteredPreprocessor<Owner, I, O> {
        return OwnedTransformedFilteredPreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, bridge: AnyFilter.wrap(predicate: predicate, on: bridge))
    }
    
    func map<U>(_ transform: @escaping (O) -> U) -> OwnedTransformedFilteredPreprocessor<Owner, I, U> {
        let bridge = AnyModificator.make(modificator: transform, with: self.bridge)
        return OwnedTransformedFilteredPreprocessor<Owner, I, U>(insiderOwner: insiderOwner, dataSource: dataSource, bridge: bridge)
    }

    func onReceive(_ event: @escaping (O, Promise) -> Void) -> OwnedOnReceivePreprocessor<Owner, I, O> {
        return OwnedOnReceivePreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, event: event, bridge: bridge)
    }
    func onReceiveMap<Result>(_ event: @escaping (O, ResultPromise<Result>) -> Void) -> OwnedOnReceiveMapPreprocessor<Owner, Result, I, O> {
        return OwnedOnReceiveMapPreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, event: event, bridge: bridge)
    }

    internal func makeBridge(with assign: @escaping (O) -> Void, source: @escaping () -> I) -> () -> Void {
        return { self.bridge(source(), assign) }
    }
    
    internal func makeBridge<Owner>(owner: ListeningOwner<Owner>, with assign: @escaping (O, Owner?) -> Void, source: @escaping () -> I) -> () -> Void {
        return makeBridge(with: owner.wrap(assign: assign), source: source)
    }
}

struct FilteredPreprocessor<V>: FilteringEntity, _ListeningMaker {
    fileprivate let dataSource: () -> V
    fileprivate let bridge: (_ value: V, _ assign: (V) -> Void) -> Void
    
    func filter(_ predicate: @escaping (V) -> Bool) -> FilteredPreprocessor<V> {
        return FilteredPreprocessor(dataSource: dataSource, bridge: AnyFilter.wrap(predicate: predicate, on: bridge))
    }
    
    func map<U>(_ transform: @escaping (V) -> U) -> TransformedFilteredPreprocessor<V, U> {
        let bridge = AnyModificator.make(modificator: transform, with: self.bridge)
        return TransformedFilteredPreprocessor(dataSource: dataSource, bridge: bridge)
    }

    func onReceive(_ event: @escaping (V, Promise) -> Void) -> OnReceivePreprocessor<V, V> {
        return OnReceivePreprocessor(dataSource: dataSource, event: event, bridge: bridge)
    }

    func onReceiveMap<Result>(_ event: @escaping (V, ResultPromise<Result>) -> Void) -> OnReceiveMapPreprocessor<Result, V, V> {
        return OnReceiveMapPreprocessor(dataSource: dataSource, event: event, bridge: { i, assign in assign(i) })
    }

    internal func makeBridge(with assign: @escaping (V) -> Void, source: @escaping () -> V) -> () -> Void {
        return { self.bridge(source(), assign) }
    }
    
    internal func makeBridge<Owner>(owner: ListeningOwner<Owner>, with assign: @escaping (V, Owner?) -> Void, source: @escaping () -> V) -> () -> Void {
        return makeBridge(with: owner.wrap(assign: assign), source: source)
    }
}
struct OwnedFilteredPreprocessor<Owner: InsiderOwner, V>: InsiderAccessor, FilteringEntity, _ListeningMaker {
    weak var insiderOwner: Owner!
    fileprivate let dataSource: () -> V
    fileprivate let bridge: (_ value: V, _ assign: (V) -> Void) -> Void
    
    func filter(_ predicate: @escaping (V) -> Bool) -> OwnedFilteredPreprocessor<Owner, V> {
        return OwnedFilteredPreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, bridge: AnyFilter.wrap(predicate: predicate, on: bridge))
    }
    
    func map<U>(_ transform: @escaping (V) -> U) -> OwnedTransformedFilteredPreprocessor<Owner, V, U> {
        let bridge = AnyModificator.make(modificator: transform, with: self.bridge)
        return OwnedTransformedFilteredPreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, bridge: bridge)
    }

    func onReceive(_ event: @escaping (V, Promise) -> Void) -> OwnedOnReceivePreprocessor<Owner, V, V> {
        return OwnedOnReceivePreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, event: event, bridge: bridge)
    }
    func onReceiveMap<Result>(_ event: @escaping (V, ResultPromise<Result>) -> Void) -> OwnedOnReceiveMapPreprocessor<Owner, Result, V, V> {
        return OwnedOnReceiveMapPreprocessor(insiderOwner: insiderOwner, dataSource: dataSource, event: event, bridge: bridge)
    }
    
    internal func makeBridge(with assign: @escaping (V) -> Void, source: @escaping () -> V) -> () -> Void {
        return { self.bridge(source(), assign) }
    }
    
    internal func makeBridge<Owner>(owner: ListeningOwner<Owner>, with assign: @escaping (V, Owner?) -> Void, source: @escaping () -> V) -> () -> Void {
        return makeBridge(with: owner.wrap(assign: assign), source: source)
    }
}

extension InsiderOwner {
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

extension Insider {
    mutating func listen<Maker: ListeningMaker>(
        as config: (AnyListening) -> AnyListening = { $0 },
        preprocessor: (Preprocessor<Data>) -> Maker,
        _ assign: @escaping (Maker.OutData) -> Void
    ) -> ListeningToken {
        return addListening(config(preprocessor(Preprocessor(dataSource: dataSource)).makeListening(assign)))
    }

    mutating func listen<O, Maker: ListeningMaker>(
        owner: ListeningOwner<O>,
        as config: (AnyListening) -> AnyListening = { $0 },
        preprocessor: (Preprocessor<Data>) -> Maker,
        _ assign: @escaping (Maker.OutData, O?) -> Void
    ) -> ListeningToken {
        return addListening(config(preprocessor(Preprocessor(dataSource: dataSource)).makeListening(owner: owner, assign: assign)))
    }
}


// MARK: Listenings

// TODO: sendData, onStop should be private
protocol AnyListening {
    var isInvalidated: Bool { get }
    func sendData()
    func onStop() // TODO: is not used now
}
extension AnyListening {
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

public struct Insider<Data> {
    typealias Token = Int
    fileprivate let dataSource: () -> Data
    private var listeners = [Token: AnyListening]()
    private var nextToken: Token = Token.min
    
    init(source: @escaping () -> Data) {
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
    
    mutating func connect<L: AnyListening>(with listening: L) -> Token {
        return connect(with: listening)
    }
    
    mutating func connect(with listening: AnyListening) -> Token {
        defer { nextToken += 1 }
        
        listeners[nextToken] = listening
        
        return nextToken
    }
    
    func has(token: Token) -> Bool {
        return listeners.contains { $0.key == token }
    }
    
    mutating func disconnect(with token: Token, callOnStop call: Bool = true) {
        if let listener = listeners.removeValue(forKey: token), call {
            listener.onStop()
        }
    }
}

extension Insider {
    func mapped<Other>(_ map: @escaping (Data) -> Other) -> Insider<Other> {
        let source = dataSource
        return Insider<Other>(source: { map(source()) })
    }
}

struct ReadonlyProperty<Value> {
    lazy var insider: Insider<Value> = Insider(source: self.concreteValue.get)
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
    
    init(getter: @escaping () -> Value) {
        self.init(value: getter(), getter: getter)
    }
    
    mutating func fetch() {
        value = getter()
    }
}

struct AsyncReadonlyProperty<Value> {
    var insider: Insider<Value> {
        get { return concreteValue.getInsider() }
        set { concreteValue.setInsider(newValue) }
    }
    private let concreteValue: ListenableValue<Value>
    private(set) var value: Value {
        get { return concreteValue.get() }
        set { concreteValue.set(newValue); }
    }
    private let getter: (@escaping (Value) -> Void) -> Void
    
    init(value: Value, getter: @escaping (@escaping (Value) -> Void) -> Void) {
        self.getter = getter
        concreteValue = ListenableValue(value)
    }
    
    mutating func fetch() {
        getter(concreteValue.set)
    }
}

extension AsyncReadonlyProperty {
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
extension ValueWrapper {
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

struct Property<Value>: ValueWrapper {
    lazy var insider: Insider<Value> = Insider(source: self.concreteValue.get)
    fileprivate let concreteValue: PropertyValue<Value>
    var value: Value {
        get { return concreteValue.get() }
        set { concreteValue.set(newValue); insider.dataDidChange() }
    }
    
    init(value: Value) {
        self.init(PropertyValue(value))
    }

    init(_ value: PropertyValue<Value>) {
        self.concreteValue = value
    }
}

// TODO: Create common protocol for Properties
extension Property {
    /// Subscribing to values from other property
    ///
    /// - Parameter other: Property as source values
    /// - Returns: Listening token
    func bind(to other: inout Property<Value>) -> Insider<Value>.ListeningToken { // TODO: Not notify subscribers about receiving new value.
        return other.insider.listen(concreteValue.set)
    }
}

extension ReadonlyProperty {
    mutating func setter(_ value: Value) -> Void { self.value = value }

    mutating func bind(to other: inout Property<Value>) -> Insider<Value>.ListeningToken { // TODO: Not notify subscribers about receiving new value.
        return other.insider.listen(concreteValue.set)
    }
}

extension InsiderOwner {
    /// Makes notification depending
    ///
    /// - Parameter other: Insider owner that will be invoke notifications himself listenings
    /// - Returns: Listening token
    @discardableResult
    func depends<Other: InsiderOwner>(on other: Other) -> ListeningDispose {
        return other.listening(as: { $0.livetime(self) }, owner: .weak(self), { _, owner in owner?.insider.dataDidChange() })
    }

    /// Binds values new values to value wrapper
    ///
    /// - Parameter other: Insider owner that will be invoke notifications himself listenings
    /// - Returns: Listening token
    @discardableResult
    func bind<Other: ValueWrapper & AnyObject>(to other: Other) -> ListeningDispose where Other.T == T {
        return listening(as: { $0.livetime(other) }, { [weak other] newValue in other?.value = newValue })
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
