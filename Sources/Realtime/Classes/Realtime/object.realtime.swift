//
//  Object.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 14/01/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation

public struct Version: Comparable, Equatable {
    /// The major version.
    public let major: UInt32

    /// The minor version.
    public let minor: UInt32

    /// Create a version object.
    public init(_ major: UInt32, _ minor: UInt32) {
        precondition(major >= 0 && minor >= 0, "Negative versioning is invalid.")
        self.major = major
        self.minor = minor
    }

    public static func < (lhs: Version, rhs: Version) -> Bool {
        return lhs.major < rhs.major || lhs.minor < rhs.minor
    }
}

public struct Versioner {
    var isCollector: Bool
    var finalized: String?
    var levels: [Version] = []
    var isEmpty: Bool { return levels.isEmpty }

    init() {
        self.isCollector = true
    }

    init(version: String) {
        self.isCollector = false
        self.finalized = version
        self.levels = Data(base64Encoded: version).map({ d in
            let size = d.count / MemoryLayout<Version>.size
            return (0 ..< size).reduce(into: [], { (res, i) in
                let offset = i * MemoryLayout<Version>.size
                res.append(
                    d.subdata(in: (offset..<offset + MemoryLayout<Version>.size))
                        .withUnsafeBytes({ $0.pointee })
                )
            })
        }) ?? []
    }

    mutating func finalize() -> String {
        guard let final = self.finalized else {
            var levels = self.levels
            let finalized = Data(bytes: &levels, count: MemoryLayout<Version>.size * levels.count).base64EncodedString()
            self.finalized = finalized
            return finalized
        }
        return final
    }

    /// Returns version from the lowest level by removing
    ///
    /// - Returns: Version object
    /// - Throws: No more levels
    public mutating func dequeue() throws -> Version {
        guard !isCollector else { fatalError("Versioner was created to collect versions") }
        if levels.isEmpty {
            throw RealtimeError(source: .value, description: "No more levels")
        } else {
            return levels.removeFirst()
        }
    }

    public mutating func enqueue(_ version: Version) {
        guard isCollector else { fatalError("Versioner was created with immutable version value") }
        levels.append(version)
    }

    fileprivate mutating func _turn() {
        isCollector = !isCollector
    }

    public static func < (lhs: Versioner, rhs: Versioner) -> Bool {
        if lhs.isEmpty {
            return !rhs.isEmpty
        } else {
            let count = min(lhs.levels.count, rhs.levels.count)
            let contains = (0..<count).contains { (i) -> Bool in
                let left = lhs.levels[i]
                let right = rhs.levels[i]
                return left < right
            }

            return contains
        }
    }

    public static func ==(lhs: Versioner, rhs: Versioner) -> Bool {
        let count = min(lhs.levels.count, rhs.levels.count)
        let contains = (0..<count).contains { (i) -> Bool in
            let left = lhs.levels[i]
            let right = rhs.levels[i]
            return left != right
        }

        return !contains
    }

    public static func ===(lhs: Versioner, rhs: Versioner) -> Bool {
        return lhs.levels == rhs.levels
    }
}
extension Versioner: CustomDebugStringConvertible {
    public var debugDescription: String {
        return levels.isEmpty ? "0.0" : levels.map { "\($0.major).\($0.minor)" }.debugDescription
    }
}

struct Reflector: Sequence {
    let startMirror: Mirror
    let toClass: Any.Type?

    init(reflecting: Any, to toClass: Any.Type?) {
        self.startMirror = Mirror(reflecting: reflecting)
        self.toClass = toClass
    }

    struct Iterator: IteratorProtocol {
        var currentMirror: Mirror?
        let stopper: Any.Type?
        mutating func next() -> Mirror? {
            defer {
                if let next = currentMirror?.superclassMirror {
                    currentMirror = stopper.flatMap { next.subjectType == $0 ? nil : next }
                } else {
                    currentMirror = nil
                }
            }
            return currentMirror
        }
    }

    func makeIterator() -> Reflector.Iterator {
        return Iterator(currentMirror: startMirror, stopper: toClass)
    }
}

public struct RealtimeValueOptions {
    public let database: RealtimeDatabase?
    public let raw: RealtimeDatabaseValue?
    public let payload: RealtimeDatabaseValue?

    public init(database: RealtimeDatabase? = nil, raw: RealtimeDatabaseValue? = nil, payload: RealtimeDatabaseValue? = nil) {
        self.database = database
        self.raw = raw
        self.payload = payload
    }

