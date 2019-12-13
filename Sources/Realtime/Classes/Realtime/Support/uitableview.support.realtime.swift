
//
//  RealtimeTableViewDelegate.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 24/06/2018.
//  Copyright © 2018 Denis Koryttsev. All rights reserved.
//

protocol ReuseItemProtocol {
    func free()
}

open class ReuseItem<View: AnyObject>: ReuseItemProtocol {
    lazy var _view: ValueStorage<View?> = ValueStorage.unsafe(weak: nil, repeater: .unsafe(with: .queue(.main)))
    public var disposeStorage: ListeningDisposeStore = ListeningDisposeStore()

    open internal(set) weak var view: View? {
        set { self._view.value = newValue }
        get { return self._view.value }
    }

    public init() {}
    deinit { free() }

    /// Connects listanable value with view
    ///
    /// Use this function if listenable has been modified somehow
    ///
    /// - Parameters:
    ///   - value: Listenable value
    ///   - source: Source of value
    ///   - assign: Closure that calls on receieve value
    public func bind<T: Listenable, S: RealtimeValueActions>(_ value: T, _ source: S, _ assign: @escaping (View, T.Out) -> Void, _ error: ((View, Error) -> Void)?) {
        set(value, assign, error)

        guard source.canObserve else { return }
        if source.runObserving() {
            ListeningDispose(source.stopObserving).add(to: disposeStorage)
        } else {
            debugFatalError("Observing is not running")
        }
    }

    public func bind<T: Listenable>(_ value: T, sources: [RealtimeValueActions], _ assign: @escaping (View, T.Out) -> Void, _ error: ((View, Error) -> Void)?) {
        set(value, assign, error)

        sources.forEach { source in
            guard source.canObserve else { return }
            if source.runObserving() {
                ListeningDispose(source.stopObserving).add(to: disposeStorage)
            } else {
                debugFatalError("Observing is not running")
            }
        }
    }

    /// Connects listanable value with view
    ///
    /// - Parameters:
    ///   - value: Listenable value
    ///   - assign: Closure that calls on receieve value
    public func bind<T: Listenable & RealtimeValueActions>(_ value: T, _ assign: @escaping (View, T.Out) -> Void, _ error: ((View, Error) -> Void)?) {
        bind(value, value, assign, error)
    }

    public func set<T: Listenable>(_ value: T, _ assign: @escaping (View, T.Out) -> Void, _ error: ((View, Error) -> Void)?) {
        debugFatalError(
            condition: self.view == nil,
            "No view in binding time"
        )
        // bindingView works if view setup before binding
        weak var bindingView = self.view
        value
            .listening({ [weak self] (event) in
                if let view = self?.view {
                    switch event {
                    case .value(let v):
                        if view === bindingView {
                            assign(view, v)
                        }
                    case .error(let e):
                        if let errClosure = error, view === bindingView {
                            errClosure(view, e)
                        } else {
                            debugLog(String(describing: e))
                        }
                    }
                }
            })
            .add(to: disposeStorage)
    }

    func free() {
        disposeStorage.dispose()
        _view.value = nil
    }
}
extension ReuseItem {
    public func set<T: Listenable>(
        _ value: T, _ assign: @escaping (View, T.Out) -> Void, _ error: @escaping (Error) -> Void
    ) {
        set(value, assign, { _, e in error(e) })
    }
    public func bind<T: Listenable & RealtimeValueActions>(
        _ value: T, _ assign: @escaping (View, T.Out) -> Void, _ error: @escaping (Error) -> Void
    ) {
        bind(value, assign, { _, e in error(e) })
    }
    public func bind<T: Listenable>(
        _ value: T, sources: [RealtimeValueActions], _ assign: @escaping (View, T.Out) -> Void, _ error: @escaping (Error) -> Void
    ) {
        bind(value, sources: sources, assign, { _, e in error(e) })
    }
    public func bind<T: Listenable, S: RealtimeValueActions>(
        _ value: T, _ source: S, _ assign: @escaping (View, T.Out) -> Void, _ error: @escaping (Error) -> Void
    ) {
        bind(value, source, assign, { _, e in error(e) })
    }
}

struct ReuseController<Row, Key: Hashable> where Row: ReuseItemProtocol {
    var freeItems: [Row] = []
    var activeItems: [Key: Row] = [:]

    typealias RowBuilder = () -> Row

    func active(at key: Key) -> Row? {
        return activeItems[key]
    }

    mutating func freeAll() {
        activeItems.forEach {
            $0.value.free()
            freeItems.append($0.value)
        }
        activeItems.removeAll()
    }

