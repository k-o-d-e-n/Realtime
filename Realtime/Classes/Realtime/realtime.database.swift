//
//  realtime.database.swift
//  Realtime
//
//  Created by Denis Koryttsev on 31/07/2018.
//

import Foundation
import FirebaseDatabase

public protocol DatabaseNode {
    var cachedData: FireDataProtocol? { get }
//    func update(use keyValuePairs: [String: Any], completion: ((Error?, DatabaseNode) -> Void)?)
}
extension DatabaseReference: DatabaseNode {
    public var cachedData: FireDataProtocol? { return nil }
//    public func update(use keyValuePairs: [String : Any], completion: ((Error?, DatabaseNode) -> Void)?) {
//        if let completion = completion {
//            updateChildValues(keyValuePairs, withCompletionBlock: completion)
//        } else {
//            updateChildValues(keyValuePairs)
//        }
//    }
}

public protocol RealtimeDatabase {
    func node() -> DatabaseNode
    func node(with valueNode: Node) -> DatabaseNode
}
extension Database: RealtimeDatabase {
    public func node() -> DatabaseNode {
        return reference()
    }

    public func node(with valueNode: Node) -> DatabaseNode {
        return reference(withPath: valueNode.rootPath)
    }
}
