//
//  DynamicSection.swift
//  Pods
//
//  Created by Denis Koryttsev on 11.06.2021.
//

#if os(iOS) || os(tvOS)
#if COMBINE && canImport(Combine)
import Combine
#endif
#if canImport(Realtime)
import Realtime
#endif

#if COMBINE
public enum DynamicSectionEvent {
    case initial
    case updated(deleted: [Int], inserted: [Int], modified: [Int], moved: [(from: Int, to: Int)])
}
#elseif REALTIME_UI
#if canImport(Realtime)
public enum RCEvent {
    case initial // TODO: Rename to `value` or `full` or `reload`
    case updated(deleted: [Int], inserted: [Int], modified: [Int], moved: [(from: Int, to: Int)]) // may be [Int] replace to IndexSet?
}
#endif
public typealias DynamicSectionEvent = RCEvent
#endif

public protocol DynamicSectionDataSource {
    associatedtype Model
    #if COMBINE
    var changes: AnyPublisher<DynamicSectionEvent, Never> { get }
    #elseif REALTIME_UI
    var changes: AnyListenable<DynamicSectionEvent> { get }
    #endif
    var keepSynced: Bool { get set }
    var count: Int { get }
    subscript(index: Int) -> Model { get }
}

public struct AnyCollectionDataSource<C>: DynamicSectionDataSource where C: RandomAccessCollection {
    public typealias Model = C.Element
    public let base: C
    public init(_ base: C) { self.base = base }
    #if COMBINE
    public var changes: AnyPublisher<DynamicSectionEvent, Never> { Empty().eraseToAnyPublisher() }
    #elseif REALTIME_UI
    public var changes: AnyListenable<DynamicSectionEvent> { AnyListenable(EmptyListenable()) }
    #endif
    public var keepSynced: Bool {
        get { true }
        set { }
    }
    public var count: Int { base.count }
    public subscript(index: Int) -> Model { base[base.index(base.startIndex, offsetBy: index)] }
}

class _DSDS<Model> {
    #if COMBINE
    var changes: AnyPublisher<DynamicSectionEvent, Never> { fatalError() }
    #elseif REALTIME_UI
    var changes: AnyListenable<DynamicSectionEvent> { fatalError() }
    #endif
    var keepSynced: Bool { get { fatalError() } set {} }
    var count: Int { fatalError() }
    subscript(index: Int) -> Model { fatalError() }
}
final class __DSDS<DS>: _DSDS<DS.Model> where DS: DynamicSectionDataSource {
    var base: DS
    init(_ base: DS) {
        self.base = base
    }
    #if COMBINE
    override var changes: AnyPublisher<DynamicSectionEvent, Never> { base.changes }
    #elseif REALTIME_UI
    override var changes: AnyListenable<DynamicSectionEvent> { base.changes }
    #endif
    override var keepSynced: Bool {
        get { base.keepSynced }
        set { base.keepSynced = newValue }
    }
    override var count: Int { base.count }
    override subscript(index: Int) -> DS.Model { base[index] }
}

open class DynamicSection<Model: AnyObject, RowModel>: Section<Model> {
    typealias ViewBuilder = (UITableView, IndexPath) -> UITableViewCell
    #if COMBINE
    var updateDispose: AnyCancellable?
    #elseif REALTIME_UI
    var updateDispose: Disposable?
    #endif
    var dataSource: _DSDS<RowModel>
    public typealias Binding<Cell: AnyObject> = (Row<Cell, Model>, Cell, RowModel, IndexPath) -> Void
    public typealias ConfigureCell = (UITableView, IndexPath, RowModel) -> UITableViewCell
    fileprivate var reuseController: ReuseController<Row<UITableViewCell, Model>, UITableViewCell> = ReuseController()
    fileprivate var registeredCells: [ObjectIdentifier: Binding<UITableViewCell>] = [:]
    fileprivate var configureCell: ConfigureCell

    var tableView: UITableView?
    var section: Int?
    #if REALTIME_UI && !canImport(Realtime)
    open var scheduledUpdate: UITableView.ScheduledUpdate?
    #endif

