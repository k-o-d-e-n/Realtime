//
//  realtime.swift
//  GoogleToolboxForMac
//
//  Created by Denis Koryttsev on 31/07/2018.
//

import Foundation
import FirebaseDatabase

struct RealtimeApp {
    let database: RealtimeDatabase
//    let storage:

    static func initialize(with database: RealtimeDatabase = Database.database()) {
        RealtimeApp.app = RealtimeApp(database: database)
    }
}
extension RealtimeApp {
    static var app: RealtimeApp!
}
