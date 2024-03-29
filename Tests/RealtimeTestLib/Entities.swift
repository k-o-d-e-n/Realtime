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
    lazy var chairman: Reference<User> = l().reference(in: self, mode: .fullPath)
    lazy var secretary: Reference<User?> = l().reference(in: self, mode: .fullPath)

    override open class func lazyPropertyKeyPath(for label: String) -> AnyKeyPath? {
        switch label {
        case "chairman": return \Conversation.chairman
        case "secretary": return \Conversation.secretary
        default: return nil
        }
    }
}

class Group: Object {
    lazy var name: Property<String> = l().property(in: self)
    lazy var users: MutableReferences<User> = l().references(in: self, mode: .path(from: Global.rtUsers.node!))
    lazy var conversations: AssociatedValues<User, User> = l().dictionary(in: self, keys: Global.rtUsers.node!)
    lazy var manager: Relation<User?> = l().relation(in: self, .one(name: "ownedGroup"))

    lazy var _manager: Relation<User?> = l().relation(in: self, .many(format: "ownedGroups/%@"))

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
    lazy var name: Property<String> = l().property(in: self)
    lazy var age: Property<UInt8> = l().property(in: self)
    lazy var photo: File<Data?> = l().file(in: self, representer: .realtimeDataValue)
    lazy var groups: MutableReferences<Group> = l().references(in: self, mode: .path(from: Global.rtGroups.node!))
    lazy var followers: MutableReferences<User> = l().references(in: self, mode: .path(from: Global.rtUsers.node!))
    lazy var scheduledConversations: Values<Conversation> = l().values(in: self)

    lazy var ownedGroup: Relation<Group?> = l().relation(in: self, .one(name: "manager"))
    lazy var ownedGroups: Relations<Group> = l().relations(in: self, .one(name: "_manager"))

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
    lazy var human: Property<String> = l().property(in: self)

    override class func lazyPropertyKeyPath(for label: String) -> AnyKeyPath? {
        switch label {
        case "human": return \User2.human
        default: return nil
        }
    }
}


@dynamicMemberLookup
protocol Realtime_Object: Object {
    associatedtype Properties
    subscript<T>(dynamicMember member: WritableKeyPath<Properties, Property<T>>) -> T? { get }
}

@dynamicMemberLookup
class RealtimeObject: Object, Realtime_Object {
    private var _properties: Properties = Properties()

    required init(in node: Node? = nil, options: RealtimeValueOptions = RealtimeValueOptions()) {
        super.init(in: node, options: options)
    }

    required init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        try super.init(data: data, event: event)
    }

    subscript<T>(dynamicMember member: WritableKeyPath<Properties, Property<T>>) -> T? {
        let storage = _properties[keyPath: member]
        if node != nil, let propNode = storage.node, propNode.parent != node {
//            propNode.parent = node
        }
        return storage.wrappedValue
    }
//    subscript<T>(dynamicMember member: KeyPath<Properties, ReadonlyProperty<T>>) -> T? {
//        _properties[keyPath: member].wrappedValue
//    }
//    subscript<T>(dynamicMember member: KeyPath<Properties, File<T>>) -> T? {
//        _properties[keyPath: member].wrappedValue
//    }
//    subscript<T>(dynamicMember member: KeyPath<Properties, ReadonlyFile<T>>) -> T? {
//        _properties[keyPath: member].wrappedValue
//    }
}
extension RealtimeObject {
    final class Properties {
        lazy var name: Property<String> = Property(in: Node(key: "name"), options: .required(.realtimeDataValue))
        lazy var age: Property<UInt8> = Property(in: Node(key: "age"), options: .required(.realtimeDataValue))
    }
}

func testImmutable() {
    let obj = User()
    let immutableObj = RealtimeObject()
    let age = immutableObj.age
    immutableObj.name
}
