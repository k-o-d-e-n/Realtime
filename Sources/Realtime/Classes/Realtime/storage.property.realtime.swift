//
//  realtime.property.storage.swift
//  Realtime
//
//  Created by Denis Koryttsev on 30/07/2018.
//

import Foundation

#if os(iOS)
import UIKit
#endif

public extension RawRepresentable where Self.RawValue == String {
    func readonlyFile<T>(in object: Object, representer: Representer<T>) -> ReadonlyFile<T> {
        return ReadonlyFile(
            in: Node(key: rawValue, parent: object.node),
            options: .required(representer, db: object.database)
        )
    }
    func readonlyFile<T>(in object: Object, representer: Representer<T>) -> ReadonlyFile<T?> {
        return ReadonlyFile(
            in: Node(key: rawValue, parent: object.node),
            options: .optional(representer, db: object.database)
        )
    }
    func file<T>(in object: Object, representer: Representer<T>, metadata: [String: Any] = [:]) -> File<T> {
        return File(
            in: Node(key: rawValue, parent: object.node),
            options: .init(
                .required(representer, db: object.database, initial: nil),
                metadata: metadata
            )
        )
    }
    func file<T>(in object: Object, representer: Representer<T>, metadata: [String: Any] = [:]) -> File<T?> {
        return File<T?>(
            in: Node(key: rawValue, parent: object.node),
            options: File<T?>.Options(
                .optional(representer, db: object.database, initial: nil),
                metadata: metadata
            )
        )
    }
    #if os(iOS)
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
    #endif
}

extension ReadonlyProperty {
    @discardableResult
    fileprivate func loadFile(timeout: DispatchTimeInterval = .seconds(30)) -> RealtimeStorageTask {
        guard let node = self.node, node.isRooted else {
            fatalError("Can`t get database reference in \(self). Object must be rooted.")
        }

        guard let cache = RealtimeApp.app.configuration.storageCache else {
            return fileTask(for: node, timeout: timeout)
        }
        return CachedFileDownloadTask(
            cache: cache,
            node: node,
            nextLevel: {
                self.fileTask(for: node, timeout: timeout)
            }
        )
    }
    fileprivate func fileTask(for node: Node, timeout: DispatchTimeInterval) -> RealtimeStorageTask {
        return RealtimeApp.app.storage.load(for: node, timeout: timeout)
    }
    fileprivate func applyData(_ data: Data?, node: Node) {
        do {
            if let value = try self.representer.decode(FileNode(node: node, value: data.map(RealtimeDatabaseValue.init))) {
                self._setRemote(value)
            } else {
                self._setRemoved(isLocal: false)
            }
        } catch let e {
            self._setError(e)
        }
    }
}

final class CachedFileDownloadTask: RealtimeStorageTask {
    private var _nextTask: RealtimeStorageTask? = nil
    let nextLevelTask: () -> RealtimeStorageTask
    let cache: RealtimeStorageCache
    let node: Node
    var state: State = .pause

    private var currentSource: ValueStorage<AnyListenable<SuccessResult>?>
    private let cacheRepeater: Repeater<SuccessResult>
    private let cacheStorage: Preprocessor<Memoize<Repeater<SuccessResult>>, SuccessResult>
    private let _memoizedSuccess: Preprocessor<ValueStorage<AnyListenable<SuccessResult>?>, SuccessResult>

    var success: AnyListenable<SuccessResult> { return _memoizedSuccess.asAny() }
    var progress: AnyListenable<Progress> { return _nextTask?.progress ?? Constant(Progress(totalUnitCount: 0)).asAny() }

    enum State {
        case run, pause, finish
    }

    init(
        cache: RealtimeStorageCache,
        node: Node,
        nextLevel task: @escaping () -> RealtimeStorageTask
    ) {
        let cacheRepeater: Repeater<SuccessResult> = .unsafe()
        let cacheStorage = cacheRepeater.memoizeOne(sendLast: true)
        self.cacheRepeater = cacheRepeater
        self.cacheStorage = cacheStorage
        let source = ValueStorage<AnyListenable<SuccessResult>?>.unsafe(strong: nil, repeater: .unsafe())
        self.currentSource = source
        let memoizedSuccess = source.then({ $0! })
        self._memoizedSuccess = memoizedSuccess

        self.nextLevelTask = task
        self.cache = cache
        self.node = node

        resume()
    }

    func resume() {
        guard state == .pause else { return }

        state = .run
        if let next = _nextTask {
            next.resume()
        } else {
            let node = self.node
            cache.file(for: node) { (data) in
                if let d = data {
                    self.state = .finish
                    self.currentSource.wrappedValue = self.cacheStorage.asAny()
                    self.cacheRepeater.send(.value((d, nil))) // TODO: Metadata in cache unsupported
                } else {
                    let task = self.nextLevelTask()
                    let cache = self.cache
                    self.currentSource.wrappedValue = task.success.do({ [weak self] res in
                        self?.state = .finish
                        if let v = res.value, let d = v.data {
                            cache.put(d, for: node, completion: nil)
                        }
                    }).asAny()
                    self._nextTask = task
                }
            }
        }
    }
    func pause() {
        guard state == .run else { return }
        state = .pause
        _nextTask?.pause()
    }
    func cancel() {
        _nextTask?.cancel()
        _nextTask = nil
        state = .finish
    }
}
extension CachedFileDownloadTask: CustomStringConvertible {
    var description: String {
        return """
            node: \(node),
            cache: \(cache),
            state: \(state)
        """
    }
}

