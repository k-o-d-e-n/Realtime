//
//  view.collection.realtime.swift
//  GoogleToolboxForMac
//
//  Created by Denis Koryttsev on 21/11/2018.
//

import Foundation

public struct RCItem: WritableRealtimeValue, Comparable {
    public var raw: RealtimeDatabaseValue?
    public var payload: RealtimeDatabaseValue?
    public let node: Node?
    var priority: Int64?
    var linkID: String?

    init(key: String?, value: RealtimeValue) {
        self.raw = value.raw
        self.payload = value.payload
        self.node = Node(key: key ?? value.dbKey)
    }

    public init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        guard let key = data.key else {
            throw RealtimeError(initialization: RCItem.self, data)
        }

        let valueData = InternalKeys.value.child(from: data)
        let dataContainer = try data.container(keyedBy: InternalKeys.self)
        self.node = Node(key: key)
        self.raw = try valueData.rawValue()
        self.linkID = try dataContainer.decodeIfPresent(String.self, forKey: .link)
        self.priority = try dataContainer.decodeIfPresent(Int64.self, forKey: .index)
        self.payload = try valueData.payload()
    }

    public func write(to transaction: Transaction, by node: Node) throws {
        transaction.addValue(try defaultRepresentation(), by: node)
    }

    private func defaultRepresentation() throws -> RealtimeDatabaseValue {
        var representation: [RealtimeDatabaseValue] = []
        if let l = linkID {
            representation.append(RealtimeDatabaseValue((RealtimeDatabaseValue(InternalKeys.link.rawValue), RealtimeDatabaseValue(l))))
        }
        if let p = priority {
            representation.append(RealtimeDatabaseValue((RealtimeDatabaseValue(InternalKeys.index.rawValue), RealtimeDatabaseValue(p))))
        }
        var value: [RealtimeDatabaseValue] = []
        if let p = self.payload {
            value.append(RealtimeDatabaseValue((RealtimeDatabaseValue(InternalKeys.payload.rawValue), RealtimeDatabaseValue(p))))
        }
        if let raw = self.raw {
            value.append(RealtimeDatabaseValue((RealtimeDatabaseValue(InternalKeys.raw.rawValue), RealtimeDatabaseValue(raw))))
        }
        representation.append(RealtimeDatabaseValue((RealtimeDatabaseValue(InternalKeys.value.rawValue), RealtimeDatabaseValue(value))))

        return RealtimeDatabaseValue(representation)
    }

    public var hashValue: Int { return dbKey.hashValue }
    public static func ==(lhs: RCItem, rhs: RCItem) -> Bool {
        return lhs.dbKey == rhs.dbKey
    }
    public static func < (lhs: RCItem, rhs: RCItem) -> Bool {
        if (lhs.priority ?? 0) < (rhs.priority ?? 0) {
            return true
        } else if (lhs.priority ?? 0) > (rhs.priority ?? 0) {
            return false
        } else {
            return lhs.dbKey < rhs.dbKey
        }
    }
}

public struct RDItem: WritableRealtimeValue, Comparable {
    public var raw: RealtimeDatabaseValue?
    public var payload: RealtimeDatabaseValue?
    public var node: Node? { return rcItem.node }
    var rcItem: RCItem

    public var dbKey: String! { return rcItem.dbKey }
    var priority: Int64? {
        set { rcItem.priority = newValue }
        get { return rcItem.priority }
    }
    var linkID: String? {
        set { rcItem.linkID = newValue }
        get { return rcItem.linkID }
    }

    init(key: RealtimeValue, value: RealtimeValue) {
        self.rcItem = RCItem(key: key.dbKey, value: value)
        self.raw = key.raw
        self.payload = key.payload
    }

