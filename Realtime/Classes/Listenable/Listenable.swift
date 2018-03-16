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

    public func fulfill() {
        action()
    }
}
public struct ResultPromise<T> {
    let receiver: (T) -> Void

    public func fulfill(_ result: T) {
        receiver(result)
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

    /// closure that called on specified dispatch queue
    static public func on(_ queue: DispatchQueue, assign: @escaping (A) -> Void) -> Assign<A> {
        return Assign(assign: { v in queue.async { assign(v) } })
    }

    /// returns new closure wrapped using queue behavior
    public func on(queue: DispatchQueue) -> Assign<A> {
        return Assign.on(queue, assign: assign)
    }
}

// MARK: Connections

protocol BridgeMaker {
    associatedtype Data
    associatedtype OutData
    func makeBridge(with assign: @escaping (OutData) -> Void, source: @escaping () -> Data) -> () -> Void
}

extension BridgeMaker where Data == OutData {
    internal func makeBridge(with assign: @escaping (OutData) -> Void, source: @escaping () -> Data) -> () -> Void {
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

protocol ListeningMaker {
    associatedtype OutData
    associatedtype Data
    func makeListening(_ assign: @escaping (OutData) -> Void) -> AnyListening
}

struct SimpleBridgeMaker<Data>: BridgeMaker {
    typealias OutData = Data
}
protocol _ListeningMaker: ListeningMaker {
    associatedtype Bridge: BridgeMaker
    var bridgeMaker: Bridge { get }
    var dataSource: () -> Data { get }
}
extension _ListeningMaker where Bridge.Data == Self.Data, Bridge.OutData == Self.OutData {
    internal func makeListening(_ assign: @escaping (OutData) -> Void) -> AnyListening {
        return Listening(bridge: bridgeMaker.makeBridge(with: assign, source: dataSource))
    }
    fileprivate func makeListening(on event: @escaping (Data, Promise) -> Void, _ assign: @escaping (OutData) -> Void) -> AnyListening {
        let source = dataSource
        let realBridge = bridgeMaker.makeBridge(with: assign, source: source)
        return Listening(bridge: { event(source(), Promise(action: realBridge)) })
    }
}

/// Common protocol for all objects that ensures listening value. 
public protocol Listenable {
    associatedtype OutData

    /// Disposable listening of value
    func listening(as config: (AnyListening) -> AnyListening, _ assign: Assign<OutData>) -> Disposable

    /// Listening with possibility to control active state
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

extension Insider: _ListeningMaker, BridgeMaker {
    typealias OutData = D
    public typealias Data = D
    var bridgeMaker: Insider<D> { return self }
    public typealias ListeningToken = (token: Token, listening: AnyListening)
    mutating func addListening(_ listening: AnyListening) -> ListeningToken {
        return (connect(with: listening), listening)
    }

    /// connects to insider to receive value changes
    mutating public func listen(as config: (AnyListening) -> AnyListening = { $0 }, _ assign: Assign<D>) -> ListeningToken {
        return addListening(config(makeListening(assign.assign)))
    }

    /// connects to insider to receive value changes with preaction on receive update
    mutating public func listen(as config: (AnyListening) -> AnyListening = { $0 }, onReceive: @escaping (D, Promise) -> Void, _ assign: Assign<D>) -> ListeningToken {
        return addListening(config(makeListening(on: onReceive, assign.assign)))
    }
}

/// Object that provides listenable data
public protocol InsiderOwner: class, Listenable {
    associatedtype T
    var insider: Insider<T> { get set }
}

protocol InsiderAccessor {
    associatedtype Owner: InsiderOwner
    weak var insiderOwner: Owner! { get }
}

extension InsiderAccessor where Self: _ListeningMaker {
    func _listening(as config: (AnyListening) -> AnyListening, _ assign: Assign<OutData>) -> Disposable {
        return insiderOwner.connect(disposed: config(makeListening(assign.assign)))
    }
    func _listeningItem(as config: (AnyListening) -> AnyListening, _ assign: Assign<OutData>) -> ListeningItem {
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

/// Entity, which is port to connect to data changes
public struct Insider<D> {
    public typealias Token = Int
    internal let dataSource: () -> D
    private var listeners = [Token: AnyListening]()
    private var nextToken: Token = Token.min
    
    public init(source: @escaping () -> D) {
        dataSource = source
    }

    public mutating func dataDidChange() {
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

/// Provides calculated listening value
public struct ReadonlyProperty<Value> {
    public lazy var insider: Insider<Value> = Insider(source: self.concreteValue.get) // TODO: Remove public
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

/// Provides listening value based on async action
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
        weak var val = value// {
        //            didSet {
        //                print(oldValue)
        //            }
        //        }
        get = { val }
        set = { val = $0 }
    }
}

/// Common protocol for entities that represents some data
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

/// Simple stored property with listening possibility
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
