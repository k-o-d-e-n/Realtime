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

/// Base class for any database value
open class _RealtimeValue: RealtimeValue, RealtimeValueEvents, CustomDebugStringConvertible {
    /// Remote version of model
    fileprivate(set) var _version: String?
    /// Database that associated with this value
    public fileprivate(set) var database: RealtimeDatabase?
    /// Node of database tree
    public fileprivate(set) var node: Node?
    /// Raw value if Realtime value represented as enumerated type
    public fileprivate(set) var raw: RealtimeDataValue?
    /// User defined payload related with this value
    public fileprivate(set) var payload: [String : RealtimeDataValue]?
    /// Indicates that value already observed
    public var isObserved: Bool { return observing.count > 0 }
    /// Indicates that value can observe
    public var canObserve: Bool { return isRooted }

    internal var observing: [DatabaseDataEvent: (token: UInt, counter: Int)] = [:]
    let dataObserver: Repeater<(RealtimeDataProtocol, DatabaseDataEvent)> = .unsafe()

    public required init(in node: Node?, options: [ValueOption : Any]) {
        self.database = options[.database] as? RealtimeDatabase ?? RealtimeApp.app.database
        self.node = node
        if case let pl as [String: RealtimeDataValue] = options[.userPayload] {
            self.payload = pl
        }
        if case let ipl as RealtimeDataValue = options[.rawValue] {
            self.raw = ipl
        }
    }

    deinit {
        observing.forEach { key, value in
            debugFatalError(condition: value.counter > 1, "Deinitialization observed value using event: \(key)")
            endObserve(for: value.token)
        }
    }