    func with(db: RealtimeDatabase?) -> RealtimeValueOptions {
        return .init(database: db, raw: raw, payload: payload)
    }
}

/// Base class for any database value
open class _RealtimeValue: RealtimeValue, RealtimeValueEvents, CustomDebugStringConvertible {
    /// Remote version of model
    fileprivate(set) var _version: String?
    /// Database that associated with this value
    public fileprivate(set) var database: RealtimeDatabase?
    /// Node of database tree
    public fileprivate(set) var node: Node?
    /// Raw value if Realtime value represented as enumerated type
    public fileprivate(set) var raw: RealtimeDatabaseValue?
    /// User defined payload related with this value
    public fileprivate(set) var payload: RealtimeDatabaseValue?
    /// Indicates that value already observed
    public var isObserved: Bool { return observing.count > 0 }
    /// Indicates that value can observe
    public var canObserve: Bool { return isRooted }

    internal var observing: [DatabaseDataEvent: (token: UInt, counter: Int)] = [:]

    public convenience init(in object: _RealtimeValue, keyedBy key: String, options: RealtimeValueOptions = .init()) {
        self.init(
            node: Node(key: key, parent: object.node),
            options: options.with(db: object.database)
        )
    }

    init(node: Node?, options: RealtimeValueOptions) {
        self.database = options.database ?? RealtimeApp.app.database
        self.node = node
        if let pl = options.payload {
            self.payload = pl
        }
        if let r = options.raw {
            self.raw = r
        }
    }

    deinit {
        observing.forEach { key, value in
            debugFatalError(condition: value.counter > 1, "Deinitialization observed value using event: \(key)")
            endObserve(for: value.token)
        }
    }

    @discardableResult
    public func load(timeout: DispatchTimeInterval = .seconds(30)) -> RealtimeTask {
        guard let node = self.node, let database = self.database else {
            fatalError("Can`t get database reference in \(self). Object must be rooted.")
        }

        let completion = _Promise<Void>()
        database.load(for: node, timeout: timeout, completion: { d in
            do {
                try self.apply(d, event: .value)
                completion.fulfill(())
            } catch let e {
                completion.reject(e)
                self._dataApplyingDidThrow(e)
            }
        }, onCancel: { e in
            completion.reject(e)
            self._dataObserverDidCancel(e)
        })

        return completion
    }

    @discardableResult
    func _runObserving(_ event: DatabaseDataEvent) -> Bool {
        guard canObserve else {
            /// shedule observing
            if let o = observing[event] {
                observing[event] = (o.token, o.counter + 1)
            } else {
                observing[event] = (0, 1)
            }
            return false
        }
        guard let o = observing[event] else {
            observing[event] = observe(event).map { ($0, 1) }
            return observing[event] != nil
        }

        debugFatalError(condition: o.counter == 0, "Internal error. Counter is null. Should been invalidated")
        observing[event] = (o.token, o.counter + 1)
        return true
    }

    func _stopObserving(_ event: DatabaseDataEvent) {
        guard var o = observing[event] else { return }

        o.counter -= 1
        if o.counter < 1 {
            endObserve(for: o.token)
            observing.removeValue(forKey: event)
        } else {
            observing[event] = o
        }
    }

    func _invalidateObserving() {
        let observingValues = self.observing
        observingValues.forEach { (args) in
            endObserve(for: args.value.token)
        }
        self.observing = [:]
    }

    // not used
    internal func _isObserved(_ event: DatabaseDataEvent) -> Bool {
        return observing[event].map { $0.counter > 0 } ?? false
    }

    // not used
    internal func _numberOfObservers(for event: DatabaseDataEvent) -> Int {
        return observing[event]?.counter ?? 0
    }
    
    func observe(_ event: DatabaseDataEvent = .value) -> UInt? {
        guard let node = self.node, let database = self.database else {
            return nil
        }
        return database.observe(event, on: node, onUpdate: { d, e in
            do {
                try self.apply(d, event: e)
            } catch let e {
                self._dataApplyingDidThrow(e)
            }
        }, onCancel: { e in
            self._dataObserverDidCancel(e)
        })
    }

    func endObserve(for token: UInt) {
        if let node = node, let database = self.database {
            database.removeObserver(for: node, with: token)
        }
    }