    mutating func free() {
        activeItems.forEach { $0.value.free() }
        activeItems.removeAll()
        freeItems.removeAll()
    }
}
extension ReuseController {
    mutating func dequeue<View: AnyObject>(at key: Key, rowBuilder: RowBuilder) -> Row where Row: ReuseItem<View> {
        guard let item = activeItems[key] else {
            let item = freeItems.popLast() ?? rowBuilder()
            activeItems[key] = item
            return item
        }
        item.free()
        return item
    }
    @discardableResult
    mutating func free<View: AnyObject>(at key: Key) -> Row? where Row: ReuseItem<View> {
        guard let item = activeItems[key] else { return nil }
        activeItems.removeValue(forKey: key)
        item.free()
        freeItems.append(item)
        return item
    }
}

#if os(iOS)
import UIKit

extension ReuseItem where View: UIView {
    var _isVisible: Bool { return view.map { !$0.isHidden && $0.window != nil } ?? false }
}

/// A type that responsible for editing of table
public protocol RealtimeEditingTableDataSource: class {
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool
    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath)
    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath)
    func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath
    ) -> IndexPath
}
public extension RealtimeEditingTableDataSource {
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { return tableView.isEditing }
    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { return false }
    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {}
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {}
    func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath
        ) -> IndexPath {
        return proposedDestinationIndexPath
    }
}

/*
protocol ReuseElement: class {
    associatedtype BaseView
}

protocol CollectibleViewDelegateProtocol {
    typealias Binding<RV: ReuseElement> = (ReuseItem<RV>, Model, Index) -> Void
    associatedtype View: AnyObject
//    associatedtype BaseReuseElement: ReuseElement where BaseReuseElement.BaseView == View
    associatedtype Model
    associatedtype Index
    func register<RV: ReuseElement>(_ item: RV.Type, binding: @escaping Binding<RV>) where RV.BaseView == View
    func bind(_ view: View)
    func model(at index: Index) -> Model
    func reload()
}
*/

/// A proxy base class that provides tools to manage UITableView reactively.
open class CollectibleViewDelegate<View, Cell: AnyObject & Hashable, Model, Section> {
    public typealias Binding<Cell: AnyObject> = (ReuseItem<Cell>, Cell, Model, IndexPath) -> Void
    public typealias ConfigureCell = (View, IndexPath, Model) -> Cell
    fileprivate var reuseController: ReuseController<ReuseItem<Cell>, Cell> = ReuseController()
    fileprivate var registeredCells: [TypeKey: Binding<Cell>] = [:]
    fileprivate var configureCell: ConfigureCell

    init(cell: @escaping ConfigureCell) {
        self.configureCell = cell
    }

    deinit {
        reuseController.free()
    }

    func _register<I: AnyObject>(_ item: I.Type, binding: @escaping Binding<I>) {
        registeredCells[TypeKey.for(item)] = unsafeBitCast(binding, to: Binding<Cell>.self)
    }

    /// Binds UITableView instance to this delegate
    open func bind(_ view: View) {
        fatalError("Implement in subclass")
    }

    /// Returns `Model` element at index path
    open func model(at indexPath: IndexPath) -> Model {
        fatalError("Implement in subclass")
    }

    open func reload() {
        // TODO: Implement reload as call `func reload()` on each active `ReuseItem`
    }

    open func item(for cell: Cell) -> ReuseItem<Cell>? {
        return reuseController.active(at: cell)
    }
}

open class TableViewDelegate<View, Item: AnyObject & Hashable, Model, Section>: CollectibleViewDelegate<View, Item, Model, Section> {
    open weak var tableDelegate: UITableViewDelegate?
    open weak var editingDataSource: RealtimeEditingTableDataSource?
    open weak var prefetchingDataSource: UITableViewDataSourcePrefetching?
}

/// A class that provides tools to manage UITableView data source reactively.
public final class SingleSectionTableViewDelegate<Model>: TableViewDelegate<UITableView, UITableViewCell, Model, Void> {
    fileprivate lazy var delegateService: Service = Service(self)
    public var headerView: UIView?

    var collection: AnySharedCollection<Model>

    public init<C: BidirectionalCollection>(_ collection: C, cell: @escaping ConfigureCell)
        where C.Element == Model {
            self.collection = AnySharedCollection(collection)
            super.init(cell: cell)
    }

    /// Registers new type of cell with binding closure
    ///
    /// - Parameters:
    ///   - cell: Cell type inherited from `UITableViewCell`.
    ///   - binding: Closure to bind model.
    public func register<Cell: UITableViewCell>(_ cell: Cell.Type, binding: @escaping Binding<Cell>) {
        _register(cell, binding: binding)
    }

    /// Sets new source of elements
    public func tableView<C: BidirectionalCollection>(_ tableView: UITableView, newData: C)
        where C.Element == Model {
            self.reuseController.freeAll()
            self.collection = AnySharedCollection(newData)
            tableView.reloadData()
    }

