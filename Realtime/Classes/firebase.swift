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

    public typealias TransactionCompletion = (Error?, DatabaseReference) -> Void
    func update(use keyValuePairs: [String: Any], completion: TransactionCompletion?) {
        if let completion = completion {
            updateChildValues(keyValuePairs, withCompletionBlock: completion)
        } else {
            updateChildValues(keyValuePairs)
        }
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

extension DatabaseReference {
    public struct Event: Listenable {
        let ref: DatabaseReference
        let event: DataEventType

        /// Disposable listening of value
        public func listening(_ assign: Assign<ListenEvent<FireDataProtocol>>) -> Disposable {
            let token = ref.listen(assign, nil)
            return ListeningDispose({
                self.ref.removeObserver(withHandle: token)
            })
        }

        /// Listening with possibility to control active state
        public func listeningItem(_ assign: Assign<ListenEvent<OutData>>) -> ListeningItem {
            var value: FireDataProtocol = ValueNode(node: Node.from(ref), value: nil)
            let token = ref.listen(assign, { value = $0 })
            return ListeningItem(
                start: { self.ref.listen(assign, { value = $0 }) },
                stop: ref.removeObserver,
                notify: { assign.assign(.value(value)) },
                token: token
            )
        }
    }

    public func snapshot(_ event: DataEventType) -> Event {
        return Event(ref: self, event: event)
    }

    private func listen(_ assign: Assign<ListenEvent<FireDataProtocol>>, _ change: ((FireDataProtocol) -> Void)?) -> UInt {
        let token = observe(
            .value,
            with: <-assign
                .map { .value($0) }
                .with(work: { change?($0) }),
            withCancel: <-assign.map { .error($0) }
        )
        return token
    }
}
