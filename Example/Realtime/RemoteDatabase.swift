//
//  RemoteDatabase.swift
//  Realtime_Example
//
//  Created by Denis Koryttsev on 30/09/2019.
//  Copyright © 2019 CocoaPods. All rights reserved.
//

import Foundation
import Starscream
import Realtime
import RealtimeFoundationDBModels
import ClientServerAPI

class RemoteDatabase {
    let connection: WebSocket
    let connectionState: Repeater<Bool> = Repeater.unsafe()

    var runningOperations: [UInt64: ThrowsClosure<Client.ServerMessage, Void>] = [:]
    var operationsCounter: UInt64 = 0
    var observeNodes: [Node: NodeObserver] = [:]

    var reconnector: Timer?

    init(url: URL) {
        self.connection = WebSocket(url: url)
    }

    deinit {
        reconnector?.invalidate()
    }

    @objc func connect() {
        connection.delegate = self
        connection.connect()
    }

    func tryReconnect(through interval: TimeInterval) {
        reconnector?.invalidate()
        reconnector = Timer.scheduledTimer(timeInterval: interval, target: self, selector: #selector(connect), userInfo: nil, repeats: true)
    }
}

extension RemoteDatabase: WebSocketDelegate {
    func websocketDidConnect(socket: WebSocketClient) {
        reconnector?.invalidate()
        print("DID CONNECT")
        self.connectionState.send(.value(true))
    }

    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        print("DISCONNECT ERROR", error)
        self.connectionState.send(.value(false))

        tryReconnect(through: 10)
    }

    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        print("RECEIVE", text)
    }

    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        do {
            let response = try Client().read(data)
            switch response {
            case .load(let message):
                try runningOperations.removeValue(forKey: message.operationID)?.call(response)
            case .write(let message):
                try runningOperations.removeValue(forKey: message.operationID)?.call(response)
            case .observe(let message):
                try runningOperations[message.operationID]?.call(response)
            case .error(let message):
                try runningOperations.removeValue(forKey: message.operationID)?.call(response)
            }
        } catch let e {
            print(e)
        }
    }
}

extension RemoteDatabase {
    enum DBError: Error {
        case badServerResponse
    }
}

extension RemoteDatabase: RealtimeDatabase {
    var cachePolicy: CachePolicy {
        get { return .noCache }
        set(newValue) {}
    }

    func generateAutoID() -> String {
        return UUID().uuidString
    }

    func commit(update: UpdateNode, completion: ((Error?) -> Void)?) {
        let opID = operationsCounter; operationsCounter += 1
        let writeMessage = WriteMessage.Client(
            operationID: opID,
            values: update.reduceValues(into: [], { (res, node, val) in
                res.append((node, val))
            })
        )
        runningOperations[opID] = ThrowsClosure({ (response) in
            DispatchQueue.main.async {
                switch response {
                case .write: completion?(nil)
                case .error(let error): completion?(error)
                default: completion?(DBError.badServerResponse)
                }
            }
        })
        do {
            connection.write(data: try writeMessage.packed())
        } catch let e {
            completion?(e)
        }
    }

    func load(for node: Node, timeout: DispatchTimeInterval, completion: @escaping (RealtimeDataProtocol) -> Void, onCancel: ((Error) -> Void)?) {
        if let observer = observeNodes[node] {
            if observer.initialLoadReceived {
                return RealtimeApp.cache.load(for: node, timeout: timeout, completion: completion, onCancel: onCancel)
            } else {
                _ = observer.repeater(for: .value).once().listening(onValue: completion, onError: { onCancel?($0) })
            }
            return
        }
        let opID = operationsCounter; operationsCounter += 1
        let loadMessage = LoadMessage(operationID: opID, node: node)
        runningOperations[opID] = ThrowsClosure({ [weak self] (response) in
            DispatchQueue.main.async {
                switch response {
                case .load(let message): completion(DatabaseNode(node: node, database: self, rows: message.values))
                case .error(let error): onCancel?(error)
                default: onCancel?(DBError.badServerResponse)
                }
            }
        })
        do {
            connection.write(data: try loadMessage.packed())
        } catch let e {
            onCancel?(e)
        }
    }

    func observe(_ event: DatabaseDataEvent, on node: Node, onUpdate: @escaping (RealtimeDataProtocol) -> Void, onCancel: ((Error) -> Void)?) -> UInt {
        let opID = operationsCounter; operationsCounter += 1

        do {
            let (observer, alreadyObserved) = try observeNodes[node].map({ ($0, true) }) ?? (_sendObserve(node, initialEvent: event, operationID: opID), false)
            let onEvent = observer.repeater(for: event)

            if alreadyObserved && observer.initialLoadReceived {
                RealtimeApp.cache.load(for: node, timeout: .seconds(30), completion: onUpdate, onCancel: onCancel)
            }

            observer.tokens[opID] = onEvent.queue(.main).listening(
                onValue: onUpdate,
                onError: { e in
                    print(e)
                    onCancel?(e)
                }
            )
        } catch let e {
            onCancel?(e)
        }

        return UInt(opID)
    }

    func observe(_ event: DatabaseDataEvent, on node: Node, limit: UInt, before: Any?, after: Any?, ascending: Bool, ordering: RealtimeDataOrdering, completion: @escaping (RealtimeDataProtocol, DatabaseDataEvent) -> Void, onCancel: ((Error) -> Void)?) -> Disposable {
        return EmptyDispose()
    }

