//
//  Observable.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 10/01/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation

/// -------------------------------------------------------------------

protocol ClosureProtocol {
    associatedtype Arg
    associatedtype Returns
    func call(_ arg: Arg, error: UnsafeMutablePointer<Error?>?) -> Returns
}
extension ClosureProtocol {
    func call(_ arg: Arg) -> Returns {
        return call(arg, error: nil)
    }
    func call(throws arg: Arg) throws -> Returns {
        var error: Error?
        let result = call(arg, error: &error)
        if let e = error {
            throw e
        }
        return result
    }
}
extension Closure: ClosureProtocol {
    func call(_ arg: I, error: UnsafeMutablePointer<Error?>?) -> O {
        return closure(arg)
    }
}
extension ThrowsClosure: ClosureProtocol {
    func call(_ arg: I, error: UnsafeMutablePointer<Error?>?) -> O? {
        do {
            return try closure(arg)
        } catch let e {
            error?.pointee = e
            return nil
        }
    }
}

public struct Closure<I, O> {
    let closure: (I) -> O

    public init(_ closure: @escaping (I) -> O) {
        self.closure = closure
    }

    public func call(_ arg: I) -> O {
        return closure(arg)
    }
}
public struct ThrowsClosure<I, O> {
    let closure: (I) throws -> O

    public init(_ closure: @escaping (I) throws -> O) {
        self.closure = closure
    }

    public func call(_ arg: I) throws -> O {
        return try closure(arg)
    }
}
public extension ThrowsClosure {
    func map<U>(_ transform: @escaping (U) throws -> I) -> ThrowsClosure<U, O> {
        return ThrowsClosure<U, O>({ try self.closure(try transform($0)) })
    }
    func map<U>(_ transform: @escaping (O) throws -> U) -> ThrowsClosure<I, U> {
        return ThrowsClosure<I, U>({ try transform(try self.closure($0)) })
    }
    func mapIn<U>(_ transform: @escaping (U) throws -> I) -> ThrowsClosure<U, O> {
        return ThrowsClosure<U, O>({ try self.closure(try transform($0)) })
    }
    func mapOut<U>(_ transform: @escaping (O) throws -> U) -> ThrowsClosure<I, U> {
        return ThrowsClosure<I, U>({ try transform(try self.closure($0)) })
    }
}
public extension Closure {
    func `throws`() -> ThrowsClosure<I, O> {
        return ThrowsClosure(closure)
    }
    func map<U>(_ transform: @escaping (U) -> I) -> Closure<U, O> {
        return Closure<U, O>({ self.closure(transform($0)) })
    }
    func map<U>(_ transform: @escaping (O) -> U) -> Closure<I, U> {
        return Closure<I, U>({ transform(self.closure($0)) })
    }
    func mapIn<U>(_ transform: @escaping (U) -> I) -> Closure<U, O> {
        return Closure<U, O>({ self.closure(transform($0)) })
    }
    func mapOut<U>(_ transform: @escaping (O) -> U) -> Closure<I, U> {
        return Closure<I, U>({ transform(self.closure($0)) })
    }
}

/// Configurable wrapper for closure that receives listening value.
public typealias Assign<A> = Closure<A, Void>

public extension Closure where O == Void {
    typealias A = I
    init(assign: @escaping (A) -> Void) {
        self.closure = assign
    }
    var assign: (A) -> Void { return closure }

    /// simple closure without side effects
    static func just(_ assign: @escaping (A) -> Void) -> Assign<A> {
        return Assign(assign: assign)
    }

    /// closure associated with object using weak reference
    static func weak<Owner: AnyObject>(_ owner: Owner, assign: @escaping (A, Owner?) -> Void) -> Assign<A> {
        return Assign(assign: { [weak owner] v in assign(v, owner) })
    }

    /// closure associated with object using unowned reference
    static func unowned<Owner: AnyObject>(_ owner: Owner, assign: @escaping (A, Owner) -> Void) -> Assign<A> {
        return Assign(assign: { [unowned owner] v in assign(v, owner) })
    }

    /// closure associated with object using weak reference, that called only when object alive
    static func guarded<Owner: AnyObject>(_ owner: Owner, assign: @escaping (A, Owner) -> Void) -> Assign<A> {
        return weak(owner) { if let o = $1 { assign($0, o) } }
    }

    /// closure that called on specified dispatch queue
    static func on(_ queue: DispatchQueue, assign: @escaping (A) -> Void) -> Assign<A> {
        return Assign<A>(assign: { v in
            queue.async {
                assign(v)
            }
        })
    }

    /// returns new closure wrapped using queue behavior
    func on(queue: DispatchQueue) -> Assign<A> {
        return Assign.on(queue, assign: assign)
    }

