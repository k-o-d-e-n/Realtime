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
    static let rtUsers: RealtimeArray<RealtimeUser> = "___tests/_users".array(from: .root)
    static let rtGroups: RealtimeArray<RealtimeGroup> = "___tests/_groups".array(from: .root)
}

class Conversation: RealtimeObject {
    lazy var chairman: RealtimeReference<RealtimeUser> = "chairman".reference(from: self.node, mode: .fullPath)
    lazy var secretary: RealtimeReference<RealtimeUser?> = "secretary".reference(from: self.node, mode: .fullPath)

    override open class func lazyPropertyKeyPath(for label: String) -> AnyKeyPath? {
        switch label {
        case "chairman": return \Conversation.chairman
        case "secretary": return \Conversation.secretary
        default: return nil
        }
    }
}

class RealtimeGroup: RealtimeObject {
    lazy var name: RealtimeProperty<String> = "name".property(from: self.node)
    //    @objc dynamic var cover: File?
    lazy var users: LinkedRealtimeArray<RealtimeUser> = "users".linkedArray(from: self.node, elements: Global.rtUsers.node!)
    lazy var conversations: RealtimeDictionary<RealtimeUser, RealtimeUser> = "conversations".dictionary(from: self.node, keys: Global.rtUsers.node!)
    lazy var manager: RealtimeRelation<RealtimeUser?> = "manager".relation(from: self.node, .oneToOne("ownedGroup"))

    lazy var _manager: RealtimeRelation<RealtimeUser> = "_manager".relation(from: self.node, rootLevelsUp: nil, .oneToMany("ownedGroups"))

    override open class func lazyPropertyKeyPath(for label: String) -> AnyKeyPath? {
        switch label {
        case "name": return \RealtimeGroup.name
        case "users": return \RealtimeGroup.users
        case "conversations": return \RealtimeGroup.conversations
        case "manager": return \RealtimeGroup.manager
        case "_manager": return \RealtimeGroup._manager
        default: return nil
        }
    }
}

class RealtimeUser: RealtimeObject {
    lazy var name: RealtimeProperty<String> = "name".property(from: self.node)
    lazy var age: RealtimeProperty<Int> = "age".property(from: self.node)
    lazy var photo: File<UIImage?> = File(in: Node(key: "photo", parent: self.node), representer: Representer.png)
    //    lazy var gender: String?
    lazy var groups: LinkedRealtimeArray<RealtimeGroup> = "groups".linkedArray(from: self.node, elements: Global.rtGroups.node!)
    lazy var followers: LinkedRealtimeArray<RealtimeUser> = "followers".linkedArray(from: self.node, elements: Global.rtUsers.node!)
    lazy var scheduledConversations: RealtimeArray<Conversation> = "scheduledConversations".array(from: self.node)

    lazy var ownedGroup: RealtimeRelation<RealtimeGroup?> = "ownedGroup".relation(from: self.node, .oneToOne("manager"))

//    lazy var ownedGroups: 

    //    override class var keyPaths: [String: AnyKeyPath] {
    //        return super.keyPaths.merging(["name": \RealtimeUser.name, "age": \RealtimeUser.age], uniquingKeysWith: { (_, new) -> AnyKeyPath in
    //            return new
    //        })
    //    }

    override class func lazyPropertyKeyPath(for label: String) -> AnyKeyPath? {
        switch label {
        case "name": return \RealtimeUser.name
        case "age": return \RealtimeUser.age
        case "photo": return \RealtimeUser.photo
        case "groups": return \RealtimeUser.groups
        case "followers": return \RealtimeUser.followers
        case "ownedGroup": return \RealtimeUser.ownedGroup
        case "scheduledConversations": return \RealtimeUser.scheduledConversations
        default: return nil
        }
    }
}

class RealtimeUser2: RealtimeUser {
    lazy var human: RealtimeProperty<[String: FireDataValue]> = "human".property(from: self.node)

    override class func lazyPropertyKeyPath(for label: String) -> AnyKeyPath? {
        switch label {
        case "human": return \RealtimeUser2.human
        default: return nil
        }
    }
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        FirebaseApp.configure()
        RealtimeApp.initialize()
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

