//
//  AppDelegate.swift
//  Realtime
//
//  Created by k-o-d-e-n on 01/11/2018.
//  Copyright (c) 2018 k-o-d-e-n. All rights reserved.
//

import UIKit
import Firebase
import Realtime

func currentDatabase() -> RealtimeDatabase {
    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
        return RealtimeApp.cache
    } else {
        return Database.database()
    }
}

func currentStorage() -> RealtimeStorage {
    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
        return RealtimeApp.cache
    } else {
        return Storage.storage()
    }
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    let store: ListeningDisposeStore = ListeningDisposeStore()
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        FirebaseApp.configure()
        let configuration = RealtimeApp.Configuration.firebase(linksNode: BranchNode(key: "___tests/__links"))
        let remoteDatabase = RemoteDatabase(url: URL(string: "ws://localhost:8080")!)
        remoteDatabase.connect()
        RealtimeApp.initialize(with: remoteDatabase, storage: currentStorage(), configuration: configuration)
        RealtimeApp.app.connectionObserver.listening(
            onValue: { (connected) in
                print("Connection did change to \(connected)")
            },
            onError: { e in
                debugPrint(e)
            }
        ).add(to: store)
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }
}

import Network

@available(iOS 12.0, *)
class RemoteConnection {
    let nwConnection: NWConnection
//    let state: Repeater<NWConnection.State> = Repeater.unsafe()
//    var currentState: NWConnection.State {
//        return nwConnection.state
//    }
    let host: String
    let port: NWEndpoint.Port

    init(host: String = "127.0.0.1", port: UInt16 = 8080) {
        let portValue = NWEndpoint.Port(rawValue: port)!
        self.host = host
        self.port = portValue
        self.nwConnection = NWConnection(to: NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: portValue), using: .tcp)
    }

    func connect() {
        nwConnection.stateUpdateHandler = { [weak self] state in
            print("STATE", state)
            switch state {
            case .ready: break
            default: break
            }
//            self?.state.send(.value(state))
        }
        nwConnection.receive(minimumIncompleteLength: 2, maximumLength: 4096, completion: { (data, context, complete, err) in
            print("RECEIVED", data.flatMap({ String(data: $0, encoding: .ascii) }), context, complete, err)
        })

        nwConnection.start(queue: .main)
    }

    func establishHandshake() {
        let req = createHTTPRequest(host: host, port: port, enableCompression: false)
        nwConnection.send(content: req.httpBody, completion: .contentProcessed({ (err) in
            print("ERROR", err)
        }))
    }

    func disconnect() {
        nwConnection.cancel()
    }
}

enum WebSockets {
static let headerWSUpgradeName     = "Upgrade"
static let headerWSUpgradeValue    = "websocket"
static let headerWSHostName        = "Host"
static let headerWSConnectionName  = "Connection"
static let headerWSConnectionValue = "Upgrade"
static let headerWSProtocolName    = "Sec-WebSocket-Protocol"
static let headerWSVersionName     = "Sec-WebSocket-Version"
static let headerWSVersionValue    = "13"
static let headerWSExtensionName   = "Sec-WebSocket-Extensions"
static let headerWSKeyName         = "Sec-WebSocket-Key"
static let headerOriginName        = "Origin"
static let headerWSAcceptName      = "Sec-WebSocket-Accept"
static let supportedSSLSchemes     = ["wss", "https"]
}

@available(iOS 12.0, *)
private func createHTTPRequest(host: String, port: NWEndpoint.Port, enableCompression: Bool) -> URLRequest {
    let urlString = "\(host):\(port.rawValue)"
    let url = URL(string: urlString)!
    var request = URLRequest(url: url)
    request.setValue(WebSockets.headerWSUpgradeValue, forHTTPHeaderField: WebSockets.headerWSUpgradeName)
    request.setValue(WebSockets.headerWSConnectionValue, forHTTPHeaderField: WebSockets.headerWSConnectionName)
    request.setValue(WebSockets.headerWSVersionValue, forHTTPHeaderField: WebSockets.headerWSVersionName)
    request.setValue(generateWebSocketKey(), forHTTPHeaderField: WebSockets.headerWSKeyName)

    if enableCompression {
        let val = "permessage-deflate; client_max_window_bits; server_max_window_bits=15"
        request.setValue(val, forHTTPHeaderField: WebSockets.headerWSExtensionName)
    }
    request.setValue(urlString, forHTTPHeaderField: WebSockets.headerWSHostName)

    var path = url.absoluteString
    let offset = (url.scheme?.count ?? 2) + 3
    path = String(path[path.index(path.startIndex, offsetBy: offset)..<path.endIndex])
    if let range = path.range(of: "/") {
        path = String(path[range.lowerBound..<path.endIndex])
    } else {
        path = "/"
        if let query = url.query {
            path += "?" + query
        }
    }

    var httpBody = "\(request.httpMethod ?? "GET") \(path) HTTP/1.1\r\n"
    if let headers = request.allHTTPHeaderFields {
        for (key, val) in headers {
            httpBody += "\(key): \(val)\r\n"
        }
    }
    httpBody += "\r\n"

    request.httpBody = httpBody.data(using: .utf8)!
    return request
//    initStreamsWithData(, Int(port!))
//    httpDelegate?.websocketHttpUpgrade(socket: self, request: httpBody)
}

private func generateWebSocketKey() -> String {
    var key = ""
    let seed = 16
    for _ in 0..<seed {
        let uni = UnicodeScalar(UInt32(97 + arc4random_uniform(25)))
        key += "\(Character(uni!))"
    }
    let data = key.data(using: String.Encoding.utf8)
    let baseKey = data?.base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0))
    return baseKey!
}