    public func setNewData<C: BidirectionalCollection>(_ newData: C) where C.Element == Model {
        self.collection = AnySharedCollection(newData)
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
    class Service: NSObject, UITableViewDataSource, UITableViewDelegate, UITableViewDataSourcePrefetching {
        unowned let delegate: SingleSectionTableViewDelegate<Model>

        init(_ delegate: SingleSectionTableViewDelegate<Model>) {
            self.delegate = delegate
        }

        func numberOfSections(in tableView: UITableView) -> Int {
            return 1
        }

        func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
            return delegate.headerView
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            return delegate.collection.count
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            return delegate.configureCell(tableView, indexPath, delegate.collection[indexPath.row])
        }

        func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
            delegate.prefetchingDataSource?.tableView(tableView, prefetchRowsAt: indexPaths)
        }

        func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
            return delegate.tableDelegate?.tableView?(tableView, heightForRowAt: indexPath) ??
                (tableView.rowHeight != UITableView.automaticDimension ? tableView.rowHeight : 44.0)
        }

        func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
            return delegate.tableDelegate?.tableView?(tableView, heightForHeaderInSection: section) ??
                delegate.headerView?.frame.height ??
                (tableView.sectionHeaderHeight != UITableView.automaticDimension ? tableView.sectionHeaderHeight : 0.0)
        }

        /// events
        func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            let item = delegate.reuseController.dequeue(at: cell, rowBuilder: ReuseItem.init)
            guard let bind = delegate.registeredCells[cell.typeKey] else {
                fatalError("Unregistered cell with type \(type(of: cell))")
            }

            let model = delegate.collection[indexPath.row]
            item.view = cell
            bind(item, cell, model, indexPath)

            delegate.tableDelegate?.tableView?(tableView, willDisplay: cell, forRowAt: indexPath)
        }

        func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            delegate.reuseController.free(at: cell)
            delegate.tableDelegate?.tableView?(tableView, didEndDisplaying: cell, forRowAt: indexPath)
        }

        func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            delegate.tableDelegate?.tableView?(tableView, didSelectRowAt: indexPath)
        }

        func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
            return delegate.tableDelegate?.tableView?(tableView, editingStyleForRowAt: indexPath) ?? .delete
        }

        func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
            delegate.editingDataSource?.tableView(tableView, commit: editingStyle, forRowAt: indexPath)
        }

        func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
            return delegate.tableDelegate?.tableView?(tableView, shouldIndentWhileEditingRowAt: indexPath) ?? true
        }

        func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
            return delegate.editingDataSource?.tableView(tableView, canEditRowAt: indexPath) ?? tableView.isEditing
        }

        func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
            return delegate.tableDelegate?.tableView?(tableView, editActionsForRowAt: indexPath) ?? nil
        }

        // MARK: UIScrollView

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewDidScroll?(scrollView)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewDidZoom?(scrollView)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewWillBeginDragging?(scrollView)
        }

        func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
            delegate.tableDelegate?.scrollViewWillEndDragging?(scrollView, withVelocity: velocity, targetContentOffset: targetContentOffset)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            delegate.tableDelegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
        }

        func scrollViewWillBeginDecelerating(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewWillBeginDecelerating?(scrollView)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewDidEndDecelerating?(scrollView)
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewDidEndScrollingAnimation?(scrollView)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return delegate.tableDelegate?.viewForZooming?(in: scrollView)
        }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            delegate.tableDelegate?.scrollViewWillBeginZooming?(scrollView, with: view)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            delegate.tableDelegate?.scrollViewDidEndZooming?(scrollView, with: view, atScale: scale)
        }

        func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
            return delegate.tableDelegate?.scrollViewShouldScrollToTop?(scrollView) ?? true
        }

        func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewDidScrollToTop?(scrollView)
        }

        @available(iOS 11.0, *)
        func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewDidChangeAdjustedContentInset?(scrollView)
        }
    }
}

open class ReuseSection<Model, View: AnyObject>: ReuseItem<View> {
    var items: AnyRealtimeCollection<Model>? {
        didSet {
            if let itms = items, !itms.keepSynced {
                itms.keepSynced = true
            }
        }
    }
    var isNotBeingDisplay: Bool {
        return items == nil
    }

    func endDisplaySection(_ tableView: UITableView, at index: Int) {
        debugFatalError(condition: self.items != nil, "Unbalanced section managing")
    }

    func endDisplaySection(_ collectionView: UICollectionView, at index: Int) {
        debugFatalError(condition: self.items != nil, "Unbalanced section managing")
    }

