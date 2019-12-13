//
//  form.support.realtime.swift
//  Realtime
//
//  Created by Denis Koryttsev on 11/09/2018.
//

#if os(iOS)
import UIKit

public enum CellBuilder<View> {
    case reuseIdentifier(String)
    case `static`(View)
    case custom((UITableView, IndexPath) -> View)
}

struct RowState: OptionSet {
    let rawValue: CShort

    init(rawValue: CShort) {
        self.rawValue = rawValue
    }
}
extension RowState {
    static let free: RowState = RowState(rawValue: 1 << 0)
    static let displaying: RowState = RowState(rawValue: 1 << 1)
    static let pending: RowState = RowState(rawValue: 1 << 2)
    static let removed: RowState = RowState(rawValue: 1 << 3)
}

@dynamicMemberLookup
open class Row<View: AnyObject, Model: AnyObject>: ReuseItem<View> {
    fileprivate var internalDispose: ListeningDisposeStore = ListeningDisposeStore()
    fileprivate lazy var _model: ValueStorage<Model?> = ValueStorage.unsafe(weak: nil, repeater: .unsafe())
    fileprivate lazy var _update: Accumulator = Accumulator(repeater: .unsafe(), _view.repeater!.compactMap(), _model.repeater!.compactMap())
    fileprivate lazy var _didSelect: Repeater<IndexPath> = .unsafe()

    var dynamicValues: [String: Any] = [:]
    var state: RowState = [.free, .pending]
    open var indexPath: IndexPath?

    open internal(set) weak var model: Model? {
        set { _model.value = newValue }
        get { return _model.value }
    }

    let cellBuilder: CellBuilder<View>

    public required init(cellBuilder: CellBuilder<View>) {
        self.cellBuilder = cellBuilder
    }
    deinit {}

    public convenience init(reuseIdentifier: String) {
        self.init(cellBuilder: .reuseIdentifier(reuseIdentifier))
    }

    open subscript<T>(dynamicMember member: String) -> T? {
        set { dynamicValues[member] = newValue }
        get { return dynamicValues[member] as? T }
    }

    open func onUpdate(_ doit: @escaping ((view: View, model: Model), Row<View, Model>) -> Void) { // TODO: Row<View, Model> replace with Self (swift 5.1)
        _update.listening(onValue: Closure.guarded(self, assign: doit)).add(to: internalDispose)
    }

    open func onSelect(_ doit: @escaping (IndexPath, Row<View, Model>) -> Void) {
        _didSelect.listening(onValue: Closure.guarded(self, assign: doit)).add(to: internalDispose)
    }

    override func free() {
        super.free()
        _model.value = nil
    }

    public func sendSelectEvent(at indexPath: IndexPath) {
        _didSelect.send(.value(indexPath))
    }

    public func removeAllValues() {
        dynamicValues.removeAll()
    }
}
extension Row where View: UITableViewCell {
    public convenience init(static view: View) {
        self.init(cellBuilder: .static(view))
    }
    internal func buildCell(for tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        switch cellBuilder {
        case .reuseIdentifier(let identifier):
            return tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)
        case .static(let cell): return cell
        case .custom(let closure): return closure(tableView, indexPath)
        }
    }
}
public extension Row where View: UIView {
    var isVisible: Bool {
        return state.contains(.displaying) && super._isVisible
    }
    internal func build(for tableView: UITableView, at section: Int) -> UIView? {
        switch cellBuilder {
        case .reuseIdentifier(let identifier):
            return tableView.dequeueReusableHeaderFooterView(withIdentifier: identifier)
        case .static(let view): return view
        case .custom(let closure): return closure(tableView, IndexPath(row: 0, section: 0))
        }
    }
}
extension Row: CustomDebugStringConvertible {
    public var debugDescription: String {
        return """
        \(type(of: self)): \(withUnsafePointer(to: self, String.init(describing:))) {
            view: \(view as Any),
            model: \(_model.value as Any),
            state: \(state),
            values: \(dynamicValues)
        }
        """
    }
}
extension Row {
    func willDisplay(with view: View, model: Model, indexPath: IndexPath) {
        if !state.contains(.displaying) || self.view !== view {
            self.indexPath = indexPath
            self.view = view
            _model.value = model
            state.insert(.displaying)
            state.remove(.free)
        }
    }
    func didEndDisplay(with view: View, indexPath: IndexPath) {
        if !state.contains(.free) && self.view === view {
            self.indexPath = nil
            state.remove(.displaying)
            free()
            state.insert([.pending, .free])
        } else {
//                debugLog("\(row.state) \n \(row.view as Any) \n\(cell)")
        }
    }
}

