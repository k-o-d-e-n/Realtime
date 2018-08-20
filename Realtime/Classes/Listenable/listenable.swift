//
//  Observable.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 10/01/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation

/// -------------------------------------------------------------------

public struct Promise {
    let action: () -> Void
    let error: (Error) -> Void

    public func fulfill() {
        action()
    }

    public func reject(_ error: Error) {
        self.error(error)
    }
}
public struct ResultPromise<T> {
    let receiver: (T) -> Void
    let error: (Error) -> Void

    public func fulfill(_ result: T) {
        receiver(result)
    }

    public func reject(_ error: Error) {
        self.error(error)
    }
}

public struct Closure<I, O> {
    let closure: (I) -> O
}
public struct ThrowsClosure<I, O> {
    let closure: (I) throws -> O
}
extension ThrowsClosure {
    func map<U>(_ transform: @escaping (U) throws -> I) -> ThrowsClosure<U, O> {
        return ThrowsClosure<U, O>(closure: { try self.closure(try transform($0)) })
    }
    func map<U>(_ transform: @escaping (O) throws -> U) -> ThrowsClosure<I, U> {
        return ThrowsClosure<I, U>(closure: { try transform(try self.closure($0)) })
    }
}
extension Closure {
    func `throws`() -> ThrowsClosure<I, O> {
        return ThrowsClosure(closure: closure)
    }
    func map<U>(_ transform: @escaping (U) -> I) -> Closure<U, O> {
        return Closure<U, O>(closure: { self.closure(transform($0)) })
    }
    func map<U>(_ transform: @escaping (O) -> U) -> Closure<I, U> {
        return Closure<I, U>(closure: { transform(self.closure($0)) })
    }
}

extension Closure where O == Void {
    func filter(_ predicate: @escaping (I) -> Bool) -> Closure<I, O> {
        return Closure<I, O>(closure: { (input) -> O in
            if predicate(input) {
                return self.closure(input)
            }
        })
    }
}

/// Configurable wrapper for closure that receive listening value.
public struct Assign<A> {
    internal let assign: (A) -> Void

    /// simple closure without side effects
    static public func just(_ assign: @escaping (A) -> Void) -> Assign<A> {
        return Assign(assign: assign)
    }

    /// closure associated with object using weak reference
    static public func weak<Owner: AnyObject>(_ owner: Owner, assign: @escaping (A, Owner?) -> Void) -> Assign<A> {
        return Assign(assign: { [weak owner] v in assign(v, owner) })
    }
    

    /// closure associated with object using unowned reference
    static public func unowned<Owner: AnyObject>(_ owner: Owner, assign: @escaping (A, Owner) -> Void) -> Assign<A> {
        return Assign(assign: { [unowned owner] v in assign(v, owner) })
    }

    /// closure associated with object using weak reference, that called only when object alive
    static public func guarded<Owner: AnyObject>(_ owner: Owner, assign: @escaping (A, Owner) -> Void) -> Assign<A> {
        return weak(owner) { if let o = $1 { assign($0, o) } }
    }

//    /// closure associated with object using weak reference, that called only when object alive
//    static public func guardedWeak<Owner: AnyObject>(_ owner: Owner, assign: @escaping (A, Owner?) -> Void) -> Assign<A> {
//        return weak(owner) { if let o = $1 { weak var o = o; assign($0, o) } }
//    }

    /// closure that called on specified dispatch queue
    static public func on(_ queue: DispatchQueue, assign: @escaping (A) -> Void) -> Assign<A> {
        return Assign<A>(assign: { v in
            queue.async {
                assign(v)
            }
        })
    }

    /// returns new closure wrapped using queue behavior
    public func on(queue: DispatchQueue) -> Assign<A> {
        return Assign.on(queue, assign: assign)
    }

    public func with(work: @escaping (A) -> Void) -> Assign<A> {
        return Assign(assign: { (v) in
            work(v)
            self.assign(v)
        })
    }
    public func after(work: @escaping (A) -> Void) -> Assign<A> {
        return Assign(assign: { (v) in
            self.assign(v)
            work(v)
        })
    }
    public func with(work: Assign<A>) -> Assign<A> {
        return with(work: work.assign)
    }
    public func after(work: Assign<A>) -> Assign<A> {
        return after(work: work.assign)
    }

    public func map<U>(_ transform: @escaping (U) -> A) -> Assign<U> {
        return Assign<U>(assign: { (u) in
            self.assign(transform(u))
        })
    }