    public typealias DidSelectEvent = (form: Form<Model>, row: Row<UITableViewCell, Model>, rowModel: RowModel)
    #if COMBINE
    fileprivate lazy var _didSelect: PassthroughSubject<DidSelectEvent, Never> = PassthroughSubject()
    #elseif REALTIME_UI
    fileprivate lazy var _didSelect: Repeater<DidSelectEvent> = .unsafe()
    #endif

    override var numberOfItems: Int { dataSource.count }

    deinit {
        dataSource.keepSynced = false
    }

    public init<DS>(
        _ dataSource: DS,
        cell viewBuilder: @escaping ConfigureCell
    ) where DS: DynamicSectionDataSource, DS.Model == RowModel {
        self.dataSource = __DSDS(dataSource)
        self.configureCell = viewBuilder
        super.init(headerTitle: nil, footerTitle: nil)
    }

    override func _hasVisibleRows(fromTop: Bool, excludingFinal cell: UITableViewCell? = nil) -> Bool {
        reuseController.activeItems.contains(where: { _, item in
            item.isVisible && item.view != cell
        })
    }

    override func buildCell(for tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        let rowModel = dataSource[indexPath.row]
        return configureCell(tableView, indexPath, rowModel)
    }

    public func register<Cell: UITableViewCell>(_ cell: Cell.Type, binding: @escaping Binding<Cell>) {
        registeredCells[ObjectIdentifier(cell)] = unsafeBitCast(binding, to: Binding<UITableViewCell>.self)
    }

    #if COMBINE
    public func selectPublisher() -> PassthroughSubject<DidSelectEvent, Never> { _didSelect }
    #elseif REALTIME_UI
    public func mapSelect() -> Repeater<DidSelectEvent> { _didSelect }
    #endif

    public func model(at indexPath: IndexPath) -> RowModel {
        dataSource[indexPath.row]
    }

    // Events

    override func willDisplayCell(_ cell: UITableViewCell, tableView: UITableView, at indexPath: IndexPath, with model: Model) {
        super.willDisplayCell(cell, tableView: tableView, at: indexPath, with: model)
        guard let bind = registeredCells[ObjectIdentifier(type(of: cell))] else {
            fatalError("Unregistered cell with type \(type(of: cell))")
        }
        let item = reuseController.dequeue(at: cell, rowBuilder: Row.init)
        if !item.state.contains(.displaying) || item.view !== cell {
            let rowModel = dataSource[indexPath.row]
            item.view = cell
            item.model = model
            item.indexPath = indexPath
            item.state.insert(.displaying)
            item.state.remove(.free)

            bind(item, cell, rowModel, indexPath)
        }
    }

    override func didEndDisplayCell(_ cell: UITableViewCell, tableView: UITableView, at indexPath: IndexPath) {
        super.didEndDisplayCell(cell, tableView: tableView, at: indexPath)
        if let row = reuseController.free(at: cell) {
            row.state.remove(.displaying)
            row.state.insert([.pending, .free])
        }
    }

    override func didSelect(_ form: Form<Model>, didSelectRowAt indexPath: IndexPath) {
        if let cell = form.tableView?.cellForRow(at: indexPath), let row = reuseController.active(at: cell) {
            _didSelect.send((form, row, dataSource[indexPath.row]))
            row.didSelect(form, didSelectRowAt: indexPath)
        }
    }