    /// returns new closure with encapsulated work closure
    /// that calls before the call of main closure
    func with(work: @escaping (A) -> Void) -> Assign<A> {
        return Assign(assign: { (v) in
            work(v)
            self.assign(v)
        })
    }
    /// returns new closure with encapsulated work closure
    /// that calls after the call of main closure
    func after(work: @escaping (A) -> Void) -> Assign<A> {
        return Assign(assign: { (v) in
            self.assign(v)
            work(v)
        })
    }
    /// returns new closure with encapsulated work closure
    /// that calls before the call of main closure
    func with(work: Assign<A>) -> Assign<A> {
        return with(work: work.assign)
    }
    /// returns new closure with encapsulated work closure
    /// that calls after the call of main closure
    func after(work: Assign<A>) -> Assign<A> {
        return after(work: work.assign)
    }
    /// returns new closure with encapsulated work closure
    /// that calls before the call of main closure
    func with(work: Assign<A>?) -> Assign<A> {
        return work.map(with) ?? self
    }
    /// returns new closure with encapsulated work closure
    /// that calls after the call of main closure
    func after(work: Assign<A>?) -> Assign<A> {
        return work.map(after) ?? self
    }

    /// returns new closure with transformed input parameter
    func map<U>(_ transform: @escaping (U) -> A) -> Assign<U> {
        return Assign<U>(assign: { (u) in
            self.assign(transform(u))
        })
    }
    /// returns new closure that filter input values using predicate closure
    func filter(_ predicate: @escaping (A) -> Bool) -> Assign<A> {
        return Assign(assign: { (a) in
            if predicate(a) {
                self.assign(a)
            }
        })
    }
}

prefix operator <-
public prefix func <-<I, O>(rhs: Closure<I, O>) -> (I) -> O {
    return rhs.closure
}
public prefix func <-<I, O>(rhs: @escaping (I) -> O) -> Closure<I, O> {
    return Closure(rhs)
}

// MARK: Connections

/// Event that sends to listeners
///
/// - value: Expected value event
/// - error: Error event indicating that something went wrong
public enum ListenEvent<T> {
    case value(T)
    case error(Error)
}
public extension ListenEvent {
    var value: T? {
        guard case .value(let v) = self else { return nil }
        return v
    }
    var error: Error? {
        guard case .error(let e) = self else { return nil }
        return e
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

    func tryValue() throws -> T {
        switch self {
        case .value(let v): return v
        case .error(let e): throw e
        }
    }
}
extension ListenEvent: Listenable {
    public func listening(_ assign: Closure<ListenEvent<T>, Void>) -> Disposable {
        assign.call(self)
        return EmptyDispose()
    }
}

/// Common protocol for all objects that ensures listening value. 
public protocol Listenable {
    associatedtype Out

    /// Disposable listening of value
    func listening(_ assign: Assign<ListenEvent<Out>>) -> Disposable
}
public extension Listenable {
    func listening(_ assign: @escaping (ListenEvent<Out>) -> Void) -> Disposable {
        return listening(.just(assign))
    }
    func listening(onValue assign: Assign<Out>) -> Disposable {
        return listening(Assign(assign: {
            if let v = $0.value {
                assign.assign(v)
            }
        }))
    }
    func listening(onValue assign: @escaping (Out) -> Void) -> Disposable {
        return listening(onValue: .just(assign))
    }

    func listening(onError assign: Assign<Error>) -> Disposable {
        return listening(Assign(assign: {
            if let v = $0.error {
                assign.assign(v)
            }
        }))
    }
    func listening(onError assign: @escaping (Error) -> Void) -> Disposable {
        return listening(onError: .just(assign))
    }

    internal func asAny() -> AnyListenable<Out> {
        return AnyListenable(listening)
    }
    func listening(onValue: @escaping (Out) -> Void, onError: @escaping (Error) -> Void) -> Disposable {
        return listening(Assign(assign: { event in
            switch event {
            case .value(let v): onValue(v)
            case .error(let e): onError(e)
            }
        }))
    }
}

public struct AnyListenable<Out>: Listenable {
    let _listening: (Assign<ListenEvent<Out>>) -> Disposable

    public init<L: Listenable>(_ base: L) where L.Out == Out {
        self._listening = base.listening
    }
    init(_ listening: @escaping (Assign<ListenEvent<Out>>) -> Disposable) {
        self._listening = listening
    }

    public func listening(_ assign: Assign<ListenEvent<Out>>) -> Disposable {
        return _listening(assign)
    }
}

/// Common protocol for entities that represents some data
public protocol ValueWrapper { // TODO: Deprecate
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

public extension Repeater {
    /// Makes notification depending
    ///
    /// - Parameter other: Listenable that will be invoke notifications himself listenings
    /// - Returns: Disposable
    func depends<L: Listenable>(on other: L) -> Disposable where L.Out == T {
        return other.listening(self.send)
    }
}
public extension Listenable {
    /// Binds values new values to value wrapper
    ///
    /// - Parameter other: Value wrapper that will be receive value
    /// - Returns: Disposable
    @available(*, deprecated, message: "has unsafe behavior")
    func bind<Other: AnyObject & ValueWrapper>(to other: Other) -> Disposable where Other.V == Self.Out {
        return livetime(of: other).listening(onValue: { [weak other] val in
            other?.value = val
        })
    }

    /// Binds events to repeater
    ///
    /// - Parameter other: Repeater that will be receive value
    /// - Returns: Disposable
    func bind(to other: Repeater<Out>) -> Disposable {
        return other.depends(on: self)
    }

    /// Binds events to property
    ///
    /// - Parameter other: Repeater that will be receive value
    /// - Returns: Disposable
    func bind(to other: ValueStorage<Out>) -> Disposable {
        return listening({ (e) in
            switch e {
            case .value(let v): other.value = v
            case .error(let e): other.sendError(e)
            }
        })
    }
}