    public init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        self.rcItem = try RCItem(data: data, event: event)
        let keyData = InternalKeys.key.child(from: data)
        self.raw = try keyData.rawValue()
        self.payload = try keyData.payload()
    }

    public func write(to transaction: Transaction, by node: Node) throws {
        transaction.addValue(try defaultRepresentation(), by: node)
    }

    private func defaultRepresentation() throws -> RealtimeDatabaseValue {
        var representation: [RealtimeDatabaseValue] = []

        if let l = rcItem.linkID {
            representation.append(RealtimeDatabaseValue((RealtimeDatabaseValue(InternalKeys.link.rawValue), RealtimeDatabaseValue(l))))
        }
        if let p = rcItem.priority {
            representation.append(RealtimeDatabaseValue((RealtimeDatabaseValue(InternalKeys.index.rawValue), RealtimeDatabaseValue(p))))
        }
        var value: [RealtimeDatabaseValue] = []
        if let p = rcItem.payload {
            value.append(RealtimeDatabaseValue((RealtimeDatabaseValue(InternalKeys.payload.rawValue), RealtimeDatabaseValue(p))))
        }
        if let raw = rcItem.raw {
            value.append(RealtimeDatabaseValue((RealtimeDatabaseValue(InternalKeys.raw.rawValue), RealtimeDatabaseValue(raw))))
        }
        representation.append(RealtimeDatabaseValue((RealtimeDatabaseValue(InternalKeys.value.rawValue), RealtimeDatabaseValue(value))))

        var key: [RealtimeDatabaseValue] = []
        if let p = self.payload {
            key.append(RealtimeDatabaseValue((RealtimeDatabaseValue(InternalKeys.payload.rawValue), RealtimeDatabaseValue(p))))
        }
        if let raw = self.raw {
            key.append(RealtimeDatabaseValue((RealtimeDatabaseValue(InternalKeys.raw.rawValue), RealtimeDatabaseValue(raw))))
        }
        representation.append(RealtimeDatabaseValue((RealtimeDatabaseValue(InternalKeys.key.rawValue), RealtimeDatabaseValue(key))))

        return RealtimeDatabaseValue(representation)
    }

    public var hashValue: Int { return dbKey.hashValue }
    public static func ==(lhs: RDItem, rhs: RDItem) -> Bool {
        return lhs.dbKey == rhs.dbKey
    }
    public static func < (lhs: RDItem, rhs: RDItem) -> Bool {
        if (lhs.priority ?? 0) < (rhs.priority ?? 0) {
            return true
        } else if (lhs.priority ?? 0) > (rhs.priority ?? 0) {
            return false
        } else {
            return lhs.dbKey < rhs.dbKey
        }
    }
}

public struct AnyRealtimeCollectionView: RealtimeCollectionView {
    var _value: RealtimeCollectionActions
    let _contains: (String, @escaping (Bool, Error?) -> Void) -> Void
    let _view: AnyBidirectionalCollection<String>

    var isSynced: Bool = false

    init<CV: RealtimeCollectionView>(_ view: CV) where CV.Element: DatabaseKeyRepresentable {
        self._value = view
        self._contains = view.contains(elementWith:completion:)
        self._view = AnyBidirectionalCollection(view.lazy.map({ $0.dbKey }))
    }

    public func contains(elementWith key: String, completion: @escaping (Bool, Error?) -> Void) {
        _contains(key, completion)
    }

    public func load(timeout: DispatchTimeInterval) -> RealtimeTask {
        return _value.load(timeout: timeout)
    }

    public var canObserve: Bool { return _value.canObserve }
    public var keepSynced: Bool {
        set { _value.keepSynced = newValue }
        get { return _value.keepSynced }
    }
    public var isObserved: Bool { return _value.isObserved }
    public func runObserving() -> Bool { return _value.runObserving() }
    public func stopObserving() { _value.stopObserving() }

    public var startIndex: AnyIndex { return _view.startIndex }
    public var endIndex: AnyIndex { return _view.endIndex }
    public func index(after i: AnyIndex) -> AnyIndex { return _view.index(after: i) }
    public func index(before i: AnyIndex) -> AnyIndex { return _view.index(before: i) }
    public subscript(position: AnyIndex) -> String { return _view[position] }
}

extension SortedArray: RealtimeDataRepresented where Element: RealtimeDataRepresented & Comparable {
    public init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        self.init(try data.map(Element.init))
    }
    public init(data: RealtimeDataProtocol, event: DatabaseDataEvent, sorting: @escaping SortedArray<Element>.Comparator<Element>) throws {
        self.init(unsorted: try data.map(Element.init), areInIncreasingOrder: sorting)
    }
}

enum ViewDataExplorer {
    case value(ascending: Bool)
    case page(PagingController)
}

public final class SortedCollectionView<Element: WritableRealtimeValue & Comparable>: _RealtimeValue, RealtimeCollectionView {
    typealias Source = SortedArray<Element>
    private var _elements: Source = Source()
    private var dataExplorer: ViewDataExplorer = .value(ascending: false) // TODO: default value may mismatch with default value of collection
    var isSynced: Bool = false
    override var _hasChanges: Bool { return isStandalone && _elements.count > 0 }
    public override var isObserved: Bool {
        switch dataExplorer {
        case .value: return super.isObserved
        case .page(let controller): return controller.isStarted
        }
    }
    let changes: Repeater = Repeater<(data: RealtimeDataProtocol, event: RCEvent)>.unsafe()