class FileDownloadTask: RealtimeStorageTask {
    var state: State = .run
    let base: RealtimeStorageTask
    let success: AnyListenable<SuccessResult>
    var progress: AnyListenable<Progress> { return base.progress }

    init(_ base: RealtimeStorageTask, success: AnyListenable<SuccessResult>) {
        self.base = base
        self.success = success
    }

    enum State {
        case run, pause, finish
    }

    func resume() {
        if state != .finish {
            state = .run
            base.resume()
        }
    }
    func pause() {
        if state == .run {
            state = .pause
            base.pause()
        }
    }
    func cancel() {
        state = .finish
        base.cancel()
    }
}

/// Defines readonly property for files storage
@propertyWrapper
public final class ReadonlyFile<T>: ReadonlyProperty<T> {
    private var _currentDownloadTask: FileDownloadTask?
    public private(set) var metadata: RealtimeMetadata?

    public override var wrappedValue: T? { super.wrappedValue }
    public override var projectedValue: ReadonlyFile<T> { return self }

    public override func runObserving() -> Bool {
        // currently it disabled
        return false
    }

    public override func stopObserving() {
        // currently it disabled
    }

    public override func load(timeout: DispatchTimeInterval = .seconds(30)) -> RealtimeTask {
        return downloadTask(timeout: timeout)
    }

    public func downloadTask(timeout: DispatchTimeInterval = .seconds(30)) -> RealtimeStorageTask {
        let task: FileDownloadTask
        if let currentTask = _currentDownloadTask, currentTask.state != .finish {
            currentTask.resume()
            task = currentTask
        } else {
            let node = self.node!
            let shadowTask = loadFile(timeout: timeout)
            task = FileDownloadTask(
                shadowTask,
                success: shadowTask.success.do({ (result) in
                    switch result {
                    case .value(let md):
                        self.metadata = md.metadata
                        self.applyData(md.data, node: node)
                    case .error: break
                    }
                    self._currentDownloadTask = nil
                })
                .shared(connectionLive: .continuous)
                .asAny()
            )
            _currentDownloadTask = task
        }
        return task
    }

    public override func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        // currently, file can be filled by data from cache only
        if data.database === Cache.root {
            try super.apply(data, event: event)
        }
    }
}

/// Defines read/write property for files storage
@propertyWrapper
public final class File<T>: Property<T> {
    private var _currentDownloadTask: FileDownloadTask?
    public private(set) var metadata: RealtimeMetadata?

    public override var wrappedValue: T? {
        get { super.wrappedValue }
        set { super.wrappedValue = newValue }
    }
    public override var projectedValue: File<T> { return self }

    public struct Options {
        let base: PropertyOptions
        let metadata: RealtimeMetadata?

        public static func required(_ representer: Representer<T>, db: RealtimeDatabase? = nil, metadata: RealtimeMetadata? = nil) -> Self {
            return .init(.required(representer, db: db), metadata: metadata)
        }
        public static func optional<U>(_ representer: Representer<U>, db: RealtimeDatabase? = nil, metadata: RealtimeMetadata? = nil) -> Self where Optional<U> == T {
            return .init(.optional(representer, db: db), metadata: metadata)
        }
        public static func writeRequired<U>(_ representer: Representer<U>, db: RealtimeDatabase? = nil, metadata: RealtimeMetadata? = nil) -> Self where Optional<U> == T {
            return .init(.writeRequired(representer, db: db), metadata: metadata)
        }

        init(_ base: PropertyOptions, metadata: RealtimeMetadata?) {
            self.base = base
            self.metadata = metadata
        }
    }

    public required init(in node: Node?, options: Options) {
        if let md = options.metadata {
            self.metadata = md
        } else {
            self.metadata = [:]
        }
        super.init(in: node, options: options.base)
    }

    required public init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        if case let file as FileNode = data {
            self.metadata = file.metadata
        } else {
            self.metadata = [:] // TODO: Metadata
        }
        try super.init(data: data, event: event)
    }

    override func cacheValue(_ node: Node, value: RealtimeDatabaseValue?) -> CacheNode {
        let file = FileNode(node: node, value: value)
        file.metadata = metadata ?? [:]
        return .file(file)
    }

    public override func runObserving() -> Bool {
        // currently it disabled
        return false
    }

    public override func stopObserving() {
        // currently it disabled
    }

    public override func load(timeout: DispatchTimeInterval = .seconds(30)) -> RealtimeTask {
        return downloadTask(timeout: timeout)
    }

    public func downloadTask(timeout: DispatchTimeInterval = .seconds(30)) -> RealtimeStorageTask {
        let task: FileDownloadTask
        if let currentTask = _currentDownloadTask, currentTask.state != .finish {
            currentTask.resume()
            task = currentTask
        } else {
            let node = self.node!
            let shadowTask = loadFile(timeout: timeout)
            task = FileDownloadTask(
                shadowTask,
                success: shadowTask.success.do({ (result) in
                    switch result {
                    case .value(let md):
                        self.metadata = md.metadata
                        self.applyData(md.data, node: node)
                    case .error: break
                    }
                    self._currentDownloadTask = nil
                })
                .memoizeOne(sendLast: true)
                .asAny()
            )
            _currentDownloadTask = task
        }
        return task
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
