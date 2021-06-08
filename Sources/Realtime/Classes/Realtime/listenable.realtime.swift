//
//  listenable.realtime.swift
//  Realtime
//
//  Created by Denis Koryttsev on 02.04.2020.
//

import Foundation

public extension Listenable where Out: _Optional, Out.Wrapped: HasDefaultLiteral {
    func `default`() -> Preprocessor<Self, Out.Wrapped> {
        return map({ $0.wrapped ?? Out.Wrapped() })
    }
}
extension ValueStorage where T: HasDefaultLiteral {
    public init(strongWith repeater: Repeater<T>?)  {
        self.init(unsafeStrong: T(), repeater: repeater)
    }
}
extension _Promise: RealtimeTask {
    public var completion: AnyListenable<Void> { return AnyListenable(map({ _ in () })) }
}

public extension Listenable {
    func bind<T>(to property: Property<T>) -> Disposable where T == Out {
        return listening(onValue: { value in
            property <== value
        })
    }
}
extension Property: RealtimeListener {
    public func take(realtime value: T) {
        self <== value
    }
}
