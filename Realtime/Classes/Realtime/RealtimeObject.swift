//
//  RealtimeObject.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 14/01/17.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import Foundation
import FirebaseDatabase

// TODO: Add caching mechanism, for reuse entities

/// Base class for any database value
open class _RealtimeValue: ChangeableRealtimeValue, RealtimeValueActions, Hashable, CustomDebugStringConvertible {
    public var dbRef: DatabaseReference?
    public internal(set) var node: Node?
    private var observing: (token: UInt, counter: Int)?
    public var isObserved: Bool { return observing != nil }
    public var localValue: Any? { fatalError("You should implement in your subclass") }
    public required init(in node: Node?) {
        self.node = node
        self.dbRef = node.flatMap { $0.isRooted ? $0.reference : nil }
    }

    deinit {
        observing.map {
            debugFatalError("Deinitialization observed value")
            endObserve(for: $0.token)
        }
    }

    public func load(completion: Assign<(error: Error?, ref: DatabaseReference)>?) {
        RemoteManager.loadData(to: self, completion: completion)
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
        guard var o = observing else {
            return debugFatalError("Try stop observing on not observed value")
        }

        o.counter -= 1
        if o.counter == 0 {
            endObserve(for: o.token)
            observing = nil
        } else {
            observing = o
        }
    }
    
    func observe(type: DataEventType = .value, onUpdate: Database.TransactionCompletion? = nil) -> UInt? {
        return RemoteManager.observe(type: type, entity: self, onUpdate: onUpdate)
    }

    func endObserve(for token: UInt) {
        guard let ref = dbRef else {
            return debugFatalError(condition: true, "Couldn`t get reference")
        }

        ref.removeObserver(withHandle: token);
    }

    public func willRemove(in transaction: RealtimeTransaction) {}
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
    public func willSave(in transaction: RealtimeTransaction, in parent: Node, by key: String) {}
    public func didSave(in parent: Node, by key: String) {
        debugFatalError(condition: self.node.map { $0.key != key } ?? false, "Value has been saved to node: \(parent) by key: \(key), but current node has key: \(node?.key ?? "").")
        debugFatalError(condition: !parent.isRooted, "Value has been saved non rooted node: \(parent)")

        if let node = self.node {
            node.parent = parent
        } else {
            self.node = Node(key: key, parent: parent)
        }
        
        self.dbRef = parent.isRooted ? self.node?.reference : nil
    }
    
    // MARK: Changeable
    
    public var hasChanges: Bool { return false }

    // MARK: Realtime Value

    public required init(snapshot: DataSnapshot) {
        self.node = Node.root.child(with: snapshot.ref.rootPath)
        self.dbRef = snapshot.ref
        apply(snapshot: snapshot)
    }
    
    open func apply(snapshot: DataSnapshot, strongly: Bool) {}

    public func insertChanges(to transaction: RealtimeTransaction, by node: Node) {
        if hasChanges {
            transaction.addValue(localValue, by: node)
        }
    }
    
    public var debugDescription: String { return "\n{\n\tref: \(node?.rootPath ?? "not referred");\n\tvalue: \(String(describing: localValue));\n\tchanges: \(String(describing: /*localChanges*/"TODO: Make local changes"));\n}" }
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
///         lazy var name: StandartProperty<String?> = "user_name".property(from: self.dbRef)
///     
///         open class func keyPath(for label: String) -> AnyKeyPath? {
///             switch label {
///                 case "name": return \User.name
///                 default: return nil
///             }
///         }
///     }
///
open class RealtimeObject: _RealtimeValue {
    override public var hasChanges: Bool { return containChild(where: { (_, val: _RealtimeValue) in return val.hasChanges }) }
    override public var localValue: Any? { return typedLocalValue }
    public var typedLocalValue: [String: Any]? { return keyedValues { return $0.localValue } }

//    private lazy var mv: StandartProperty<Int?> = Nodes.modelVersion.property(from: self.node)
    typealias Links = RealtimeProperty<[SourceLink], SourceLinkArraySerializer>
    lazy var links: Links! = self.node!.linksNode.property() // TODO: Remove. It is needed only in remote.

    open var parent: RealtimeObject?

    public override func willSave(in transaction: RealtimeTransaction, in parent: Node, by key: String) {
        super.willSave(in: transaction, in: parent, by: key)
        let node = parent.child(with: key)
//        mv.willSave(in: transaction, in: node)
        links.willSave(in: transaction, in: node.linksNode)
        enumerateKeyPathChilds(from: RealtimeObject.self) { (_, value: RealtimeValue & RealtimeValueEvents) in
            value.willSave(in: transaction, in: node, by: value.node!.key)
        }
    }

    override public func didSave(in parent: Node, by key: String) {
        super.didSave(in: parent, by: key)
        if let node = self.node {
//            mv.didSave(in: node)
            links.didSave(in: node.linksNode)
            enumerateKeyPathChilds(from: RealtimeObject.self) { (_, value: RealtimeValue & RealtimeValueEvents) in
                value.didSave(in: node)
            }
        } else {
            debugFatalError("Unkeyed value has been saved to undefined location in parent node: \(parent.rootPath)")
        }
    }
    
    override public func willRemove(in transaction: RealtimeTransaction) {
        let links = self.links!
        transaction.addPrecondition { [unowned transaction] (promise) in
            links.loadValue(completion: Assign.just({ err, refs in
                refs.flatMap { $0.links.map(Node.linksNode.child) }.forEach { transaction.addValue(nil, by: $0) }
                transaction.delete(links)
                promise.fulfill(err)
            }))
        }
    }
    
