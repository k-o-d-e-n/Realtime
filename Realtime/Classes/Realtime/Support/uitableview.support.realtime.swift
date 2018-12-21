
//
//  RealtimeTableViewDelegate.swift
//  LinkInTeam
//
//  Created by Denis Koryttsev on 24/06/2018.
//  Copyright © 2018 Denis Koryttsev. All rights reserved.
//

import UIKit

protocol ReuseItemProtocol {
    func free()
}

open class ReuseItem<View: AnyObject>: ReuseItemProtocol {
    lazy var _view: ValueStorage<View?> = ValueStorage.unsafe(weak: nil, dispatcher: .queue(.main))
    public var disposeStorage: ListeningDisposeStore = ListeningDisposeStore()

    open internal(set) weak var view: View? {
        set {
            if self._view.value !== newValue {
                reload()
            }
            self._view.value = newValue
        }
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
    public func bind<T: Listenable, S: RealtimeValueActions>(_ value: T, _ source: S, _ assign: @escaping (View, T.Out) -> Void) {
        // current function requires the call on each willDisplay event.
        // TODO: On rebinding will not call listeningItem in Property<...>, because Accumulator call listening once and only
        value.listening(Closure.guarded(self, assign: { (val, owner) in
            if let view = owner._view.value, let v = val.value {
                assign(view, v)
            }
        })).add(to: disposeStorage)

        guard source.canObserve else { return }
        if source.runObserving() {
            ListeningDispose(source.stopObserving).add(to: disposeStorage)
        } else {
            debugFatalError("Observing is not running")
        }
    }

    public func bind<T: Listenable>(_ value: T, sources: [RealtimeValueActions], _ assign: @escaping (View, T.Out) -> Void) {
        // current function requires the call on each willDisplay event.
        // TODO: On rebinding will not call listeningItem in Property<...>, because Accumulator call listening once and only
        value.listening(Closure.guarded(self, assign: { (val, owner) in
            if let view = owner._view.value, let v = val.value {
                assign(view, v)
            }
        })).add(to: disposeStorage)

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
    public func bind<T: Listenable & RealtimeValueActions>(_ value: T, _ assign: @escaping (View, T.Out) -> Void) {
        bind(value, value, assign)
    }

    /// Sets value immediatelly when view will be received
    ///
    /// - Parameters:
    ///   - value: Some value
    ///   - assign: Closure that calls on receive view
    public func set<T>(_ value: T, _ assign: @escaping (View, T) -> Void) {
        // current function does not require the call on each willDisplay event. It can call only on initialize `ReuseItem`.
        // But for it, need to separate dispose storages on iterated and permanent.
        _view.value.map { assign($0, value) }
        _view.compactMap().listening(onValue: { assign($0, value) }).add(to: disposeStorage)
    }

    public func set<T: Listenable>(_ value: T, _ assign: @escaping (View, T.Out) -> Void) {
        value.listening(Closure.guarded(self, assign: { (val, owner) in
            if let view = owner._view.value, let v = val.value {
                assign(view, v)
            }
        })).add(to: disposeStorage)
    }

    /// Adds configuration block that will be called on receive view
    ///
    /// - Parameters:
    ///   - config: Closure to configure view
    public func set(config: @escaping (View) -> Void) {
        // by analogue with `set(_:_:)` function
        _view.value.map(config)
        _view.compactMap().listening(onValue: config).add(to: disposeStorage)
    }

    func free() {
        disposeStorage.dispose()
        _view.value = nil
    }

    open func reload() {
        disposeStorage.resume()
    }
}

class ReuseController<View: AnyObject, Key: Hashable> {
    private var freeItems: [ReuseItem<View>] = []
    private var activeItems: [Key: ReuseItem<View>] = [:]

    deinit {
        free()
    }

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
            else { return debugLog("Try free non-active reuse item by key \(key)") } //fatalError("Try free non-active reuse item") }
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

    func free() {
        activeItems.forEach({ $0.value.free() })
        activeItems.removeAll()
        freeItems.removeAll()
    }

//    func exchange(indexPath: IndexPath, to ip: IndexPath) {
//        swap(&items[indexPath], &items[ip])
//    }
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

/// A proxy base class that provides tools to manage UITableView reactively.
open class RealtimeTableViewDelegate<Model, Section> {
    public typealias BindingCell<Cell: AnyObject> = (ReuseItem<Cell>, Model, IndexPath) -> Void
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

    deinit {
        reuseController.free()
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

    open func reload() {
        // TODO: Implement reload as call `func reload()` on each active `ReuseItem`
    }
}

/// A class that provides tools to manage UITableView data source reactively.
public final class SingleSectionTableViewDelegate<Model>: RealtimeTableViewDelegate<Model, Void> {
    fileprivate lazy var delegateService: Service = Service(self)
    public var headerView: UIView?

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

    public func setNewData<C: BidirectionalCollection>(_ newData: C) where C.Element == Model, C.Index == Int {
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
    class Service: _TableViewSectionedAdapter {
        unowned let delegate: SingleSectionTableViewDelegate<Model>

        init(_ delegate: SingleSectionTableViewDelegate<Model>) {
            self.delegate = delegate
        }

        override func numberOfSections(in tableView: UITableView) -> Int {
            return 1
        }

        override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
            return delegate.headerView
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
            return delegate.tableDelegate?.tableView?(tableView, heightForRowAt: indexPath) ??
                (tableView.rowHeight != UITableView.automaticDimension ? tableView.rowHeight : 44.0)
        }

        override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
            return delegate.tableDelegate?.tableView?(tableView, heightForHeaderInSection: section) ??
                delegate.headerView?.frame.height ??
                (tableView.sectionHeaderHeight != UITableView.automaticDimension ? tableView.sectionHeaderHeight : 0.0)
        }

        /// events
        override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            let item = delegate.reuseController.dequeueItem(at: indexPath)
            guard let bind = delegate.registeredCells[cell.typeKey] else {
                fatalError("Unregistered cell by type \(type(of: cell))")
            }

            let model = delegate.collection[indexPath.row]
            item.view = cell
            bind(item, model, indexPath)

            delegate.tableDelegate?.tableView?(tableView, willDisplay: cell, forRowAt: indexPath)
        }

        override func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            delegate.reuseController.free(at: indexPath)
            delegate.tableDelegate?.tableView?(tableView, didEndDisplaying: cell, forRowAt: indexPath)
        }

        override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            delegate.tableDelegate?.tableView?(tableView, didSelectRowAt: indexPath)
        }

        override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
            return delegate.tableDelegate?.tableView?(tableView, editingStyleForRowAt: indexPath) ?? .delete
        }

