//
//  Listening.swift
//  GoogleToolboxForMac
//
//  Created by Denis Koryttsev on 31/01/2018.
//

import Foundation

// MARK: Listenings

// TODO: sendData, onStop should be private
/// Represents connection data source and data receiver
public protocol AnyListening {
    var isInvalidated: Bool { get }
    func sendData()
    func onStop() // TODO: is not used now
}
public extension AnyListening {
    /// calls if closure returns true
    func `if`(_ itRight: @autoclosure @escaping () -> Bool) -> AnyListening {
        return IfListening(base: self, ifRight: itRight)
    }
    /// calls if closure returns true
    func `if`(_ itRight: @escaping () -> Bool) -> AnyListening {
        return IfListening(base: self, ifRight: itRight)
    }

	/// calls closure on disconnect
    func onFire(_ todo: @escaping () -> Void) -> AnyListening {
        return OnFireListening(base: self, onFire: todo)
    }

    /// connection to receive single value
    func once() -> AnyListening {
        return OnceListening(base: self)
    }

    /// calls connection on specific queue
    func queue(_ queue: DispatchQueue) -> AnyListening {
        return ConcurrencyListening(base: self, queue: queue)
    }

    /// works until time has not reached deadline
    func deadline(_ time: DispatchTime) -> AnyListening {
        return DeadlineListening(base: self, deadline: time)
    }

    /// works until alive specified object
    func livetime(_ byItem: AnyObject) -> AnyListening {
        return LivetimeListening(base: self, living: byItem)
    }

    /// each next event are calling not earlier a specified period
    func debounce(_ time: DispatchTimeInterval) -> AnyListening {
        return DebounceListening(base: self, time: time)
    }
}
/// Fires if disposes use his Disposable. Else if has previous dispose behaviors like as once(), livetime(_:) and others, will not called.
/// Can calls before last event.
public struct OnFire<T>: Listenable {
    fileprivate let listenable: AnyListenable<T>
    fileprivate let onFire: () -> Void

    public func listening(as config: (AnyListening) -> AnyListening, _ assign: Assign<T>) -> Disposable {
        let disposable = listenable.listening(as: config, assign)
        return ListeningDispose({
            disposable.dispose()
            self.onFire()
        })
    }

    public func listeningItem(as config: (AnyListening) -> AnyListening, _ assign: Assign<T>) -> ListeningItem {
        let item = listenable.listeningItem(as: config, assign)
        return ListeningItem(start: item.start, stop: { _ in
            item.stop()
            self.onFire()
        }, notify: item.notify, token: nil)
    }
}
public extension Listenable {
    /// calls closure on disconnect
    func onFire(_ todo: @escaping () -> Void) -> OnFire<OutData> {
        return OnFire(listenable: AnyListenable(self.listening, self.listeningItem), onFire: todo)
    }
}

public struct Do<T>: Listenable {
    fileprivate let listenable: AnyListenable<T>
    fileprivate let doit: (T) -> Void

    public func listening(as config: (AnyListening) -> AnyListening, _ assign: Assign<T>) -> Disposable {
        return listenable.listening(as: config, assign.with(work: doit))
    }

