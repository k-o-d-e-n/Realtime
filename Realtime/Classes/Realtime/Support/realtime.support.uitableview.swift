
//
//  RealtimeTableViewDelegate.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 24/06/2018.
//  Copyright © 2018 Denis Koryttsev. All rights reserved.
//

import UIKit

public class ReuseItem<View: AnyObject> {
    private weak var view: View? {
        didSet {
            if let v = view, v !== oldValue {
                reload()
            }
        }
    }
    private var listeningItems: [ListeningItem] = []

    init() {}
    deinit { free() }

    /// Connects listanable value with view
    ///
    /// Use this function if listenable has been modified somehow
    ///
    /// - Parameters:
    ///   - value: Listenable value
    ///   - source: Source of value
    ///   - assign: Closure that calls on receieve value
    public func bind<T: Listenable, S: RealtimeValueActions>(_ value: T, _ source: S, _ assign: @escaping (View, T.OutData) -> Void) {
        var data: T.OutData {
            set { view.map { v in assign(v, newValue) } }
            get { fatalError() }
        }
        listeningItems.append(value.listeningItem(onValue: { data = $0 }))

        guard source.canObserve else { return }
        if source.runObserving() {
            listeningItems.append(ListeningItem(resume: { () }, pause: source.stopObserving, token: nil))
        } else {
            debugFatalError("Observing is not running")
        }
    }

    /// Connects listanable value with view
    ///
    /// - Parameters:
    ///   - value: Listenable value
    ///   - assign: Closure that calls on receieve value
    public func bind<T: Listenable & RealtimeValueActions>(_ value: T, _ assign: @escaping (View, T.OutData) -> Void) {
        var data: T.OutData {
            set { view.map { v in assign(v, newValue) } }
            get { fatalError() }
        }
        listeningItems.append(value.listeningItem(onValue: { data = $0 }))

        guard value.canObserve else { return }
        if value.runObserving() {
            listeningItems.append(ListeningItem(resume: { () }, pause: value.stopObserving, token: nil))
        } else {
            debugFatalError("Observing is not running")
        }
    }

    /// Sets value immediatelly when view will be received
    ///
    /// - Parameters:
    ///   - value: Some value
    ///   - assign: Closure that calls on receive view
    public func set<T>(_ value: T, _ assign: @escaping (View, T) -> Void) {
        listeningItems.append(flatMap({ $0 }).listeningItem(onValue: { assign($0, value) }))
    }

    func free() {
        listeningItems.forEach { $0.dispose() }
        listeningItems.removeAll()
        view = nil
    }

    func set(view: View) {
        self.view = view
        repeater.send(.value(view))
    }

    func reload() {
        listeningItems.forEach { $0.resume() }
    }

    lazy var repeater: Repeater<View?> = Repeater.unsafe()
}
extension ReuseItem: Listenable {
    public func listening(_ assign: Assign<ListenEvent<View?>>) -> Disposable {
        return repeater.listening(assign)
    }
}

class ReuseController<View: AnyObject, Key: Hashable> {
    private var freeItems: [ReuseItem<View>] = []
    private var activeItems: [Key: ReuseItem<View>] = [:]

    func dequeueItem(at key: Key) -> ReuseItem<View> {
        guard let item = activeItems[key] else {
            let item = freeItems.popLast() ?? ReuseItem<View>()
            activeItems[key] = item
            return item
        }
        return item
    }

    func free(at key: Key) {
        guard let item = activeItems.removeValue(forKey: key)
            else { return debugLog("Try free non-active reuse item") } //fatalError("Try free non-active reuse item") }
        item.free()
        freeItems.append(item)
    }

    func freeAll() {
        activeItems.forEach {
            $0.value.free()
            freeItems.append($0.value)
        }
        activeItems.removeAll()
    }

//    func exchange(indexPath: IndexPath, to ip: IndexPath) {
//        swap(&items[indexPath], &items[ip])
//    }
}

/// A type that responsible for editing of table
public protocol RealtimeEditingTableDataSource: class {
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath)
    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath)
}

/// A proxy base class that provides tools to manage UITableView reactively.
open class RealtimeTableViewDelegate<Model, Section> {
    public typealias BindingCell<Cell: AnyObject> = (ReuseItem<Cell>, Model) -> Void
    public typealias ConfigureCell = (UITableView, IndexPath, Model) -> UITableViewCell
    fileprivate let reuseController: ReuseController<UITableViewCell, IndexPath> = ReuseController()
    fileprivate var registeredCells: [TypeKey: BindingCell<UITableViewCell>] = [:]
    fileprivate var configureCell: ConfigureCell

