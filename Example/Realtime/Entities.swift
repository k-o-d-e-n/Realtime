//
//  Entities.swift
//  Realtime
//
//  Created by Denis Koryttsev on 24/12/2018.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import Foundation
import Realtime

#if canImport(UIKit)
import UIKit
#endif

enum Global {
    static let rtUsers: Values<User> = Values(in: Node.root("___tests/_users"))
    static let rtGroups: Values<Group> = Values(in: Node.root("___tests/_groups"))
}

class Conversation: Object {
    lazy var chairman: Reference<User> = "chairman".reference(in: self, mode: .fullPath)
    lazy var secretary: Reference<User?> = "secretary".reference(in: self, mode: .fullPath)

    override open class func lazyPropertyKeyPath(for label: String) -> AnyKeyPath? {
        switch label {
        case "chairman": return \Conversation.chairman
        case "secretary": return \Conversation.secretary
        default: return nil
        }
    }
}

class Group: Object {
    lazy var name: Property<String> = "name".property(in: self)
    lazy var users: MutableReferences<User> = "users".references(in: self, mode: .path(from: Global.rtUsers.node!))
    lazy var conversations: AssociatedValues<User, User> = "conversations".dictionary(in: self, keys: Global.rtUsers.node!)
    lazy var manager: Relation<User?> = "manager".relation(in: self, .one(name: "ownedGroup"))

    lazy var _manager: Relation<User?> = "_manager".relation(in: self, .many(format: "ownedGroups/%@"))

    override open class func lazyPropertyKeyPath(for label: String) -> AnyKeyPath? {
        switch label {
        case "name": return \Group.name
        case "users": return \Group.users
        case "conversations": return \Group.conversations
        case "manager": return \Group.manager
        case "_manager": return \Group._manager
        default: return nil
        }
    }
}

class User: Object {
    lazy var name: Property<String> = "name".property(in: self)
    lazy var age: Property<UInt8> = "age".property(in: self)
    lazy var photo: File<Data?> = "photo".file(in: self, representer: .realtimeDataValue)
    lazy var groups: MutableReferences<Group> = "groups".references(in: self, mode: .path(from: Global.rtGroups.node!))
    lazy var followers: MutableReferences<User> = "followers".references(in: self, mode: .path(from: Global.rtUsers.node!))
    lazy var scheduledConversations: Values<Conversation> = "scheduledConversations".values(in: self)

    lazy var ownedGroup: Relation<Group?> = "ownedGroup".relation(in: self, .one(name: "manager"))
    lazy var ownedGroups: Relations<Group> = "ownedGroups".relations(in: self, .one(name: "_manager"))

    //    override class var keyPaths: [String: AnyKeyPath] {
    //        return super.keyPaths.merging(["name": \RealtimeUser.name, "age": \RealtimeUser.age], uniquingKeysWith: { (_, new) -> AnyKeyPath in
    //            return new
    //        })
    //    }

    override class func lazyPropertyKeyPath(for label: String) -> AnyKeyPath? {
        switch label {
        case "name": return \User.name
        case "age": return \User.age
        case "photo": return \User.photo
        case "groups": return \User.groups
        case "followers": return \User.followers
        case "ownedGroup": return \User.ownedGroup
        case "ownedGroups": return \User.ownedGroups
        case "scheduledConversations": return \User.scheduledConversations
        default: return nil
        }
    }
}

class User2: User {
    lazy var human: Property<String> = "human".property(in: self)

    override class func lazyPropertyKeyPath(for label: String) -> AnyKeyPath? {
        switch label {
        case "human": return \User2.human
        default: return nil
        }
    }
}