        override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
            delegate.editingDataSource?.tableView(tableView, commit: editingStyle, forRowAt: indexPath)
        }

        // MARK: UIScrollView

        override func scrollViewDidScroll(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewDidScroll?(scrollView)
        }

        override func scrollViewDidZoom(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewDidZoom?(scrollView)
        }

        override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewWillBeginDragging?(scrollView)
        }

        override func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
            delegate.tableDelegate?.scrollViewWillEndDragging?(scrollView, withVelocity: velocity, targetContentOffset: targetContentOffset)
        }

        override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            delegate.tableDelegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
        }

        override func scrollViewWillBeginDecelerating(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewWillBeginDecelerating?(scrollView)
        }

        override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewDidEndDecelerating?(scrollView)
        }

        override func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewDidEndScrollingAnimation?(scrollView)
        }

        override func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return delegate.tableDelegate?.viewForZooming?(in: scrollView)
        }

        override func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            delegate.tableDelegate?.scrollViewWillBeginZooming?(scrollView, with: view)
        }

        override func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            delegate.tableDelegate?.scrollViewDidEndZooming?(scrollView, with: view, atScale: scale)
        }

        override func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
            return delegate.tableDelegate?.scrollViewShouldScrollToTop?(scrollView) ?? true
        }

        override func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewDidScrollToTop?(scrollView)
        }

        @available(iOS 11.0, *)
        override func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
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

    func willDisplaySection(_ tableView: UITableView, items: AnyRealtimeCollection<Model>, at index: Int) {
        items.changes.listening(onValue: { [weak tableView] e in
            guard let tv = tableView else { return }
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
        }).add(to: disposeStorage)
        self.items = items
    }

    func endDisplaySection(_ tableView: UITableView, at index: Int) {
        guard let itms = items else { return debugLog("Ends display section that already not visible") }
        debugFatalError(condition: !itms.isObserved, "Trying to stop observing of section, but it is no longer observed")
        items = nil
    }

    override func free() {
        super.free()
        items = nil
    }
}

public final class SectionedTableViewDelegate<Model, Section>: RealtimeTableViewDelegate<Model, Section> {
    public typealias BindingSection<View: AnyObject> = (ReuseSection<Model, View>, Section, Int) -> Void
    public typealias ConfigureSection = (UITableView, Int) -> UIView?
    fileprivate var configureSection: ConfigureSection
    fileprivate var registeredHeaders: [TypeKey: BindingSection<UIView>] = [:]
    fileprivate var reuseSectionController: ReuseRowController<ReuseSection<Model, UIView>, Int> = ReuseRowController()
    fileprivate lazy var delegateService: Service = Service(self)
    var sections: AnySharedCollection<Section> {
        willSet {
            sections.lazy.map(models).forEach { $0.keepSynced = false }
        }
    }
    let models: (Section) -> AnyRealtimeCollection<Model>

    public init<C: BidirectionalCollection>(_ sections: C,
                                            _ models: @escaping (Section) -> AnyRealtimeCollection<Model>,
                                            cell: @escaping ConfigureCell,
                                            section: @escaping ConfigureSection)
        where C.Element == Section, C.Index == Int {
            self.sections = AnySharedCollection(sections)
            self.models = models
            self.configureSection = section
            super.init(cell: cell)
    }

