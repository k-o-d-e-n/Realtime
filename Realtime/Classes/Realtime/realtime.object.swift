//
//  Object.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 14/01/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation
import FirebaseDatabase

/// Base class for any database value
open class _RealtimeValue: RealtimeValue, RealtimeValueEvents, Hashable, CustomDebugStringConvertible {
    /// Database that associated with this value
    public fileprivate(set) var database: RealtimeDatabase?
    /// Node of database tree
    public fileprivate(set) var node: Node?
    /// Version of representation
    public fileprivate(set) var version: Int?
    /// Raw value if Realtime value represented as enumerated type
    public fileprivate(set) var raw: RealtimeDataValue?
    /// User defined payload related with this value
    public fileprivate(set) var payload: [String : RealtimeDataValue]?
    /// Indicates that value already observed
    public var isObserved: Bool { return observing.count > 0 }
    /// Indicates that value can observe
    public var canObserve: Bool { return isRooted }

    private var observing: [DatabaseDataEvent: (token: UInt, counter: Int)] = [:]
    let dataObserver: Repeater<(RealtimeDataProtocol, DatabaseDataEvent)> = .unsafe()

    public required init(in node: Node?, options: [ValueOption : Any]) {
        self.database = options[.database] as? RealtimeDatabase ?? RealtimeApp.app.database
        self.node = node
        if case let pl as [String: RealtimeDataValue] = options[.payload] {
            self.payload = pl
        }
        if case let ipl as InternalPayload = options[.internalPayload] {
            self.version = ipl.version
            self.raw = ipl.raw
        }
    }

    deinit {
        observing.forEach { key, value in
            debugFatalError(condition: value.counter > 1, "Deinitialization observed value using event: \(key)")
            endObserve(for: value.token)
        }
    }

