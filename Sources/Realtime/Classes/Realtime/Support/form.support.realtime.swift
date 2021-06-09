//
//  form.support.realtime.swift
//  Realtime
//
//  Created by Denis Koryttsev on 11/09/2018.
//

#if os(iOS)
import UIKit
#if COMBINE && canImport(Combine)
import Combine
/// #elseif REALTIME && canImport(Realtime)
/// import Realtime
#endif

open class ReuseFormRow<View: AnyObject, Model: AnyObject, RowModel>: Row<View, Model> {
    #if COMBINE
    lazy var _rowModel: PassthroughSubject<RowModel, Never> = PassthroughSubject()
    #else
    lazy var _rowModel: Repeater<RowModel> = Repeater.unsafe()
    #endif

    public required init() {
        super.init(viewBuilder: .custom({ _,_  in fatalError("Reuse form row does not responsible for cell building") }))
    }

    public required init(viewBuilder: RowViewBuilder<View>) {
        fatalError("Use init() initializer instead")
    }

    public func onRowModel(_ doit: @escaping (RowModel, ReuseFormRow<View, Model, RowModel>) -> Void) {
        #if COMBINE
        _rowModel.sink(receiveValue: { [unowned self] in doit($0, self) }).store(in: &internalDispose)
        #else
        _rowModel.listening(onValue: Closure.guarded(self, assign: doit)).add(to: &internalDispose)
        #endif
    }
}

extension UITableView {
    public enum Operation {
        case reload
        case move(IndexPath)
        case insert
        case delete
        case none

        var isActive: Bool {
            if case .none = self {
                return false
            }
            return true
        }
    }

    func scheduleOperation(_ operation: Operation, for indexPath: IndexPath, with animation: UITableView.RowAnimation) {
        switch operation {
        case .none: break
        case .reload: reloadRows(at: [indexPath], with: animation)
        case .move(let ip): moveRow(at: indexPath, to: ip)
        case .insert: insertRows(at: [indexPath], with: animation)
        case .delete: deleteRows(at: [indexPath], with: animation)
        }
    }

    public class ScheduledUpdate {
        internal private(set) var events: [IndexPath: UITableView.Operation]
        var operations: [(IndexPath, UITableView.Operation)] = []
        var isReadyToUpdate: Bool { return events.isEmpty && !operations.isEmpty }

        public init(events: [IndexPath: UITableView.Operation]) {
            precondition(!events.isEmpty, "Events must not be empty")
            self.events = events
        }

        func fulfill(_ indexPath: IndexPath) -> Bool {
            if let operation = events.removeValue(forKey: indexPath) {
                operations.append((indexPath, operation))
                return true
            } else {
                return false
            }
        }

        func batchUpdatesIfFulfilled(in tableView: UITableView) {
            while !operations.isEmpty {
                let (ip, op) = operations.removeLast()
                tableView.scheduleOperation(op, for: ip, with: .automatic)
            }
        }
    }
}

#if canImport(Realtime)
public protocol DynamicSectionDataSource: AnyObject, RandomAccessCollection {
    var keepSynced: Bool { set get }
    var changes: AnyListenable<RCEvent> { get }
}

public struct ReuseRowSectionDataSource<RowModel> {
    let keepSynced: (Bool) -> Void
    let changes: AnyListenable<RCEvent>
    let collection: AnySharedCollection<RowModel>
    var isSynced: Bool = false

    public init<DS: DynamicSectionDataSource>(_ dataSource: DS) where DS.Element == RowModel {
        self.keepSynced = { dataSource.keepSynced = $0 }
        self.changes = dataSource.changes
        self.collection = AnySharedCollection(dataSource)
    }

    public init<RC: RealtimeCollection>(collection: RC) where RC.Element == RowModel, RC.View.Element: DatabaseKeyRepresentable {
        self.init(AnyRealtimeCollection(collection))
    }
}
extension AnyRealtimeCollection: DynamicSectionDataSource {}