open class Section<Model: AnyObject>: RandomAccessCollection {
    open var footerTitle: String?
    open var headerTitle: String?
    open internal(set) var headerRow: Row<UIView, Model>?
    open internal(set) var footerRow: Row<UIView, Model>?

    var numberOfItems: Int { fatalError("override") }

    public init(headerTitle: String?, footerTitle: String?) {
        self.headerTitle = headerTitle
        self.footerTitle = footerTitle
    }

    // TODO: set_Row does not recognize with code completer
    open func setHeaderRow<V: UIView>(_ row: Row<V, Model>) {
        self.headerRow = unsafeBitCast(row, to: Row<UIView, Model>.self)
    }
    open func setFooterRow<V: UIView>(_ row: Row<V, Model>) {
        self.footerRow = unsafeBitCast(row, to: Row<UIView, Model>.self)
    }

    internal func addRow<Cell: UITableViewCell>(_ row: Row<Cell, Model>) { fatalError() }
    internal func insertRow<Cell: UITableViewCell>(_ row: Row<Cell, Model>, at index: Int) { fatalError() }
    internal func moveRow(at index: Int, to newIndex: Int) { fatalError() }
    @discardableResult
    internal func deleteRow(at index: Int) -> Row<UITableViewCell, Model> { fatalError() }

