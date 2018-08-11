//
//  realtime.swift
//  GoogleToolboxForMac
//
//  Created by Denis Koryttsev on 31/07/2018.
//

import Foundation
import FirebaseDatabase

public struct RealtimeApp {
    let database: RealtimeDatabase
    let linksNode: Node
//    let storage:

    public static func initialize(with database: RealtimeDatabase = Database.database(),
                           linksNode: Node? = nil) {
        RealtimeApp._app = RealtimeApp(database: database, linksNode: linksNode ?? Node(key: InternalKeys.links, parent: .root))
    }
}
extension RealtimeApp {
    fileprivate static var _app: RealtimeApp!
    public static var app: RealtimeApp { return _app }
}
