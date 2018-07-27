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

    public func load(completion: Assign<(error: Error?, ref: DatabaseReference)>?) {
        guard let ref = dbRef else {
            debugFatalError(condition: true, "Couldn`t get reference")
            completion?.assign((RealtimeError("Couldn`t get reference"), .root()))
            return
        }

        ref.observeSingleEvent(of: .value, with: { self.apply($0); completion?.assign((nil, ref)) }, withCancel: { completion?.assign(($0, ref)) })
    }

    @discardableResult
    public func runObserving() -> Bool {
        debugFatalError(condition: node.map { !$0.isRooted } ?? true, "Try observe not rooted value")
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
    
    func observe(type: DataEventType = .value, onUpdate: Database.TransactionCompletion? = nil) -> UInt? {
        guard let ref = dbRef else {
            debugFatalError(condition: true, "Couldn`t get reference")
            onUpdate?(RealtimeError("Couldn`t get reference"), .root())
            return nil
        }
        return ref.observe(type, with: { self.apply($0); onUpdate?(nil, $0.ref) }, withCancel: { onUpdate?($0, ref) })
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

    internal func _writeChanges(to transaction: RealtimeTransaction, by node: Node) {
        if _hasChanges {
            _write(to: transaction, by: node)
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

    internal func _write(to transaction: RealtimeTransaction, by node: Node) {
        _write_RealtimeValue(to: transaction, by: node)
    }

    // MARK: Realtime Value

    public required init(fireData: FireDataProtocol) throws {
        self.node = Node.root.child(with: fireData.dataRef!.rootPath)
        self.dbRef = fireData.dataRef
        apply(fireData)
    }
    
    open func apply(_ data: FireDataProtocol, strongly: Bool) {}
    
    public var debugDescription: String { return "\n{\n\tref: \(node?.rootPath ?? "not referred");\n\tvalue: \("TODO:");\n\tchanges: \(String(describing: /*localChanges*/"TODO: Make local changes"));\n}" }
}
extension WritableRealtimeValue where Self: _RealtimeValue {
    public func write(to transaction: RealtimeTransaction, by node: Node) {
        _write(to: transaction, by: node)
    }
}
extension ChangeableRealtimeValue where Self: _RealtimeValue {
    public var hasChanges: Bool { return _hasChanges }
    public func writeChanges(to transaction: RealtimeTransaction, by node: Node) {
        if hasChanges {
            _write(to: transaction, by: node)
        }
    }
}

/// Main class to define Realtime models objects.
/// You can define child properties using classes:
///
/// - RealtimeObject subclasses;
/// - RealtimeProperty;
/// - LinkedRealtimeArray, RealtimeArray, RealtimeDictionary;
///
/// Also for auto decoding you need implement class function **keyPath(for:)**.
///
/// This function called for each subclass, therefore you don`t need call super implementation.
///
/// Example:
///
///     class User: RealtimeObject {
///         lazy var name: RealtimeProperty<String?> = "user_name".property(from: self.node)
///     
///         open class func keyPath(for label: String) -> AnyKeyPath? {
///             switch label {
///                 case "name": return \User.name
///                 default: return nil
///             }
///         }
///     }
///
open class RealtimeObject: _RealtimeValue, ChangeableRealtimeValue, WritableRealtimeValue {
    override var _hasChanges: Bool { return containChild(where: { (_, val: _RealtimeValue) in return val._hasChanges }) }

    open var parent: RealtimeObject?

    public override func willSave(in transaction: RealtimeTransaction, in parent: Node, by key: String) {
        super.willSave(in: transaction, in: parent, by: key)
        let node = parent.child(with: key)
        enumerateKeyPathChilds(from: RealtimeObject.self) { (_, value: RealtimeValue & RealtimeValueEvents) in
            value.willSave(in: transaction, in: node, by: value.node!.key)
        }
    }

    override public func didSave(in parent: Node, by key: String) {
        super.didSave(in: parent, by: key)
        if let node = self.node {
            enumerateKeyPathChilds(from: RealtimeObject.self) { (_, value: RealtimeValue & RealtimeValueEvents) in
                value.didSave(in: node)
            }
        } else {
            debugFatalError("Unkeyed value has been saved to undefined location in parent node: \(parent.rootPath)")
        }
    }

    typealias Links = RealtimeProperty<[SourceLink]>
    public override func willRemove(in transaction: RealtimeTransaction, from ancestor: Node) {
        super.willRemove(in: transaction, from: ancestor)
        enumerateKeyPathChilds(from: RealtimeObject.self) { (_, value: RealtimeValueEvents & RealtimeValue) in
            value.willRemove(in: transaction, from: ancestor)
        }
        let links: Links = Links(in: node!.linksNode, options: [.representer: Representer(serializer: SourceLinkArraySerializer.self)])
        transaction.addPrecondition { [unowned transaction] (promise) in
            links.loadValue(
                completion: .just({ refs in
                    refs.flatMap { $0.links.map(Node.root.child) }.forEach { transaction.removeValue(by: $0) }
                    transaction.delete(links)
                    promise.fulfill(nil)
                }),
                fail: .just(promise.fulfill)
            )
        }
    }
    
    override public func didRemove(from node: Node) {
        enumerateKeyPathChilds(from: RealtimeObject.self) { (_, value: RealtimeValueEvents & RealtimeValue) in
            value.didRemove(from: node)
        }
        super.didRemove(from: node)
    }
    
    override open func apply(_ data: FireDataProtocol, strongly: Bool) {
        super.apply(data, strongly: strongly)
        reflect { (mirror) in
            apply(data, strongly: strongly, to: mirror)
        }
    }
    private func apply(_ data: FireDataProtocol, strongly: Bool, to mirror: Mirror) {
        mirror.children.forEach { (child) in
            guard var label = child.label else { return }

            if label.hasSuffix(lazyStoragePath) {
                label = String(label.prefix(upTo: label.index(label.endIndex, offsetBy: -lazyStoragePath.count)))
            }

            if let keyPath = (mirror.subjectType as! RealtimeObject.Type).keyPath(for: label) {
                if case let value as _RealtimeValue = self[keyPath: keyPath] {
                    value.apply(parentDataIfNeeded: data, strongly: strongly)
                }
            }
        }
    }

    open class func keyPath(for label: String) -> AnyKeyPath? {
        fatalError("You should implement class func keyPath(for:)")
    }

    override func _write(to transaction: RealtimeTransaction, by node: Node) {
        super._write(to: transaction, by: node)
        reflect { (mirror) in
            mirror.children.forEach({ (child) in
                guard var label = child.label else { return }

                if label.hasSuffix(lazyStoragePath) {
                    guard !((child.value as AnyObject) is NSNull) else { return }

                    label = String(label.prefix(upTo: label.index(label.endIndex, offsetBy: -lazyStoragePath.count)))
                }
                if let keyPath = (mirror.subjectType as! RealtimeObject.Type).keyPath(for: label) {
                    if case let value as _RealtimeValue = self[keyPath: keyPath] {
                        if let valNode = value.node {
                            value._write(to: transaction, by: node.child(with: valNode.key))
                        } else {
                            fatalError("There is not specified child node in \(self)")
                        }
                    }
                }
            })
        }
    }

    override func _writeChanges(to transaction: RealtimeTransaction, by node: Node) {
        reflect { (mirror) in
            mirror.children.forEach({ (child) in
                guard var label = child.label else { return }

                if label.hasSuffix(lazyStoragePath) {
                    guard !((child.value as AnyObject) is NSNull) else { return }
                    
                    label = String(label.prefix(upTo: label.index(label.endIndex, offsetBy: -lazyStoragePath.count)))
                }
                if let keyPath = (mirror.subjectType as! RealtimeObject.Type).keyPath(for: label) {
                    if case let value as _RealtimeValue = self[keyPath: keyPath] {
                        if let valNode = value.node {
                            value._writeChanges(to: transaction, by: node.child(with: valNode.key))
                        } else {
                            fatalError("There is not specified child node in \(self)")
                        }
                    }
                }
            })
        }
    }

    // MARK: RealtimeObject

    private func keyedValues(use maping: (_RealtimeValue) -> Any?) -> [String: Any]? {
        var keyedValues: [String: Any]? = nil
        enumerateChilds { (_, value: _RealtimeValue) in
            guard let mappedValue = maping(value) else { return }

            if keyedValues == nil { keyedValues = [String: Any]() }
            keyedValues![value.dbKey] = mappedValue
        }
        return keyedValues
    }
    fileprivate func enumerateKeyPathChilds<As>(from type: Any.Type = _RealtimeValue.self, _ block: (String, As) -> Void) {
        reflect(to: type) { (mirror) in
            mirror.children.forEach({ (child) in
                guard mirror.subjectType != RealtimeObject.self && (child.value as AnyObject) !== parent else { return }
                guard var label = child.label else { return }

                if label.hasSuffix(lazyStoragePath) {
                    label = String(label.prefix(upTo: label.index(label.endIndex, offsetBy: -lazyStoragePath.count)))
                }

                guard
                    let keyPath = (mirror.subjectType as! RealtimeObject.Type).keyPath(for: label),
                    case let value as As = self[keyPath: keyPath]
                else
                    { return }

                block(label, value)
            })
        }
    }
    fileprivate func enumerateChilds<As>(from type: Any.Type = _RealtimeValue.self, _ block: (String?, As) -> Void) {
        reflect(to: type) { (mirror) in
            mirror.children.forEach({ (child) in
                guard mirror.subjectType != RealtimeObject.self && (child.value as AnyObject) !== parent else { return }
                guard case let value as As = child.value else { return }

                block(child.label, value)
            })
        }
    }
    private func containChild<As>(from type: Any.Type = _RealtimeValue.self, where block: (String?, As) -> Bool) -> Bool {
        var contains = false
        reflect(to: type) { (mirror) in
            guard !contains else { return }
            contains = mirror.children.contains(where: { (child) -> Bool in
                guard mirror.subjectType != RealtimeObject.self && (child.value as AnyObject) !== parent else { return false }
                guard case let value as As = child.value else { return false }

                return block(child.label, value)
            })
        }
        return contains
    }
    private func reflect(to type: Any.Type = RealtimeObject.self, _ block: (Mirror) -> Void) {
        var mirror = Mirror(reflecting: self)
        block(mirror)
        while let _mirror = mirror.superclassMirror, _mirror.subjectType != type {
            block(_mirror)
            mirror = _mirror
        }
    }
    
//    override public var debugDescription: String { return "\n{\n\tref: \(dbRef.pathFromRoot);" }//_allProps.reduce("\n{\n\tref: \(dbRef.pathFromRoot);") { $0 + "\n\"\($1.dbKey)\":" + $1.debugDescription } + "\n}" }
}

extension RealtimeObject: Reverting {
    public func revert() {
        enumerateChilds { (_, value: Reverting) in
            value.revert()
        }
    }
    public func currentReversion() -> () -> Void {
        var revertions: [() -> Void] = []
        enumerateChilds { (_, value: Reverting) in
            revertions.insert(value.currentReversion(), at: 0)
        }
        return { revertions.forEach { $0() } }
    }
}

extension RealtimeObject {
    /// writes RealtimeObject in transaction like as single value
    public func save(in parent: Node, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        guard let key = self.dbKey else { fatalError("Object has not key. If you cannot set key manually use RealtimeTransaction.set(_:by:) method instead") }

        let transaction = transaction ?? RealtimeTransaction()
        transaction.set(self, by: Node(key: key, parent: parent))
        return transaction
    }

    /// writes changes of RealtimeObject in transaction as independed values
    public func update(in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        let transaction = transaction ?? RealtimeTransaction()
        transaction.update(self)
        return transaction
    }

    /// writes empty value by RealtimeObject reference in transaction 
    public func delete(in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        let transaction = transaction ?? RealtimeTransaction()
        transaction.delete(self)
        return transaction
    }
}
