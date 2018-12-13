//
//  view.collection.realtime.swift
//  GoogleToolboxForMac
//
//  Created by Denis Koryttsev on 21/11/2018.
//

import Foundation

public struct RCItem: RCViewItem {
    public let dbKey: String!
    var priority: Int
    var linkID: String?
    public let valuePayload: RealtimeValuePayload

    public typealias Element = (key: String, payload: RealtimeValuePayload)
    public init(_ element: Element) {
        self.dbKey = element.key
        self.priority = 0
        self.linkID = nil
        self.valuePayload = element.payload
    }

    init<T: RealtimeValue>(element: T, key: String, priority: Int, linkID: String?) {
        self.dbKey = key
        self.priority = priority
        self.linkID = linkID
        self.valuePayload = RealtimeValuePayload((element.version, element.raw), element.payload)
    }

    init<T: RealtimeValue>(element: T, priority: Int, linkID: String?) {
        self.dbKey = element.dbKey
        self.priority = priority
        self.linkID = linkID
        self.valuePayload = RealtimeValuePayload((element.version, element.raw), element.payload)
    }

    public init(data: RealtimeDataProtocol, exactly: Bool) throws {
        guard let key = data.key else {
            throw RealtimeError(initialization: RCItem.self, data)
        }
        guard let index: Int = try InternalKeys.index.map(from: data) else {
            throw RealtimeError(initialization: RCItem.self, data)
        }

        self.dbKey = key
        self.priority = index
        self.linkID = try InternalKeys.link.map(from: data)
        let valueData = InternalKeys.value.child(from: data)
        self.valuePayload = RealtimeValuePayload(
            try (InternalKeys.modelVersion.map(from: valueData), InternalKeys.raw.map(from: valueData)),
            try InternalKeys.payload.map(from: valueData)
        )
    }

    public func defaultRepresentation() throws -> Any {
        var value: [String: RealtimeDataValue] = [:]
        value[InternalKeys.value.rawValue] = databaseValue(of: valuePayload)
        value[InternalKeys.link.rawValue] = linkID
        value[InternalKeys.index.rawValue] = priority

        return value
    }

    public var hashValue: Int { return dbKey.hashValue }

    public static func ==(lhs: RCItem, rhs: RCItem) -> Bool {
        return lhs.dbKey == rhs.dbKey
    }

    public static func < (lhs: RCItem, rhs: RCItem) -> Bool {
        if lhs.priority < rhs.priority {
            return true
        } else if lhs.priority > rhs.priority {
            return false
        } else {
            return lhs.dbKey < rhs.dbKey
        }
    }
}

public struct RDItem: RCViewItem {
    var rcItem: RCItem
    public let valuePayload: RealtimeValuePayload

    public var dbKey: String! { return rcItem.dbKey }
    var priority: Int { return rcItem.priority }
    var linkID: String? {
        set { rcItem.linkID = newValue }
        get { return rcItem.linkID }
    }

    public typealias Element = (key: String, keyPayload: RealtimeValuePayload, valuePayload: RealtimeValuePayload)
    public init(_ element: Element) {
        self.rcItem = RCItem((key: element.key, element.valuePayload))
        self.valuePayload = element.keyPayload
    }

    init<V: RealtimeValue, K: RealtimeValue>(value: V, key: K, priority: Int, linkID: String?) {
        self.rcItem = RCItem(element: value, key: key.dbKey, priority: priority, linkID: linkID)
        self.valuePayload = RealtimeValuePayload((key.version, key.raw), key.payload)
    }

    public init(data: RealtimeDataProtocol, exactly: Bool) throws {
        self.rcItem = try RCItem(data: data, exactly: exactly)
        let keyData = InternalKeys.key.child(from: data)
        self.valuePayload = RealtimeValuePayload(
            try (InternalKeys.modelVersion.map(from: keyData), InternalKeys.raw.map(from: keyData)),
            try InternalKeys.payload.map(from: keyData)
        )
    }

    public func defaultRepresentation() throws -> Any {
        var value: [String: RealtimeDataValue] = [:]
        value[InternalKeys.value.rawValue] = databaseValue(of: rcItem.valuePayload)
        value[InternalKeys.key.rawValue] = databaseValue(of: valuePayload)
        value[InternalKeys.link.rawValue] = rcItem.linkID
        value[InternalKeys.index.rawValue] = rcItem.priority

        return value
    }

    public var hashValue: Int { return dbKey.hashValue }

    public static func ==(lhs: RDItem, rhs: RDItem) -> Bool {
        return lhs.dbKey == rhs.dbKey
    }

