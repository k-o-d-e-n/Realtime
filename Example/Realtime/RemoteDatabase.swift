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
    var observeNodes: [UInt64: DatabaseDataEvent] = [:]

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
        let observeMessage = ObserveMessage(operationID: opID, enable: true, event: event, node: node)
        runningOperations[opID] = ThrowsClosure({ [weak self] (response) in
            DispatchQueue.main.async {
                switch response {
                case .observe(let message):
                    switch (event, message.event) {
                    case (.value, .value): onUpdate(DatabaseNode(node: node, database: self, rows: message.values))
                    case (.child(let expectedTypes), .child(.added)) where expectedTypes.contains(.added),
                         (.child(let expectedTypes), .child(.removed)) where expectedTypes.contains(.removed),
                         (.child(let expectedTypes), .child(.changed)) where expectedTypes.contains(.changed),
                         (.child(let expectedTypes), .child(.moved)) where expectedTypes.contains(.moved):
                        onUpdate(DatabaseNode(node: node, database: self, rows: message.values))
                    case (.child, .value):
                        print("Initial value for node:", node, ":", message)
                        onUpdate(DatabaseNode(node: node, database: self, rows: message.values))
                    case (.value, .child(let occuredTypes)):
                        print("Child received", message)
                    default: break
                    }
                case .error(let error):
                    self?.observeNodes.removeValue(forKey: opID)
                    onCancel?(error)
                default:
                    self?.observeNodes.removeValue(forKey: opID)
                    onCancel?(DBError.badServerResponse)
                }
            }
        })
        do {
            connection.write(data: try observeMessage.packed())
            observeNodes[opID] = event
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
        let opID = UInt64(token)
        guard let event = observeNodes[opID] else {
            return print("Cannot remove observer, because didn't found token")
        }
        let observeMessage = ObserveMessage(operationID: opID, enable: false, event: event, node: node)
        do {
            connection.write(data: try observeMessage.packed())
        } catch let e {
            print(e)
        }
    }

    var isConnectionActive: AnyListenable<Bool> {
        return AnyListenable(self.connectionState)
    }
}
