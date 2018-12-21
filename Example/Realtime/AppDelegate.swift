//
//  AppDelegate.swift
//  Realtime
//
//  Created by k-o-d-e-n on 01/11/2018.
//  Copyright (c) 2018 k-o-d-e-n. All rights reserved.
//

import UIKit
import Firebase
import Realtime

enum Global {
    static let rtUsers: Values<User> = Values(in: Node(key: "___tests/_users", parent: .root))
    static let rtGroups: Values<Group> = Values(in: Node(key: "___tests/_groups", parent: .root))
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
    lazy var users: References<User> = "users".references(in: self, elements: Global.rtUsers.node!)
    lazy var conversations: AssociatedValues<User, User> = "conversations".dictionary(in: self, keys: Global.rtUsers.node!)
    lazy var manager: Relation<User?> = "manager".relation(in: self, .oneToOne("ownedGroup"))

    lazy var _manager: Relation<User?> = "_manager".relation(in: self, rootLevelsUp: nil, .oneToMany("ownedGroups"))

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
    lazy var age: Property<Int> = "age".property(in: self)
    lazy var photo: File<UIImage?> = "photo".file(in: self, representer: .png)
    lazy var groups: References<Group> = "groups".references(in: self, elements: Global.rtGroups.node!)
    lazy var followers: References<User> = "followers".references(in: self, elements: Global.rtUsers.node!)
    lazy var scheduledConversations: Values<Conversation> = "scheduledConversations".values(in: self)

    lazy var ownedGroup: Relation<Group?> = "ownedGroup".relation(in: self, .oneToOne("manager"))

//    lazy var ownedGroups: 

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
        case "scheduledConversations": return \User.scheduledConversations
        default: return nil
        }
    }
}

class User2: User {
    lazy var human: Property<[String: RealtimeDataValue]> = "human".property(in: self)

    override class func lazyPropertyKeyPath(for label: String) -> AnyKeyPath? {
        switch label {
        case "human": return \User2.human
        default: return nil
        }
    }
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        FirebaseApp.configure()
        RealtimeApp.initialize(linksNode: Node(key: "__links", parent: Node(key: "___tests", parent: .root)))
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }
}