    public static func < (lhs: RDItem, rhs: RDItem) -> Bool {
        if lhs.priority < rhs.priority {
            return true
        } else if lhs.priority > rhs.priority {
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

    internal(set) var isSynced: Bool = false

    init<CV: RealtimeCollectionView>(_ view: CV) where CV.Element: DatabaseKeyRepresentable {
        self._value = view
        self._contains = view.contains(elementWith:completion:)
        self._view = AnyBidirectionalCollection(view.lazy.map({ $0.dbKey }))
    }

    public func contains(elementWith key: String, completion: @escaping (Bool, Error?) -> Void) {
        _contains(key, completion)
    }

    public func load(timeout: DispatchTimeInterval, completion: Closure<Error?, Void>?) {
        _value.load(timeout: timeout, completion: completion)
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

public final class SortedCollectionView<Element: RCViewElementProtocol & Comparable>: _RealtimeValue, RealtimeCollectionView {
    typealias Source = SortedArray<Element>
    private var _elements: Source = Source()
    internal(set) var isSynced: Bool = false

    override var _hasChanges: Bool { return isStandalone && _elements.count > 0 }

    var elements: Source {
        set { _elements = newValue }
        get { return _elements }
    }

    var changes: AnyListenable<RCEvent> {
        return dataObserver
            .filter({ [unowned self] e in
                self.isSynced || e.1 == .value                
            })
            .map { [unowned self] (value) -> RCEvent in
                switch value.1 {
                case .value:
                    return .initial
                case .child(.added):
                    let item = try Element(data: value.0)
                    let index: Int = self._elements.insert(item)
                    return .updated((deleted: [], inserted: [index], modified: [], moved: []))
                case .child(.removed):
                    let item = try Element(data: value.0)
                    if let index = self._elements.remove(item)?.index {
                        return .updated((deleted: [index], inserted: [], modified: [], moved: []))
                    } else {
                        throw RealtimeError(source: .coding, description: "Element has been removed in remote collection, but couldn`t find in local storage.")
                    }
                case .child(.changed):
                    let item = try Element(data: value.0)
                    if let indexes = self._elements.move(item) {
                        if indexes.from != indexes.to {
                            return .updated((deleted: [], inserted: [], modified: [], moved: [indexes]))
                        } else {
                            return .updated((deleted: [], inserted: [], modified: [indexes.to], moved: []))
                        }
                    } else {
                        throw RealtimeError(source: .collection, description: "Cannot move items")
                    }
                default:
                    throw RealtimeError(source: .collection, description: "Unexpected data event: \(value)")
                }
            }
            .asAny()
    }

    public var keepSynced: Bool = false {
        didSet {
            guard oldValue != keepSynced else { return }
            if keepSynced { runObserving() }
            else { stopObserving() }
        }
    }

    public required init(in node: Node?, options: [ValueOption: Any]) {
        super.init(in: node, options: options)
    }

    public required convenience init(data: RealtimeDataProtocol, exactly: Bool) throws {
        self.init(in: data.node, options: [.database: data.database as Any, .storage: data.storage as Any])
        try apply(data, exactly: exactly)
    }

    @discardableResult
    public func runObserving() -> Bool {
        let isNeedLoadFull = !isObserved
        let added = _runObserving(.child(.added))
        let removed = _runObserving(.child(.removed))
        let changed = _runObserving(.child(.changed))
        if isNeedLoadFull {
            if isRooted {
                load(completion: .just { [weak self] e in
                    self.map { this in
                        this.isSynced = this.isObserved && e == nil
                    }
                })
            } else {
                isSynced = true
            }
        }
        return added && removed && changed
    }

    public func stopObserving() {
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
    }

    override func _write(to transaction: Transaction, by node: Node) throws {
        /// skip the call of super
        let view = _elements
        transaction.addReversion { [weak self] in
            self?._elements = view
        }
        _elements.removeAll()
        for item in view {
            let itemNode = node.child(with: item.dbKey)
            transaction.addValue(try item.defaultRepresentation(), by: itemNode)
        }
    }

    public override func apply(_ data: RealtimeDataProtocol, exactly: Bool) throws {
        /// partial data processing see in `changes`
        guard exactly else { return }
        let representer = Representer<SortedArray<Element>>(collection: Representer.realtimeData).defaultOnEmpty()
        self._elements = try representer.decode(data)
    }

    public func contains(elementWith key: String, completion: @escaping (Bool, Error?) -> Void) {
        _contains(with: key, completion: completion)
    }

    public var startIndex: Int { return _elements.startIndex }
    public var endIndex: Int { return _elements.endIndex }
    public func index(after i: Int) -> Int { return _elements.index(after: i) }
    public func index(before i: Int) -> Int { return _elements.index(before: i) }
    public subscript(position: Int) -> Element { return _elements[position] }

    @discardableResult
    func insert(_ element: Element) -> Int {
        return _elements.insert(element)
    }

    @discardableResult
    func remove(at index: Int) -> Element {
        return _elements.remove(at: index)
    }

    func removeAll() {
        _elements.removeAll()
    }

    func load(_ completion: Assign<(Error?)>) {
        guard !isSynced else { completion.assign(nil); return }

        super.load(completion: completion)
    }

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
