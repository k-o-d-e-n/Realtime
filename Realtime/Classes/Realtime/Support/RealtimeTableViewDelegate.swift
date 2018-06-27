//
//  RealtimeTableViewDelegate.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 24/06/2018.
//  Copyright © 2018 Denis Koryttsev. All rights reserved.
//

import UIKit

public class ReuseItem<View: AnyObject> {
    public weak var view: View? {
        didSet {
            if let v = view, v !== oldValue {
                reload()
            }
        }
    }
    private var listeningItems: [ListeningItem] = []

    init() {}
    deinit { free() }

    public func bind<T: Listenable>(_ value: T, _ assign: @escaping (View, T.OutData) -> Void) {
        var data: T.OutData {
            set { view.map { v in assign(v, newValue) } }
            get { fatalError() }
        }
        listeningItems.append(value.listeningItem({ data = $0 }))
    }

    func free() {
        listeningItems.forEach { $0.dispose() }
        listeningItems.removeAll()
        view = nil
    }

    func reload() {
        listeningItems.forEach { $0.start() }
    }
}

public class ReuseController<View: AnyObject> {
    private var freeItems: [ReuseItem<View>] = []
    private var activeItems: [IndexPath: ReuseItem<View>] = [:]

    func dequeueItem(at indexPath: IndexPath) -> ReuseItem<View> {
        guard let item = activeItems[indexPath] else {
            let item = freeItems.popLast() ?? ReuseItem<View>()
            activeItems[indexPath] = item
            return item
        }
        return item
    }

    func free(at indexPath: IndexPath) {
        guard let item = activeItems.removeValue(forKey: indexPath)
            else { fatalError("Try free non-active reuse item") }
        item.free()
        freeItems.append(item)
    }

//    func exchange(indexPath: IndexPath, to ip: IndexPath) {
//        swap(&items[indexPath], &items[ip])
//    }
}

public final class RealtimeTableViewDelegate<Model: RealtimeValueActions>: NSObject {
    public typealias Binding<Cell: AnyObject> = (ReuseItem<Cell>, Model) -> Void
    public typealias ConfigureCell = (UITableView, IndexPath) -> UITableViewCell
    public private(set) var collection: AnyBidirectionalCollection<Model>
    fileprivate let reuseController: ReuseController<UITableViewCell> = ReuseController()
    fileprivate var registeredCells: [TypeKey<UITableViewCell>: Binding<UITableViewCell>] = [:]
    fileprivate var configureCell: ConfigureCell
    fileprivate lazy var delegateService: TableViewService = TableViewService(self)

    public weak var tableDelegate: UITableViewDelegate?

    public init<C: BidirectionalCollection>(_ collection: C, cell: @escaping ConfigureCell)
        where C.Element == Model, C.Index == Int {
            self.collection = AnyBidirectionalCollection(collection)
            self.configureCell = cell
    }

    public func register<Cell: UITableViewCell>(_ cell: Cell.Type, binding: Binding<Cell>) {
        registeredCells[cell.typeKey] = unsafeBitCast(binding, to: Binding<UITableViewCell>.self)
    }

    public func tableView<C: BidirectionalCollection>(_ tableView: UITableView, newData: C)
        where C.Element == Model, C.Index == Int {
            self.collection.forEach { $0.stopObserving() }
            self.collection = AnyBidirectionalCollection(newData)
            tableView.reloadData()
    }

    public func bind(_ tableView: UITableView) {
        tableView.delegate = delegateService
        tableView.dataSource = delegateService
        if #available(iOS 10.0, *) {
            tableView.prefetchDataSource = delegateService
        }
    }

    /// UITableView service
    class TableViewService: _TableViewSectionedAdapter, UITableViewDataSourcePrefetching {
        unowned let delegate: RealtimeTableViewDelegate<Model>

        init(_ delegate: RealtimeTableViewDelegate<Model>) {
            self.delegate = delegate
        }

        override func numberOfSections(in tableView: UITableView) -> Int {
            return 1
        }

        override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            return delegate.collection.count
        }

        override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            return delegate.configureCell(tableView, indexPath)
        }

        func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
            indexPaths.forEach { ip in
                delegate.collection.element(by: ip.row).load(completion: nil)
            }
        }

        /// events
        override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            let item = delegate.reuseController.dequeueItem(at: indexPath)
            guard let bind = delegate.registeredCells[cell.typeKey] else {
                fatalError("Unregistered cell by type \(type(of: cell))")
            }

            let model = delegate.collection.element(by: indexPath.row)
            bind(item, model)
            item.view = cell
            model.runObserving()

            delegate.tableDelegate?.tableView?(tableView, willDisplay: cell, forRowAt: indexPath)
        }

        override func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            delegate.reuseController.free(at: indexPath)
            if delegate.collection.count > indexPath.row {
                delegate.collection.element(by: indexPath.row).stopObserving()
            }
            delegate.tableDelegate?.tableView?(tableView, didEndDisplaying: cell, forRowAt: indexPath)
        }

        override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            delegate.tableDelegate?.tableView?(tableView, didSelectRowAt: indexPath)
        }
    }
}