    func buildCell(for tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell { fatalError() }
    func dequeueRow(for cell: UITableViewCell, at index: Int) -> Row<UITableViewCell, Model> { fatalError() }
    func reloadCell(at indexPath: IndexPath) { fatalError() }
    func willDisplay(_ cell: UITableViewCell, at indexPath: IndexPath, with model: Model) {}
    func didEndDisplay(_ cell: UITableViewCell, at indexPath: IndexPath) {}
    func didSelect(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {}

    func willDisplaySection(_ tableView: UITableView, at index: Int) { fatalError("override") }
    func didEndDisplaySection(_ tableView: UITableView, at index: Int) { fatalError("override") }

    func willDisplayHeaderView(_ view: UIView, at section: Int, with model: Model) {
        headerRow?.willDisplay(with: view, model: model, indexPath: IndexPath(row: -1, section: section))
    }
    func didEndDisplayHeaderView(_ view: UIView, at section: Int, with model: Model) {
        headerRow?.didEndDisplay(with: view, indexPath: IndexPath(row: -1, section: section))
    }
    func willDisplayFooterView(_ view: UIView, at section: Int, with model: Model) {
        footerRow?.willDisplay(with: view, model: model, indexPath: IndexPath(row: .max, section: section))
    }
    func didEndDisplayFooterView(_ view: UIView, at section: Int, with model: Model) {
        footerRow?.didEndDisplay(with: view, indexPath: IndexPath(row: .max, section: section))
    }

    public typealias Element = Row<UITableViewCell, Model>
    open var startIndex: Int { fatalError("override") }
    open var endIndex: Int { fatalError("override") }
    open func index(after i: Int) -> Int {
        fatalError("override")
    }
    open func index(before i: Int) -> Int {
        fatalError("override")
    }
    open subscript(position: Int) -> Row<UITableViewCell, Model> {
        fatalError("override")
    }
}
public extension Section {
    var visibleIndexPaths: [IndexPath] {
        return compactMap({ $0.indexPath })
    }
}

open class StaticSection<Model: AnyObject>: Section<Model> {
    var rows: [Row<UITableViewCell, Model>] = []
    var removedRows: [Int: Row<UITableViewCell, Model>] = [:]

    override var numberOfItems: Int { return rows.count }

    override func buildCell(for tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        return rows[indexPath.row].buildCell(for: tableView, at: indexPath)
    }

    override func dequeueRow(for cell: UITableViewCell, at index: Int) -> Row<UITableViewCell, Model> {
        return rows[index]
    }

    override open func addRow<Cell: UITableViewCell>(_ row: Row<Cell, Model>) {
        insertRow(row, at: rows.count)
    }

    override open func insertRow<Cell: UITableViewCell>(_ row: Row<Cell, Model>, at index: Int) {
        rows.insert(unsafeBitCast(row, to: Row<UITableViewCell, Model>.self), at: index)
    }

    override open func moveRow(at index: Int, to newIndex: Int) {
        rows.insert(rows.remove(at: index), at: newIndex)
    }

    @discardableResult
    override open func deleteRow(at index: Int) -> Row<UITableViewCell, Model> {
        let removed = rows.remove(at: index)
        removedRows[index] = removed
        removed.state.insert(.removed)
        return removed
    }

    override func didEndDisplay(_ cell: UITableViewCell, at indexPath: IndexPath) {
        if let removed = removedRows.removeValue(forKey: indexPath.row) {
            removed.state.remove(.displaying)
            if !removed.state.contains(.free) {
                removed.free()
                removed.state.insert(.free)
            }
        } else if rows.indices.contains(indexPath.row) {
            let row = rows[indexPath.row]
            row.didEndDisplay(with: cell, indexPath: indexPath)
        }
    }

    override func willDisplay(_ cell: UITableViewCell, at indexPath: IndexPath, with model: Model) {
        let item = rows[indexPath.row]
        item.willDisplay(with: cell, model: model, indexPath: indexPath)
    }

    override func willDisplaySection(_ tableView: UITableView, at index: Int) {}
    override func didEndDisplaySection(_ tableView: UITableView, at index: Int) {}

    override func didSelect(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        rows[indexPath.row]._didSelect.send(.value(indexPath))
    }

    override func reloadCell(at indexPath: IndexPath) {
        let row = rows[indexPath.row]
        if row.isVisible {
            // TODO: Current action is insufficiently
            row.view = row.view
        }
    }

    // Collection

    override open var startIndex: Int { return rows.startIndex }
    override open var endIndex: Int { return rows.endIndex }
    override open func index(after i: Int) -> Int {
        return rows.index(after: i)
    }
    override open func index(before i: Int) -> Int {
        return rows.index(before: i)
    }
    override open subscript(position: Int) -> Row<UITableViewCell, Model> {
        return rows[position]
    }
}

open class ReuseFormRow<View: AnyObject, Model: AnyObject, RowModel>: Row<View, Model> {
    lazy var _rowModel: Repeater<RowModel> = Repeater.unsafe()

    public required init() {
        super.init(cellBuilder: .custom({ _,_  in fatalError("Reuse form row does not responsible for cell building") }))
    }

    public required init(cellBuilder: CellBuilder<View>) {
        fatalError("Use init() initializer instead")
    }

    public func onRowModel(_ doit: @escaping (RowModel, ReuseFormRow<View, Model, RowModel>) -> Void) {
        _rowModel.listening(onValue: Closure.guarded(self, assign: doit)).add(to: internalDispose)
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

public protocol DynamicSectionDataSource: class, RandomAccessCollection {
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

open class ReuseRowSection<Model: AnyObject, RowModel>: Section<Model> {
    typealias CellBuilder = (UITableView, IndexPath) -> UITableViewCell
    var updateDispose: Disposable?
    var reuseController: ReuseController<ReuseFormRow<UITableViewCell, Model, RowModel>, UITableViewCell> = ReuseController()
    let rowBuilder: ReuseController<ReuseFormRow<UITableViewCell, Model, RowModel>, UITableViewCell>.RowBuilder
    let cellBuilder: CellBuilder
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
        cell cellBuilder: @escaping (UITableView, IndexPath) -> Cell,
        row rowBuilder: @escaping () -> ReuseFormRow<Cell, Model, RowModel>
    ) {
        self.dataSource = dataSource
        self.cellBuilder = unsafeBitCast(cellBuilder, to: CellBuilder.self)
        self.rowBuilder = unsafeBitCast(rowBuilder, to: ReuseController<ReuseFormRow<UITableViewCell, Model, RowModel>, UITableViewCell>.RowBuilder.self)
        super.init(headerTitle: nil, footerTitle: nil)
    }

    override func buildCell(for tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        return cellBuilder(tableView, indexPath)
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
            item._rowModel.send(.value(dataSource.collection[indexPath.row]))
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

    override func didSelect(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let cell = tableView.cellForRow(at: indexPath) {
            reuseController.active(at: cell)?._didSelect.send(.value(indexPath))
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
                debugPrintLog(String(describing: error))
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

open class Form<Model: AnyObject> {
    lazy var table: Table = Table(self)
    var sections: [Section<Model>]
    var removedSections: [Int: Section<Model>] = [:]
    var performsUpdates: Bool = false

    open var numberOfSections: Int {
        return sections.count
    }

    open weak var tableDelegate: UITableViewDelegate?
    open weak var editingDataSource: RealtimeEditingTableDataSource?
    open weak var prefetchingDataSource: UITableViewDataSourcePrefetching?

    open var model: Model
    open weak var tableView: UITableView? {
        willSet {
            if newValue == nil {
                tableView?.delegate = nil
                tableView?.dataSource = nil
            }
        }
        didSet {
            if let tv = tableView {
                tv.delegate = table
                tv.dataSource = table
            }
        }
    }

    public init(model: Model, sections: [Section<Model>]) {
        self.model = model
        self.sections = sections
    }

    open func numberOfItems(in section: Int) -> Int {
        return sections[section].count
    }

    open func beginUpdates() {
        guard let tv = tableView else { fatalError() }
        guard tv.window != nil else { return }
        tv.beginUpdates()
        performsUpdates = true
    }

    open func endUpdates() {
        guard let tv = tableView else { fatalError() }
        guard performsUpdates else { return }
        tv.endUpdates()
        performsUpdates = false
    }

    open func addRow<Cell: UITableViewCell>(
        _ row: Row<Cell, Model>, with animation: UITableView.RowAnimation = .automatic
        ) {
        guard let last = self.last else { fatalError("Form is empty") }
        let rowIndex = last.numberOfItems
        last.addRow(row)
        if performsUpdates {
            tableView?.insertRows(at: [IndexPath(row: rowIndex, section: numberOfSections - 1)], with: animation)
        }
    }

    open func insertRow<Cell: UITableViewCell>(
        _ row: Row<Cell, Model>, at indexPath: IndexPath, with animation: UITableView.RowAnimation = .automatic
        ) {
        sections[indexPath.section].insertRow(row, at: indexPath.row)
        if performsUpdates { tableView?.insertRows(at: [indexPath], with: animation) }
    }

    open func deleteRows(at indexPaths: [IndexPath], with animation: UITableView.RowAnimation = .automatic) {
        indexPaths.sorted(by: >).forEach { sections[$0.section].deleteRow(at: $0.row) }
        if performsUpdates { tableView?.deleteRows(at: indexPaths, with: animation) }
    }

    open func moveRow(at indexPath: IndexPath, to newIndexPath: IndexPath) {
        if indexPath.section == newIndexPath.section {
            sections[indexPath.section].moveRow(at: indexPath.row, to: newIndexPath.row)
        } else {
            let row = sections[indexPath.section].deleteRow(at: indexPath.row)
            sections[newIndexPath.section].insertRow(row, at: newIndexPath.row)
        }
        if performsUpdates { tableView?.moveRow(at: indexPath, to: newIndexPath) }
    }

    open func addSection(_ section: Section<Model>, with animation: UITableView.RowAnimation = .automatic) {
        insertSection(section, at: sections.count, with: animation)
    }

    open func insertSection(_ section: Section<Model>, at index: Int, with animation: UITableView.RowAnimation = .automatic) {
        sections.insert(section, at: index)
        if let tv = tableView, tv.window != nil {
            tv.insertSections([index], with: animation)
        }
    }

    open func deleteSections(at indexes: IndexSet, with animation: UITableView.RowAnimation = .automatic) {
        indexes.reversed().forEach { removedSections[$0] = sections.remove(at: $0) }
        if performsUpdates { tableView?.deleteSections(indexes, with: animation) }
    }

    open func reloadRows(at indexPaths: [IndexPath], with animation: UITableView.RowAnimation = .automatic) {
        if performsUpdates, let tv = tableView, tv.window != nil {
            tv.reloadRows(at: indexPaths, with: animation)
        }
    }

    open func reloadSections(_ sections: IndexSet, with animation: UITableView.RowAnimation = .automatic) {
        if performsUpdates, let tv = tableView, tv.window != nil {
            tv.reloadSections(sections, with: animation)
        }
    }

    open func didSelect(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        sections[indexPath.section].didSelect(tableView, didSelectRowAt: indexPath)
    }

    open func reloadVisible() {
        if let tv = tableView {
            tv.indexPathsForVisibleRows?.forEach({ (ip) in
                sections[ip.section].reloadCell(at: ip)
            })
        }
    }
}
extension Form: RandomAccessCollection {
    public typealias Element = Section<Model>
    public var startIndex: Int { return sections.startIndex }
    public var endIndex: Int { return sections.endIndex }
    public func index(after i: Int) -> Int {
        return sections.index(after: i)
    }
    public func index(before i: Int) -> Int {
        return sections.index(before: i)
    }
    public subscript(position: Int) -> Section<Model> {
        return sections[position]
    }
}
extension Form {
    final class Table: NSObject, UITableViewDelegate, UITableViewDataSource {
        unowned var form: Form

        init(_ form: Form) {
            self.form = form
        }

        func numberOfSections(in tableView: UITableView) -> Int {
            return form.numberOfSections
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            return form.sections[section].numberOfItems
        }

        func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
            return form.tableDelegate?.tableView?(tableView, heightForRowAt: indexPath) ?? tableView.rowHeight
        }

        func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
            return form.tableDelegate?.tableView?(tableView, heightForHeaderInSection: section) ?? tableView.sectionHeaderHeight
        }

        func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
            return form.tableDelegate?.tableView?(tableView, heightForFooterInSection: section) ?? tableView.sectionFooterHeight
        }

        func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
            return form.sections[section].headerTitle
        }

        func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
            return form.sections[section].headerRow?.build(for: tableView, at: section)
        }

        func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
            return form.sections[section].footerTitle
        }

        func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
            return form.sections[section].footerRow?.build(for: tableView, at: section)
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            return form.sections[indexPath.section].buildCell(for: tableView, at: indexPath)
        }

        func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            form.sections[indexPath.section].willDisplay(cell, at: indexPath, with: form.model)
        }

        func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            if let removed = form.removedSections[indexPath.section] {
                removed.didEndDisplay(cell, at: indexPath)
                if tableView.indexPathsForVisibleRows.map({ !$0.contains(where: { $0.section == indexPath.section }) }) ?? true {
                    form.removedSections.removeValue(forKey: indexPath.section)
                }
            } else if form.sections.indices.contains(indexPath.section) {
                form.sections[indexPath.section].didEndDisplay(cell, at: indexPath)
            }
        }