    public func filter(_ predicate: @escaping (A) -> Bool) -> Assign<A> {
        return Assign(assign: { (a) in
            if predicate(a) {
                self.assign(a)
            }
        })
    }
}

prefix operator <-
public prefix func <-<A>(rhs: Assign<A>) -> (A) -> Void {
    return rhs.assign
}
public prefix func <-<A>(rhs: @escaping (A) -> Void) -> Assign<A> {
    return Assign(assign: rhs)
}

// MARK: Connections

public enum ListenEvent<T> {
    case value(T)
    case error(Error)
}
public extension ListenEvent {
    var value: T? {
        guard case .value(let v) = self else { return nil }
        return v
    }
    func map<U>(_ transform: (T) throws -> U) rethrows -> ListenEvent<U> {
        switch self {
        case .value(let v): return .value(try transform(v))
        case .error(let e): return .error(e)
        }
    }
    func flatMap<U>(_ transform: (T) throws -> U) rethrows -> U? {
        switch self {
        case .value(let v): return try transform(v)
        case .error: return nil
        }
    }
}

/// Common protocol for all objects that ensures listening value. 
public protocol Listenable {
    associatedtype OutData

    /// Disposable listening of value
    func listening(_ assign: Assign<ListenEvent<OutData>>) -> Disposable

    /// Listening with possibility to control active state
    func listeningItem(_ assign: Assign<ListenEvent<OutData>>) -> ListeningItem
}
public extension Listenable {
    func listening(_ assign: @escaping (ListenEvent<OutData>) -> Void) -> Disposable {
        return listening(.just(assign))
    }
    func listeningItem(_ assign: @escaping (ListenEvent<OutData>) -> Void) -> ListeningItem {
        return listeningItem(.just(assign))
    }
    func listening(onValue assign: Assign<OutData>) -> Disposable {
        return listening(Assign(assign: {
            if let v = $0.value {
                assign.assign(v)
            }
        }))
    }
    func listeningItem(onValue assign: Assign<OutData>) -> ListeningItem {
        return listeningItem(Assign(assign: {
            if let v = $0.value {
                assign.assign(v)
            }
        }))
    }
    func listening(onValue assign: @escaping (OutData) -> Void) -> Disposable {
        return listening(onValue: .just(assign))
    }
    func listeningItem(onValue assign: @escaping (OutData) -> Void) -> ListeningItem {
        return listeningItem(onValue: .just(assign))
    }
}
struct AnyListenable<Out>: Listenable {
    let _listening: (Assign<ListenEvent<Out>>) -> Disposable
    let _listeningItem: (Assign<ListenEvent<Out>>) -> ListeningItem

    init<L: Listenable>(_ base: L) where L.OutData == Out {
        self._listening = base.listening
        self._listeningItem = base.listeningItem
    }
    init(_ listening: @escaping (Assign<ListenEvent<Out>>) -> Disposable,
         _ listeningItem: @escaping (Assign<ListenEvent<Out>>) -> ListeningItem) {
        self._listening = listening
        self._listeningItem = listeningItem
    }

    func listening(_ assign: Assign<ListenEvent<Out>>) -> Disposable {
        return _listening(assign)
    }
    func listeningItem(_ assign: Assign<ListenEvent<Out>>) -> ListeningItem {
        return _listeningItem(assign)
    }
}

extension Insider: _ListeningMaker, BridgeMaker {
    typealias OutData = D
    public typealias Data = D
    var bridgeMaker: Insider<D> { return self }
    public typealias ListeningToken = (token: Token, listening: AnyListening)
    internal mutating func addListening(_ listening: AnyListening) -> ListeningToken {
        return (connect(with: listening), listening)
    }

    /// connects to insider to receive value changes
    mutating public func listen(as config: (AnyListening) -> AnyListening = { $0 }, _ assign: Assign<ListenEvent<D>>) -> ListeningToken {
        return addListening(config(makeListening(assign.assign)))
    }

    /// connects to insider to receive value changes with preaction on receive update
    mutating public func listen(as config: (AnyListening) -> AnyListening = { $0 }, onReceive: @escaping (D, Promise) -> Void, _ assign: Assign<ListenEvent<D>>) -> ListeningToken {
        return addListening(config(makeListening(on: onReceive, assign.assign)))
    }

    func wrapAssign(_ assign: Assign<ListenEvent<D>>) -> Assign<ListenEvent<D>> {
        return assign
    }
}