    open weak var tableDelegate: UITableViewDelegate?
    open weak var editingDataSource: RealtimeEditingTableDataSource?
    open weak var prefetchingDataSource: UITableViewDataSourcePrefetching?

    init(cell: @escaping ConfigureCell) {
        self.configureCell = cell
    }

    /// Registers new type of cell with binding closure
    ///
    /// - Parameters:
    ///   - cell: Cell type inherited from `UITableViewCell`.
    ///   - binding: Closure to bind model.
    open func register<Cell: UITableViewCell>(_ cell: Cell.Type, binding: @escaping BindingCell<Cell>) {
        registeredCells[cell.typeKey] = unsafeBitCast(binding, to: BindingCell<UITableViewCell>.self)
    }

    /// Binds UITableView instance to this delegate
    open func bind(_ tableView: UITableView) {
        fatalError("Implement in subclass")
    }

    /// Returns `Model` element at index path
    open func model(at indexPath: IndexPath) -> Model {
        fatalError("Implement in subclass")
    }
}

/// A class that provides tools to manage UITableView data source reactively.
public final class SingleSectionTableViewDelegate<Model>: RealtimeTableViewDelegate<Model, Void> {
    fileprivate lazy var delegateService: Service = Service(self)

    var collection: AnySharedCollection<Model>

    public init<C: BidirectionalCollection>(_ collection: C, cell: @escaping ConfigureCell)
        where C.Element == Model, C.Index == Int {
            self.collection = AnySharedCollection(collection)
            super.init(cell: cell)
    }

    /// Sets new source of elements
    public func tableView<C: BidirectionalCollection>(_ tableView: UITableView, newData: C)
        where C.Element == Model, C.Index == Int {
            self.reuseController.freeAll()
            self.collection = AnySharedCollection(newData)
            tableView.reloadData()
    }

    public override func bind(_ tableView: UITableView) {
        tableView.delegate = nil
        tableView.dataSource = nil
        tableView.delegate = delegateService
        tableView.dataSource = delegateService
        if #available(iOS 10.0, *) {
            tableView.prefetchDataSource = nil
            tableView.prefetchDataSource = delegateService
        }
    }

    public override func model(at indexPath: IndexPath) -> Model {
        return collection[indexPath.row]
    }
}

/// UITableView service
extension SingleSectionTableViewDelegate {
    class Service: _TableViewSectionedAdapter {
        unowned let delegate: SingleSectionTableViewDelegate<Model>

        init(_ delegate: SingleSectionTableViewDelegate<Model>) {
            self.delegate = delegate
        }

        override func numberOfSections(in tableView: UITableView) -> Int {
            return 1
        }

        override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            return delegate.collection.count
        }

        override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            return delegate.configureCell(tableView, indexPath, delegate.collection[indexPath.row])
        }

        override func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
            delegate.prefetchingDataSource?.tableView(tableView, prefetchRowsAt: indexPaths)
        }

        override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
            return delegate.tableDelegate?.tableView?(tableView, heightForRowAt: indexPath) ?? 44.0
        }

        /// events
        override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            let item = delegate.reuseController.dequeueItem(at: indexPath)
            guard let bind = delegate.registeredCells[cell.typeKey] else {
                fatalError("Unregistered cell by type \(type(of: cell))")
            }

            let model = delegate.collection[indexPath.row]
            bind(item, model)
            item.set(view: cell)

            delegate.tableDelegate?.tableView?(tableView, willDisplay: cell, forRowAt: indexPath)
        }

        override func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            delegate.reuseController.free(at: indexPath)
            delegate.tableDelegate?.tableView?(tableView, didEndDisplaying: cell, forRowAt: indexPath)
        }

        override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            delegate.tableDelegate?.tableView?(tableView, didSelectRowAt: indexPath)
        }

        override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {
            return delegate.tableDelegate?.tableView?(tableView, editingStyleForRowAt: indexPath) ?? .delete
        }

        override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
            delegate.editingDataSource?.tableView(tableView, commit: editingStyle, forRowAt: indexPath)
        }
    }
}

public final class SectionedTableViewDelegate<Model, Section>: RealtimeTableViewDelegate<Model, Section> {
    public typealias BindingSection<Cell: AnyObject> = (ReuseItem<Cell>, Section) -> Void
    public typealias ConfigureSection = (UITableView, Int) -> UIView?
    fileprivate var configureSection: ConfigureSection
    fileprivate var registeredHeaders: [TypeKey: BindingSection<UIView>] = [:]
    fileprivate let reuseHeadersController: ReuseController<UIView, Int> = ReuseController()
    fileprivate lazy var delegateService: Service = Service(self)
    var sections: AnySharedCollection<Section>
    let mapElement: (Section, Int) -> Model
    let mapCount: (Section) -> Int