    public func willRemove(in transaction: Transaction, from ancestor: Node) {
        // fixme: string values will be calculates and in release builder
        debugFatalError(condition: self.node == nil || !self.node!.isRooted,
                        "Value will be removed from node: \(ancestor), but has not been inserted before. Current: \(self.node?.description ?? "")")
        debugFatalError(condition: !self.node!.hasAncestor(node: ancestor),
                        "Value will be removed from node: \(ancestor), but it is not ancestor for current node: \(self.node?.description ?? "")")
        debugFatalError(condition: !ancestor.isRooted, "Value will be removed from non rooted node: \(ancestor)")
    }
    public func didRemove(from ancestor: Node) {
        debugFatalError(condition: self.node == nil || !self.node!.isRooted,
                        "Value has been removed from node: \(ancestor), but has not been inserted before. Current: \(self.node?.description ?? "")")
        debugFatalError(condition: !self.node!.hasAncestor(node: ancestor),
                        "Value has been removed from node: \(ancestor), that is not ancestor for current node: \(self.node?.description ?? "")")
        debugFatalError(condition: !ancestor.isRooted, "Value has been removed from non rooted node: \(ancestor)")

        node.map { n in database?.removeAllObservers(for: n) }
        observing.removeAll()
        if node?.parent == ancestor {
            self.node?.parent = nil
        }
        self.database = nil
    }
    public func willSave(in transaction: Transaction, in parent: Node, by key: String) {
        debugFatalError(condition: self.node.map { $0.key != key } ?? false, "Value will be saved to node: \(parent) by key: \(key), but current node has key: \(node?.key ?? "").")
        debugFatalError(condition: !parent.isRooted, "Value will be saved non rooted node: \(parent)")
    }
    public func didSave(in database: RealtimeDatabase, in parent: Node, by key: String) {
        _RealtimeValue_didSave(in: database, in: parent, by: key)
    }

    func _RealtimeValue_didSave(in database: RealtimeDatabase, in parent: Node, by key: String) {
        debugFatalError(condition: self.node.map { $0.key != key } ?? false, "Value has been saved to node: \(parent) by key: \(key), but current node has key: \(node?.key ?? "").")
        debugFatalError(condition: !parent.isRooted, "Value has been saved non rooted node: \(parent)")

        self.database = database
        if let node = self.node {
            debugFatalError(condition: node === parent, "Parent node cannot be equal child")
            node.parent = parent
        } else {
            self.node = Node(key: key, parent: parent)
        }
        /// run sheduled observing
        observing.forEach { (item) in
            observing[item.key] = (observe(item.key)!, item.value.counter)
        }
    }

    public func willUpdate(through ancestor: Node, in transaction: Transaction) {
        debugFatalError(condition: self.node == nil || !self.node!.isRooted,
                        "Value will be updated, but has not been inserted before. Current node: \(self.node?.description ?? "")")
        debugFatalError(condition: ancestor != self.node && !self.node!.hasAncestor(node: ancestor),
                        "Value will be updated through node: \(ancestor), but it is not ancestor for current node: \(self.node?.description ?? "")")
    }

    public func didUpdate(through ancestor: Node) {
        debugFatalError(condition: self.node == nil || !self.node!.isRooted,
                        "Value has been updated, but has not been inserted before. Current node: \(self.node?.description ?? "")")
        debugFatalError(condition: ancestor != self.node && !self.node!.hasAncestor(node: ancestor),
                        "Value has been updated through node: \(ancestor), but it is not ancestor for current node: \(self.node?.description ?? "")")
    }
    
    // MARK: Changeable & Writable

    internal var _hasChanges: Bool { return false }

    internal func _writeChanges(to transaction: Transaction, by node: Node) throws {
        if _hasChanges {
            try _write(to: transaction, by: node)
        }
    }

    internal final func _write_RealtimeValue(to transaction: Transaction, by node: Node) {
        var versioner = Versioner()
        putVersion(into: &versioner)
        if !versioner.isEmpty {
            let finalizedVersion = versioner.finalize()
            transaction.addValue(RealtimeDatabaseValue(finalizedVersion), by: Node(key: InternalKeys.modelVersion, parent: node))
            transaction.addCompletion { [weak self] (result) in
                guard result, let `self` = self else { return }
                self._version = finalizedVersion
            }
        }
        if let rw = raw {
            transaction.addValue(rw, by: Node(key: InternalKeys.raw, parent: node))
        }
        if let pl = payload {
            transaction.addValue(pl, by: Node(key: InternalKeys.payload, parent: node))
        }
    }

