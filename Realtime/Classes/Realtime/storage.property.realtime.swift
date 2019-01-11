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
    func file<T>(in object: Object, representer: Representer<T>, metadata: [String: Any] = [:]) -> File<T> {
        return File(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .representer: representer.requiredProperty(),
                .metadata: metadata
            ]
        )
    }
    func file<T>(in object: Object, representer: Representer<T>, metadata: [String: Any] = [:]) -> File<T?> {
        return File(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .representer: representer.optionalProperty(),
                .metadata: metadata
            ]
        )
    }
    func png(in object: Object) -> File<UIImage> {
        return file(in: object, representer: Representer<UIImage>.png, metadata: ["contentType": "image/png"])
    }
    func png(in object: Object) -> File<UIImage?> {
        return file(in: object, representer: Representer<UIImage>.png, metadata: ["contentType": "image/png"])
    }
    func jpeg(in object: Object, compressionQuality: CGFloat = 1.0) -> File<UIImage> {
        return file(in: object, representer: Representer<UIImage>.jpeg(quality: compressionQuality), metadata: ["contentType": "image/jpeg"])
    }
    func jpeg(in object: Object, compressionQuality: CGFloat = 1.0) -> File<UIImage?> {
        return file(in: object, representer: Representer<UIImage>.jpeg(quality: compressionQuality), metadata: ["contentType": "image/jpeg"])
    }
    func readonlyPng(in object: Object) -> ReadonlyFile<UIImage> {
        return readonlyFile(in: object, representer: Representer<UIImage>.png)
    }
    func readonlyPng(in object: Object) -> ReadonlyFile<UIImage?> {
        return readonlyFile(in: object, representer: Representer<UIImage>.png)
    }
    func readonlyJpeg(in object: Object, compressionQuality: CGFloat = 1.0) -> ReadonlyFile<UIImage> {
        return readonlyFile(in: object, representer: Representer<UIImage>.jpeg(quality: compressionQuality))
    }
    func readonlyJpeg(in object: Object, compressionQuality: CGFloat = 1.0) -> ReadonlyFile<UIImage?> {
        return readonlyFile(in: object, representer: Representer<UIImage>.jpeg(quality: compressionQuality))
    }
}

extension ReadonlyProperty {
    @discardableResult
    fileprivate func loadFile(timeout: DispatchTimeInterval = .seconds(30), completion: Assign<Error?>?) -> RealtimeStorageTask {
        guard let node = self.node, node.isRooted else {
            fatalError("Can`t get database reference in \(self). Object must be rooted.")
        }
        return RealtimeApp.app.storage.load(
            for: node,
            timeout: timeout,
            completion: { (data) in
                do {
                    if let value = try self.representer.decode(FileNode(node: node, value: data)) {
                        self._setValue(.remote(value))
                    } else {
                        self._setRemoved(isLocal: false)
                    }
                    completion?.call(nil)
                } catch let e {
                    self._setError(e)
                    completion?.call(e)
                }
            },
            onCancel: { e in
                self._setError(e)
                completion?.call(e)
            }
        )
    }
}

extension ValueOption {
    /// Key for `RealtimeStorage` instance
    static var storage: ValueOption = ValueOption("realtime.storage")
    static var metadata: ValueOption = ValueOption("realtime.file.metadata")
}

/// Defines readonly property for files storage
public final class ReadonlyFile<T>: ReadonlyProperty<T> {
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

    public func downloadTask(timout: DispatchTimeInterval = .seconds(30), completion: Assign<Error?>?) -> RealtimeStorageTask {
        return loadFile(timeout: timout, completion: completion)
    }

    public override func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        // currently, file can be filled by data from cache only
        if data.database === Cache.root {
            try super.apply(data, event: event)
        }
    }
}

/// Defines read/write property for files storage
public final class File<T>: Property<T> {
    let metadata: [String: Any]

    public required init(in node: Node?, options: [ValueOption : Any]) {
        if case let md as [String: Any] = options[.metadata] {
            self.metadata = md
        } else {
            self.metadata = [:]
        }
        super.init(in: node, options: options)
    }

    required public init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        self.metadata = [:] // TODO: Metadata
        try super.init(data: data, event: event)
    }

    override func cacheValue(_ node: Node, value: Any?) -> CacheNode {
        let file = FileNode(node: node, value: value)
        file.metadata = metadata
        return .file(file)
    }

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

    public func downloadTask(timout: DispatchTimeInterval = .seconds(30), completion: Assign<Error?>?) -> RealtimeStorageTask {
        return loadFile(timeout: timout, completion: completion)
    }

    public override func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        // currently, file can be filled by data from cache only
        if data.database === Cache.root {
            try super.apply(data, event: event)
        }
    }

    override func _addReversion(to transaction: Transaction, by node: Node) {
        transaction.addFileReversion(node, currentReversion())
    }
}
