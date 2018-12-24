//
//  realtime.swift
//  GoogleToolboxForMac
//
//  Created by Denis Koryttsev on 31/07/2018.
//

import Foundation
import FirebaseDatabase
import FirebaseStorage

internal func debugAction(_ action: () -> Void) {
    #if DEBUG
    action()
    #endif
}

internal func debugLog(_ message: String, _ file: String = #file, _ line: Int = #line) {
    debugAction {
        debugPrint("File: \(file)")
        debugPrint("Line: \(line)")
        debugPrint("Message: \(message)")
    }
}

internal func debugPrintLog(_ message: String) {
    debugAction {
        debugPrint("Realtime log: \(message)")
    }
}

internal func debugFatalError(condition: @autoclosure () -> Bool = true,
                              _ message: @autoclosure () -> String = "", _ file: String = #file, _ line: Int = #line) {
    debugAction {
        if condition() {
            debugLog(message(), file, line)
            if ProcessInfo.processInfo.arguments.contains("REALTIME_CRASH_ON_ERROR") {
                fatalError(message)
            }
        }
    }
}

extension ObjectIdentifier {
    var memoryAddress: String {
        return "0x\(String(hashValue, radix: 16))"
    }
}

public class RealtimeApp {
    /// Default database instance
    public let database: RealtimeDatabase
    public let storage: RealtimeStorage
    let linksNode: Node
    let maxNodeDepth: Int
    let unavailableSymbols: CharacterSet = CharacterSet(charactersIn: ".#$][/")
    var cachePolicy: CachePolicy = .noCache

    init(db: RealtimeDatabase, storage: RealtimeStorage, linksNode: Node, maxDepth: Int) {
        self.database = db
        self.storage = storage
        self.linksNode = linksNode
        self.maxNodeDepth = maxDepth
    }

    /// Creates default configuration for Realtime application.
    ///
    /// Should call once in `application(_:didFinishLaunchingWithOptions:)`.
    ///
    /// - Parameters:
    ///   - database: Realtime database instance
    ///   - cachePolicy: Cache policy. Default value = .default
    ///   - linksNode: Database reference where will be store service data
    /// is related with creation external links.
    public static func initialize(
        with database: RealtimeDatabase = Database.database(),
        storage: RealtimeStorage = Storage.storage(),
        cachePolicy: CachePolicy = .default,
        linksNode: BranchNode? = nil,
        maxNodeDepth: Int = 32
        ) {
        guard !_isInitialized else {
            fatalError("Realtime application already initialized. Call it only once.")
        }

        RealtimeApp._app = RealtimeApp(
            db: database, storage: storage,
            linksNode: linksNode ?? BranchNode(key: InternalKeys.links),
            maxDepth: maxNodeDepth
        )
        database.cachePolicy = cachePolicy
        RealtimeApp._isInitialized = true
    }
}
extension RealtimeApp {
    internal static var _isInitialized: Bool = false
    fileprivate static var _app: RealtimeApp?
    /// Instance that contained Realtime database configuration
    public static var app: RealtimeApp {
        guard let app = _app else {
            fatalError("Realtime is not initialized. Call please RealtimeApp.initialize(...) in application(_:didFinishLaunchingWithOptions:)")
        }
        return app
    }
    public static var cache: RealtimeDatabase { return Cache.root }
    public var connectionObserver: AnyListenable<Bool> { return database.isConnectionActive }
}