    deinit {
        reuseSectionController.free()
        sections.lazy.map(models).forEach { $0.keepSynced = false }
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
        guard let items = reuseSectionController.activeItem(at: indexPath.section)?.items else {
            return models(sections[indexPath.section])[indexPath.row]
        }

        return items[indexPath.row]
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

    public func setNewData<C: BidirectionalCollection>(_ newData: C) where C.Element == Section, C.Index == Int {
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
    class Service: _TableViewSectionedAdapter {
        var oldOffset: CGFloat = 0.0
        unowned let delegate: SectionedTableViewDelegate<Model, Section>

        init(_ delegate: SectionedTableViewDelegate<Model, Section>) {
            self.delegate = delegate
        }

        override func numberOfSections(in tableView: UITableView) -> Int {
            return delegate.sections.count
        }

        override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            return delegate.models(delegate.sections[section]).count
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
            return delegate.tableDelegate?.tableView?(tableView, heightForHeaderInSection: section) ??
                (tableView.sectionHeaderHeight != UITableView.automaticDimension ? tableView.sectionHeaderHeight : 35.0)
        }

        override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
            return delegate.tableDelegate?.tableView?(tableView, heightForRowAt: indexPath) ??
                (tableView.rowHeight != UITableView.automaticDimension ? tableView.rowHeight : 44.0)
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
            item.view = cell
            bind(item, model, indexPath)

            delegate.tableDelegate?.tableView?(tableView, willDisplay: cell, forRowAt: indexPath)

//            guard
//                delegate.sections.count > indexPath.section + 1,
//                let items = delegate.reuseSectionController.activeItem(at: indexPath.section)?.items,
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

        override func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            delegate.reuseController.free(at: indexPath)
            delegate.tableDelegate?.tableView?(tableView, didEndDisplaying: cell, forRowAt: indexPath)

//            var endDisplaySection: Bool {
//                if oldOffset > tableView.contentOffset.y {
//                    if let items = delegate.reuseSectionController.activeItem(at: indexPath.section)?.items {
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
//            guard endDisplaySection, let sectionItem = delegate.reuseSectionController.activeItem(at: indexPath.section) else { return }
//
//            sectionItem.endDisplaySection(tableView, at: indexPath.section)
//            sectionItem.free()
        }

        override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            delegate.tableDelegate?.tableView?(tableView, didSelectRowAt: indexPath)
        }

        override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
            let item = delegate.reuseSectionController.dequeueItem(at: section, rowBuilder: ReuseSection.init)
            guard let bind = delegate.registeredHeaders[TypeKey.for(type(of: view))] else {
                fatalError("Unregistered header by type \(type(of: view))")
            }
            let model = delegate.sections[section]
            item.view = view
            bind(item, model, section)

            if item.isNotBeingDisplay {
                item.willDisplaySection(tableView, items: delegate.models(delegate.sections[section]), at: section)
            }

            delegate.tableDelegate?.tableView?(tableView, willDisplayHeaderView: view, forSection: section)
        }

        override func tableView(_ tableView: UITableView, didEndDisplayingHeaderView view: UIView, forSection section: Int) {
            delegate.tableDelegate?.tableView?(tableView, didEndDisplayingHeaderView: view, forSection: section)

            guard let sectionItem = delegate.reuseSectionController.activeItem(at: section) else { return }

            sectionItem.endDisplaySection(tableView, at: section)
            sectionItem.free()
        }

        override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
            return delegate.tableDelegate?.tableView?(tableView, editingStyleForRowAt: indexPath) ?? .delete
        }

        override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
            delegate.editingDataSource?.tableView(tableView, commit: editingStyle, forRowAt: indexPath)
        }

//        override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
//            delegate.editingDataSource?.tableView(tableView, moveRowAt: sourceIndexPath, to: destinationIndexPath)
//        }

        // MARK: UIScrollView

        override func scrollViewDidScroll(_ scrollView: UIScrollView) {
            oldOffset = scrollView.contentOffset.y
            delegate.tableDelegate?.scrollViewDidScroll?(scrollView)
        }

        override func scrollViewDidZoom(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewDidZoom?(scrollView)
        }

        override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewWillBeginDragging?(scrollView)
        }

        override func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
            delegate.tableDelegate?.scrollViewWillEndDragging?(scrollView, withVelocity: velocity, targetContentOffset: targetContentOffset)
        }

        override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            delegate.tableDelegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
        }

        override func scrollViewWillBeginDecelerating(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewWillBeginDecelerating?(scrollView)
        }

        override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewDidEndDecelerating?(scrollView)
        }

        override func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewDidEndScrollingAnimation?(scrollView)
        }

        override func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return delegate.tableDelegate?.viewForZooming?(in: scrollView)
        }

        override func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            delegate.tableDelegate?.scrollViewWillBeginZooming?(scrollView, with: view)
        }

        override func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            delegate.tableDelegate?.scrollViewDidEndZooming?(scrollView, with: view, atScale: scale)
        }

        override func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
            return delegate.tableDelegate?.scrollViewShouldScrollToTop?(scrollView) ?? true
        }

        override func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewDidScrollToTop?(scrollView)
        }

        @available(iOS 11.0, *)
        override func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
            delegate.tableDelegate?.scrollViewDidChangeAdjustedContentInset?(scrollView)
        }
    }
}