    override func free() {
        super.free()
        items = nil
    }
}
extension ReuseSection where View: UIView {
    func willDisplaySection(_ collectionView: UICollectionView, items: AnyRealtimeCollection<Model>, at index: Int) {
        debugFatalError(condition: self.items != nil, "Unbalanced section managing")
        items.changes.listening(
            onValue: { [weak collectionView] e in
                guard self._isVisible, let cv = collectionView else { return }
                cv.performBatchUpdates({
                    switch e {
                    case .initial:
                        cv.reloadSections([index])
                    case .updated(let deleted, let inserted, let modified, let moved):
                        cv.insertItems(at: inserted.map { IndexPath(row: $0, section: index) })
                        cv.deleteItems(at: deleted.map { IndexPath(row: $0, section: index) })
                        cv.reloadItems(at: modified.map { IndexPath(row: $0, section: index) })
                        moved.forEach({ (move) in
                            cv.moveItem(at: IndexPath(row: move.from, section: index), to: IndexPath(row: move.to, section: index))
                        })
                    }
                }, completion: nil)
            },
            onError: { error in
                debugPrintLog(String(describing: error))
            }
        ).add(to: disposeStorage)
        self.items = items
    }
    func willDisplaySection(_ tableView: UITableView, items: AnyRealtimeCollection<Model>, at index: Int) {
        debugFatalError(condition: self.items != nil, "Unbalanced section managing")
        items.changes.listening(
            onValue: { [unowned self, weak tableView] e in
                // TODO: visibillity checks because tableView has unbalanced call `willDisplayHeaderView` method
                guard self._isVisible, let tv = tableView else { return }
                tv.beginUpdates()
                switch e {
                case .initial:
                    tv.reloadSections([index], with: .automatic)
                case .updated(let deleted, let inserted, let modified, let moved):
                    tv.insertRows(at: inserted.map { IndexPath(row: $0, section: index) }, with: .automatic)
                    tv.deleteRows(at: deleted.map { IndexPath(row: $0, section: index) }, with: .automatic)
                    tv.reloadRows(at: modified.map { IndexPath(row: $0, section: index) }, with: .automatic)
                    moved.forEach({ (move) in
                        tv.moveRow(at: IndexPath(row: move.from, section: index), to: IndexPath(row: move.to, section: index))
                    })
                }
                tv.endUpdates()
            },
            onError: { error in
                debugPrintLog(String(describing: error))
            }
        ).add(to: disposeStorage)
        self.items = items
    }
}

public final class SectionedTableViewDelegate<Model, Section>: TableViewDelegate<UITableView, UITableViewCell, Model, Section> {
    public typealias BindingSection<View: AnyObject> = (ReuseSection<Model, View>, View, Section, Int) -> Void
    public typealias ConfigureSection = (UITableView, Int) -> UIView?
    fileprivate var configureSection: ConfigureSection
    fileprivate var registeredHeaders: [TypeKey: BindingSection<UIView>] = [:]
    fileprivate var reuseSectionController: ReuseController<ReuseSection<Model, UIView>, UIView> = ReuseController()
    fileprivate lazy var delegateService: Service = Service(self)
    var sections: AnySharedCollection<Section> {
        willSet {
            sections.enumerated().lazy.map({ self.models($1, $0) }).forEach { $0.keepSynced = false }
        }
    }
    let models: (Section, Int) -> AnyRealtimeCollection<Model>

    public init<C: BidirectionalCollection>(_ sections: C,
                                            _ models: @escaping (Section, Int) -> AnyRealtimeCollection<Model>,
                                            cell: @escaping ConfigureCell,
                                            section: @escaping ConfigureSection)
        where C.Element == Section {
            self.sections = AnySharedCollection(sections)
            self.models = models
            self.configureSection = section
            super.init(cell: cell)
    }

    deinit {
        reuseSectionController.free()
        sections.enumerated().lazy.map({ self.models($1, $0) }).forEach { $0.keepSynced = false }
    }

    /// Registers new type of cell with binding closure
    ///
    /// - Parameters:
    ///   - cell: Cell type inherited from `UITableViewCell`.
    ///   - binding: Closure to bind model.
    public func register<Cell: UITableViewCell>(_ cell: Cell.Type, binding: @escaping Binding<Cell>) {
        _register(cell, binding: binding)
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
        let items = models(sections[indexPath.section], indexPath.section)
        return items[items.index(items.startIndex, offsetBy: indexPath.row)]
    }

    /// Returns `Section` element at index
    public func section(at index: Int) -> Section {
        return sections[index]
    }

    /// Sets new source of elements
    public func tableView<C: BidirectionalCollection>(_ tableView: UITableView, newData: C)
        where C.Element == Section {
            self.reuseController.freeAll()
            self.sections = AnySharedCollection(newData)
            tableView.reloadData()
    }

