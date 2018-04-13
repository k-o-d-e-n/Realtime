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

public class ReuseViewPrototype<View: AnyObject> {
    fileprivate let weakView = WeakPropertyValue<View>(nil)
    weak var view: View? {
        set { weakView.set(newValue) }
        get { return weakView.get() }
    }
    var disposeStore = ListeningDisposeStore()

    deinit {
        disposeStore.dispose()
    }

    public func assign<Data>(with binder: @escaping (View, Data) -> Void) -> (Data) -> Void {
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

public final class RealtimeTableAdapter<RC: RealtimeCollection>: _RealtimeTableAdapter<RCBasedDataSource<RC>> {
    public convenience init(tableView: UITableView, collection: RC) {
        self.init(tableView: tableView, models: RCBasedDataSource(collection), onChanges: { collection.listening(changes: $0) })
    }
}
public extension RCBasedDataSource {
    func reloadData(completion: ((Error?) -> Void)? = nil) {
        collection.prepare(forUse: { err in completion?(err) })
    }
}

extension Collection {
    func element(by offset: Int) -> Iterator.Element {
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

public protocol ModelDataSource {
    associatedtype Model
    func numberOfRowsInSection(_ section: Int) -> Int
    func model(by indexPath: IndexPath) -> Model
}
public struct RCBasedDataSource<RC: RealtimeCollection>: ModelDataSource {
    let collection: RC

    init(_ collection: RC) {
        self.collection = collection
    }

    public func numberOfRowsInSection(_ section: Int) -> Int {
        return collection.count.toOther()
    }
    public func model(by indexPath: IndexPath) -> RC.Iterator.Element {
        return collection.element(by: indexPath.row.toOther())
    }
}

// TODO: Add registration section model
// TODO: Overhead with recompilation listenings; DECISION: Save listening items by indexPath
public class _RealtimeTableAdapter<Models: ModelDataSource> {
    public typealias CellFactory<Cell: UITableViewCell> = (ReuseViewPrototype<Cell>, Models.Model) -> [ListeningItem]
    weak var tableView: UITableView!
    private var _freePrototypes: [ReuseViewPrototype<UITableViewCell>] = []
    private var _prototypeCache = Dictionary<IndexPath, ReuseViewPrototype<UITableViewCell>>()
    private var _cellProtos: [TypeKey<UITableViewCell>: CellFactory<UITableViewCell>] = [:]
    private var _isNeedReload: Bool = false // TODO: Not reset, need reset after reload
    private var _listening: Disposable!

    public var cellForIndexPath: ((IndexPath) -> UITableViewCell.Type)!
    public var didSelect: ((Models.Model) -> Void)?
    public let models: Models
    lazy var ddsAdapter: DDSAdapter = DDSAdapter(self)

    public required init(tableView: UITableView, models: Models, onChanges: (@escaping () -> Void) -> ListeningItem) {
        self.tableView = tableView
        self.models = models
        tableView.delegate = ddsAdapter
        tableView.dataSource = ddsAdapter
        self._listening = onChanges({ [weak self] in
            guard let owner = self else { return }
            owner.reloadTable()
        })
    }

    deinit {
//        print("Table adapter deinit")
        _listening.dispose()
    }

    public func register<Cell: UITableViewCell>(_ cell: Cell.Type, builder: @escaping CellFactory<Cell>) {
        _cellProtos[cell.typeKey] = unsafeBitCast(builder, to: CellFactory<UITableViewCell>.self)
        tableView.register(cell, forCellReuseIdentifier: NSStringFromClass(cell))
    }

    class DDSAdapter: _TableViewSectionedAdapter {
        weak var parent: _RealtimeTableAdapter<Models>!
        init(_ parent: _RealtimeTableAdapter<Models>) {
            self.parent = parent
        }

        override func numberOfSections(in tableView: UITableView) -> Int {
            return 1
        }
        override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            return parent.models.numberOfRowsInSection(section)
        }
        override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let key = parent.cellForIndexPath(indexPath).typeKey
            let cell = tableView.dequeueReusableCell(withIdentifier: NSStringFromClass(key.type), for: indexPath)
            guard let proto = parent._prototypeCache[indexPath] else {
                let proto = parent._freePrototypes.popLast() ?? ReuseViewPrototype<UITableViewCell>()
                parent._prototypeCache[indexPath] = proto
                parent._cellProtos[key]!(proto, parent.models.model(by: indexPath)).forEach { $0.add(to: &proto.disposeStore) }
                return cell
            }
            if parent._isNeedReload {
                proto.disposeStore.dispose()
                parent._cellProtos[key]!(proto, parent.models.model(by: indexPath)).forEach { $0.add(to: &proto.disposeStore) }
            }
            return cell
        }

        override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            guard let proto = parent._prototypeCache[indexPath] else { return }

            proto.view = cell
            proto.disposeStore.resume(true)
        }

        override func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            guard let proto = parent._prototypeCache[indexPath] else { return }

            proto.disposeStore.dispose()
            proto.view = nil
            parent._prototypeCache[indexPath] = nil
            parent._freePrototypes.append(proto)
        }

        override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            parent.didSelect?(parent.models.model(by: indexPath))
        }
    }

    public func setNeedsReload() {
        _isNeedReload = true
    }
    public func reloadTable() {
        _isNeedReload = true
        tableView.reloadData()
    }
}
