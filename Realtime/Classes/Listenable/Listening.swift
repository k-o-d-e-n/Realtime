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