    internal func _write(to transaction: Transaction, by node: Node) throws {
        _write_RealtimeValue(to: transaction, by: node)
    }

    // MARK: Realtime Value

    public required init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        self.database = data.database ?? RealtimeApp.app.database
        self.node = data.node
        try apply(data, event: event)
    }

    func _apply_RealtimeValue(_ data: RealtimeDataProtocol) throws {
        self._version = try data.version()
        self.raw = try data.rawValue()
        self.payload = try data.payload()
    }
    open func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        debugFatalError(condition: data.node.map { $0 != node } ?? false, "Tries apply data with incorrect reference")
        try _apply_RealtimeValue(data)
    }

    func _dataApplyingDidThrow(_ error: Error) {
        debugLog(String(describing: error))
    }

    func _dataObserverDidCancel(_ error: Error) {
        debugLog(String(describing: error))
    }

    /// support Versionable
    open func putVersion(into versioner: inout Versioner) {
        // override in subclass
        // always call super method first, to achieve correct version value
    }
    
    public var debugDescription: String {
        return """
        \(type(of: self)): \(ObjectIdentifier(self).memoryAddress) {
            ref: \(node?.absolutePath ?? "not referred"),
            raw: \(raw.map(String.init(describing:)) ?? "null"),
            hasChanges: \(_hasChanges)
        }
        """
    }
}
extension WritableRealtimeValue where Self: _RealtimeValue {
    public func write(to transaction: Transaction, by node: Node) throws {
        try _write(to: transaction, by: node)
    }
}
extension ChangeableRealtimeValue where Self: _RealtimeValue {
    public var hasChanges: Bool { return _hasChanges }
    public func writeChanges(to transaction: Transaction, by node: Node) throws {
        try _writeChanges(to: transaction, by: node)
    }
}

public extension RawRepresentable where Self.RawValue == String {
    func nested<Type: Object>(in object: Object, options: RealtimeValueOptions = .init()) -> Type {
        let property = Type(
            in: Node(key: rawValue, parent: object.node),
            options: RealtimeValueOptions(database: object.database, raw: options.raw, payload: options.payload)
        )
        property.parent = object
        return property
    }
}

/// Main class to define Realtime models objects.
/// You can define child properties using classes:
///
/// - Object subclasses;
/// - ReadonlyProperty subclasses;
/// - References, Values, AssociatedValues;
///
/// If you use lazy properties, you need implement class function function **lazyPropertyKeyPath(for:)**.
/// Show it description for details.
///
/// This function called for each subclass, therefore you don`t need call super implementation.
///
/// Example:
///
///     class User: Object {
///         lazy var name: Property<String?> = "user_name".property(in: self)
///     
///         open class func lazyPropertyKeyPath(for label: String) -> AnyKeyPath? {
///             switch label {
///                 case "name": return \User.name
///                 default: return nil
///             }
///         }
///     }
///
open class Object: _RealtimeValue, ChangeableRealtimeValue, WritableRealtimeValue, RealtimeValueActions, Hashable, Comparable, Versionable {
    override var _hasChanges: Bool { return containsInLoadedChild(where: { (_, val: _RealtimeValue) in return val._hasChanges }) }
    lazy var repeater: Repeater<Object> = Repeater.unsafe()

    public var keepSynced: Bool = false {
        didSet {
            guard oldValue != keepSynced else { return }
            if keepSynced { runObserving() }
            else { stopObserving() }
        }
    }

    /// Parent object
    open weak var parent: Object? {
        didSet {
            if let node = self.node, let p = parent {
                debugFatalError(condition: p === self, "Parent object cannot be equal child")
                /// node.parent annulled in didRemove
                debugFatalError(condition: node.parent.map({ $0 != p.node }) ?? false,
                                "Parent object was changed, but his node doesn`t equal parent node in current object")
                debugFatalError(condition: node === p.node, "Parent object has the same node reference that child object")
                node.parent = p.node
            }
        }
    }

    /// Labels of properties that shouldn`t represent as database data
    open var ignoredLabels: [String] {
        return []
    }

    public init(in object: Object, keyedBy key: String, options: RealtimeValueOptions) {
        super.init(
            node: Node(key: key, parent: object.node),
            options: options.with(db: object.database)
        )
        self.parent = object
    }