    public func listeningItem(as config: (AnyListening) -> AnyListening, _ assign: Assign<T>) -> ListeningItem {
        return listenable.listeningItem(as: config, assign.with(work: doit))
    }
}
public extension Listenable {
    /// calls closure on receive next value
    func `do`(_ something: @escaping (OutData) -> Void) -> Do<OutData> {
        return Do(listenable: AnyListenable(self.listening, self.listeningItem), doit: something)
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

struct IfListening: AnyListening {
    private let base: AnyListening
    private let ifRight: () -> Bool
    var isInvalidated: Bool { return base.isInvalidated }

    init(base: AnyListening, ifRight: @escaping () -> Bool) {
        self.base = base
        self.ifRight = ifRight
    }

    func sendData() {
        if ifRight() {
            base.sendData()
        }
    }

    func onStop() {
        base.onStop()
    }
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
public struct Once<T>: Listenable {
    private let listenable: AnyListenable<T>

    init(base: AnyListenable<T>) {
        self.listenable = base
    }

    public func listening(as config: (AnyListening) -> AnyListening, _ assign: Assign<T>) -> Disposable {
        var disposable: Disposable! = nil
        disposable = listenable.listening(as: config, assign.with(work: { (_) in
            disposable.dispose()
        }))
        return disposable
    }

    public func listeningItem(as config: (AnyListening) -> AnyListening, _ assign: Assign<T>) -> ListeningItem {
        var item: ListeningItem! = nil
        item = listenable.listeningItem(as: config, assign.with(work: { (_) in
            item.dispose()
        }))
        return item
    }
}
public extension Listenable {
    /// connection to receive single value
    func once() -> Once<OutData> {
        return Once(base: AnyListenable(self.listening, self.listeningItem))
    }
}

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
extension Bridge where I == O {
    init(queue: DispatchQueue) {
        self.init { (value, assign) in
            queue.async {
                assign(value)
            }
        }
    }
}
public extension Listenable {
    /// calls connection on specific queue
    func queue(_ queue: DispatchQueue) -> Preprocessor<OutData, OutData> {
        return Preprocessor(listenable: AnyListenable(self.listening, self.listeningItem), bridgeMaker: Bridge(queue: queue))
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
public struct Deadline<T>: Listenable {
    private let listenable: AnyListenable<T>
    private let deadline: DispatchTime

    init(base: AnyListenable<T>, deadline: DispatchTime) {
        self.listenable = base
        self.deadline = deadline
    }

    public func listening(as config: (AnyListening) -> AnyListening, _ assign: Assign<T>) -> Disposable {
        var disposable: Disposable! = nil
        disposable = listenable.listening(as: config, assign.filter({ _ -> Bool in
            guard self.deadline >= .now() else {
                disposable.dispose()
                return false
            }
            return true
        }))
        return disposable
    }

    public func listeningItem(as config: (AnyListening) -> AnyListening, _ assign: Assign<T>) -> ListeningItem {
        var item: ListeningItem! = nil
        item = listenable.listeningItem(as: config, assign.filter({ _ -> Bool in
            guard self.deadline >= .now() else {
                item.dispose()
                return false
            }
            return true
        }))
        return item
    }
}
public extension Listenable {
    /// works until time has not reached deadline
    func deadline(_ time: DispatchTime) -> Deadline<OutData> {
        return Deadline(base: AnyListenable(self.listening, self.listeningItem), deadline: time)
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
public struct Livetime<T>: Listenable {
    private let listenable: AnyListenable<T>
    private weak var livingItem: AnyObject?

    init(base: AnyListenable<T>, living: AnyObject) {
        self.listenable = base
        self.livingItem = living
    }

    public func listening(as config: (AnyListening) -> AnyListening, _ assign: Assign<T>) -> Disposable {
        var disposable: Disposable! = nil
        disposable = listenable.listening(as: config, assign.filter({ _ -> Bool in
            guard self.livingItem != nil else {
                disposable.dispose()
                return false
            }
            return true
        }))
        return disposable
    }

    public func listeningItem(as config: (AnyListening) -> AnyListening, _ assign: Assign<T>) -> ListeningItem {
        var item: ListeningItem! = nil
        item = listenable.listeningItem(as: config, assign.filter({ _ -> Bool in
            guard self.livingItem != nil else {
                item.dispose()
                return false
            }
            return true
        }))
        return item
    }
}
public extension Listenable {
    /// works until alive specified object
    func livetime(_ byItem: AnyObject) -> Livetime<OutData> {
        return Livetime(base: AnyListenable(self.listening, self.listeningItem), living: byItem)
    }
}

class DebounceListening: AnyListening {
    private let listening: AnyListening
    private let repeatTime: DispatchTimeInterval
    private var isNeedSend: Bool = true
    private var fireDate: DispatchTime
    var isInvalidated: Bool { return listening.isInvalidated }

    init(base: AnyListening, time: DispatchTimeInterval) {
        self.listening = base
        self.repeatTime = time
        self.fireDate = .now()
    }

    func sendData() {
        guard !isInvalidated else { return }

        guard fireDate <= .now() else { isNeedSend = true; return }

        isNeedSend = false
        listening.sendData()
        fireDate = .now() + repeatTime
        DispatchQueue.main.asyncAfter(deadline: fireDate, execute: {
            if self.isNeedSend {
                self.sendData()
            }
        })
    }

    func onStop() {
        listening.onStop()
    }
}
extension Bridge where I == O {
    init(debounce time: DispatchTimeInterval) {
        var isNeedSend = true
        var fireDate: DispatchTime = .now()
        var next: I?

        func debounce(_ value: I, _ assign: @escaping (O) -> Void) {
            next = value
            guard fireDate <= .now() else { isNeedSend = true; return }

            isNeedSend = false
            next.map(assign)
            fireDate = .now() + time
            DispatchQueue.main.asyncAfter(deadline: fireDate, execute: {
                if isNeedSend, let n = next {
                    debounce(n, assign)
                }
            })
        }

        self.init(bridge: debounce)
    }
}
public extension Listenable {
    /// each next event are calling not earlier a specified period
    func debounce(_ time: DispatchTimeInterval) -> Preprocessor<OutData, OutData> {
        return Preprocessor(listenable: AnyListenable(self.listening, self.listeningItem), bridgeMaker: Bridge(debounce: time))
    }
}

// MARK: Cancellable listenings

// TODO: Disposable and ListeningItem does not have information about real active state listening (lifetime, delay listenings with autostop)
/// Disposes existing connection
public protocol Disposable {
    var dispose: () -> Void { get }
}

struct ListeningDispose: Disposable {
    let dispose: () -> Void
    init(_ dispose: @escaping () -> Void) {
        self.dispose = dispose
    }
}

/// Listening with possibility to control connection state
public struct ListeningItem {
    let start: () -> Void
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
    func add(to store: inout ListeningDisposeStore) {
        store.add(self)
    }
}

public extension Disposable {
    func add(to store: inout ListeningDisposeStore) {
        store.add(self)
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