    public func setNewData<C: BidirectionalCollection>(_ newData: C) where C.Element == Section {
        self.sections = AnySharedCollection(newData)
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
    class Service: NSObject, UITableViewDataSource, UITableViewDelegate, UITableViewDataSourcePrefetching {
//        var oldOffset: CGFloat = 0.0
        unowned let delegate: SectionedTableViewDelegate<Model, Section>

        init(_ delegate: SectionedTableViewDelegate<Model, Section>) {
            self.delegate = delegate
        }

        func numberOfSections(in tableView: UITableView) -> Int {
            return delegate.sections.count
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            return delegate.models(delegate.sections[section], section).count
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            return delegate.configureCell(tableView, indexPath, delegate.model(at: indexPath))
        }

        func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
            return delegate.configureSection(tableView, section)
        }

        func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
            return delegate.tableDelegate?.tableView?(tableView, heightForHeaderInSection: section) ??
                (tableView.sectionHeaderHeight != UITableView.automaticDimension ? tableView.sectionHeaderHeight : 35.0)
        }

        func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
            return delegate.tableDelegate?.tableView?(tableView, heightForRowAt: indexPath) ??
                (tableView.rowHeight != UITableView.automaticDimension ? tableView.rowHeight : 44.0)
        }

        func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
            delegate.prefetchingDataSource?.tableView(tableView, prefetchRowsAt: indexPaths)
        }

        /// events
        func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            let item = delegate.reuseController.dequeue(at: cell, rowBuilder: ReuseItem.init)
            guard let bind = delegate.registeredCells[cell.typeKey] else {
                fatalError("Unregistered cell by type \(type(of: cell))")
            }

            let model = delegate.model(at: indexPath)
            item.view = cell
            bind(item, cell, model, indexPath)

            delegate.tableDelegate?.tableView?(tableView, willDisplay: cell, forRowAt: indexPath)

//            guard
//                delegate.sections.count > indexPath.section + 1,
//                let items = delegate.reuseSectionController.active(at: indexPath.section)?.items,
//                indexPath.row >= (items.count / 2)
//            else {
//                return
//            }
//
//            let sectionItem = delegate.reuseSectionController.dequeueItem(at: indexPath.section + 1, rowBuilder: ReuseSection.init)
//            if sectionItem.isNotBeingDisplay {
//                sectionItem.willDisplaySection(tableView, items: delegate.models(delegate.sections[indexPath.section + 1]), at: indexPath.section + 1)
//            }
        }

        func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            delegate.reuseController.free(at: cell)
            delegate.tableDelegate?.tableView?(tableView, didEndDisplaying: cell, forRowAt: indexPath)

//            var endDisplaySection: Bool {
//                if oldOffset > tableView.contentOffset.y {
//                    if let items = delegate.reuseSectionController.active(at: indexPath.section)?.items {
//                        return items.count == indexPath.row + 1
//                    } else {
//                        // unexpected behavior
//                        return false
//                    }
//                } else {
//                    return indexPath.row == 0
//                }
//            }
//
//            guard endDisplaySection, let sectionItem = delegate.reuseSectionController.active(at: indexPath.section) else { return }
//
//            sectionItem.endDisplaySection(tableView, at: indexPath.section)
//            sectionItem.free()
        }

        func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            delegate.tableDelegate?.tableView?(tableView, didSelectRowAt: indexPath)
        }

        func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
            let item = delegate.reuseSectionController.dequeue(at: view, rowBuilder: ReuseSection.init)
            guard let bind = delegate.registeredHeaders[TypeKey.for(type(of: view))] else {
                fatalError("Unregistered header by type \(type(of: view))")
            }
            let model = delegate.sections[section]
            item.view = view
            bind(item, view, model, section)

            if item.isNotBeingDisplay {
                item.willDisplaySection(tableView, items: delegate.models(delegate.sections[section], section), at: section)
            }

            delegate.tableDelegate?.tableView?(tableView, willDisplayHeaderView: view, forSection: section)
        }

        func tableView(_ tableView: UITableView, didEndDisplayingHeaderView view: UIView, forSection section: Int) {
            delegate.tableDelegate?.tableView?(tableView, didEndDisplayingHeaderView: view, forSection: section)

            if let sectionItem = delegate.reuseSectionController.free(at: view) {
                sectionItem.endDisplaySection(tableView, at: section)
            }
        }

        func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
            return delegate.tableDelegate?.tableView?(tableView, editingStyleForRowAt: indexPath) ?? .delete
        }

        func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
            delegate.editingDataSource?.tableView(tableView, commit: editingStyle, forRowAt: indexPath)
        }

        func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
            return delegate.tableDelegate?.tableView?(tableView, shouldIndentWhileEditingRowAt: indexPath) ?? true
        }

