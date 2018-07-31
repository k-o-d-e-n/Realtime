//
//  LinkedRealtimeArray.swift
//  Realtime
//
//  Created by Denis Koryttsev on 16/03/2018.
//

import Foundation

public extension RawRepresentable where RawValue == String {
    func linkedArray<Element>(from node: Node?, elements: Node) -> LinkedRealtimeArray<Element> {
        return LinkedRealtimeArray(in: Node(key: rawValue, parent: node), options: [.elementsNode: elements])
    }
    func linkedArray<Element>(from node: Node?, elements: Node, elementOptions: [RealtimeValueOption: Any]) -> LinkedRealtimeArray<Element> {
        return linkedArray(from: node, elements: elements, builder: { (node, options) in
            let compoundOptions = options.merging(elementOptions, uniquingKeysWith: { remote, local in remote })
            return Element(in: node, options: compoundOptions)
        })
    }
    func linkedArray<Element>(from node: Node?, elements: Node, builder: @escaping RCElementBuilder<Element>) -> LinkedRealtimeArray<Element> {
        return LinkedRealtimeArray(in: node, options: [.elementsNode: elements, .elementBuilder: builder])
    }
}

public extension RealtimeValueOption {
    static let elementsNode = RealtimeValueOption("realtime.linkedarray.elements")
}

public final class LinkedRealtimeArray<Element>: _RealtimeValue, ChangeableRealtimeValue, RC where Element: RealtimeValue {
    public override var version: Int? { return nil }
    public override var raw: FireDataValue? { return nil }
    public override var payload: [String : FireDataValue]? { return nil }
    override var _hasChanges: Bool { return storage.localElements.count > 0 }
    public internal(set) var storage: RCArrayStorage<Element>
    public var view: RealtimeCollectionView { return _view }
    public var isPrepared: Bool { return _view.isPrepared }

    let _view: AnyRealtimeCollectionView<[RCItem], LinkedRealtimeArray>

    public required init(in node: Node?, options: [RealtimeValueOption: Any]) {
        guard case let elements as Node = options[.elementsNode] else { fatalError("Skipped required options") }
        let builder = options[.elementBuilder] as? RCElementBuilder<Element> ?? Element.init

        self.storage = RCArrayStorage(sourceNode: elements,
                                      elementBuilder: builder,
                                      elements: [:],
                                      localElements: [])
        self._view = AnyRealtimeCollectionView(RealtimeProperty(in: node, representer: Representer<[RCItem]>(collection: Representer.fireData)))
        super.init(in: node, options: options)
        self._view.collection = self
    }

    // MARK: Realtime

    public convenience init(fireData: FireDataProtocol, elementsNode: Node) throws {
        self.init(in: fireData.dataRef.map(Node.from), options: [.elementsNode: elementsNode])
        try apply(fireData, strongly: true)
    }

    public required init(fireData: FireDataProtocol) throws {
        #if DEBUG
            fatalError("LinkedRealtimeArray does not supported init(fireData:) yet.")
        #else
            throw RealtimeError(source: .collection, description: "LinkedRealtimeArray does not supported init(fireData:) yet.")
        #endif
    }

    // Implementation

    public func contains(_ element: Element) -> Bool { return _view.contains { $0.dbKey == element.dbKey } }

    public subscript(position: Int) -> Element { return storage.object(for: _view[position]) }
    public var startIndex: Int { return _view.startIndex }
    public var endIndex: Int { return _view.endIndex }
    public func index(after i: Int) -> Int { return _view.index(after: i) }
    public func index(before i: Int) -> Int { return _view.index(before: i) }
    public func listening(changes handler: @escaping () -> Void) -> ListeningItem { return _view.source.listeningItem(.just { _ in handler() }) }
    @discardableResult
    override public func runObserving() -> Bool { return _view.source.runObserving() }
    override public func stopObserving() { _view.source.stopObserving() }
    override public var debugDescription: String { return _view.source.debugDescription }
    public func prepare(forUse completion: Assign<(Error?)>) { _view.prepare(forUse: completion) }

    override public func apply(_ data: FireDataProtocol, strongly: Bool) throws {
        try super.apply(data, strongly: strongly)
        try _view.source.apply(data, strongly: strongly)
        _view.isPrepared = strongly
    }

    override func _writeChanges(to transaction: RealtimeTransaction, by node: Node) throws {
        for (index, element) in storage.localElements.enumerated() {
            try _write(element, at: index, by: node, in: transaction)
        }
    }

    /// Collection does not respond for versions and raw value, and also payload.
    /// To change value version/raw can use enum, but use modified representer.
    override func _write(to transaction: RealtimeTransaction, by node: Node) throws {
//        super._write(to: transaction, by: node)
        // writes changes because after save collection can use only transaction mutations
        try _writeChanges(to: transaction, by: node)
    }

    public func didPrepare() {}

//    public func willSave(in transaction: RealtimeTransaction, in parent: Node, by key: String) {

//    }
    override public func didSave(in parent: Node, by key: String) {
        super.didSave(in: parent, by: key)
        _view.source.didSave(in: parent)
    }

