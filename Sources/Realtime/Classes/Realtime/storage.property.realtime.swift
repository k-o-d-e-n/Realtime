//
//  realtime.property.storage.swift
//  Realtime
//
//  Created by Denis Koryttsev on 30/07/2018.
//

import Foundation

public extension RawRepresentable where Self.RawValue == String {
    func readonlyFile<T>(in object: Object, representer: Representer<T>) -> ReadonlyFile<T> {
        return ReadonlyFile(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .representer: Availability.required(representer)
            ]
        )
    }
    func readonlyFile<T>(in object: Object, representer: Representer<T>) -> ReadonlyFile<T?> {
        return ReadonlyFile(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .representer: Availability.optional(representer)
            ]
        )
    }
    func file<T>(in object: Object, representer: Representer<T>, metadata: [String: Any] = [:]) -> File<T> {
        return File(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .representer: Availability.required(representer),
                .metadata: metadata
            ]
        )
    }
    func file<T>(in object: Object, representer: Representer<T>, metadata: [String: Any] = [:]) -> File<T?> {
        return File(
            in: Node(key: rawValue, parent: object.node),
            options: [
                .database: object.database as Any,
                .representer: Availability.optional(representer),
                .metadata: metadata
            ]
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
            nextLevel: self.fileTask(for: node, timeout: timeout),
            cache: cache,
            node: node,
            completion: { data in
                self.applyData(data, node: node, needCaching: false)
            }
        )
    }
    fileprivate func fileTask(for node: Node, timeout: DispatchTimeInterval) -> RealtimeStorageTask {
        return RealtimeApp.app.storage.load(
            for: node,
            timeout: timeout,
            completion: { (data) in
                self.applyData(data, node: node, needCaching: true)
            },
            onCancel: { e in
                self._setError(e)
            }
        )
    }
    fileprivate func applyData(_ data: Data?, node: Node, needCaching: Bool) {
        do {
            if let value = try self.representer.decode(FileNode(node: node, value: data)) {
                self._setValue(.remote(value))
                if needCaching, let data = data, let cache = RealtimeApp.app.configuration.storageCache {
                    cache.put(data, for: node, completion: nil)
                }
            } else {
                self._setRemoved(isLocal: false)
            }
        } catch let e {
            self._setError(e)
        }
    }
}

extension ValueOption {
    /// Key for `RealtimeStorage` instance
    public static var storage: ValueOption = ValueOption("realtime.storage")
    public static var metadata: ValueOption = ValueOption("realtime.file.metadata")
}

class CachedFileDownloadTask: RealtimeStorageTask {
    var _nextTask: RealtimeStorageTask? = nil
    let nextLevelTask: () -> RealtimeStorageTask
    let cache: RealtimeStorageCache
    let node: Node
    let completion: (Data) -> Void
    var state: State = .pause
    enum State {
        case run, pause, finish
    }

    var progress: AnyListenable<Progress> { return _nextTask?.progress ?? Constant(Progress(totalUnitCount: 0)).asAny() }
    let _success: Repeater<RealtimeMetadata?>
    let _memoizedSuccess: Preprocessor<Memoize<Repeater<RealtimeMetadata?>>, RealtimeMetadata?>
    var success: AnyListenable<RealtimeMetadata?> { return _memoizedSuccess.asAny() }

    init(nextLevel task: @escaping @autoclosure () -> RealtimeStorageTask,
         cache: RealtimeStorageCache,
         node: Node,
         completion: @escaping (Data?) -> Void) {
        let success = Repeater<RealtimeMetadata?>.unsafe()
        self._success = success
        self._memoizedSuccess = success.memoizeOne(sendLast: true)
        self.nextLevelTask = task
        self.cache = cache
        self.node = node
        self.completion = completion
        resume()
    }

    func resume() {
        guard state == .pause else { return }

        state = .run
        if let next = _nextTask {
            next.resume()
        } else {
            let cacheCompl = self.completion
            cache.file(for: node) { (data) in
                if let d = data {
                    self.state = .finish
                    cacheCompl(d)
                    self._success.send(.value(nil))
                } else {
                    let task = self.nextLevelTask()
                    task.success.bind(to: self._success)
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

class FileDownloadTask: RealtimeStorageTask {
    var dispose: Disposable?
    let base: RealtimeStorageTask
    var state: State = .run

    init(_ base: RealtimeStorageTask) {
        self.base = base
    }

    enum State {
        case run, pause, finish
    }

    var progress: AnyListenable<Progress> { return base.progress }
    var success: AnyListenable<RealtimeMetadata?> { return base.success }
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
public final class ReadonlyFile<T>: ReadonlyProperty<T> {
    private var _currentDownloadTask: FileDownloadTask?
    public private(set) var metadata: RealtimeMetadata?
    public override func runObserving() -> Bool {
        // currently it disabled
        return false
    }

    public override func stopObserving() {
        // currently it disabled
    }

    public override func load(timeout: DispatchTimeInterval = .seconds(30)) -> RealtimeTask {
        return loadFile(timeout: timeout)
    }

    public func downloadTask(timeout: DispatchTimeInterval = .seconds(30)) -> RealtimeStorageTask {
        let task: FileDownloadTask
        if let currentTask = _currentDownloadTask, currentTask.state != .finish {
            currentTask.resume()
            task = currentTask
        } else {
            task = FileDownloadTask(loadFile(timeout: timeout))
            _currentDownloadTask = task
            task.dispose = task.success.listening({ (result) in
                switch result {
                case .value(let md): self.metadata = md
                case .error: break
                }
                self._currentDownloadTask = nil
            })
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
public final class File<T>: Property<T> {
    private var _currentDownloadTask: FileDownloadTask?
    public private(set) var metadata: RealtimeMetadata?

    public required init(in node: Node?, options: [ValueOption : Any]) {
        if case let md as [String: Any] = options[.metadata] {
            self.metadata = md
        } else {
            self.metadata = [:]
        }
        super.init(in: node, options: options)
    }

    required public init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        if case let file as FileNode = data {
            self.metadata = file.metadata
        } else {
            self.metadata = [:] // TODO: Metadata
        }
        try super.init(data: data, event: event)
    }

    override func cacheValue(_ node: Node, value: Any?) -> CacheNode {
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
        return loadFile(timeout: timeout)
    }

    public func downloadTask(timeout: DispatchTimeInterval = .seconds(30)) -> RealtimeStorageTask {
        let task: FileDownloadTask
        if let currentTask = _currentDownloadTask, currentTask.state != .finish {
            currentTask.resume()
            task = currentTask
        } else {
            task = FileDownloadTask(loadFile(timeout: timeout))
            _currentDownloadTask = task
            task.dispose = task.success.listening({ (result) in
                switch result {
                case .value(let md): self.metadata = md
                case .error: break
                }
                self._currentDownloadTask = nil
            })
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
