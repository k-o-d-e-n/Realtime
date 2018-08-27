//
//  realtime.swift
//  GoogleToolboxForMac
//
//  Created by Denis Koryttsev on 31/07/2018.
//

import Foundation
import FirebaseDatabase

public class RealtimeApp {
    public let database: RealtimeDatabase
    //    let storage:
    let linksNode: Node
    var cachePolicy: CachePolicy = .noCache

    init(db: RealtimeDatabase, linksNode: Node) {
        self.database = db
        self.linksNode = linksNode
    }

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
    public static var app: RealtimeApp {
        guard let app = _app else {
            fatalError("Realtime is not initialized. Call please RealtimeApp.initialize(...) in application(_:didFinishLaunchingWithOptions:)")
        }
        return app
    }
}