    var elements: Source {
        set { _elements = newValue }
        get { return _elements }
    }

    public var keepSynced: Bool = false {
        didSet {
            guard oldValue != keepSynced else { return }
            if keepSynced { runObserving() }
            else { stopObserving() }
        }
    }

    public required convenience init(data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        self.init(node: data.node, options: RealtimeValueOptions(database: data.database, raw: nil, payload: nil))
        try apply(data, event: event)
    }

    @discardableResult
    public func runObserving() -> Bool {
        switch dataExplorer {
        case .value:
            let isNeedLoadFull = !isObserved
            let added = _runObserving(.child(.added))
            let removed = _runObserving(.child(.removed))
            let changed = _runObserving(.child(.changed))
            if isNeedLoadFull {
                if isRooted {
                    _ = load()
                } else {
                    isSynced = true
                }
            }
            return added && removed && changed
        case .page(let controller):
            if !controller.isStarted {
                controller.start()
            }
            return true
        }
    }

    public func stopObserving() {
        switch dataExplorer {
        case .value:
            // checks 'added' only, can lead to error
            guard !keepSynced || (observing[.child(.added)].map({ $0.counter > 1 }) ?? true) else {
                return
            }

            _stopObserving(.child(.added))
            _stopObserving(.child(.removed))
            _stopObserving(.child(.changed))
            if !isObserved {
                isSynced = false
            }
        case .page(let controller):
            if controller.isStarted {
                controller.stop()
                isSynced = false
            }
        }
    }

    override func _write(to transaction: Transaction, by node: Node) throws {
        /// skip the call of super
        let view = _elements
        transaction.addReversion { [weak self] in
            self?._elements = view
        }
        _elements.removeAll()
        for item in view {
            let itemNode = node.child(with: item.node?.key ?? RealtimeApp.app.database.generateAutoID())
            try item.write(to: transaction, by: itemNode)
        }
    }

    public override func apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws {
        let event = try _apply(data, event: event)
        switch dataExplorer {
        case .value:
            if isSynced {
                changes.send(.value(event))
            }
        case .page:
            changes.send(.value(event))
        }
    }

    override func _dataApplyingDidThrow(_ error: Error) {
        super._dataApplyingDidThrow(error)
        changes.send(.error(error))
    }

    override func _dataObserverDidCancel(_ error: Error) {
        super._dataObserverDidCancel(error)
        changes.send(.error(error))
    }

    func _apply(_ data: RealtimeDataProtocol, event: DatabaseDataEvent) throws -> (data: RealtimeDataProtocol, event: RCEvent) {
        switch event {
        case .value:
            switch dataExplorer {
            case .value(let ascending):
                self._elements = try SortedArray(data: data, event: event, sorting: ascending ? (<) : (>))
            case .page(let c):
                self._elements = try SortedArray(data: data, event: event, sorting: c.ascending ? (<) : (>))
            }

            self.isSynced = self.isObserved
            return (data, .initial)
        case .child(.added):
            let indexes: [Int]
            if data.key == self.node?.key {
                let elements = try data.map(Element.init)
                self._elements.insert(contentsOf: elements)
                indexes = elements.compactMap(self._elements.index(of:))
            } else {
                let item = try Element(data: data)
                indexes = [self._elements.insert(item)]
                debugFatalError(condition: indexes.isEmpty, "Did update collection, but couldn`t recognized indexes. Data: \(data), event: \(event)")
            }
            return (data, .updated(deleted: [], inserted: indexes, modified: [], moved: []))
        case .child(.removed):
            if data.key == self.node?.key {
                let indexes: [Int] = try data.map(Element.init).compactMap({ self._elements.remove($0)?.index })
                if indexes.count == data.childrenCount {
                    return (data, .updated(deleted: indexes, inserted: [], modified: [], moved: []))
                } else {
                    debugFatalError("Indexes: \(indexes), data: \(data)")
                    throw RealtimeError(source: .coding, description: "Element has been removed in remote collection, but couldn`t find in local storage.")
                }
            } else {
                let item = try Element(data: data)
                let indexes: [Int] = self._elements.remove(item).map({ [$0.index] }) ?? []
                debugFatalError(condition: indexes.isEmpty, "Did update collection, but couldn`t recognized indexes. Data: \(data), event: \(event)")
                return (data, .updated(deleted: indexes, inserted: [], modified: [], moved: []))
            }
        case .child(.changed):
            let item = try Element(data: data)
            if let indexes = self._elements.move(item) {
                if indexes.from != indexes.to {
                    return (data, .updated(deleted: [], inserted: [], modified: [], moved: [indexes]))
                } else {
                    return (data, .updated(deleted: [], inserted: [], modified: [indexes.to], moved: []))
                }
            } else {
                throw RealtimeError(source: .collection, description: "Cannot move items")
            }
        default:
            throw RealtimeError(source: .collection, description: "Unexpected data: \(data) for event: \(event)")
        }
    }