    public init<C: BidirectionalCollection>(_ sections: C,
                                            _ mapElement: @escaping (Section, Int) -> Model,
                                            _ mapCount: @escaping (Section) -> Int,
                                            cell: @escaping ConfigureCell,
                                            section: @escaping ConfigureSection)
        where C.Element == Section, C.Index == Int {
            self.sections = AnySharedCollection(sections)
            self.mapElement = mapElement
            self.mapCount = mapCount
            self.configureSection = section
            super.init(cell: cell)
    }

    /// Registers new type of header/footer with binding closure
    ///
    /// - Parameters:
    ///   - header: Header type inherited from `UITableViewHeaderFooterView`.
    ///   - binding: Closure to bind model.
    public func register<Header: UITableViewHeaderFooterView>(_ header: Header.Type, binding: @escaping BindingSection<Header>) {
        registeredHeaders[TypeKey.for(header)] = unsafeBitCast(binding, to: BindingSection<UIView>.self)
    }

    public override func model(at indexPath: IndexPath) -> Model {
        return mapElement(sections[indexPath.section], indexPath.row)
    }

    /// Returns `Section` element at index
    public func section(at index: Int) -> Section {
        return sections[index]
    }

    /// Sets new source of elements
    public func tableView<C: BidirectionalCollection>(_ tableView: UITableView, newData: C)
        where C.Element == Section, C.Index == Int {
            self.reuseController.freeAll()
            self.sections = AnySharedCollection(newData)
            tableView.reloadData()
    }

    public override func bind(_ tableView: UITableView) {
        tableView.delegate = delegateService
        tableView.dataSource = delegateService
        if #available(iOS 10.0, *) {
            tableView.prefetchDataSource = delegateService
        }
    }
}

extension SectionedTableViewDelegate {
    class Service: _TableViewSectionedAdapter {
        unowned let delegate: SectionedTableViewDelegate<Model, Section>

        init(_ delegate: SectionedTableViewDelegate<Model, Section>) {
            self.delegate = delegate
        }

        override func numberOfSections(in tableView: UITableView) -> Int {
            return delegate.sections.count
        }

        override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            return delegate.mapCount(delegate.sections[section])
        }

        override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            return delegate.configureCell(tableView, indexPath, delegate.model(at: indexPath))
        }

        override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
            return delegate.configureSection(tableView, section)
        }
//        override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
//            return nil
//        }

//        override func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
//            return index
//        }

        override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
            return delegate.tableDelegate?.tableView?(tableView, heightForHeaderInSection: section) ?? 44.0
        }

        override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
            return delegate.tableDelegate?.tableView?(tableView, heightForRowAt: indexPath) ?? 44.0
        }

        override func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
            delegate.prefetchingDataSource?.tableView(tableView, prefetchRowsAt: indexPaths)
        }

        /// events
        override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            let item = delegate.reuseController.dequeueItem(at: indexPath)
            guard let bind = delegate.registeredCells[cell.typeKey] else {
                fatalError("Unregistered cell by type \(type(of: cell))")
            }

            let model = delegate.model(at: indexPath)
            bind(item, model)
            item.set(view: cell)

            delegate.tableDelegate?.tableView?(tableView, willDisplay: cell, forRowAt: indexPath)
        }

        override func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            delegate.reuseController.free(at: indexPath)
            delegate.tableDelegate?.tableView?(tableView, didEndDisplaying: cell, forRowAt: indexPath)
        }

        override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            delegate.tableDelegate?.tableView?(tableView, didSelectRowAt: indexPath)
        }

        override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
            let item = delegate.reuseHeadersController.dequeueItem(at: section)
            guard let bind = delegate.registeredHeaders[TypeKey.for(type(of: view))] else {
                fatalError("Unregistered header by type \(type(of: view))")
            }
            let model = delegate.sections[section]
            bind(item, model)
            item.set(view: view)

            delegate.tableDelegate?.tableView?(tableView, willDisplayHeaderView: view, forSection: section)
        }

        override func tableView(_ tableView: UITableView, didEndDisplayingHeaderView view: UIView, forSection section: Int) {
            delegate.reuseHeadersController.free(at: section)
            delegate.tableDelegate?.tableView?(tableView, didEndDisplayingHeaderView: view, forSection: section)
        }

        override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {
            return delegate.tableDelegate?.tableView?(tableView, editingStyleForRowAt: indexPath) ?? .delete
        }

        override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
            delegate.editingDataSource?.tableView(tableView, commit: editingStyle, forRowAt: indexPath)
        }

//        override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
//            delegate.editingDataSource?.tableView(tableView, moveRowAt: sourceIndexPath, to: destinationIndexPath)
//        }
    }
}
