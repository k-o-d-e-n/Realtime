//
//  _concepts_.swift
//  Pods
//
//  Created by Denis Koryttsev on 31/01/2018.
//

import Foundation

struct ListenableValue<T> {
    let get: () -> T
    let set: (T) -> Void
    let setWithoutNotify: (T) -> Void
    let getInsider: () -> Insider<T>
    let setInsider: (Insider<T>) -> Void

    init(_ value: T) {
        var val = value
        get = { val }
        var insider = Insider(source: get)
        set = { val = $0; insider.dataDidChange(); }
        setWithoutNotify = { val = $0 }
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

// MARK: Not used yet or unsuccessful attempts

protocol AnyInsider {
    associatedtype Data
    associatedtype Token
//    var dataSource: () -> Data { get }
    mutating func connect(with listening: AnyListening) -> Token
    mutating func disconnect(with token: Token)
}
