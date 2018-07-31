//
//  realtime.database.swift
//  Realtime
//
//  Created by Denis Koryttsev on 31/07/2018.
//

import Foundation
import FirebaseDatabase

protocol DatabaseNode {
    func update(use keyValuePairs: [String: Any], completion: ((Error?, DatabaseNode) -> Void)?)
}
extension DatabaseReference: DatabaseNode {
    func update(use keyValuePairs: [String : Any], completion: ((Error?, DatabaseNode) -> Void)?) {
        if let completion = completion {
            updateChildValues(keyValuePairs, withCompletionBlock: completion)
        } else {
            updateChildValues(keyValuePairs)
        }
    }
}

protocol RealtimeDatabase {
    func node() -> DatabaseNode
    func node(with valueNode: Node) -> DatabaseNode
}
extension Database: RealtimeDatabase {
    func node() -> DatabaseNode {
        return reference()
    }

    func node(with valueNode: Node) -> DatabaseNode {
        return reference(withPath: valueNode.rootPath)
    }
}
