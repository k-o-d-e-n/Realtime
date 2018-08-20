//
//  RealtimeObject.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 14/01/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation
import FirebaseDatabase

// TODO: Add caching mechanism, for reuse entities (Can use root global element describing all database)

/// Base class for any database value
open class _RealtimeValue: RealtimeValue, RealtimeValueActions, Hashable, CustomDebugStringConvertible {
    public var dbRef: DatabaseReference?
    public fileprivate(set) var node: Node?
    public fileprivate(set) var version: Int?
    public fileprivate(set) var raw: FireDataValue?
    public fileprivate(set) var payload: [String : FireDataValue]?
    public var isObserved: Bool { return observing != nil }
    public var canObserve: Bool { return isRooted }

    private var observing: (token: UInt, counter: Int)?

    public required init(in node: Node?, options: [RealtimeValueOption : Any]) {
        self.node = node
        self.dbRef = node.flatMap { $0.isRooted ? $0.reference() : nil }
        if case let pl as [String: FireDataValue] = options[.payload] {
            self.payload = pl
        }
        if case let ipl as InternalPayload = options[.internalPayload] {
            self.version = ipl.version
            self.raw = ipl.raw
        }
    }

    deinit {
        observing.map {
            debugFatalError(condition: $0.counter > 1, "Deinitialization observed value")
            endObserve(for: $0.token)
        }
    }

    public func load(completion: Assign<Error?>?) {
        guard let ref = dbRef else {
            fatalError("Can`t get database reference in \(self). Object must be rooted.")
        }

        ref.observeSingleEvent(
            of: .value,
            with: { d in
                do {
                    try self.apply(d, strongly: true)
                    completion?.assign(nil)
                } catch let e {
                    completion?.assign(e)
                }
        },
            withCancel: { e in
                completion?.assign(e)
        })
    }

    @discardableResult
    public func runObserving() -> Bool {
        guard isRooted else { fatalError("Tries observe not rooted value") }
        guard let o = observing else {
            observing = observe(type: .value, onUpdate: nil).map { ($0, 1) }
            return observing != nil
        }

        debugFatalError(condition: o.counter == 0, "Counter is null. Should been invalidated")
        observing = (o.token, o.counter + 1)
        return true
    }

    public func stopObserving() {
        guard var o = observing else { return }

        o.counter -= 1
        if o.counter < 1 {
            endObserve(for: o.token)
            observing = nil
        } else {
            observing = o
        }
    }
    
    func observe(type: DataEventType = .value, onUpdate: ((Error?) -> Void)? = nil) -> UInt? {
        guard let ref = dbRef else {
            fatalError("Can`t get database reference in \(self). Object must be rooted.")
        }
        return ref.observe(
            type,
            with: { d in
                do {
                    try self.apply(d, strongly: type == .value)
                    onUpdate?(nil)
                } catch let e {
                    onUpdate?(e)
                }
        },
            withCancel: { e in
                onUpdate?(e)
        })
    }

    func endObserve(for token: UInt) {
        guard let ref = dbRef else {
            return debugFatalError(condition: true, "Couldn`t get reference")
        }

        ref.removeObserver(withHandle: token);
    }

    public func willRemove(in transaction: RealtimeTransaction, from ancestor: Node) {
        debugFatalError(condition: self.node == nil || !self.node!.isRooted,
                        "Value will be removed from node: \(ancestor), but has not been inserted before. Current: \(self.node?.description ?? "")")
        debugFatalError(condition: !self.node!.hasParent(node: ancestor),
                        "Value will be removed from node: \(ancestor), that is not ancestor for this location: \(self.node!.description)")
        debugFatalError(condition: !ancestor.isRooted, "Value will be removed from non rooted node: \(ancestor)")
    }
    public func didRemove(from ancestor: Node) {
        debugFatalError(condition: self.node == nil || !self.node!.isRooted,
                        "Value has been removed from node: \(ancestor), but has not been inserted before. Current: \(self.node?.description ?? "")")
        debugFatalError(condition: !self.node!.hasParent(node: ancestor),
                        "Value has been removed from node: \(ancestor), that is not ancestor for this location: \(self.node!.description)")
        debugFatalError(condition: !ancestor.isRooted, "Value has been removed from non rooted node: \(ancestor)")

        dbRef?.removeAllObservers()
        observing = nil
        if node?.parent == ancestor {
            self.node?.parent = nil
            self.dbRef = nil
        }
    }
    public func willSave(in transaction: RealtimeTransaction, in parent: Node, by key: String) {
        debugFatalError(condition: self.node.map { $0.key != key } ?? false, "Value will be saved to node: \(parent) by key: \(key), but current node has key: \(node?.key ?? "").")
        debugFatalError(condition: !parent.isRooted, "Value will be saved non rooted node: \(parent)")
    }
    public func didSave(in parent: Node, by key: String) {
        debugFatalError(condition: self.node.map { $0.key != key } ?? false, "Value has been saved to node: \(parent) by key: \(key), but current node has key: \(node?.key ?? "").")
        debugFatalError(condition: !parent.isRooted, "Value has been saved non rooted node: \(parent)")

        if let node = self.node {
            node.parent = parent
        } else {
            self.node = Node(key: key, parent: parent)
        }
        
        self.dbRef = parent.isRooted ? self.node?.reference() : nil
    }
    