    func runTransaction(in node: Node, withLocalEvents: Bool, _ updater: @escaping (RealtimeDataProtocol) -> ConcurrentIterationResult, onComplete: ((ConcurrentOperationResult) -> Void)?) {

    }

    func removeAllObservers(for node: Node) {

    }

    func removeObserver(for node: Node, with token: UInt) {
        let token = UInt64(token)
        guard let observer = observeNodes[node] else {
            return print("Cannot remove observer, because node is not observed")
        }
        guard let disposable = observer.tokens.removeValue(forKey: token) else {
            return print("Cannot remove observer, because didn't found token")
        }
        disposable.dispose()
        guard observer.tokens.isEmpty else { return }

        let observeMessage = ObserveMessage(operationID: observer.operationID, enable: false, event: .value, node: node)
        do {
            connection.write(data: try observeMessage.packed())
            observeNodes.removeValue(forKey: node)
        } catch let e {
            print(e)
        }
    }

    var isConnectionActive: AnyListenable<Bool> {
        return AnyListenable(self.connectionState)
    }
}

class NodeObserver {
    let operationID: UInt64
    var observers: [DatabaseObservingEvent: Repeater<RealtimeDataProtocol>] = [:]
    var tokens: [UInt64: Disposable] = [:]
    var initialLoadReceived: Bool = false

    init(operationID: UInt64) {
        self.operationID = operationID
    }

    func repeater(for event: DatabaseObservingEvent) -> AnyListenable<RealtimeDataProtocol> {
        let repeater = observers[event] ?? {
            let repeater = Repeater<RealtimeDataProtocol>.unsafe()
            observers[event] = repeater
            return repeater
        }()
        return AnyListenable(repeater)
    }

    func sendAll(_ data: RealtimeDataProtocol) {
        observers.forEach { (key, value) in
            value.send(.value(data))
        }
    }

    func cancel(_ error: Error) {
        observers.forEach { (key, value) in
            value.send(.error(error))
        }
    }

    func obtain(next message: ObserveResponseMessage, for node: Node, in database: RealtimeDatabase, cache: RealtimeDatabase) {
        if !initialLoadReceived {
            initialLoadReceived = true
            sendAll(DatabaseNode(node: node, database: database, rows: message.values))

            message.write(to: cache)
        } else {
            cache.load(
                for: node, timeout: .seconds(30),
                completion: { (cachedData: RealtimeDataProtocol) in
                    let analyzedUpdate = try! UpdateEventAnalyzer(node: node).analyze(message, cached: cachedData)
                    switch analyzedUpdate {
                    case .value(let removed):
                        if let value = self.observers[.value] {
                            value.send(.value(DatabaseNode(node: node, database: database, rows: message.values)))
                        }
                        if let changed = self.observers[.child(.changed)] {
                            if removed {
                                cachedData.forEach({ child in
                                    changed.send(.value(DatabaseNode(node: child.node!, database: database, result: .single(nil))))
                                })
                            } else {
                                changed.send(.value(DatabaseNode(node: node, database: database, rows: message.values)))
                            }
                        }
                        if let added = self.observers[.child(.added)] {
                            if !removed {
                                added.send(.value(DatabaseNode(node: node, database: database, rows: message.values)))
                            } else {
                                print("skip event", message)
                            }
                        }
                        if let removedObservers = self.observers[.child(.removed)] {
                            if removed {
                                cachedData.forEach({ child in
                                    removedObservers.send(.value(child))
                                })
                            } else {
                                print("skip event", message)
                            }
                        }
                    case .child(let change):
                        if let value = self.observers[.value] {
                            // TODO: mutate cache data
                            let mutated = cachedData
                            value.send(.value(mutated))
                        }
                        if let event = self.observers[.child(change)] {
                            if change != .removed {
                                event.send(.value(DatabaseNode(node: node, database: database, rows: message.values)))
                            } else {
                                event.send(.value(cachedData.child(forPath: try! message.actionKey.read(at: message.actionKey.count - 1))))
                            }
                        }
                    }
                    message.write(to: cache)
                },
                onCancel: nil
            )
        }
    }
}

extension RemoteDatabase {
    func _sendObserve(_ node: Node, initialEvent: DatabaseObservingEvent, operationID: UInt64) throws -> NodeObserver {
        let observer = NodeObserver(operationID: operationID)

        let observeMessage = ObserveMessage(operationID: operationID, enable: true, event: .value, node: node)
        runningOperations[operationID] = ThrowsClosure({ [unowned self] (response) in
            switch response {
            case .observe(let message):
                observer.obtain(next: message, for: node, in: self, cache: RealtimeApp.cache)
            case .error(let error):
                self.observeNodes.removeValue(forKey: node)?.cancel(error)
            default:
                self.observeNodes.removeValue(forKey: node)?.cancel(DBError.badServerResponse)
            }
        })

        connection.write(data: try observeMessage.packed())
        observeNodes[node] = observer

        return observer
    }
}

fileprivate extension ObserveResponseMessage {
    func write(to database: RealtimeDatabase) {
        let transaction = Transaction(database: database, storage: RealtimeApp.cache)
        if values.isEmpty {
            transaction.removeValue(by: try! Node(tuple: actionKey))
        } else {
           values.forEach({ (key, value) in
                transaction.addValue(try! value.extractAsRealtimeDatabaseValue(), by: try! Node(tuple: key))
            })
        }
        transaction.commit(with: nil)
    }
}
