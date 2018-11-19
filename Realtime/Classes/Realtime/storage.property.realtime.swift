//
//  realtime.property.storage.swift
//  Realtime
//
//  Created by Denis Koryttsev on 30/07/2018.
//

import Foundation
import FirebaseStorage

public extension RawRepresentable where Self.RawValue == String {
    func readonlyFile<T>(in object: Object, representer: Representer<T>) -> ReadonlyFile<T> {
        return ReadonlyFile(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .representer: representer.requiredProperty()
            ]
        )
    }
    func readonlyFile<T>(in object: Object, representer: Representer<T>) -> ReadonlyFile<T?> {
        return ReadonlyFile(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .representer: representer.optionalProperty()
            ]
        )
    }
    func file<T>(in object: Object, representer: Representer<T>) -> File<T> {
        return File(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .representer: representer.requiredProperty()
            ]
        )
    }
    func file<T>(in object: Object, representer: Representer<T>) -> File<T?> {
        return File(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .representer: representer.optionalProperty()
            ]
        )
    }
}

extension ReadonlyProperty {
    fileprivate func loadFile(timeout: DispatchTimeInterval = .seconds(30), completion: Assign<Error?>?) {
        guard let node = self.node, node.isRooted else {
            fatalError("Can`t get database reference in \(self). Object must be rooted.")
        }

        var invalidated: Int32 = 0
        var task: StorageDownloadTask!
        let invalidate = { () -> Bool in
            if OSAtomicCompareAndSwap32Barrier(0, 1, &invalidated) {
                task.cancel()
                return true
            } else {
                return false
            }
        }
        task = node.file().getData(maxSize: .max) { (data, err) in
            let canCallCompletion = invalidate()
            if let e = err {
                self._setError(e)
                if canCallCompletion { completion?.assign(e) }
            } else {
                do {
                    if let value = try self.representer.decode(FileNode(node: node, value: data)) {
                        self._setValue(.remote(value))
                    } else {
                        self._setRemoved(isLocal: false)
                    }
                    if canCallCompletion { completion?.call(nil) }
                } catch let e {
                    self._setError(e)
                    if canCallCompletion { completion?.call(e) }
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: {
            if invalidate() {
                completion?.call(RealtimeError(source: .database, description: "Operation timeout"))
            }
        })
    }
}

extension ValueOption {
    /// Key for `RealtimeStorage` instance
    static var storage: ValueOption = ValueOption("realtime.storage")
}

/// Defines readonly property for files storage
public final class ReadonlyFile<T>: ReadonlyProperty<T> {
    override var updateType: ValueNode.Type { return FileNode.self }

    public override func runObserving() -> Bool {
        // currently it disabled
        return false
    }

    public override func stopObserving() {
        // currently it disabled
    }

    public override func load(timeout: DispatchTimeInterval = .seconds(30), completion: Assign<Error?>?) {
        loadFile(timeout: timeout, completion: completion)
    }

    public override func apply(_ data: RealtimeDataProtocol, exactly: Bool) throws {
        // currently, file can be filled by data from cache only
        if data.database === CacheNode.root {
            try super.apply(data, exactly: exactly)
        }
    }
}

/// Defines read/write property for files storage
public final class File<T>: Property<T> {
    override var updateType: ValueNode.Type { return FileNode.self }

    public override func runObserving() -> Bool {
        // currently it disabled
        return false
    }

    public override func stopObserving() {
        // currently it disabled
    }

    public override func load(timeout: DispatchTimeInterval = .seconds(30), completion: Assign<Error?>?) {
        loadFile(timeout: timeout, completion: completion)
    }

    public override func apply(_ data: RealtimeDataProtocol, exactly: Bool) throws {
        // currently, file can be filled by data from cache only
        if data.database === CacheNode.root {
            try super.apply(data, exactly: exactly)
        }
    }

    override func _addReversion(to transaction: Transaction, by node: Node) {
        transaction.addFileReversion(node, currentReversion())
    }
}
