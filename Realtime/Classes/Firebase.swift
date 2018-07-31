//
//  Firebase.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 25/02/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import FirebaseDatabase
import FirebaseStorage

public typealias StorageMetadata = FirebaseStorage.StorageMetadata
public typealias DataSnapshot = FirebaseDatabase.DataSnapshot
public typealias DatabaseReference = FirebaseDatabase.DatabaseReference

public extension DatabaseReference {
    static func root(of database: Database = Database.database()) -> DatabaseReference { return database.reference() }
    static func fromRoot(_ path: String, of database: Database = Database.database()) -> DatabaseReference {
        return database.reference(withPath: path)
    }

    var rootPath: String { return path(from: root) }
    
    func path(from ref: DatabaseReference) -> String {
        return String(url[ref.url.endIndex...])
    }
    
    func isChild(for ref: DatabaseReference) -> Bool {
        return !isEqual(for: ref) && url.hasPrefix(ref.url)
    }
    func isEqual(for ref: DatabaseReference) -> Bool {
        return self === ref || url == ref.url
    }

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

// MARK: Storage


/// TODO: Temporary

extension Dictionary {
    public init<Keys: Collection, Values: Collection>(keys: Keys, values: Values) where Keys.Iterator.Element: Hashable, Values.Index == Int, Key == Keys.Iterator.Element, Value == Values.Iterator.Element {
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

/*
extension DatabaseReference: Listenable {
    private func makeDispose(for token: UInt) -> ListeningDispose {
        return ListeningDispose({ [weak self] in self?.removeObserver(withHandle: token) })
    }
    private func makeListeningItem(for event: DataEventType, listening: AnyListening, assign: Assign<OutData>) -> ListeningItem {
        let snapListening = SnapshotListening(self, event: event, listening: listening, assign: assign)
        return ListeningItem(start: snapListening.onStart,
                             stop: snapListening.onStop,
                             notify: {},
                             token: ())
    }

    public typealias OutData = (snapshot: DataSnapshot?, error: Error?)

    /// Disposable listening of value
    public func listening(as config: (AnyListening) -> AnyListening, _ assign: Assign<OutData>) -> Disposable {
        return SnapshotListening(self, event: .value, listening: config(Listening(bridge: {})), assign: assign)
    }

    /// Listening with possibility to control active state
    public func listeningItem(as config: (AnyListening) -> AnyListening, _ assign: Assign<OutData>) -> ListeningItem {
        return makeListeningItem(for: .value, listening: config(Listening(bridge: {})), assign: assign)
    }

    private class SnapshotListening: AnyListening, Disposable, Hashable {
        let ref: DatabaseReference
        let event: DataEventType
        var token: UInt?
        let assign: Assign<OutData>

        var isInvalidated: Bool { return token == nil }
        var dispose: () -> Void { return onStop }

        init(_ ref: DatabaseReference, event: DataEventType, listening: AnyListening, assign: Assign<OutData>) {
            self.ref = ref
            self.event = event
            self.assign = assign

            onStart()
        }

        @objc func onEvent(_ control: UIControl, _ event: UIEvent) { // TODO: UIEvent
            sendData()
        }

        func sendData() {
        }

        func onStart() {
            guard token == nil else { return }
            let receiver = assign.assign
            token = ref.observe(event, with: { receiver(($0, nil)) }, withCancel: { receiver((nil, $0)) })
        }

        func onStop() {
            if let t = token {
                ref.removeObserver(withHandle: t)
            }
        }

        var hashValue: Int { return Int(event.rawValue) }
        static func ==(lhs: SnapshotListening, rhs: SnapshotListening) -> Bool {
            return lhs === rhs
        }
    }
}
*/