    public required init(in node: Node? = nil, options: RealtimeValueOptions = RealtimeValueOptions()) {
        super.init(node: node, options: options)
    }

    public required init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        try super.init(data: data, event: event)
    }

    @discardableResult
    public func runObserving() -> Bool {
        return _runObserving(.value)
    }
    public func stopObserving() {
        if !keepSynced || (observing[.value].map({ $0.counter > 1 }) ?? true) {
            _stopObserving(.value)
        }
    }

    public override func willSave(in transaction: Transaction, in parent: Node, by key: String) {
        super.willSave(in: transaction, in: parent, by: key)
        let node = parent.child(with: key)
        enumerateLoadedChilds { (_, value: _RealtimeValue) in
            value.willSave(in: transaction, in: node, by: value.node!.key)
        }
    }

    public override func didSave(in database: RealtimeDatabase, in parent: Node, by key: String) {
        super.didSave(in: database, in: parent, by: key)
        if let node = self.node {
            enumerateLoadedChilds { (_, value: _RealtimeValue) in
                if conditionForWrite(of: value) {
                    value.didSave(in: database, in: node)
                } else {
                    if let node = value.node {
                        value._RealtimeValue_didSave(in: database, in: parent, by: node.key)
                    } else {
                        debugFatalError("Unkeyed value has been saved to undefined location in parent node: \(parent.absolutePath)")
                    }
                }
            }
        } else {
            debugFatalError("Unkeyed value has been saved to location in parent node: \(parent.absolutePath)")
        }
    }

    public override func willUpdate(through ancestor: Node, in transaction: Transaction) {
        super.willUpdate(through: ancestor, in: transaction)

        guard var current = self._version.map(Versioner.init(version:)) else {
            _performMigrationIfNeeded(in: transaction)
            return
        }
        var targetVersion = Versioner()
        putVersion(into: &targetVersion)
        if !targetVersion.isEmpty, current < targetVersion {
            _performMigration(from: &current, to: &targetVersion, in: transaction)
        }
    }

    public override func didUpdate(through ancestor: Node) {
        super.didUpdate(through: ancestor)
        enumerateLoadedChilds { (_, value: _RealtimeValue) in
            value.didUpdate(through: ancestor)
        }
    }

    typealias Links = Property<[SourceLink]>
    public override func willRemove(in transaction: Transaction, from ancestor: Node) {
        super.willRemove(in: transaction, from: ancestor)
        forceEnumerateAllChilds { (_, value: _RealtimeValue) in
            value.willRemove(in: transaction, from: ancestor)
        }
        let linksWillNotBeRemovedInAncestor = node?.parent == ancestor
        let links: Links = Links(
            in: self.node.map { Node(key: InternalKeys.linkItems, parent: $0.linksNode) },
            options: .required(Representer<[SourceLink]>.links, db: database, initial: [])
        ).defaultOnEmpty()
        transaction.addPrecondition { [unowned transaction] (promise) in
            _ = links.loadValue().listening({ (event) in
                switch event {
                case .value(let refs):
                    refs.flatMap { $0.links.map(Node.root.child) }.forEach { n in
                        if !n.hasAncestor(node: ancestor) {
                            transaction.removeValue(by: n)
                        }
                    }
                    if linksWillNotBeRemovedInAncestor {
                        transaction.delete(links)
                    }
                    promise.fulfill()
                case .error(let e): promise.reject(e)
                }
            })
        }
    }
    
    override public func didRemove(from ancestor: Node) {
        enumerateLoadedChilds { (_, value: _RealtimeValue) in
            value.didRemove(from: ancestor)
        }
        if ancestor == self.node?.parent {
            parent = nil
        }
        super.didRemove(from: ancestor)
    }
    
    override open func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        try super.apply(data, event: event)
        var errors: [String: Error] = [:]
        Reflector(reflecting: self, to: Object.self).forEach { (mirror) in
            apply(data, event: event, to: mirror, errorsContainer: &errors)
        }
        if errors.count > 0 {
            let error = RealtimeError(source: .objectCoding(errors), description: "Failed decoding data: \(data) to type: \(type(of: self))")
            repeater.send(.error(error))
            throw error
        } else {
            repeater.send(.value(self))
        }
    }
    private func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent, to mirror: Mirror, errorsContainer: inout [String: Error]) {
        mirror.children.forEach { (child) in
            guard isNotIgnoredLabel(child.label) else { return }

            if var value: _RealtimeValue = forceValue(from: child, mirror: mirror), conditionForRead(of: value) {
                do {
                    try value.apply(parentDataIfNeeded: data, parentEvent: event)
                } catch let e {
                    errorsContainer[value.dbKey] = e
                }
            }
        }
    }

    public func currentVersion(on level: UInt) throws -> Version {
        if isRooted {
            guard var versioner = _version.map(Versioner.init) else { return Version(0, 0) }
            try (0..<level).forEach({ _ in _ = try versioner.dequeue() })
            return try versioner.dequeue()
        } else {
            var versioner = Versioner()
            putVersion(into: &versioner)
            try (0..<level).forEach({ _ in _ = try versioner.dequeue() })
            return try versioner.dequeue()
        }
    }

    open func performMigration(from currentVersion: inout Versioner, to newVersion: inout Versioner, in transaction: Transaction) throws {
        // override in subclass
        // always call super method first, otherwise result of migration can be unexpected
    }

    func _performMigrationIfNeeded(in transaction: Transaction) {
        guard let node = self.node, node.isRooted else { return }

        var targetVersion = Versioner()
        putVersion(into: &targetVersion)
        targetVersion._turn()
        transaction.addPrecondition { [unowned self] (promise) in
            transaction.database.load(
                for: Node(key: InternalKeys.modelVersion, parent: node),
                timeout: .seconds(10),
                completion: { (data) in
                    do {
                        var currentVersion = data.exists() ? Versioner(version: try data.singleValueContainer().decode(String.self)) : Versioner(version: "")
                        if !targetVersion.isEmpty, currentVersion < targetVersion {
                            self._performMigration(from: &currentVersion, to: &targetVersion, in: transaction)
                        }
                        promise.fulfill()
                    } catch let e {
                        debugPrintLog("Migration aborted. Error: \(String(describing: e))")
//                        promise.reject(err)
                        // or
                        promise.fulfill()
                    }
                },
                onCancel: { err in
                    debugPrintLog("Migration aborted. Cannot load model version. Error: \(String(describing: err))")
//                    promise.reject(err)
                    // or
                    promise.fulfill()
                }
            )
        }
    }

    func _performMigration(from oldVersion: inout Versioner, to newVersion: inout Versioner, in transaction: Transaction) {
        debugPrintLog("Begin migration from \(oldVersion) to \(newVersion)")
        do {
            try performMigration(from: &oldVersion, to: &newVersion, in: transaction)
            let finalizedVersion = newVersion.finalize()
            transaction.addValue(RealtimeDatabaseValue(finalizedVersion), by: Node(key: InternalKeys.modelVersion, parent: self.node))
            transaction.addCompletion { [weak self] (result) in
                if result {
                    self?._version = finalizedVersion
                    debugPrintLog("Migration was ended successful")
                } else {
                    debugPrintLog("Migration was ended with errors:")
                }
            }
        } catch let e {
            debugPrintLog("Migration failed. Error: \(String(describing: e))")
        }
    }

    /// Returns key path for lazy properties to force access.
    /// Method should not call super method.
    /// If object has not lazy properies, it is recommended override anyway to avoid calls
    /// super class implementation and conflicts with private properties of super class.
    ///
    /// - Parameter label: Label of property
    /// - Returns: Key path to access property
    open class func lazyPropertyKeyPath(for label: String) -> AnyKeyPath? {
        fatalError("You should implement class func lazyPropertyKeyPath(for:)")
    }

    /// Returns flag of condition that writing is enabled/disabled for current transaction
    ///
    /// Override this method to create conditional-required properties.
    /// It calls only in save operation.
    ///
    /// - Parameter property: Value to evalute condition
    /// - Returns: Boolean value of condition
    open func conditionForWrite(of property: _RealtimeValue) -> Bool {
        return true
    }

    // temporary decision to avoid error in optional nested objects that has required properties
    open func conditionForRead(of property: _RealtimeValue) -> Bool {
        return true
    }

    override func _write(to transaction: Transaction, by node: Node) throws {
        try super._write(to: transaction, by: node)
        try Reflector(reflecting: self, to: Object.self).forEach { mirror in
            try mirror.children.forEach({ (child) in
                guard isNotIgnoredLabel(child.label) else { return }

                if
                    let value: _RealtimeValue = forceValue(from: child, mirror: mirror),
                    conditionForWrite(of: value)
                {
                    if let valNode = value.node {
                        try value._write(to: transaction, by: node.child(with: valNode.key))
                    } else {
                        fatalError("There is not specified child node in \(self)")
                    }
                }
            })
        }
    }

    override func _writeChanges(to transaction: Transaction, by node: Node) throws {
//        super._writeChanges(to: transaction, by: node)
        try Reflector(reflecting: self, to: Object.self).lazy.flatMap({ $0.children })
            .forEach { (child) in
                guard isNotIgnoredLabel(child.label) else { return }

                if let value: _RealtimeValue = realtimeValue(from: child.value) {
                    if let valNode = value.node {
                        try value._writeChanges(to: transaction, by: node.child(with: valNode.key))
                    } else {
                        fatalError("There is not specified child node in \(self)")
                    }
                }
        }
    }

    // MARK: Object

    private func realtimeValue<T>(from value: Any) -> T? {
        guard case let child as T = value else { return nil }

        return child
    }
    private func forceValue<T>(from mirrorChild: (label: String?, value: Any), mirror: Mirror) -> T? {
        guard let value: T = realtimeValue(from: mirrorChild.value) else {
            #if swift(>=5.0)
            guard
                var label = mirrorChild.label,
                label.hasPrefix(lazyStoragePath)
            else { return nil }
            #else
            guard
                var label = mirrorChild.label,
                label.hasSuffix(lazyStoragePath)
            else { return nil }
            #endif

            #if swift(>=5.0)
            label = String(label.suffix(from: label.index(label.startIndex, offsetBy: lazyStoragePath.count)))
            #else
            label = String(label.prefix(upTo: label.index(label.endIndex, offsetBy: -lazyStoragePath.count)))
            #endif

            guard let keyPath = (mirror.subjectType as! Object.Type).lazyPropertyKeyPath(for: label) else {
                return nil
            }
            guard case let value as T = self[keyPath: keyPath] else {
                return nil
            }

            return value
        }
        return value
    }
    func forceEnumerateAllChilds<As>(from type: Any.Type = Object.self, _ block: (String?, As) -> Void) {
        Reflector(reflecting: self, to: type).forEach { mirror in
            mirror.children.forEach({ (child) in
                guard isNotIgnoredLabel(child.label) else { return }
                guard let value: As = forceValue(from: child, mirror: mirror) else { return }

                block(child.label, value)
            })
        }
    }
    fileprivate func enumerateLoadedChilds<As>(from type: Any.Type = Object.self, _ block: (String?, As) -> Void) {
        Reflector(reflecting: self, to: type).lazy.flatMap({ $0.children })
            .forEach { (child) in
                guard isNotIgnoredLabel(child.label) else { return }
                guard case let value as As = child.value else { return }

                block(child.label, value)
        }
    }
    private func containsInLoadedChild<As>(from type: Any.Type = Object.self, where block: (String?, As) -> Bool) -> Bool {
        return Reflector(reflecting: self, to: type).lazy.flatMap({ $0.children })
            .contains { (child) -> Bool in
                guard isNotIgnoredLabel(child.label) else { return false }
                guard case let value as As = child.value else { return false }

                return block(child.label, value)
        }
    }
    private func isNotIgnoredLabel(_ label: String?) -> Bool {
        return label.map { lbl -> Bool in
            #if swift(>=5.0)
            if lbl.hasPrefix(lazyStoragePath) {
                return !ignoredLabels.contains(String(lbl.suffix(from: lbl.index(lbl.startIndex, offsetBy: lazyStoragePath.count))))
            } else {
                return !ignoredLabels.contains(lbl)
            }
            #else
            if lbl.hasSuffix(lazyStoragePath) {
                return !ignoredLabels.contains(String(lbl.prefix(upTo: lbl.index(lbl.endIndex, offsetBy: -lazyStoragePath.count))))
            } else {
                return !ignoredLabels.contains(lbl)
            }
            #endif
        } ?? true
    }
    
    override public var debugDescription: String {
        var values: String = ""
        enumerateLoadedChilds { (label, val: _RealtimeValue) in
            let l = label.map({ lbl -> String in
                #if swift(>=5.0)
                if lbl.hasPrefix(lazyStoragePath) {
                    return String(lbl.suffix(from: lbl.index(lbl.startIndex, offsetBy: lazyStoragePath.count)))
                } else {
                    return lbl
                }
                #else
                if lbl.hasSuffix(lazyStoragePath) {
                    return String(lbl.prefix(upTo: lbl.index(lbl.endIndex, offsetBy: -lazyStoragePath.count)))
                } else {
                    return lbl
                }
                #endif
            })
            if values.isEmpty {
                values.append(
                    """
                    \(l ?? ""): \(val.debugDescription)
                    """
                )
            } else {
                values.append(
                    """
                    \t\t\(l ?? ""): \(val.debugDescription)
                    """
                )
                values.append(",\n")
            }
            values.append(",\n")
        }
        return """
        \(type(of: self)): \(withUnsafePointer(to: self, String.init(describing:))) {
            ref: \(node?.absolutePath ?? "not referred"),
            raw: \(raw.map(String.init(describing:)) ?? "no raw"),
            has changes: \(_hasChanges),
            keepSynced: \(keepSynced),
            values: [
                \(values)
            ]
        }
        """
    }
}

