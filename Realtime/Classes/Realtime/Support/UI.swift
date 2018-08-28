//
//  UIKit.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 29/09/2017.
//  Copyright © 2017 Denis Koryttsev. All rights reserved.
//

import UIKit

// MARK: UITableView - Adapter

internal class _TableViewSectionedAdapter: NSObject, UITableViewDataSource, UITableViewDelegate, UITableViewDataSourcePrefetching {
    internal func numberOfSections(in tableView: UITableView) -> Int {
        fatalError("Need override this method")
    }

    internal func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        fatalError("Need override this method")
    }

    internal func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        fatalError("Need override this method")
    }

    // MARK: UITableViewDelegate

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { return 0.0 }
    @available(iOS 2.0, *)
    internal func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {}

    @available(iOS 6.0, *)
    internal func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {}
    internal func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {}

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {}
    func tableView(_ tableView: UITableView, didEndDisplayingHeaderView view: UIView, forSection section: Int) {}
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? { return nil }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { return nil }
    func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int { return index }
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { return 0.0 }
    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {}
    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle { return .delete }
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {}
//    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {}
}

struct TypeKey: Hashable {
    fileprivate let type: AnyClass

    var hashValue: Int {
        return ObjectIdentifier(type).hashValue
    }

    static func ==(lhs: TypeKey, rhs: TypeKey) -> Bool {
        return lhs.type === rhs.type
    }

    static func `for`<T: AnyObject>(_ type: T.Type) -> TypeKey {
        return TypeKey(type: type)
    }
}
extension UITableViewCell {
    // convenience static computed property to get the wrapped metatype value.
    static var typeKey: TypeKey {
        return TypeKey.for(self)
    }
    var typeKey: TypeKey {
        return type(of: self).typeKey
    }
}


extension SignedInteger {
    func toOther<SI: SignedInteger>() -> SI {
        return SI(self)
    }
}

/// Deprecated

@available(*, deprecated: 0.1.0)
extension Collection {
    func element(by offset: Int) -> Iterator.Element {
        return self[index(startIndex, offsetBy: offset)]
    }
}


@available(*, deprecated: 0.1.0)
public class ReuseViewPrototype<View: AnyObject> {
    fileprivate let weakView: ValueStorage<View?> = ValueStorage.unsafe(weak: nil)
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

@available(*, deprecated: 0.1.0, message: "Use RealtimeTableViewDelegate instead")
public final class RealtimeTableAdapter<RC: RealtimeCollection>: _RealtimeTableAdapter<RCBasedDataSource<RC>> {
    public convenience init(tableView: UITableView, collection: RC) {
        self.init(tableView: tableView, models: RCBasedDataSource(collection), onChanges: collection.listening)
    }
}
public extension RCBasedDataSource {
    func reloadData(completion: ((Error?) -> Void)? = nil) {
        collection.prepare(forUse: .just { err in completion?(err) })
    }
}

@available(*, deprecated: 0.1.0)
public protocol ModelDataSource {
    associatedtype Model
    func numberOfRowsInSection(_ section: Int) -> Int
    func model(by indexPath: IndexPath) -> Model
}
@available(*, deprecated: 0.1.0)
public struct RCBasedDataSource<RC: RealtimeCollection>: ModelDataSource {
    let collection: RC

    init(_ collection: RC) {
        self.collection = collection
    }

    public func numberOfRowsInSection(_ section: Int) -> Int {
        return collection.count
    }
    public func model(by indexPath: IndexPath) -> RC.Iterator.Element {
        return collection.element(by: indexPath.row.toOther())
    }
}

@available(*, deprecated: 0.1.0, message: "Use RealtimeTableViewDelegate instead")
public class _RealtimeTableAdapter<Models: ModelDataSource> {
    public typealias CellFactory<Cell: UITableViewCell> = (ReuseViewPrototype<Cell>, Models.Model) -> [ListeningItem]
    weak var tableView: UITableView!
    private var _freePrototypes: [ReuseViewPrototype<UITableViewCell>] = []
    private var _prototypeCache = Dictionary<IndexPath, ReuseViewPrototype<UITableViewCell>>()
    private var _cellProtos: [TypeKey: CellFactory<UITableViewCell>] = [:]
    private var _isNeedReload: Bool = false
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
            proto.disposeStore.resume()
        }

        override func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            guard let proto = parent._prototypeCache.removeValue(forKey: indexPath) else { return }

            proto.disposeStore.dispose()
            proto.view = nil
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

// MARK: Views

@available(*, deprecated: 0.3.0)
open class RealtimeTableView<RC: RealtimeCollection>: UITableView where RC.Index == Int {
    public var adapter: RealtimeTableAdapter<RC>!

    required public init(collection: RC, configuration: ((RealtimeTableAdapter<RC>) -> Void)? = nil) {
        super.init(frame: .zero, style: .plain)
        self.adapter = RealtimeTableAdapter(tableView: self, collection: collection)
        configuration?(self.adapter)
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override open func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }

        adapter.reloadTable()
    }
}