//        override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
//            delegate.editingDataSource?.tableView(tableView, moveRowAt: sourceIndexPath, to: destinationIndexPath)
//        }

        // MARK: UIScrollView

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
//            oldOffset = scrollView.contentOffset.y
            delegate.tableDelegate?.scrollViewDidScroll?(scrollView)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewDidZoom?(scrollView)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewWillBeginDragging?(scrollView)
        }

        func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
            delegate.tableDelegate?.scrollViewWillEndDragging?(scrollView, withVelocity: velocity, targetContentOffset: targetContentOffset)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            delegate.tableDelegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
        }

        func scrollViewWillBeginDecelerating(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewWillBeginDecelerating?(scrollView)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewDidEndDecelerating?(scrollView)
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewDidEndScrollingAnimation?(scrollView)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return delegate.tableDelegate?.viewForZooming?(in: scrollView)
        }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            delegate.tableDelegate?.scrollViewWillBeginZooming?(scrollView, with: view)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            delegate.tableDelegate?.scrollViewDidEndZooming?(scrollView, with: view, atScale: scale)
        }

        func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
            return delegate.tableDelegate?.scrollViewShouldScrollToTop?(scrollView) ?? true
        }

        func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewDidScrollToTop?(scrollView)
        }

        @available(iOS 11.0, *)
        func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewDidChangeAdjustedContentInset?(scrollView)
        }
    }
}


public final class CollectionViewDelegate<Model, Section>: CollectibleViewDelegate<UICollectionView, UICollectionViewCell, Model, Section> {
    public typealias BindingSection<View: AnyObject> = (ReuseSection<Model, View>, View, Section, IndexPath) -> Void
    public typealias ConfigureSection = (UICollectionView, String, IndexPath) -> UICollectionReusableView
    fileprivate var configureSection: ConfigureSection
    fileprivate var registeredHeaders: [TypeKey: BindingSection<UICollectionReusableView>] = [:]
    fileprivate var reuseSectionController: ReuseController<ReuseSection<Model, UICollectionReusableView>, UICollectionReusableView> = ReuseController()
    fileprivate lazy var delegateService: Service = Service(self)
    var sections: AnySharedCollection<Section> {
        willSet {
            sections.lazy.map(models).forEach { $0.keepSynced = false }
        }
    }
    let models: (Section) -> AnyRealtimeCollection<Model>

    public weak var collectionDelegate: UICollectionViewDelegate?
    public weak var layoutDelegate: UICollectionViewDelegateFlowLayout?
    public weak var prefetchingDataSource: UICollectionViewDataSourcePrefetching?

    public init<C: BidirectionalCollection>(_ sections: C,
                                            _ models: @escaping (Section) -> AnyRealtimeCollection<Model>,
                                            cell: @escaping ConfigureCell,
                                            section: @escaping ConfigureSection)
        where C.Element == Section {
            self.sections = AnySharedCollection(sections)
            self.models = models
            self.configureSection = section
            super.init(cell: cell)
    }

    deinit {
        reuseSectionController.free()
        sections.lazy.map(models).forEach { $0.keepSynced = false }
    }

    /// Registers new type of cell with binding closure
    ///
    /// - Parameters:
    ///   - cell: Cell type inherited from `UICollectionViewCell`.
    ///   - binding: Closure to bind model.
    public func register<Cell: UICollectionViewCell>(_ cell: Cell.Type, binding: @escaping Binding<Cell>) {
        _register(cell, binding: binding)
    }

    /// Registers new type of header/footer with binding closure
    ///
    /// - Parameters:
    ///   - header: Header type inherited from `UITableViewHeaderFooterView`.
    ///   - binding: Closure to bind model.
    public func register<Header: UICollectionReusableView>(supplementaryView header: Header.Type, binding: @escaping BindingSection<Header>) {
        registeredHeaders[TypeKey.for(header)] = unsafeBitCast(binding, to: BindingSection<UICollectionReusableView>.self)
    }

    public override func model(at indexPath: IndexPath) -> Model {
        let items = models(sections[indexPath.section])
        return items[items.index(items.startIndex, offsetBy: indexPath.row)]
    }

    /// Returns `Section` element at index
    public func section(at index: Int) -> Section {
        return sections[index]
    }

    /// Sets new source of elements
    public func collectionView<C: BidirectionalCollection>(_ collectionView: UICollectionView, newData: C)
        where C.Element == Section {
            self.reuseController.freeAll()
            self.sections = AnySharedCollection(newData)
            collectionView.reloadData()
    }

    public func setNewData<C: BidirectionalCollection>(_ newData: C) where C.Element == Section {
        self.sections = AnySharedCollection(newData)
    }

    public override func bind(_ collectionView: UICollectionView) {
        collectionView.delegate = nil
        collectionView.dataSource = nil
        collectionView.delegate = delegateService
        collectionView.dataSource = delegateService
        if #available(iOS 10.0, *) {
            collectionView.prefetchDataSource = nil
            collectionView.prefetchDataSource = delegateService
        }
    }
}
extension CollectionViewDelegate {
    final class Service: _CollectionViewSectionedAdapter, UICollectionViewDelegateFlowLayout {
        unowned let delegate: CollectionViewDelegate<Model, Section>