extension RTime: Listenable where Base: Object {
    public typealias Out = Base
    /// Disposable listening of value
    public func listening(_ assign: Assign<ListenEvent<Base>>) -> Disposable {
        return base.repeater.map({ $0 as! Base }).listening(assign)
    }
}
extension Object: RealtimeCompatible {}

extension Object: Reverting {
    public func revert() {
        enumerateLoadedChilds { (_, value: Reverting) in
            value.revert()
        }
    }
    public func currentReversion() -> () -> Void {
        var revertions: [() -> Void] = []
        enumerateLoadedChilds { (_, value: Reverting) in
            revertions.insert(value.currentReversion(), at: 0)
        }
        return { revertions.forEach { $0() } }
    }
}

public extension Object {
    /* TODO: creates objects with `Object` type and get EXC_BAD_ACCESS crash on runtime, because `_RealtimeValue.init` is not required
    /// Creates new instance associated with database node
    ///
    /// - Parameter node: Node location for value
    convenience init(in node: Node?) { self.init(in: node, options: RealtimeValueOptions()) }
    /// Creates new standalone instance with undefined node
    convenience init() { self.init(in: nil) }
     */
}

public extension Object {
    /// writes Object in transaction like as single value
    @discardableResult
    func save(by node: Node, in transaction: Transaction) throws -> Transaction {
        try transaction.set(self, by: node)
        return transaction
    }