    public func contains(elementWith key: String, completion: @escaping (Bool, Error?) -> Void) {
        _contains(with: key, completion: completion)
    }

    public var startIndex: Int { return _elements.startIndex }
    public var endIndex: Int { return _elements.endIndex }
    public func index(after i: Int) -> Int { return _elements.index(after: i) }
    public func index(before i: Int) -> Int { return _elements.index(before: i) }
    public subscript(position: Int) -> Element { return _elements[position] }

    func didChange(dataExplorer: RCDataExplorer) {
        switch (dataExplorer, self.dataExplorer) {
        case (.view(let ascending), .page(let controller)):
            self.dataExplorer = .value(ascending: ascending)
            if controller.isStarted {
                controller.stop()
                runObserving()
            }
        case (.viewByPages(let control, let size, let ascending), .value):
            _setPageController(with: control, pageSize: size, ascending: ascending)
        case (.viewByPages(let control, let size, let ascending), .page(let oldController)):
            guard oldController.isStarted else {
                return _setPageController(with: control, pageSize: size, ascending: ascending)
            }
            guard control === oldController, ascending == oldController.ascending else {
                fatalError("In observing state available to change page size only")
            }
            oldController.pageSize = size
        case (.view(let collectionAscending), .value(let viewAscending)):
            if collectionAscending != viewAscending {
                self.dataExplorer = .value(ascending: collectionAscending)
                self._elements = SortedArray.init(unsorted: _elements, areInIncreasingOrder: collectionAscending ? (<) : (>))
            }
        }
    }

    private func _setPageController(with control: PagingControl, pageSize: UInt, ascending: Bool) {
        guard let database = self.database, let node = self.node else { return }
        let controller = PagingController(
            database: database,
            node: node,
            pageSize: pageSize,
            ascending: ascending,
            delegate: self
        )
        control.controller = controller
        self.dataExplorer = .page(controller)
        if super.isObserved {
            _invalidateObserving()
            controller.start()
        }
    }

    @discardableResult
    func insert(_ element: Element) -> Int {
        return _elements.insert(element)
    }

    @discardableResult
    func remove(at index: Int) -> Element {
        return _elements.remove(at: index)
    }

    @discardableResult
    func remove(_ element: Element) -> Int? {
        return _elements.remove(element)?.index
    }

    func removeAll() {
        _elements.removeAll()
    }

//    func load(_ completion: Assign<(Error?)>) {
//        guard !isSynced else { completion.assign(nil); return }
//
//        super.load(completion: completion)
//    }

    func _contains(with key: String, completion: @escaping (Bool, Error?) -> Void) {
        guard let db = database, let node = self.node else {
            fatalError("Unexpected behavior")
        }
        db.load(
            for: node.child(with: key),
            timeout: .seconds(10),
            completion: { (data) in
                completion(data.exists(), nil)
        },
            onCancel: { completion(false, $0) }
        )
    }

    func _item(for key: String, completion: @escaping (Source.Element?, Error?) -> Void) {
        guard let db = database, let node = self.node else {
            fatalError("Unexpected behavior")
        }
        db.load(
            for: node.child(with: key),
            timeout: .seconds(10),
            completion: { (data) in
                if data.exists() {
                    do {
                        completion(try Element(data: data), nil)
                    } catch let e {
                        completion(nil, e)
                    }
                } else {
                    completion(nil, nil)
                }
        },
            onCancel: { completion(nil, $0) }
        )
    }
}
extension SortedCollectionView: PagingControllerDelegate {
    func firstKey() -> String? {
        return first?.dbKey
    }

    func lastKey() -> String? {
        return last?.dbKey
    }

    func pagingControllerDidReceive(data: RealtimeDataProtocol, with event: DatabaseDataEvent) {
        do {
            try self.apply(data, event: event)
        } catch let e {
            _dataApplyingDidThrow(e)
        }
    }

    func pagingControllerDidCancel(with error: Error) {
        _dataObserverDidCancel(error)
    }
}