/// Object that provides listenable data
protocol InsiderOwner: class, Listenable {
    associatedtype InsiderValue
    var insider: Insider<InsiderValue> { get set }
}

extension InsiderOwner {
    private func makeDispose(for token: Insider<InsiderValue>.Token) -> ListeningDispose {
        return ListeningDispose({ [weak self] in self?.insider.disconnect(with: token) })
    }
    private func makeListeningItem(token: Insider<InsiderValue>.Token, listening: AnyListening) -> ListeningItem {
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

    public func listening(_ assign: Assign<ListenEvent<InsiderValue>>) -> Disposable {
        return makeDispose(for: insider.listen(assign).token)
    }
    public func listeningItem(_ assign: Assign<ListenEvent<InsiderValue>>) -> ListeningItem {
        let item = insider.listen(assign)
        return makeListeningItem(token: item.token, listening: item.listening)
    }

    public func listening(_ assign: @escaping (ListenEvent<InsiderValue>) -> Void) -> Disposable {
        return listening(.just(assign))
    }
    public func listeningItem(_ assign: @escaping (ListenEvent<InsiderValue>) -> Void) -> ListeningItem {
        return listeningItem(.just(assign))
    }
}

/// Entity, which is port to connect to data changes
struct Insider<D> {
    typealias Token = Int
    internal let dataSource: () -> D
    private var listeners = [Token: AnyListening]()
    private var nextToken: Token = Token.min
    internal var hasConnections: Bool { return listeners.count > 0 }
    
    init(source: @escaping () -> D) {
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
    
    mutating func disconnect(with token: Token) {
        listeners.removeValue(forKey: token)
    }
}

extension Insider {
    func mapped<Other>(_ map: @escaping (D) -> Other) -> Insider<Other> {
        let source = dataSource
        return Insider<Other>(source: { map(source()) })
    }
}

/// Provides calculated listening value
public struct ReadonlyProperty<Value> {
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
    
    public init(getter: @escaping () -> Value) {
        self.init(value: getter(), getter: getter)
    }

    init<T>(property: Property<T>, getter: @escaping (T) -> Value) {
        let accessor = property.concreteValue
        self.init(getter: { getter(accessor.get()) })
    }
    
    mutating func fetch() {
        concreteValue.set(getter())
        insider.dataDidChange()
    }
}

/// Provides listening value based on async action
public struct AsyncReadonlyProperty<Value> {
    var insider: Insider<Value> {
        get { return concreteValue.getInsider() }
        set { concreteValue.setInsider(newValue) }
    }
    private let concreteValue: ListenableValue<Value>
    public private(set) var value: Value {
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
    let didSet: ((T, T) -> Void)?
    
    init(_ value: T, didSet: ((T, T) -> Void)? = nil) {
        var val = value {
            didSet { didSet?(oldValue, val) }
        }
        self.get = { val }
        self.set = { val = $0 }
        self.didSet = didSet
    }

    init<O: AnyObject>(unowned owner: O, getter: @escaping (O) -> T, setter: @escaping (O, T) -> Void, didSet: ((T, T) -> Void)? = nil) {
        self.get = { [unowned owner] in return getter(owner) }
        self.set = { [unowned owner] in setter(owner, $0) }
        self.didSet = didSet
    }
}

struct WeakPropertyValue<T> where T: AnyObject {
    let get: () -> T?
    let set: (T?) -> Void

    init(_ value: T?) {
        weak var val = value
        get = { val }
        set = { val = $0 }
    }
}

/// Common protocol for entities that represents some data
public protocol ValueWrapper {
    associatedtype V
    var value: V { get set }
}

public extension ValueWrapper {
    static func <==(_ prop: inout Self, _ value: V) {
        prop.value = value
    }
    static func <==(_ value: inout V, _ prop: Self) {
        value = prop.value
    }
    static func <==(_ value: inout V?, _ prop: Self) {
        value = prop.value
    }
}
public extension ValueWrapper {
    func mapValue<U>(_ transform: (V) -> U) -> U {
        return transform(value)
    }
}
public extension ValueWrapper where V: _Optional {
    static func <==(_ value: inout V?, _ prop: Self) {
        value = prop.value
    }
    func mapValue<U>(_ transform: (V.Wrapped) -> U) -> U? {
        return value.map(transform)
    }
    func flatMapValue<U>(_ transform: (V.Wrapped) -> U?) -> U? {
        return value.flatMap(transform)
    }
}

/// Simple stored property with listening possibility
public struct Property<Value>: ValueWrapper {
    lazy var insider: Insider<Value> = Insider(source: self.concreteValue.get)
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

public struct WeakProperty<Value>: ValueWrapper where Value: AnyObject {
    lazy var insider: Insider<Value?> = Insider(source: self.concreteValue.get)
    fileprivate let concreteValue: WeakPropertyValue<Value>
    public var value: Value? {
        get { return concreteValue.get() }
        set { concreteValue.set(newValue); insider.dataDidChange() }
    }

