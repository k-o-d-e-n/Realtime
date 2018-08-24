//
//  Listening.swift
//  GoogleToolboxForMac
//
//  Created by Denis Koryttsev on 31/01/2018.
//

import Foundation

// MARK: Cancellable listenings

/// Disposes existing connection
public protocol Disposable {
    func dispose()
}

class ListeningDispose: Disposable {
    let _dispose: () -> Void
    init(_ dispose: @escaping () -> Void) {
        self._dispose = dispose
    }
    func dispose() {
        _dispose()
    }
    deinit {
        _dispose()
    }
}

/// Listening with possibility to control connection state
public class ListeningItem {
    let _start: () -> Void
    let _stop: () -> Void
    let _isListen: () -> Bool

    public var isListen: Bool { return _isListen() }

    init<Token>(resume: @escaping () -> Token?, pause: @escaping (Token) -> Void, token: Token?) {
        var tkn = token
        self._isListen = { tkn != nil }
        self._start = {
            guard tkn == nil else { return }
            tkn = resume()
        }
        self._stop = {
            guard let token = tkn else { return }
            pause(token)
            tkn = nil
        }
    }

    public func resume() {
        _start()
    }

    public func pause() {
        _stop()
    }

    deinit {
        dispose()
    }
}
extension ListeningItem: Disposable {
    public func dispose() {
        _stop()
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
        listeningItems.forEach { $0.dispose() }
        listeningItems.removeAll()
    }

    public func pause() {
        listeningItems.forEach { $0.pause() }
    }

    public func resume() {
        listeningItems.forEach { $0.resume() }
    }
}