    override public func didRemove(from node: Node) {
//        mv.didRemove(from: node)
        links.didRemove()
        enumerateKeyPathChilds(from: RealtimeObject.self) { (_, value: RealtimeValueEvents & RealtimeValue) in
            value.didRemove(from: node)
        }
        super.didRemove(from: node)
    }
    
    override open func apply(snapshot: DataSnapshot, strongly: Bool) {
//        if strongly || Nodes.modelVersion.has(in: snapshot) { mv.apply(snapshot: Nodes.modelVersion.snapshot(from: snapshot)) }
        if strongly || Nodes.links.has(in: snapshot) { links.apply(snapshot: Nodes.links.snapshot(from: snapshot)) }

        reflect { (mirror) in
            apply(snapshot: snapshot, strongly: strongly, to: mirror)
        }
    }
    private func apply(snapshot: DataSnapshot, strongly: Bool, to mirror: Mirror) {
        mirror.children.forEach { (child) in
            guard var label = child.label else { return }

            if label.hasSuffix(lazyStoragePath) {
                label = String(label.prefix(upTo: label.index(label.endIndex, offsetBy: -lazyStoragePath.count)))
            }

            if let keyPath = (mirror.subjectType as! RealtimeObject.Type).keyPath(for: label) {
                if let value = self[keyPath: keyPath] as? (DataSnapshotRepresented & RealtimeValue) {
                    value.apply(parentSnapshotIfNeeded: snapshot, strongly: strongly)
                }
            }
        }
    }

    open class func keyPath(for label: String) -> AnyKeyPath? {
        fatalError("You should implement class func keyPath(for:)")
    }

    override public func insertChanges(to transaction: RealtimeTransaction, by node: Node) {
        reflect { (mirror) in
            mirror.children.forEach({ (child) in
                guard var label = child.label else { return }

                if label.hasSuffix(lazyStoragePath) {
                    label = String(label.prefix(upTo: label.index(label.endIndex, offsetBy: -lazyStoragePath.count)))
                }
                if let keyPath = (mirror.subjectType as! RealtimeObject.Type).keyPath(for: label) {
                    if let value = self[keyPath: keyPath] as? _RealtimeValue {
                        if let valNode = value.node {
                            value.insertChanges(to: transaction, by: node.child(with: valNode.key))
                        } else {
                            fatalError("There is not specified child node in \(self)")
                        }
                    }
                }
            })
        }
//        mv.insertChanges(to: , by: )
    }

    // MARK: RealtimeObject
    
    // TODO: Link as callback for modelVersion property
    open func performMigration(from version: Int?) {
        // implement migration
    }

    private func keyedValues(use maping: (_RealtimeValue) -> Any?) -> [String: Any]? {
        var keyedValues: [String: Any]? = nil
        enumerateChilds { (_, value: _RealtimeValue) in
            guard value !== links, let mappedValue = maping(value) else { return }

            if keyedValues == nil { keyedValues = [String: Any]() }
            keyedValues![value.dbKey] = mappedValue
        }
        return keyedValues
    }
    fileprivate func enumerateKeyPathChilds<As>(from type: Any.Type = _RealtimeValue.self, _ block: (String, As) -> Void) {
        reflect(to: type) { (mirror) in
            mirror.children.forEach({ (child) in
                guard var label = child.label else { return }

                if label.hasSuffix(lazyStoragePath) {
                    label = String(label.prefix(upTo: label.index(label.endIndex, offsetBy: -lazyStoragePath.count)))
                }

                guard
                    let keyPath = (mirror.subjectType as! RealtimeObject.Type).keyPath(for: label),
                    let value = self[keyPath: keyPath] as? As
                else
                    { return }

                block(label, value)
            })
        }
    }
    fileprivate func enumerateChilds<As>(from type: Any.Type = _RealtimeValue.self, _ block: (String?, As) -> Void) {
        reflect(to: type) { (mirror) in
            mirror.children.forEach({ (child) in
                guard let value = child.value as? As else { return }

                block(child.label, value)
            })
        }
    }
    private func containChild<As>(from type: Any.Type = _RealtimeValue.self, where block: (String?, As) -> Bool) -> Bool {
        var contains = false
        reflect(to: type) { (mirror) in
            guard !contains else { return }
            contains = mirror.children.contains(where: { (child) -> Bool in
                guard let value = child.value as? As else { return false }

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
    public func save(in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        let transaction = transaction ?? RealtimeTransaction()
        transaction.set(self)
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

extension RealtimeObject: Linkable {
    public var linksNode: Node! { return links.node! }
    @discardableResult
    public func add(link: SourceLink) -> Self {
        guard !links.value.contains(where: { $0.id == link.id }) else { return self }
            
        links.value.append(link)
        return self
    }
    @discardableResult
    public func remove(linkBy id: String) -> Self {
        guard let index = links.value.index(where: { $0.id == id }) else { return self }

        links.value.remove(at: index)
        return self
    }
}
public extension Linkable {
    func addLink(_ link: SourceLink, in transaction: RealtimeTransaction) {
        add(link: link)
        transaction.addValue(link.localValue, by: linksNode.child(with: link.id))
    }
    func removeLink(by id: String, in transaction: RealtimeTransaction) {
        remove(linkBy: id)
        transaction.addValue(nil, by: linksNode.child(with: id))
    }
}
