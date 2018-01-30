//
//  Firebase.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 25/02/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import FirebaseDatabase

public typealias DataSnapshot = FirebaseDatabase.DataSnapshot
public typealias DatabaseReference = FirebaseDatabase.DatabaseReference

public extension DatabaseReference {
    static func root() -> DatabaseReference { return Database.database().reference() }
    static func fromRoot(_ path: String) -> DatabaseReference { return Database.database().reference(withPath: path) }

    var pathFromRoot: String { return path(from: root) }
    
    func path(from ref: DatabaseReference) -> String {
        return String(url[ref.url.endIndex...])
    }
    
    func isChild(for ref: DatabaseReference) -> Bool {
        return url.hasPrefix(ref.url)
    }
    func isEqual(for ref: DatabaseReference) -> Bool {
        return self === ref || url == ref.url
    }

//    public typealias UpdateItem = (path: String, value: Any?)
    func update(use keyValuePairs: [String: Any?], completion: Database.TransactionCompletion?) {
        if completion == nil {
            updateChildValues(keyValuePairs as Any as! [AnyHashable : Any])
        } else {
            updateChildValues(keyValuePairs as Any as! [String: Any], withCompletionBlock: completion!)
        }
    }
}

public extension Database {
    public typealias UpdateItem = (ref: DatabaseReference, value: Any?)
    public typealias TransactionCompletion = (Error?, DatabaseReference) -> Void
    func update(use refValuePairs: [UpdateItem],
                      completion: TransactionCompletion?) {
        let root = reference()
        let childValues = Dictionary<String, Any?>(keyValues: refValuePairs, mapKey: { $0.path(from: root) })
        root.update(use: childValues, completion: completion)
    }
}

public extension DataSnapshot {
    func map<Mapped>(child: String, map: (DataSnapshot) -> Mapped) -> Mapped? {
        guard hasChild(child) else { return nil }
        return map(childSnapshot(forPath: child))
    }
    func mapExactly(if truth: Bool, child: String, map: (DataSnapshot) -> Void) { if truth || hasChild(child) { map(childSnapshot(forPath: child)) } }
}

/// TODO: Temporary

extension Dictionary {
    public init<Keys: Collection, Values: Collection>(keys: Keys, values: Values) where Keys.Iterator.Element: Hashable, Keys.IndexDistance == Values.IndexDistance, Values.Index == Int, Key == Keys.Iterator.Element, Value == Values.Iterator.Element {
        precondition(keys.count == values.count)

        self.init()
        for (index, key) in keys.enumerated() {
            self[key] = values[index]
        }
    }
    public init<OldKey, OldValue>(keyValues: [(OldKey, OldValue)],
                                  mapKey: (OldKey) -> Key,
                                  mapValue: (OldValue) -> Value) {
        self.init()
        keyValues.forEach { self[mapKey($0)] = mapValue($1) }
    }
    public init<OldKey>(keyValues: [(OldKey, Value)],
                        mapKey: (OldKey) -> Key) {
        self.init()
        keyValues.forEach { self[mapKey($0)] = $1 }
    }
}