// TODO: Try use register approach like in `CollectibleViewDelegate`, it can make possible to avoid usage of `ReuseFormRow`
open class ReuseRowSection<Model: AnyObject, RowModel>: Section<Model> {
    typealias ViewBuilder = (UITableView, IndexPath) -> UITableViewCell
    var updateDispose: Disposable?
    var reuseController: ReuseController<ReuseFormRow<UITableViewCell, Model, RowModel>, UITableViewCell> = ReuseController()
    let rowBuilder: ReuseController<ReuseFormRow<UITableViewCell, Model, RowModel>, UITableViewCell>.RowBuilder
    let viewBuilder: ViewBuilder
    var dataSource: ReuseRowSectionDataSource<RowModel>

    var tableView: UITableView?
    var section: Int?
    open var scheduledUpdate: UITableView.ScheduledUpdate?

    override var numberOfItems: Int { return dataSource.collection.count }

    deinit {
        dataSource.keepSynced(false)
    }

    public init<Cell: UITableViewCell>(
        _ dataSource: ReuseRowSectionDataSource<RowModel>,
        cell viewBuilder: @escaping (UITableView, IndexPath) -> Cell,
        row rowBuilder: @escaping () -> ReuseFormRow<Cell, Model, RowModel>
    ) {
        self.dataSource = dataSource
        self.viewBuilder = unsafeBitCast(viewBuilder, to: ViewBuilder.self)
        self.rowBuilder = unsafeBitCast(rowBuilder, to: ReuseController<ReuseFormRow<UITableViewCell, Model, RowModel>, UITableViewCell>.RowBuilder.self)
        super.init(headerTitle: nil, footerTitle: nil)
    }

    override func buildCell(for tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        return viewBuilder(tableView, indexPath)
    }

    override func dequeueRow(for cell: UITableViewCell, at index: Int) -> Row<UITableViewCell, Model> {
        let item = reuseController.dequeue(at: cell, rowBuilder: rowBuilder)
        return item
    }

    override func willDisplay(_ cell: UITableViewCell, at indexPath: IndexPath, with model: Model) {
        let item = reuseController.dequeue(at: cell, rowBuilder: rowBuilder)

        if !item.state.contains(.displaying) || item.view !== cell {
            item.view = cell
            item.model = model
            #if COMBINE
            item._rowModel.send(dataSource.collection[indexPath.row])
            #else
            item._rowModel.send(dataSource.collection[indexPath.row])
            #endif
            item.state.insert(.displaying)
            item.state.remove(.free)
        }
    }

    override func didEndDisplay(_ cell: UITableViewCell, at indexPath: IndexPath) {
        if let row = reuseController.free(at: cell) {
            row.state.remove(.displaying)
            row.state.insert([.pending, .free])
        }
    }

    override func didSelect(_ form: Form<Model>, didSelectRowAt indexPath: IndexPath) {
        if let cell = form.tableView?.cellForRow(at: indexPath) {
            reuseController.active(at: cell)?.didSelect(form, didSelectRowAt: indexPath)
        }
    }

    override func willDisplaySection(_ tableView: UITableView, at index: Int) {
        self.tableView = tableView
        self.section = index
        updateDispose?.dispose()
        updateDispose = dataSource.changes.listening(
            onValue: { [weak tableView, unowned self] e in
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
            },
            onError: { error in
                #if canImport(Realtime)
                debugPrintLog(String(describing: error))
                #endif
            }
        )

        if !dataSource.isSynced {
            dataSource.keepSynced(true)
            dataSource.isSynced = true
        }
    }

    override func didEndDisplaySection(_ tableView: UITableView, at index: Int) {
        self.tableView = nil
        self.section = index
        if let d = updateDispose {
            d.dispose()
            updateDispose = nil
        }
    }

    // Collection

    override open var startIndex: Int { return 0 }
    override open var endIndex: Int { return reuseController.activeItems.count }
    override open func index(after i: Int) -> Int {
        return i + 1
    }
    override open func index(before i: Int) -> Int {
        return i - 1
    }
    override open subscript(position: Int) -> Row<UITableViewCell, Model> {
        guard let tv = tableView, let section = self.section else { fatalError("Section is not displaying") }
        guard let cell = tv.cellForRow(at: IndexPath(row: position, section: section)), let row = reuseController.active(at: cell)
        else { fatalError("Current row is not displaying") }
        return row
    }

    public func model(at indexPath: IndexPath) -> RowModel {
        return dataSource.collection[indexPath.row]
    }
}
#endif
#endif