    /// writes Object in transaction like as single value
    func save(by node: Node) throws -> Transaction {
        guard let db = database else { fatalError("To create new instance `Transaction` object must has database reference") }

        let transaction = Transaction(database: db)
        do {
            return try save(by: node, in: transaction)
        } catch let e {
            transaction.revert()
            throw e
        }
    }

    /// writes Object in transaction like as single value
    @discardableResult
    func save(in parent: Node, in transaction: Transaction) throws -> Transaction {
        guard let key = self.dbKey else { fatalError("Object has no key. If you cannot set key manually use Object.save(by:in:) method instead") }

        return try save(by: Node(key: key, parent: parent), in: transaction)
    }

    /// writes Object in transaction like as single value
    func save(in parent: Node) throws -> Transaction {
        guard let key = self.dbKey else { fatalError("Object has no key. If you cannot set key manually use Object.save(by:in:) method instead") }
        guard let db = database else { fatalError("To create new instance `Transaction` object must has database reference") }

        let transaction = Transaction(database: db)
        do {
            return try save(by: Node(key: key, parent: parent), in: transaction)
        } catch let e {
            transaction.revert()
            throw e
        }
    }

    /// writes changes of Object in transaction as independed values
    @discardableResult
    func update(in transaction: Transaction) throws -> Transaction {
        try transaction.update(self)
        return transaction
    }

    func update() throws -> Transaction {
        guard let db = database else { fatalError("To create new instance `Transaction` object must has database reference") }

        let transaction = Transaction(database: db)
        do {
            return try update(in: transaction)
        } catch let e {
            transaction.revert()
            throw e
        }
    }

    /// writes empty value by Object node in transaction
    @discardableResult
    func delete(in transaction: Transaction) -> Transaction {
        transaction.delete(self)
        return transaction
    }

    func delete() -> Transaction {
        guard let db = self.database else { fatalError("Object has not database reference, because was not saved") }

        let transaction = Transaction(database: db)
        return delete(in: transaction)
    }
}