    override func willDisplay(_ tableView: UITableView, at index: Int) {
        super.willDisplay(tableView, at: index)
        self.tableView = tableView
        self.section = index
        #if COMBINE
        updateDispose?.cancel()
        #elseif REALTIME_UI
        updateDispose?.dispose()
        #endif

        #if COMBINE || canImport(Realtime)
        let handler: (DynamicSectionEvent) -> Void = { [weak tableView] e in
            guard let tv = tableView else { return }
            tv.beginUpdates()
            switch e {
            case .initial:
                tv.reloadSections([index], with: .automatic)
            case .updated(let deleted, let inserted, let modified, let moved): // TODO: After update rows have invalid `indexPath` property
                tv.insertRows(at: inserted.map { IndexPath(row: $0, section: index) }, with: .automatic)
                tv.deleteRows(at: deleted.map { IndexPath(row: $0, section: index) }, with: .automatic)
                tv.reloadRows(at: modified.map { IndexPath(row: $0, section: index) }, with: .automatic)
                moved.forEach({ (move) in
                    tv.moveRow(at: IndexPath(row: move.from, section: index), to: IndexPath(row: move.to, section: index))
                })
            }
            tv.endUpdates()
        }
        #if COMBINE
        updateDispose = dataSource.changes.sink(receiveValue: handler)
        #else
        updateDispose = dataSource.changes.listening(onValue: handler)
        #endif
        #elseif REALTIME_UI
        let onValue: (DynamicSectionEvent) -> Void = { [weak tableView, unowned self] e in
            guard let tv = tableView else { return }
            switch e {
            case .initial:
                tv.beginUpdates()
                tv.reloadSections([index], with: .automatic)
                tv.endUpdates()
            case .updated(let deleted, let inserted, let modified, let moved):
                var changes: [(IndexPath, UITableView.Operation)] = []
                inserted.forEach({ row in
                    let ip = IndexPath(row: row, section: index)
                    if self.scheduledUpdate?.fulfill(ip) ?? false {
                    } else {
                        changes.append((ip, .insert))
                    }
                })
                deleted.forEach({ row in
                    let ip = IndexPath(row: row, section: index)
                    if self.scheduledUpdate?.fulfill(ip) ?? false {
                    } else {
                        changes.append((ip, .delete))
                    }
                })
                modified.forEach({ row in
                    let ip = IndexPath(row: row, section: index)
                    if self.scheduledUpdate?.fulfill(ip) ?? false {
                    } else {
                        changes.append((ip, .reload))
                    }
                })
                moved.forEach({ (move) in
                    let ip = IndexPath(row: move.from, section: index)
                    if self.scheduledUpdate?.fulfill(ip) ?? false {
                    } else {
                        changes.append((ip, .move(IndexPath(row: move.to, section: index))))
                    }
                })
                if changes.contains(where: { $0.1.isActive }) {
                    tv.beginUpdates()
                    changes.forEach({ (ip, operation) in
                        tv.scheduleOperation(operation, for: ip, with: .automatic)
                    })
                    self.scheduledUpdate?.batchUpdatesIfFulfilled(in: tv)
                    self.scheduledUpdate = nil
                    tv.endUpdates()
                } else if self.scheduledUpdate?.isReadyToUpdate ?? false {
                    tv.beginUpdates()
                    self.scheduledUpdate?.batchUpdatesIfFulfilled(in: tv)
                    self.scheduledUpdate = nil
                    tv.endUpdates()
                }
            }
        }
        updateDispose = dataSource.changes.listening(
            onValue: onValue,
            onError: { error in
                #if !canImport(Realtime)
                debugPrintLog(String(describing: error))
                #endif
            }
        )
        #endif

        dataSource.keepSynced = true
    }

    override func didEndDisplay(_ tableView: UITableView, at index: Int) {
        super.didEndDisplay(tableView, at: index)
        self.tableView = nil
        self.section = index
        if let d = updateDispose {
            #if COMBINE
            d.cancel()
            #elseif REALTIME_UI
            d.dispose()
            #endif
            updateDispose = nil
        }
    }

    // Collection

    override open var startIndex: Int { 0 }
    override open var endIndex: Int { reuseController.activeItems.count }
    override open func index(after i: Int) -> Int { i + 1 }
    override open func index(before i: Int) -> Int { i - 1 }
    override open subscript(position: Int) -> Row<UITableViewCell, Model> {
        guard let tv = tableView, let section = self.section else { fatalError("Section is not displaying") }
        guard let cell = tv.cellForRow(at: IndexPath(row: position, section: section)), let row = reuseController.active(at: cell)
        else { fatalError("Current row is not displaying") }
        return row
    }
}
#endif