    public init(value: Value?) {
        self.init(WeakPropertyValue(value))
    }

    init(_ value: WeakPropertyValue<Value>) {
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
        let value = concreteValue
        return other.insider.listen(Assign(assign: { (e) in
            if let v = e.value {
                value.set(v)
            }
        }))
    }
}

extension ReadonlyProperty {
    mutating func setter(_ value: Value) -> Void { self.value = value }

    mutating func bind(to other: inout Property<Value>) -> Insider<Value>.ListeningToken { // TODO: Not notify subscribers about receiving new value.
        let value = concreteValue
        return other.insider.listen(Assign(assign: { (e) in
            if let v = e.value {
                value.set(v)
            }
        }))
    }
}

extension InsiderOwner {
    /// Makes notification depending
    ///
    /// - Parameter other: Insider owner that will be invoke notifications himself listenings
    /// - Returns: Listening token
    @discardableResult
    func depends<Other: InsiderOwner>(on other: Other) -> Disposable {
        return other.livetime(self).listening(.weak(self) { _, owner in owner?.insider.dataDidChange() })
    }
}
public extension Listenable {
    /// Binds values new values to value wrapper
    ///
    /// - Parameter other: Insider owner that will be invoke notifications himself listenings
    /// - Returns: Listening token
    @discardableResult
    func bind<Other: AnyObject & ValueWrapper>(to other: Other) -> Disposable where Other.V == Self.OutData {
        return livetime(other).listening({ [weak other] val in
            if let v = val.value {
                other?.value = v
            }
        })
    }
}

// ------------------------------------------ DEPRECATED ------------------------------------------

protocol BridgeMaker {
    associatedtype Data
    associatedtype OutData
    func makeBridge(with assign: @escaping (ListenEvent<OutData>) -> Void, source: @escaping () -> Data) -> () -> Void
    func wrapAssign(_ assign: Assign<ListenEvent<OutData>>) -> Assign<ListenEvent<Data>>
}

extension BridgeMaker where Data == OutData {
    internal func makeBridge(with assign: @escaping (ListenEvent<OutData>) -> Void, source: @escaping () -> Data) -> () -> Void {
        return { assign(.value(source())) }
    }
    fileprivate func makeBridge(on event: @escaping (OutData, Promise) -> Void, with assign: @escaping (ListenEvent<OutData>) -> Void, source: @escaping () -> Data) -> () -> Void {
        let realBridge = makeBridge(with: assign, source: source)
        return makeBridge(on: event, bridge: realBridge, source: source)
    }
    fileprivate func makeBridge(on event: @escaping (OutData, Promise) -> Void, bridge: @escaping () -> Void, source: @escaping () -> Data) -> () -> Void {
        return { event(source(), Promise(action: bridge, error: {_ in})) }
    }
}

protocol ListeningMaker {
    associatedtype OutData
    associatedtype Data
    func makeListening(_ assign: @escaping (ListenEvent<OutData>) -> Void) -> AnyListening
}
protocol _ListeningMaker: ListeningMaker {
    associatedtype Bridge: BridgeMaker
    var bridgeMaker: Bridge { get }
    var dataSource: () -> Data { get }
}
extension _ListeningMaker where Bridge.Data == Self.Data, Bridge.OutData == Self.OutData {
    internal func makeListening(_ assign: @escaping (ListenEvent<OutData>) -> Void) -> AnyListening {
        return Listening(bridge: bridgeMaker.makeBridge(with: assign, source: dataSource))
    }
    fileprivate func makeListening(on event: @escaping (Data, Promise) -> Void, _ assign: @escaping (ListenEvent<OutData>) -> Void) -> AnyListening {
        let source = dataSource
        let realBridge = bridgeMaker.makeBridge(with: assign, source: source)
        return Listening(bridge: { event(source(), Promise(action: realBridge, error: {_ in})) })
    }
}