    // MARK: Changeable & Writable

    internal var _hasChanges: Bool { return false }

    internal func _writeChanges(to transaction: RealtimeTransaction, by node: Node) throws {
        if _hasChanges {
            try _write(to: transaction, by: node)
        }
    }

    internal final func _write_RealtimeValue(to transaction: RealtimeTransaction, by node: Node) {
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

    internal func _write(to transaction: RealtimeTransaction, by node: Node) throws {
        _write_RealtimeValue(to: transaction, by: node)
    }

    // MARK: Realtime Value

    public required init(fireData: FireDataProtocol) throws {
        self.node = Node.root.child(with: fireData.dataRef!.rootPath)
        self.dbRef = fireData.dataRef
        try apply(fireData, strongly: true)
    }

    func _apply_RealtimeValue(_ data: FireDataProtocol, strongly: Bool) {
        version = data.version
        raw = data.rawValue
        payload = InternalKeys.payload.map(from: data)
    }
    open func apply(_ data: FireDataProtocol, strongly: Bool) throws {
        _apply_RealtimeValue(data, strongly: strongly)
    }
    
    public var debugDescription: String { return "\n{\n\tref: \(node?.rootPath ?? "not referred");\n\tvalue: \("TODO:");\n\tchanges: \(String(describing: /*localChanges*/"TODO: Make local changes"));\n}" }
}
extension WritableRealtimeValue where Self: _RealtimeValue {
    public func write(to transaction: RealtimeTransaction, by node: Node) throws {
        try _write(to: transaction, by: node)
    }
}
extension ChangeableRealtimeValue where Self: _RealtimeValue {
    public var hasChanges: Bool { return _hasChanges }
    public func writeChanges(to transaction: RealtimeTransaction, by node: Node) throws {
        try _writeChanges(to: transaction, by: node)
    }
}

/// Main class to define Realtime models objects.
/// You can define child properties using classes:
///
/// - RealtimeObject subclasses;
/// - RealtimeProperty;
/// - LinkedRealtimeArray, RealtimeArray, RealtimeDictionary;
///
/// If you use lazy properties, you need implement class function function **lazyPropertyKeyPath(for:)**.
/// Show it description for details.
///
/// This function called for each subclass, therefore you don`t need call super implementation.
///
/// Example:
///
///     class User: RealtimeObject {
///         lazy var name: RealtimeProperty<String?> = "user_name".property(from: self.node)
///     
///         open class func lazyPropertyKeyPath(for label: String) -> AnyKeyPath? {
///             switch label {
///                 case "name": return \User.name
///                 default: return nil
///             }
///         }
///     }
///
open class RealtimeObject: _RealtimeValue, ChangeableRealtimeValue, WritableRealtimeValue {
    override var _hasChanges: Bool { return containsInLoadedChild(where: { (_, val: _RealtimeValue) in return val._hasChanges }) }

    open weak var parent: RealtimeObject?

    open var ignoredLabels: [String] {
        return []
    }

    public override func willSave(in transaction: RealtimeTransaction, in parent: Node, by key: String) {
        super.willSave(in: transaction, in: parent, by: key)
        let node = parent.child(with: key)
        enumerateLoadedChilds { (_, value: _RealtimeValue) in
            value.willSave(in: transaction, in: node, by: value.node!.key)
        }
    }

    override public func didSave(in parent: Node, by key: String) {
        super.didSave(in: parent, by: key)
        if let node = self.node {
            enumerateLoadedChilds { (_, value: _RealtimeValue) in
                value.didSave(in: node)
            }
        } else {
            debugFatalError("Unkeyed value has been saved to undefined location in parent node: \(parent.rootPath)")
        }
    }

