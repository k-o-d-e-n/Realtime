//
//  realtime.swift
//  GoogleToolboxForMac
//
//  Created by Denis Koryttsev on 31/07/2018.
//

import Foundation
import FirebaseDatabase

public class RealtimeApp {
    /// Default database instance
    public let database: RealtimeDatabase
    //    let storage:
    let linksNode: Node
    var cachePolicy: CachePolicy = .noCache

    init(db: RealtimeDatabase, linksNode: Node) {
        self.database = db
        self.linksNode = linksNode
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
        cachePolicy: CachePolicy = .default,
        linksNode: Node? = nil
        ) {
        RealtimeApp._app = RealtimeApp(db: database, linksNode: linksNode ?? Node(key: InternalKeys.links, parent: .root))
        database.cachePolicy = cachePolicy
    }
}
extension RealtimeApp {
    fileprivate static var _app: RealtimeApp?
    /// Instance that contained Realtime database configuration
    public static var app: RealtimeApp {
        guard let app = _app else {
            fatalError("Realtime is not initialized. Call please RealtimeApp.initialize(...) in application(_:didFinishLaunchingWithOptions:)")
        }
        return app
    }
}
