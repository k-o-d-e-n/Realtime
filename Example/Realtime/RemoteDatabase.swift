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

class RemoteDatabase {
    let connection: WebSocket
    let connectionState: Repeater<Bool> = Repeater.unsafe()

    var sheduledCommands: [UInt: ClientMessage] = [:]
    var commandsCounter: UInt = 0

    init(url: URL) {
        self.connection = WebSocket(url: url)
    }

    func connect() {
        connection.delegate = self
        connection.connect()
    }
}

extension RemoteDatabase: WebSocketDelegate {
    func websocketDidConnect(socket: WebSocketClient) {
        print("DID CONNECT")
        self.connectionState.send(.value(true))
    }

    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        print("DISCONNECT ERROR", error)
        self.connectionState.send(.value(false))
    }

    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        print("RECEIVE", text)
    }

    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        print("RECEIVE DATA", String(data: data, encoding: .utf8))
    }
}

struct ClientMessage: Codable {
    let c: String
    let cid: String
    let k: String?

    static func load(node: Node, commandID: UInt, completion: @escaping (Data) -> Void) -> ClientMessage {
        return ClientMessage(c: "l", cid: "\(commandID)", k: node.absolutePath)
    }

    func encoded() throws -> Data {
        return try JSONEncoder().encode(self)
    }
}
extension RemoteDatabase {
    struct ServerMessage: Codable {
        let cid: String
//        let r: NSDictionary
    }
    struct Response {
        let response: ServerMessage?
        let error: ServerError?
    }
    struct ServerError: Error, Codable {
        let message: String
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

    }

    func load(for node: Node, timeout: DispatchTimeInterval, completion: @escaping (RealtimeDataProtocol) -> Void, onCancel: ((Error) -> Void)?) {
        let commandID = commandsCounter; commandsCounter += 1
        let loadCommand = ClientMessage.load(node: node, commandID: commandID) { (data) in
            
        }
        sheduledCommands[commandID] = loadCommand
        connection.write(data: try! loadCommand.encoded())
    }

    func observe(_ event: DatabaseDataEvent, on node: Node, onUpdate: @escaping (RealtimeDataProtocol) -> Void, onCancel: ((Error) -> Void)?) -> UInt {
        return 0
    }

    func observe(_ event: DatabaseDataEvent, on node: Node, limit: UInt, before: Any?, after: Any?, ascending: Bool, ordering: RealtimeDataOrdering, completion: @escaping (RealtimeDataProtocol, DatabaseDataEvent) -> Void, onCancel: ((Error) -> Void)?) -> Disposable {
        return EmptyDispose()
    }

    func runTransaction(in node: Node, withLocalEvents: Bool, _ updater: @escaping (RealtimeDataProtocol) -> ConcurrentIterationResult, onComplete: ((ConcurrentOperationResult) -> Void)?) {

    }

    func removeAllObservers(for node: Node) {

    }

    func removeObserver(for node: Node, with token: UInt) {

    }

    var isConnectionActive: AnyListenable<Bool> {
        return AnyListenable(self.connectionState)
    }
}