        init(_ delegate: CollectionViewDelegate<Model, Section>) {
            self.delegate = delegate
        }

        override var providesSupplementaryViews: Bool { return true }

        override func responds(to aSelector: Selector!) -> Bool {
            if aSelector == #selector(UICollectionViewDelegate.collectionView(_:transitionLayoutForOldLayout:newLayout:)) {
                return delegate.collectionDelegate?.responds(to: aSelector) ?? false
            } else {
                return super.responds(to: aSelector)
            }
        }

        @available(iOS 10.0, *)
        override func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            delegate.prefetchingDataSource?.collectionView?(collectionView, cancelPrefetchingForItemsAt: indexPaths)
        }
        @available(iOS 10.0, *)
        override func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            delegate.prefetchingDataSource?.collectionView(collectionView, prefetchItemsAt: indexPaths)
        }
        override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            return delegate.models(delegate.sections[section]).count
        }
        override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            return delegate.configureCell(collectionView, indexPath, delegate.model(at: indexPath))
        }
        override func numberOfSections(in collectionView: UICollectionView) -> Int {
            return delegate.sections.count
        }
        override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
            return delegate.configureSection(collectionView, kind, indexPath)
        }
        override func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool { return false }
        override func collectionView(_ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {}
        override func indexTitles(for collectionView: UICollectionView) -> [String]? { return nil }
        override func collectionView(_ collectionView: UICollectionView, indexPathForIndexTitle title: String, at index: Int) -> IndexPath { fatalError() }

        override func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
            return delegate.collectionDelegate?.collectionView?(collectionView, shouldHighlightItemAt: indexPath) ?? false
        }
        override func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
            delegate.collectionDelegate?.collectionView?(collectionView, didHighlightItemAt: indexPath)
        }
        override func collectionView(_ collectionView: UICollectionView, didUnhighlightItemAt indexPath: IndexPath) {
            delegate.collectionDelegate?.collectionView?(collectionView, didUnhighlightItemAt: indexPath)
        }
        override func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
            return delegate.collectionDelegate?.collectionView?(collectionView, shouldSelectItemAt: indexPath) ?? false
        }
        override func collectionView(_ collectionView: UICollectionView, shouldDeselectItemAt indexPath: IndexPath) -> Bool {
            return delegate.collectionDelegate?.collectionView?(collectionView, shouldDeselectItemAt: indexPath) ?? false
        }
        override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            delegate.collectionDelegate?.collectionView?(collectionView, didSelectItemAt: indexPath)
        }
        override func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
            delegate.collectionDelegate?.collectionView?(collectionView, didDeselectItemAt: indexPath)
        }
        override func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            let item = delegate.reuseController.dequeue(at: cell, rowBuilder: ReuseItem.init)
            guard let bind = delegate.registeredCells[TypeKey.for(type(of: cell))] else {
                fatalError("Unregistered cell by type \(type(of: cell))")
            }

            let model = delegate.model(at: indexPath)
            item.view = cell
            bind(item, cell, model, indexPath)

            delegate.collectionDelegate?.collectionView?(collectionView, willDisplay: cell, forItemAt: indexPath)
        }
        override func collectionView(_ collectionView: UICollectionView, willDisplaySupplementaryView view: UICollectionReusableView, forElementKind elementKind: String, at indexPath: IndexPath) {
            let item = delegate.reuseSectionController.dequeue(at: view, rowBuilder: ReuseSection.init)
            guard let bind = delegate.registeredHeaders[TypeKey.for(type(of: view))] else {
                fatalError("Unregistered header by type \(type(of: view))")
            }
            let model = delegate.sections[indexPath.section]
            item.view = view
            bind(item, view, model, indexPath)

            if item.isNotBeingDisplay {
                item.willDisplaySection(collectionView, items: delegate.models(delegate.sections[indexPath.section]), at: indexPath.section)
            }

            delegate.collectionDelegate?.collectionView?(collectionView, willDisplaySupplementaryView: view, forElementKind: elementKind, at: indexPath)
        }
        override func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            delegate.reuseController.free(at: cell)
            delegate.collectionDelegate?.collectionView?(collectionView, didEndDisplaying: cell, forItemAt: indexPath)
        }
        override func collectionView(_ collectionView: UICollectionView, didEndDisplayingSupplementaryView view: UICollectionReusableView, forElementOfKind elementKind: String, at indexPath: IndexPath) {
            if let sectionItem = delegate.reuseSectionController.free(at: view) {
                sectionItem.endDisplaySection(collectionView, at: indexPath.section)
            }
            delegate.collectionDelegate?.collectionView?(collectionView, didEndDisplayingSupplementaryView: view, forElementOfKind: elementKind, at: indexPath)
        }
        override func collectionView(_ collectionView: UICollectionView, shouldShowMenuForItemAt indexPath: IndexPath) -> Bool {
            return delegate.collectionDelegate?.collectionView?(collectionView, shouldShowMenuForItemAt: indexPath) ?? false
        }
        override func collectionView(_ collectionView: UICollectionView, canPerformAction action: Selector, forItemAt indexPath: IndexPath, withSender sender: Any?) -> Bool {
            return delegate.collectionDelegate?.collectionView?(collectionView, canPerformAction: action, forItemAt: indexPath, withSender: sender) ?? false
        }
        override func collectionView(_ collectionView: UICollectionView, performAction action: Selector, forItemAt indexPath: IndexPath, withSender sender: Any?) {
            delegate.collectionDelegate?.collectionView?(collectionView, performAction: action, forItemAt: indexPath, withSender: sender)
        }
        override func collectionView(_ collectionView: UICollectionView, transitionLayoutForOldLayout fromLayout: UICollectionViewLayout, newLayout toLayout: UICollectionViewLayout) -> UICollectionViewTransitionLayout {
            return delegate.collectionDelegate!.collectionView!(collectionView, transitionLayoutForOldLayout: fromLayout, newLayout: toLayout)
        }
        @available(iOS 9.0, *)
        override func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
            return delegate.collectionDelegate?.collectionView?(collectionView, canFocusItemAt: indexPath) ?? false
        }
        @available(iOS 9.0, *)
        override func collectionView(_ collectionView: UICollectionView, shouldUpdateFocusIn context: UICollectionViewFocusUpdateContext) -> Bool {
            return delegate.collectionDelegate?.collectionView?(collectionView, shouldUpdateFocusIn: context) ?? false
        }
        @available(iOS 9.0, *)
        override func collectionView(_ collectionView: UICollectionView, didUpdateFocusIn context: UICollectionViewFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
            delegate.collectionDelegate?.collectionView?(collectionView, didUpdateFocusIn: context, with: coordinator)
        }
        @available(iOS 9.0, *)
        override func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
            return delegate.collectionDelegate?.indexPathForPreferredFocusedView?(in: collectionView)
        }
        @available(iOS 9.0, *)
        override func collectionView(_ collectionView: UICollectionView, targetIndexPathForMoveFromItemAt originalIndexPath: IndexPath, toProposedIndexPath proposedIndexPath: IndexPath) -> IndexPath {
            return delegate.collectionDelegate?.collectionView?(collectionView, targetIndexPathForMoveFromItemAt: originalIndexPath, toProposedIndexPath: proposedIndexPath) ?? proposedIndexPath
        }
        @available(iOS 9.0, *)
        override func collectionView(_ collectionView: UICollectionView, targetContentOffsetForProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {
            return delegate.collectionDelegate?.collectionView?(collectionView, targetContentOffsetForProposedContentOffset: proposedContentOffset) ?? proposedContentOffset
        }
        @available(iOS 11.0, *)
        override func collectionView(_ collectionView: UICollectionView, shouldSpringLoadItemAt indexPath: IndexPath, with context: UISpringLoadedInteractionContext) -> Bool {
            return delegate.collectionDelegate?.collectionView?(collectionView, shouldSpringLoadItemAt: indexPath, with: context) ?? false
        }

        // Flow layout

        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
            return delegate.layoutDelegate?.collectionView?(collectionView, layout: collectionViewLayout, sizeForItemAt: indexPath)
                ?? (collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize
                ?? .zero
        }
        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
            return delegate.layoutDelegate?.collectionView?(collectionView, layout: collectionViewLayout, insetForSectionAt: section)
                ?? (collectionViewLayout as? UICollectionViewFlowLayout)?.sectionInset
                ?? .zero
        }
        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
            return delegate.layoutDelegate?.collectionView?(collectionView, layout: collectionViewLayout, minimumLineSpacingForSectionAt: section)
                ?? (collectionViewLayout as? UICollectionViewFlowLayout)?.minimumLineSpacing
                ?? 0
        }
        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
            return delegate.layoutDelegate?.collectionView?(collectionView, layout: collectionViewLayout, minimumInteritemSpacingForSectionAt: section)
                ?? (collectionViewLayout as? UICollectionViewFlowLayout)?.minimumInteritemSpacing
                ?? 0
        }
        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
            return delegate.layoutDelegate?.collectionView?(collectionView, layout: collectionViewLayout, referenceSizeForHeaderInSection: section)
                ?? (collectionViewLayout as? UICollectionViewFlowLayout)?.headerReferenceSize
                ?? .zero
        }
        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForFooterInSection section: Int) -> CGSize {
            return delegate.layoutDelegate?.collectionView?(collectionView, layout: collectionViewLayout, referenceSizeForFooterInSection: section)
                ?? (collectionViewLayout as? UICollectionViewFlowLayout)?.footerReferenceSize
                ?? .zero
        }
    }
}
#endif