        // (will/didEnd)DisplaySection calls only for header, but it doesn't correct
        func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
            let s = form[section]
            s.willDisplaySection(tableView, at: section) // if section has no header willDisplay won't called
            s.willDisplayHeaderView(view, at: section, with: form.model)
            form.tableDelegate?.tableView?(tableView, willDisplayHeaderView: view, forSection: section)
        }

        func tableView(_ tableView: UITableView, didEndDisplayingHeaderView view: UIView, forSection section: Int) {
            let s = form[section]
            s.didEndDisplaySection(tableView, at: section)
            s.didEndDisplayHeaderView(view, at: section, with: form.model)
            form.tableDelegate?.tableView?(tableView, didEndDisplayingHeaderView: view, forSection: section)
        }

        func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
            let s = form[section]
            s.willDisplayFooterView(view, at: section, with: form.model)
            form.tableDelegate?.tableView?(tableView, willDisplayFooterView: view, forSection: section)
        }

        func tableView(_ tableView: UITableView, didEndDisplayingFooterView view: UIView, forSection section: Int) {
            let s = form[section]
            s.didEndDisplayFooterView(view, at: section, with: form.model)
            form.tableDelegate?.tableView?(tableView, didEndDisplayingFooterView: view, forSection: section)
        }

        func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
            return form.tableDelegate?.tableView?(tableView, shouldHighlightRowAt: indexPath) ?? true
        }

        func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
            return form.tableDelegate?.tableView?(tableView, willSelectRowAt: indexPath) ?? indexPath
        }

        func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            tableView.endEditing(false)
            form.didSelect(tableView, didSelectRowAt: indexPath)
            form.tableDelegate?.tableView?(tableView, didSelectRowAt: indexPath)
        }

        func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
            form.tableDelegate?.tableView?(tableView, didDeselectRowAt: indexPath)
        }

        func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
            return form.editingDataSource?.tableView(tableView, canEditRowAt: indexPath) ?? true
        }

        func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
            return form.editingDataSource?.tableView(tableView, canMoveRowAt: indexPath) ?? true
        }

        func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
            return form.tableDelegate.flatMap { $0.tableView?(tableView, shouldIndentWhileEditingRowAt: indexPath) } ?? true
        }

        func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
            return form.tableDelegate.flatMap { $0.tableView?(tableView, editingStyleForRowAt: indexPath) } ?? .none
        }

        func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
            form.editingDataSource?.tableView(tableView, commit: editingStyle, forRowAt: indexPath)
        }

        func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
            form.editingDataSource?.tableView(tableView, moveRowAt: sourceIndexPath, to: destinationIndexPath)
        }

        func tableView(
            _ tableView: UITableView,
            targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
            toProposedIndexPath proposedDestinationIndexPath: IndexPath
        ) -> IndexPath {
            return form.editingDataSource?.tableView(
                tableView,
                targetIndexPathForMoveFromRowAt: sourceIndexPath,
                toProposedIndexPath: proposedDestinationIndexPath
            )
            ?? proposedDestinationIndexPath
        }

        // MARK: UIScrollViewDelegate

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            form.tableDelegate?.scrollViewDidScroll?(scrollView)
        }
    }
}

public extension Form {
    func indexPath<Cell: UITableViewCell>(for row: Row<Cell, Model>) -> IndexPath? {
        if let tv = tableView, let view = row.view {
            return tv.indexPath(for: view)
        } else {
            for (index, section) in enumerated() {
                if let row = section.firstIndex(where: { $0 === row }) {
                    return IndexPath(row: row, section: index)
                }
            }
            return nil
        }
    }
}
#endif