    public override func willRemove(in transaction: RealtimeTransaction, from ancestor: Node) {
        super.willRemove(in: transaction, from: ancestor)
        _view.source.willRemove(in: transaction, from: ancestor)
    }
    override public func didRemove(from node: Node) {
        super.didRemove(from: node)
        _view.source.didRemove()
    }
}

// MARK: Mutating

public extension LinkedRealtimeArray {
    @discardableResult
    func write(element: Element, at index: Int? = nil,
                in transaction: RealtimeTransaction? = nil) throws -> RealtimeTransaction {
        guard isRooted else { fatalError("This method is available only for rooted objects. Use method insert(element:at:)") }
        guard element.node?.parent == storage.sourceNode else { fatalError("Element must be located in elements node") }
        guard isPrepared else {
            let transaction = transaction ?? RealtimeTransaction()
            transaction.addPrecondition { [unowned transaction] promise in
                self.prepare(forUse: .just { collection, err in
                    guard err == nil else { return promise.fulfill(err) }
                    do {
                        try collection._write(element, at: index, in: transaction)
                        promise.fulfill(nil)
                    } catch let e {
                        promise.fulfill(e)
                    }
                })
            }
            return transaction
        }

        return try _write(element, at: index, in: transaction)
    }

    func insert(element: Element, at index: Int? = nil) {
        guard isStandalone else { fatalError("This method is available only for standalone objects. Use method write(element:at:in:)") }
        guard element.node?.parent == storage.sourceNode else { fatalError("Element must be located in elements node") }
        let contains = element.node.map { n in storage.localElements.contains(where: { $0.dbKey == n.key }) } ?? false
        guard !contains else {
            fatalError("Element with such key already exists")
        }

        storage.localElements.insert(element, at: index ?? storage.localElements.count)
    }

    @discardableResult
    func _write(_ element: Element, at index: Int? = nil, in transaction: RealtimeTransaction? = nil) throws -> RealtimeTransaction {
        guard !contains(element) else { throw RealtimeError(source: .collection, description: "Element already contains. Element: \(element)") }

        let transaction = transaction ?? RealtimeTransaction()
        try _write(element, at: index ?? count, by: node!, in: transaction)
        transaction.addCompletion { [weak self] (result) in
            if result {
                self?.didSave()
            }
        }
        return transaction
    }

    func _write(_ element: Element, at index: Int,
                by location: Node, in transaction: RealtimeTransaction) throws {
        let itemNode = location.child(with: element.dbKey)
        let link = element.node!.generate(linkTo: itemNode)
        let item = RCItem(element: element, linkID: link.link.id, index: index)

        var reversion: () -> Void {
            let sourceRevers = _view.source.hasChanges ?
                nil : _view.source.currentReversion()

            return { [weak self] in
                sourceRevers?()
                self?.storage.elements.removeValue(forKey: item.dbKey)
            }
        }
        transaction.addReversion(reversion)
        _view.insert(item, at: item.index)
        storage.store(value: element, by: item)
        transaction.addValue(item.fireValue, by: itemNode)
        transaction.addValue(link.link.fireValue, by: link.node)
    }

    @discardableResult
    func remove(element: Element, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction? {
        guard isRooted else { fatalError("This method is available only for rooted objects") }

        let transaction = transaction ?? RealtimeTransaction()
        guard isPrepared else {
            transaction.addPrecondition { [unowned transaction] promise in
                self.prepare(forUse: .just { collection, err in
                    collection._remove(element, in: transaction)
                    promise.fulfill(err)
                })
            }
            return transaction
        }

        _remove(element, in: transaction)
        return transaction
    }

    @discardableResult
    func remove(at index: Int, in transaction: RealtimeTransaction? = nil) -> RealtimeTransaction {
        guard isRooted else { fatalError("This method is available only for rooted objects") }

        let transaction = transaction ?? RealtimeTransaction()
        guard isPrepared else {
            transaction.addPrecondition { [unowned transaction] promise in
                self.prepare(forUse: .just { collection, err in
                    collection._remove(at: index, in: transaction)
                    promise.fulfill(err)
                })
            }
            return transaction
        }

        _remove(at: index, in: transaction)
        return transaction
    }

    private func _remove(_ element: Element, in transaction: RealtimeTransaction) {
        if let index = _view.index(where: { $0.dbKey == element.dbKey }) {
            _remove(at: index, in: transaction)
        } else {
            debugFatalError("Tries to remove not existed value")
        }
    }

    private func _remove(at index: Int, in transaction: RealtimeTransaction) {
        if !_view.source.hasChanges {
            transaction.addReversion(_view.source.currentReversion())
        }
        let item = _view.remove(at: index)
        let element = storage.elements.removeValue(forKey: item.dbKey)
        transaction.addReversion { [weak self] in
            self?.storage.elements[item.dbKey] = element
        }
        transaction.removeValue(by: _view.source.node!.child(with: item.dbKey))
        let elementLinksNode = storage.sourceNode.linksNode.child(
            with: item.dbKey.subpath(with: item.linkID)
        )
        transaction.removeValue(by: elementLinksNode)
        transaction.addCompletion { [weak self] (result) in
            if result {
                self?.didSave()
            }
        }
    }
}

