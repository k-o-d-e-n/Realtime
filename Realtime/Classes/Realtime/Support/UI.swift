//
//  UIKit.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 29/09/2017.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import UIKit

// MARK: UITableView - Adapter

open class _TableViewSectionedAdapter: NSObject, UITableViewDataSource, UITableViewDelegate {
    // MARK: UITableViewDataSource

    open func numberOfSections(in tableView: UITableView) -> Int {
        fatalError("Need override this method")
    }

    open func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        fatalError("Need override this method")
    }

    open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        fatalError("Need override this method")
    }

    // MARK: UITableViewDelegate

    @available(iOS 2.0, *)
    public func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {}

    @available(iOS 6.0, *)
    public func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {}

    open func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {}
}

class ReuseViewPrototype<View: AnyObject> {
    fileprivate let weakView = WeakPropertyValue<View>(nil)
    weak var view: View? {
        set { weakView.set(newValue) }
        get { return weakView.get() }
    }
    var disposeStore = ListeningDisposeStore()

    deinit {
        disposeStore.dispose()
    }

    func assign<Data>(with binder: @escaping (View, Data) -> Void) -> (Data) -> Void {
        return { data in
            guard let view = self.weakView.get() else { return }

            binder(view, data)
        }
    }
}
class ReuseViewReference {
    var indexPath = Property<IndexPath>(value: IndexPath())
    private(set) var listeningItem: ListeningItem! {
        willSet { listeningItem.stop() }
        didSet { listeningItem.start(true) }
    }

    init(data: @escaping (IndexPath) -> ListeningItem?) {
        _ = self.indexPath.insider.listen(.just { [unowned self] (path) in
            data(path).map { self.listeningItem = $0 }
        })
    }
}

class ReuseReference<View, Data> {
    var binder = Property<(view: View?, data: Data?)>(value: (nil, nil))

    private var token: Int
    init(_ assign: @escaping (View, Data?) -> Void) {
        self.token = self.binder.insider.listen(.just { view, data in
            view.map { assign($0, data) }
        }).token
    }
}

struct TypeKey<T>: Hashable {
    let type: T.Type

    var hashValue: Int {
        return ObjectIdentifier(type).hashValue
    }

    static func ==(lhs: TypeKey, rhs: TypeKey) -> Bool {
        return lhs.type == rhs.type
    }
}
extension UITableViewCell {
    // convenience static computed property to get the wrapped metatype value.
    static var typeKey: TypeKey<UITableViewCell> {
        return TypeKey(type: self)
    }
}

final class RealtimeTableAdapter<RC: RealtimeCollection>: _RealtimeTableAdapter<RCBasedDataSource<RC>> {
    convenience init(tableView: UITableView, collection: RC) {
        self.init(tableView: tableView, models: RCBasedDataSource(collection), onChanges: { collection.changesListening(completion: $0) })
    }
}
extension RCBasedDataSource {
    func reloadData(completion: ((Error?) -> Void)? = nil) {
        collection.prepare(forUse: { _, err in completion?(err) })
    }
}

extension Collection {
    func element(by offset: IndexDistance) -> Iterator.Element {
        return self[index(startIndex, offsetBy: offset)]
    }
}

extension Int64 {
    func toInt() -> Int {
        return Int(self)
    }
}
extension SignedInteger {
    func toOther<SI: SignedInteger>() -> SI {
        return SI(self)
    }
}

protocol ModelDataSource {
    associatedtype Model
    func numberOfRowsInSection(_ section: Int) -> Int
    func model(by indexPath: IndexPath) -> Model
}
struct RCBasedDataSource<RC: RealtimeCollection>: ModelDataSource {
    let collection: RC

    init(_ collection: RC) {
        self.collection = collection
    }

    func numberOfRowsInSection(_ section: Int) -> Int {
        return collection.count.toOther()
    }
    func model(by indexPath: IndexPath) -> RC.Iterator.Element {
        return collection.element(by: indexPath.row.toOther())
    }
}

// TODO: Add registration section model
// TODO: Overhead with recompilation listenings; DECISION: Save listening items by indexPath
class _RealtimeTableAdapter<Models: ModelDataSource>: _TableViewSectionedAdapter {
    typealias CellFactory<Cell: UITableViewCell> = (ReuseViewPrototype<Cell>, Models.Model) -> [ListeningItem]
    weak var tableView: UITableView!
    private var _freePrototypes: [ReuseViewPrototype<UITableViewCell>] = []
    private var _prototypeCache = Dictionary<IndexPath, ReuseViewPrototype<UITableViewCell>>()
    private var _cellProtos: [TypeKey<UITableViewCell>: CellFactory<UITableViewCell>] = [:]
    private var _isNeedReload: Bool = false // TODO: Not reset, need reset after reload
    private var _listening: Disposable!

    var cellForIndexPath: ((IndexPath) -> UITableViewCell.Type)!
    var didSelect: ((Models.Model) -> Void)?
    let models: Models

    required init(tableView: UITableView, models: Models, onChanges: (@escaping () -> Void) -> ListeningItem) {
        self.tableView = tableView
        self.models = models
        super.init()
        tableView.delegate = self
        tableView.dataSource = self
        self._listening = onChanges({ [weak self] in
            guard let owner = self else { return }
            owner.reloadTable()
        })
    }

    deinit {
//        print("Table adapter deinit")
        _listening.dispose()
    }

    func register<Cell: UITableViewCell>(_ cell: Cell.Type, builder: @escaping CellFactory<Cell>) {
        _cellProtos[cell.typeKey] = unsafeBitCast(builder, to: CellFactory<UITableViewCell>.self)
        tableView.register(cell, forCellReuseIdentifier: NSStringFromClass(cell))
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return models.numberOfRowsInSection(section)
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let key = cellForIndexPath(indexPath).typeKey
        let cell = tableView.dequeueReusableCell(withIdentifier: NSStringFromClass(key.type), for: indexPath)
        guard let proto = _prototypeCache[indexPath] else {
            let proto = _freePrototypes.popLast() ?? ReuseViewPrototype<UITableViewCell>()
            _prototypeCache[indexPath] = proto
            _cellProtos[key]!(proto, models.model(by: indexPath)).forEach { $0.add(to: &proto.disposeStore) }
            return cell
        }
        if _isNeedReload {
            proto.disposeStore.dispose()
            _cellProtos[key]!(proto, models.model(by: indexPath)).forEach { $0.add(to: &proto.disposeStore) }
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let proto = _prototypeCache[indexPath] else { return }

        proto.view = cell
        proto.disposeStore.resume(true)
    }

    override func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let proto = _prototypeCache[indexPath] else { return }

        proto.disposeStore.dispose()
        proto.view = nil
        _prototypeCache[indexPath] = nil
        _freePrototypes.append(proto)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        didSelect?(models.model(by: indexPath))
    }

    func setNeedsReload() {
        _isNeedReload = true
    }
    func reloadTable() {
        _isNeedReload = true
        tableView.reloadData()
    }
}