    public func load(completion: Assign<Error?>?) {
        guard let node = self.node, let database = self.database else {
            fatalError("Can`t get database reference in \(self). Object must be rooted.")
        }

        database.load(for: node, completion: { d in
            do {
                try self.apply(d, exactly: true)
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
        guard isRooted else { fatalError("Tries observe not rooted value") }
        guard let o = observing[event] else {
            observing[event] = observe(event).map { ($0, 1) }
            return observing[event] != nil
        }

        debugFatalError(condition: o.counter == 0, "Counter is null. Should been invalidated")
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
            fatalError("Can`t get database reference in \(self). Object must be rooted.")
        }
        return database.observe(event, on: node, onUpdate: { d in
            do {
                try self.apply(d, exactly: event == .value)
                self.dataObserver.send(.value((d, event)))
            } catch let e {
                self.dataObserver.send(.error(e))
            }
        }, onCancel: { e in
            self.dataObserver.send(.error(e))
        })
    }

    func endObserve(for token: UInt) {
        guard let node = node, let database = self.database else {
            return debugFatalError(condition: true, "Couldn`t get reference")
        }

        database.removeObserver(for: node, with: token)
    }

    public func willRemove(in transaction: Transaction, from ancestor: Node) {
        debugFatalError(condition: self.node == nil || !self.node!.isRooted,
                        "Value will be removed from node: \(ancestor), but has not been inserted before. Current: \(self.node?.description ?? "")")
        debugFatalError(condition: !self.node!.hasAncestor(node: ancestor),
                        "Value will be removed from node: \(ancestor), that is not ancestor for this location: \(self.node!.description)")
        debugFatalError(condition: !ancestor.isRooted, "Value will be removed from non rooted node: \(ancestor)")
    }
    public func didRemove(from ancestor: Node) {
        debugFatalError(condition: self.node == nil || !self.node!.isRooted,
                        "Value has been removed from node: \(ancestor), but has not been inserted before. Current: \(self.node?.description ?? "")")
        debugFatalError(condition: !self.node!.hasAncestor(node: ancestor),
                        "Value has been removed from node: \(ancestor), that is not ancestor for this location: \(self.node!.description)")
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
        debugFatalError(condition: self.node.map { $0.key != key } ?? false, "Value has been saved to node: \(parent) by key: \(key), but current node has key: \(node?.key ?? "").")
        debugFatalError(condition: !parent.isRooted, "Value has been saved non rooted node: \(parent)")

        self.database = database
        if let node = self.node {
            node.parent = parent
        } else {
            self.node = Node(key: key, parent: parent)
        }
    }
    
    // MARK: Changeable & Writable

    internal var _hasChanges: Bool { return false }

    internal func _writeChanges(to transaction: Transaction, by node: Node) throws {
        if _hasChanges {
            try _write(to: transaction, by: node)
        }
    }

    internal final func _write_RealtimeValue(to transaction: Transaction, by node: Node) {
        if let mv = version {
            transaction.addValue(mv, by: Node(key: InternalKeys.modelVersion, parent: node))
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

    public required init(data: RealtimeDataProtocol, exactly: Bool) throws {
        self.database = data.database
        self.node = data.node
        try apply(data, exactly: exactly)
    }

    func _apply_RealtimeValue(_ data: RealtimeDataProtocol, exactly: Bool) {
        version = data.version
        raw = data.rawValue
        payload = InternalKeys.payload.map(from: data)
    }
    open func apply(_ data: RealtimeDataProtocol, exactly: Bool) throws {
        _apply_RealtimeValue(data, exactly: exactly)
    }
    
    public var debugDescription: String {
        return """
        {
            ref: \(node?.rootPath ?? "not referred"),
            version: \(version ?? 0),
            raw: \(raw ?? "no raw"),
            has changes: \(_hasChanges)
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
///         lazy var name: Property<String?> = "user_name".property(from: self.node)
///     
///         open class func lazyPropertyKeyPath(for label: String) -> AnyKeyPath? {
///             switch label {
///                 case "name": return \User.name
///                 default: return nil
///             }
///         }
///     }
///
open class Object: _RealtimeValue, ChangeableRealtimeValue, WritableRealtimeValue, RealtimeValueActions {
    override var _hasChanges: Bool { return containsInLoadedChild(where: { (_, val: _RealtimeValue) in return val._hasChanges }) }

    public var keepSynced: Bool = false {
        didSet {
            guard oldValue != keepSynced else { return }
            if keepSynced { runObserving() }
            else { stopObserving() }
        }
    }

    /// Parent object
    open weak var parent: Object?

    /// Labels of properties that shouldn`t represent as database data
    open var ignoredLabels: [String] {
        return []
    }

    @discardableResult
    public func runObserving() -> Bool {
        return _runObserving(.value)
    }
    public func stopObserving() {
        _stopObserving(.value)
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
                value.didSave(in: database, in: node)
            }
        } else {
            debugFatalError("Unkeyed value has been saved to undefined location in parent node: \(parent.rootPath)")
        }
    }

    typealias Links = Property<[SourceLink]>
    public override func willRemove(in transaction: Transaction, from ancestor: Node) {
        super.willRemove(in: transaction, from: ancestor)
        forceEnumerateAllChilds { (_, value: _RealtimeValue) in
            value.willRemove(in: transaction, from: ancestor)
        }
        let needRemoveLinks = node?.parent == ancestor
        let links: Links = Links(in: node!.linksNode, representer: Representer<[SourceLink]>.links).defaultOnEmpty()
        transaction.addPrecondition { [unowned transaction] (promise) in
            links.loadValue(
                completion: .just({ refs in
                    refs.flatMap { $0.links.map(Node.root.child) }.forEach { n in
                        if !n.hasAncestor(node: ancestor) {
                            transaction.removeValue(by: n)
                        }
                    }
                    do {
                        if needRemoveLinks {
                            try transaction.delete(links)
                        }
                        promise.fulfill()
                    } catch let e {
                        promise.reject(e)
                    }
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
    
    override open func apply(_ data: RealtimeDataProtocol, exactly: Bool) throws {
        try super.apply(data, exactly: exactly)
        try reflect { (mirror) in
            try apply(data, exactly: exactly, to: mirror)
        }
    }
    private func apply(_ data: RealtimeDataProtocol, exactly: Bool, to mirror: Mirror) throws {
        try mirror.children.forEach { (child) in
            guard isNotIgnoredLabel(child.label) else { return }

            if var value: _RealtimeValue = forceValue(from: child, mirror: mirror) {
                try value.apply(parentDataIfNeeded: data, exactly: exactly)
            }
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

    override func _write(to transaction: Transaction, by node: Node) throws {
        try super._write(to: transaction, by: node)
        try reflect { (mirror) in
            try mirror.children.forEach({ (child) in
                guard isNotIgnoredLabel(child.label) else { return }

                if let value: _RealtimeValue = forceValue(from: child, mirror: mirror) {
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
    fileprivate func forceEnumerateAllChilds<As>(from type: Any.Type = Object.self, _ block: (String?, As) -> Void) {
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
        while let _mirror = mirror.superclassMirror, _mirror.subjectType != type {
            try block(_mirror)
            mirror = _mirror
        }
    }
    private func isNotIgnoredLabel(_ label: String?) -> Bool {
        guard var l = label else { return true }

        if l.hasPrefix(lazyStoragePath) {
            l = String(l.prefix(upTo: l.index(l.endIndex, offsetBy: -lazyStoragePath.count)))
        }
        return !ignoredLabels.contains(l)
    }
    
    override public var debugDescription: String {
        var values: String = ""
        enumerateLoadedChilds { (label, val: _RealtimeValue) in
            if values.isEmpty {
                values.append(
                    """
                            \(label as Any): \(val.debugDescription)
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
        {
            ref: \(node?.rootPath ?? "not referred"),
            version: \(version ?? 0),
            raw: \(raw ?? "no raw"),
            has changes: \(_hasChanges),
            keepSynced: \(keepSynced),
            values:
            \(values)
        }
        """
    }
}

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
    public func delete(in transaction: Transaction) throws -> Transaction {
        try transaction.delete(self)
        return transaction
    }

    public func delete() throws -> Transaction {
        guard let db = self.database else { fatalError("Object has not database reference, because was not saved") }

        let transaction = Transaction(database: db)
        do {
            return try delete(in: transaction)
        } catch let e {
            transaction.revert()
            throw e
        }
    }
}
