//
//  realtime.swift
//  GoogleToolboxForMac
//
//  Created by Denis Koryttsev on 31/07/2018.
//

import Foundation

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

public final class RealtimeApp {
    /// Default database instance
    public let database: RealtimeDatabase
    public let storage: RealtimeStorage
    public let configuration: Configuration

    init(db: RealtimeDatabase, storage: RealtimeStorage, configuration: Configuration) {
        self.database = db
        self.storage = storage
        self.configuration = configuration
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
        with database: RealtimeDatabase,
        storage: RealtimeStorage,
        configuration: Configuration = Configuration()
    ) {
        guard !_isInitialized else {
            fatalError("Realtime application already initialized. Call it only once.")
        }

        RealtimeApp._app = RealtimeApp(db: database, storage: storage, configuration: configuration)
        database.cachePolicy = configuration.cachePolicy
        RealtimeApp._isInitialized = true
    }

    public struct Configuration {
        public let linksNode: Node
        public let maxNodeDepth: UInt
        public let unavailableSymbols: CharacterSet
        public let cachePolicy: CachePolicy
        public let storageCache: RealtimeStorageCache?

        /// Default configuration based on Firebase Realtime Database
        public init(linksNode: BranchNode? = nil,
                    maxNodeDepth: UInt = .max,
                    unavailableSymbols: CharacterSet = CharacterSet(),
                    cachePolicy: CachePolicy = .noCache,
                    storageCache: RealtimeStorageCache? = nil
        ) {
            self.linksNode = linksNode ?? BranchNode(key: InternalKeys.links)
            self.maxNodeDepth = maxNodeDepth
            self.unavailableSymbols = unavailableSymbols
            self.cachePolicy = cachePolicy
            self.storageCache = storageCache

            debugFatalError(
                condition: self.linksNode.key.split(separator: "/")
                    .contains(where: { $0.rangeOfCharacter(from: self.unavailableSymbols) != nil }),
                "Key has unavailable symbols"
            )
        }
    }
}
extension RealtimeApp {
    internal static var _isInitialized: Bool = false
    fileprivate static var _app: RealtimeApp?
    /// Instance that contained Realtime database configuration
    public static var app: RealtimeApp {
        guard let app = _app else {
            fatalError("Realtime is not initialized. You must call RealtimeApp.initialize(...) in application(_:didFinishLaunchingWithOptions:)")
        }
        return app
    }
    public static var cache: RealtimeDatabase & RealtimeStorage { return Cache.root }
    public var connectionObserver: AnyListenable<Bool> { return database.isConnectionActive }
}

#if canImport(FirebaseDatabase) && (os(macOS) || os(iOS))
import FirebaseDatabase
import FirebaseStorage
#endif

#if canImport(FirebaseDatabase) && (os(macOS) || os(iOS))
public extension RealtimeApp.Configuration {
    static func firebase(
        linksNode: BranchNode? = nil,
        cachePolicy: CachePolicy = .noCache,
        storageCache: RealtimeStorageCache? = nil
    ) -> RealtimeApp.Configuration {
        return RealtimeApp.Configuration(
            linksNode: linksNode,
            maxNodeDepth: 32,
            unavailableSymbols: CharacterSet(charactersIn: ".#$][/"),
            cachePolicy: cachePolicy,
            storageCache: storageCache
        )
    }
}

extension RealtimeApp {
    public static func firebase(
        databaseUrl: String? = nil, storageUrl: String? = nil,
        configuration: Configuration = .firebase()
        ) {
        initialize(
            with: databaseUrl.map(Database.database) ?? Database.database(),
            storage: storageUrl.map(Storage.storage) ?? Storage.storage(),
            configuration: configuration
        )
    }
}
#endif