    public func load(timeout: DispatchTimeInterval = .seconds(30), completion: Assign<Error?>?) {
        guard let node = self.node, let database = self.database else {
            fatalError("Can`t get database reference in \(self). Object must be rooted.")
        }

        database.load(for: node, timeout: timeout, completion: { d in
            do {
                try self.apply(d, event: .value)
                completion?.assign(nil)
                self.dataObserver.send(.value((d, .value)))
            } catch let e {
                completion?.assign(e)
                self.dataObserver.send(.error(e))
            }
        }, onCancel: { e in
            completion?.call(e)
            self.dataObserver.send(.error(e))
        })
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

    internal func _isObserved(_ event: DatabaseDataEvent) -> Bool {
        return observing[event].map { $0.counter > 0 } ?? false
    }

    internal func _numberOfObservers(for event: DatabaseDataEvent) -> Int {
        return observing[event]?.counter ?? 0
    }
    
    func observe(_ event: DatabaseDataEvent = .value) -> UInt? {
        guard let node = self.node, let database = self.database else {
            return nil
        }
        return database.observe(event, on: node, onUpdate: { d in
            do {
                try self.apply(d, event: event)
                self.dataObserver.send(.value((d, event)))
            } catch let e {
                self.dataObserver.send(.error(e))
            }
        }, onCancel: { e in
            self.dataObserver.send(.error(e))
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
            transaction.addValue(finalizedVersion, by: Node(key: InternalKeys.modelVersion, parent: node))
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

    /// support Versionable
    open func putVersion(into versioner: inout Versioner) {
        // override in subclass
        // always call super method first, to achieve correct version value
    }
    
    public var debugDescription: String {
        return """
        \(type(of: self)): \(ObjectIdentifier(self).memoryAddress) {
            ref: \(node?.absolutePath ?? "not referred"),
            raw: \(raw ?? "null"),
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
open class Object: _RealtimeValue, ChangeableRealtimeValue, WritableRealtimeValue, RealtimeValueActions, Hashable, Versionable {
    override var _hasChanges: Bool { return containsInLoadedChild(where: { (_, val: _RealtimeValue) in return val._hasChanges }) }

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
                /// node.parent annulled in didRemove
                debugFatalError(condition: node.parent.map({ $0 != parent.node }) ?? false,
                                "Parent object was changed, but his node doesn`t equal parent node in current object")
                node.parent = p.node
            }
        }
    }

    /// Labels of properties that shouldn`t represent as database data
    open var ignoredLabels: [String] {
        return []
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
            options: [.database: database as Any, .representer: Representer<[SourceLink]>.links.requiredProperty()]
        ).defaultOnEmpty()
        transaction.addPrecondition { [unowned transaction] (promise) in
            links.loadValue(
                completion: .just({ refs in
                    refs.flatMap { $0.links.map(Node.root.child) }.forEach { n in
                        if !n.hasAncestor(node: ancestor) {
                            transaction.removeValue(by: n)
                        }
                    }
                    if linksWillNotBeRemovedInAncestor {
                        transaction.delete(links)
                    }
                    promise.fulfill()
                }),
                fail: .just(promise.reject)
            )
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
        try reflect { (mirror) in
            try apply(data, event: event, to: mirror)
        }
    }
    private func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent, to mirror: Mirror) throws {
        try mirror.children.forEach { (child) in
            guard isNotIgnoredLabel(child.label) else { return }

            if var value: _RealtimeValue = forceValue(from: child, mirror: mirror) {
                try value.apply(parentDataIfNeeded: data, parentEvent: event)
            }
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
                        var currentVersion = data.exists() ? Versioner(version: try data.unbox(as: String.self)) : Versioner(version: "")
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
            transaction.addValue(finalizedVersion, by: Node(key: InternalKeys.modelVersion, parent: self.node))
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

    override func _write(to transaction: Transaction, by node: Node) throws {
        try super._write(to: transaction, by: node)
        try reflect { (mirror) in
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
        try reflect { (mirror) in
            try mirror.children.forEach({ (child) in
                guard isNotIgnoredLabel(child.label) else { return }

                if let value: _RealtimeValue = realtimeValue(from: child.value) {
                    if let valNode = value.node {
                        try value._writeChanges(to: transaction, by: node.child(with: valNode.key))
                    } else {
                        fatalError("There is not specified child node in \(self)")
                    }
                }
            })
        }
    }

    // MARK: Object

    private func realtimeValue<T>(from value: Any) -> T? {
        guard case let child as T = value else { return nil }

        return child
    }
    private func forceValue<T>(from mirrorChild: (label: String?, value: Any), mirror: Mirror) -> T? {
        guard let value: T = realtimeValue(from: mirrorChild.value) else {
            guard
                var label = mirrorChild.label,
                label.hasSuffix(lazyStoragePath)
            else { return nil }

            label = String(label.prefix(upTo: label.index(label.endIndex, offsetBy: -lazyStoragePath.count)))

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
        reflect(to: type) { (mirror) in
            mirror.children.forEach({ (child) in
                guard isNotIgnoredLabel(child.label) else { return }
                guard let value: As = forceValue(from: child, mirror: mirror) else { return }

                block(child.label, value)
            })
        }
    }
    fileprivate func enumerateLoadedChilds<As>(from type: Any.Type = Object.self, _ block: (String?, As) -> Void) {
        reflect(to: type) { (mirror) in
            mirror.children.forEach({ (child) in
                guard isNotIgnoredLabel(child.label) else { return }
                guard case let value as As = child.value else { return }

                block(child.label, value)
            })
        }
    }
    private func containsInLoadedChild<As>(from type: Any.Type = Object.self, where block: (String?, As) -> Bool) -> Bool {
        var contains = false
        reflect(to: type) { (mirror) in
            guard !contains else { return }
            contains = mirror.children.contains(where: { (child) -> Bool in
                guard isNotIgnoredLabel(child.label) else { return false }
                guard case let value as As = child.value else { return false }

                return block(child.label, value)
            })
        }
        return contains
    }
    private func reflect(to type: Any.Type = Object.self, _ block: (Mirror) throws -> Void) rethrows {
        var mirror = Mirror(reflecting: self)
        try block(mirror)
        guard type != mirror.subjectType else { return }
        while let _mirror = mirror.superclassMirror, _mirror.subjectType != type {
            try block(_mirror)
            mirror = _mirror
        }
    }
    private func isNotIgnoredLabel(_ label: String?) -> Bool {
        return label.map { lbl -> Bool in
            if lbl.hasSuffix(lazyStoragePath) {
                return !ignoredLabels.contains(String(lbl.prefix(upTo: lbl.index(lbl.endIndex, offsetBy: -lazyStoragePath.count))))
            } else {
                return !ignoredLabels.contains(lbl)
            }
        } ?? true
    }
    
    override public var debugDescription: String {
        var values: String = ""
        enumerateLoadedChilds { (label, val: _RealtimeValue) in
            let l = label.map({ lbl -> String in
                if lbl.hasSuffix(lazyStoragePath) {
                    return String(lbl.prefix(upTo: lbl.index(lbl.endIndex, offsetBy: -lazyStoragePath.count)))
                } else {
                    return lbl
                }
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
                    \(val.debugDescription)
                    """
                )
                values.append(",\n")
            }
        }
        return """
        \(type(of: self)): \(ObjectIdentifier(self).memoryAddress) {
            ref: \(node?.absolutePath ?? "not referred"),
            raw: \(raw ?? "no raw"),
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
        return base.dataObserver.map({ [weak base] _ in base }).compactMap().listening(assign)
    }
    /// Listening with possibility to control active state
    public func listeningItem(_ assign: Assign<ListenEvent<Base>>) -> ListeningItem {
        return base.dataObserver.map({ [weak base] _ in base }).compactMap().listeningItem(assign)
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
    /// Creates new instance associated with database node
    ///
    /// - Parameter node: Node location for value
    convenience init(in node: Node?) { self.init(in: node, options: [:]) }
    /// Creates new standalone instance with undefined node
    convenience init() { self.init(in: nil) }
}

public extension Object {
    /// writes Object in transaction like as single value
    @discardableResult
    public func save(by node: Node, in transaction: Transaction) throws -> Transaction {
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
    public func save(in parent: Node, in transaction: Transaction) throws -> Transaction {
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
    public func update(in transaction: Transaction) throws -> Transaction {
        try transaction.update(self)
        return transaction
    }

    public func update() throws -> Transaction {
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
    public func delete(in transaction: Transaction) -> Transaction {
        transaction.delete(self)
        return transaction
    }

    public func delete() -> Transaction {
        guard let db = self.database else { fatalError("Object has not database reference, because was not saved") }

        let transaction = Transaction(database: db)
        return delete(in: transaction)
    }
}