    typealias Links = RealtimeProperty<[SourceLink]>
    public override func willRemove(in transaction: RealtimeTransaction, from ancestor: Node) {
        super.willRemove(in: transaction, from: ancestor)
        forceEnumerateAllChilds { (_, value: _RealtimeValue) in
            value.willRemove(in: transaction, from: ancestor)
        }
        let links: Links = Links(in: node!.linksNode, options: [.representer: Representer<[SourceLink]>.links])
        transaction.addPrecondition { [unowned transaction] (promise) in
            links.loadValue(
                completion: .just({ refs in
                    refs.flatMap { $0.links.map(Node.root.child) }.forEach(transaction.removeValue)
                    do {
                        try transaction.delete(links)
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
    
    override open func apply(_ data: FireDataProtocol, strongly: Bool) throws {
        try super.apply(data, strongly: strongly)
        try reflect { (mirror) in
            try apply(data, strongly: strongly, to: mirror)
        }
    }
    private func apply(_ data: FireDataProtocol, strongly: Bool, to mirror: Mirror) throws {
        try mirror.children.forEach { (child) in
            guard isNotIgnoredLabel(child.label) else { return }

            if var value: _RealtimeValue = forceValue(from: child, mirror: mirror) {
                try value.apply(parentDataIfNeeded: data, strongly: strongly)
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
        fatalError("You should implement class func keyPath(for:)")
    }

    override func _write(to transaction: RealtimeTransaction, by node: Node) throws {
        try super._write(to: transaction, by: node)
        try reflect { (mirror) in
            try mirror.children.forEach({ (child) in
                guard isNotIgnoredLabel(child.label) else { return }

                if let value: _RealtimeValue = realtimeValue(from: child.value) {
                    if let valNode = value.node {
                        try value._write(to: transaction, by: node.child(with: valNode.key))
                    } else {
                        fatalError("There is not specified child node in \(self)")
                    }
                }
            })
        }
    }

    override func _writeChanges(to transaction: RealtimeTransaction, by node: Node) throws {
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

    // MARK: RealtimeObject

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

            guard let keyPath = (mirror.subjectType as! RealtimeObject.Type).lazyPropertyKeyPath(for: label) else {
                return nil
            }
            guard case let value as T = self[keyPath: keyPath] else {
                return nil
            }

            return value
        }
        return value
    }
    fileprivate func forceEnumerateAllChilds<As>(from type: Any.Type = RealtimeObject.self, _ block: (String?, As) -> Void) {
        reflect(to: type) { (mirror) in
            mirror.children.forEach({ (child) in
                guard isNotIgnoredLabel(child.label) else { return }
                guard let value: As = forceValue(from: child, mirror: mirror) else { return }

                block(child.label, value)
            })
        }
    }
    fileprivate func enumerateLoadedChilds<As>(from type: Any.Type = RealtimeObject.self, _ block: (String?, As) -> Void) {
        reflect(to: type) { (mirror) in
            mirror.children.forEach({ (child) in
                guard isNotIgnoredLabel(child.label) else { return }
                guard case let value as As = child.value else { return }

                block(child.label, value)
            })
        }
    }
    private func containsInLoadedChild<As>(from type: Any.Type = RealtimeObject.self, where block: (String?, As) -> Bool) -> Bool {
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
    private func reflect(to type: Any.Type = RealtimeObject.self, _ block: (Mirror) throws -> Void) rethrows {
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
    
//    override public var debugDescription: String { return "\n{\n\tref: \(dbRef.pathFromRoot);" }//_allProps.reduce("\n{\n\tref: \(dbRef.pathFromRoot);") { $0 + "\n\"\($1.dbKey)\":" + $1.debugDescription } + "\n}" }
}

extension RealtimeObject: Reverting {
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

extension RealtimeObject {
    /// writes RealtimeObject in transaction like as single value
    public func save(in parent: Node, in transaction: RealtimeTransaction? = nil) throws -> RealtimeTransaction {
        guard let key = self.dbKey else { fatalError("Object has not key. If you cannot set key manually use RealtimeTransaction.set(_:by:) method instead") }

        let transaction = transaction ?? RealtimeTransaction()
        try transaction.set(self, by: Node(key: key, parent: parent))
        return transaction
    }

    /// writes changes of RealtimeObject in transaction as independed values
    public func update(in transaction: RealtimeTransaction? = nil) throws -> RealtimeTransaction {
        let transaction = transaction ?? RealtimeTransaction()
        try transaction.update(self)
        return transaction
    }

    /// writes empty value by RealtimeObject reference in transaction 
    public func delete(in transaction: RealtimeTransaction? = nil) throws -> RealtimeTransaction {
        let transaction = transaction ?? RealtimeTransaction()
        try transaction.delete(self)
        return transaction
    }
}
