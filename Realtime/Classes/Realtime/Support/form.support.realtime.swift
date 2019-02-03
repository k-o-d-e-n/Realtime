//
//  form.support.realtime.swift
//  Realtime
//
//  Created by Denis Koryttsev on 11/09/2018.
//

import Foundation

public enum CellBuilder {
    case reuseIdentifier(String)
    case `static`(UITableViewCell)
    case custom(() -> UITableViewCell)
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

// probably `ReuseItem` should be a subclass of static item
// can add row dependency didSelect to hide/show optional cells
open class Row<View: AnyObject, Model: AnyObject>: ReuseItem<View> {
    var internalDispose: ListeningDisposeStore = ListeningDisposeStore()
    lazy var _model: ValueStorage<Model?> = ValueStorage.unsafe(weak: nil)
    lazy var _update: Accumulator = Accumulator(repeater: .unsafe(), _view.compactMap(), _model.compactMap())
    lazy var _didSelect: Repeater<IndexPath> = .unsafe()

    var state: RowState = [.free, .pending]

    open internal(set) weak var model: Model? {
        set { _model.value = newValue }
        get { return _model.value }
    }

    let cellBuilder: CellBuilder

    public init(cellBuilder: CellBuilder) {
        self.cellBuilder = cellBuilder
    }
    deinit {}

    public convenience init(reuseIdentifier: String) {
        self.init(cellBuilder: .reuseIdentifier(reuseIdentifier))
    }

    open func onUpdate(_ doit: @escaping ((view: View, model: Model), Row<View, Model>) -> Void) {
        _update.listeningItem(onValue: Closure.guarded(self, assign: doit)).add(to: internalDispose)
    }

    open func onSelect(_ doit: @escaping ((IndexPath), Row<View, Model>) -> Void) {
        _didSelect.listeningItem(onValue: Closure.guarded(self, assign: doit)).add(to: internalDispose)
    }

    override func free() {
        super.free()
        _model.value = nil
    }

    func buildCell(for tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        switch cellBuilder {
        case .reuseIdentifier(let identifier):
            return tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)
        case .static(let cell): return cell
        case .custom(let closure): return closure()
        }
    }

    public func sendSelectEvent(at indexPath: IndexPath) {
        _didSelect.send(.value(indexPath))
    }
}
extension Row where View: UITableViewCell {
    public convenience init(static view: View) {
        self.init(cellBuilder: .static(view))
    }
}
public extension Row where View: UIView {
    var isVisible: Bool {
        return state.contains(.displaying) && view.map { !$0.isHidden && $0.window != nil } ?? false
    }
}
extension Row: CustomDebugStringConvertible {
    public var debugDescription: String {
        return """
        \(type(of: self)): \(ObjectIdentifier(self).memoryAddress) {
            view: \(view as Any),
            model: \(_model.value as Any),
            state: \(state)
        }
        """
    }
}

open class Section<Model: AnyObject>: RandomAccessCollection {
    open var footerTitle: String?
    open var headerTitle: String?

    var numberOfItems: Int { return 0 }

    public init(headerTitle: String?, footerTitle: String?) {
        self.headerTitle = headerTitle
        self.footerTitle = footerTitle
    }

    open func addRow<Cell: UITableViewCell>(_ row: Row<Cell, Model>) {}
    open func insertRow<Cell: UITableViewCell>(_ row: Row<Cell, Model>, at index: Int) {}
    open func moveRow(at index: Int, to newIndex: Int) {}
    @discardableResult
    open func deleteRow(at index: Int) -> Row<UITableViewCell, Model> { fatalError() }
    func dequeueRow(at index: Int) -> Row<UITableViewCell, Model> { fatalError() }
    func row(at index: Int) -> Row<UITableViewCell, Model>? { fatalError() }
    func reloadCell(at indexPath: IndexPath) { fatalError() }
    func willDisplay(_ cell: UITableViewCell, at indexPath: IndexPath, with model: Model) {}
    func didEndDisplay(_ cell: UITableViewCell, at indexPath: IndexPath) {}
    func didSelect(at indexPath: IndexPath) {}

    public typealias Element = Row<UITableViewCell, Model>
    open var startIndex: Int { fatalError("Override") }
    open var endIndex: Int { fatalError("Override") }
    open func index(after i: Int) -> Int {
        fatalError("Override")
    }
    open func index(before i: Int) -> Int {
        fatalError("Override")
    }
    open subscript(position: Int) -> Row<UITableViewCell, Model> {
        guard let r = row(at: position) else { fatalError("Index out of range") }
        return r
    }
}

open class StaticSection<Model: AnyObject>: Section<Model> {
    var rows: [Row<UITableViewCell, Model>] = []
    var removedRows: [Int: Row<UITableViewCell, Model>] = [:]

    override var numberOfItems: Int { return rows.count }

    override func dequeueRow(at index: Int) -> Row<UITableViewCell, Model> {
        return rows[index]
    }

    override func row(at index: Int) -> Row<UITableViewCell, Model>? {
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
            if !row.state.contains(.free) && row.view === cell {
                row.state.remove(.displaying)
                row.free()
                row.state.insert([.pending, .free])
            } else {
//                debugLog("\(row.state) \n \(row.view as Any) \n\(cell)")
            }
        }
    }

    override func willDisplay(_ cell: UITableViewCell, at indexPath: IndexPath, with model: Model) {
        let item = rows[indexPath.row]

        if !item.state.contains(.displaying) || item.view !== cell {
            item.view = cell
            item._model.value = model
            item.state.insert(.displaying)
            item.state.remove(.free)
        }
    }

    override func didSelect(at indexPath: IndexPath) {
        rows[indexPath.row]._didSelect.send(.value(indexPath))
    }

    override func reloadCell(at indexPath: IndexPath) {
        let row = rows[indexPath.row]
        if row.isVisible {
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

    public func onRowModel(_ doit: @escaping (RowModel, ReuseFormRow<View, Model, RowModel>) -> Void) {
        _rowModel.listeningItem(onValue: Closure.guarded(self, assign: doit)).add(to: internalDispose)
    }
}

// Warning! is not responsible for update collection, necessary to make it.
open class ReuseRowSection<Model: AnyObject, RowModel>: Section<Model> {
    var reuseController: ReuseController<ReuseFormRow<UITableViewCell, Model, RowModel>, Int> = ReuseController()
    let rowBuilder: ReuseController<ReuseFormRow<UITableViewCell, Model, RowModel>, Int>.RowBuilder

    var collection: AnySharedCollection<RowModel>

    public init<C: BidirectionalCollection>(_ collection: C, row builder: @escaping () -> ReuseFormRow<UITableViewCell, Model, RowModel>)
        where C.Element == RowModel, C.Index == Int {
            self.collection = AnySharedCollection(collection)
            self.rowBuilder = builder
            super.init(headerTitle: nil, footerTitle: nil)
    }

    override var numberOfItems: Int { return collection.count }

    override func dequeueRow(at index: Int) -> Row<UITableViewCell, Model> {
        let item = reuseController.dequeue(at: index, rowBuilder: rowBuilder)
        return item
    }

    override func row(at index: Int) -> Row<UITableViewCell, Model>? {
        return reuseController.active(at: index)
    }

    override open func addRow<Cell: UITableViewCell>(_ row: Row<Cell, Model>) {
        fatalError()
    }

    override open func insertRow<Cell: UITableViewCell>(_ row: Row<Cell, Model>, at index: Int) {
        fatalError()
    }

    override open func deleteRow(at index: Int) -> Row<UITableViewCell, Model> {
        fatalError()
    }

    override func willDisplay(_ cell: UITableViewCell, at indexPath: IndexPath, with model: Model) {
        let item = reuseController.dequeue(at: indexPath.row, rowBuilder: rowBuilder)

        if !item.state.contains(.displaying) || item.view !== cell {
            item._rowModel.send(.value(collection[indexPath.row]))
            item.view = cell
            item.model = model
            item.state.insert(.displaying)
            item.state.remove(.free)
        }
    }

    override func didEndDisplay(_ cell: UITableViewCell, at indexPath: IndexPath) {
        if let row = reuseController.free(at: indexPath.row, ifRespondsFor: cell) {
            row.state.remove(.displaying)
            row.state.insert([.pending, .free])
        }
    }

    override func didSelect(at indexPath: IndexPath) {
        reuseController.active(at: indexPath.row)?._didSelect.send(.value(indexPath))
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
        guard let row = reuseController.active(at: position) else { fatalError("Index out of range") }
        return row
    }
}

open class Form<Model: AnyObject> {
    lazy var table: Table = Table(self)
    var sections: [Section<Model>]
    var removedSections: [Int: Section<Model>] = [:]

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
        return sections[section].numberOfItems
    }

    open func beginUpdates() {
        guard let tv = tableView else { fatalError() }
        guard tv.window != nil else { return }
        tv.beginUpdates()
    }

    open func endUpdates() {
        guard let tv = tableView else { fatalError() }
        guard tv.window != nil else { return }
        tv.endUpdates()
    }

    open func insertRow<Cell: UITableViewCell>(
        _ row: Row<Cell, Model>, at indexPath: IndexPath, with animation: UITableViewRowAnimation = .automatic
        ) {
        sections[indexPath.section].insertRow(row, at: indexPath.row)
        tableView?.insertRows(at: [indexPath], with: animation)
    }

    open func deleteRows(at indexPaths: [IndexPath], with animation: UITableViewRowAnimation = .automatic) {
        indexPaths.sorted(by: >).forEach { sections[$0.section].deleteRow(at: $0.row) }
        tableView?.deleteRows(at: indexPaths, with: animation)
    }

    open func moveRow(at indexPath: IndexPath, to newIndexPath: IndexPath) {
        if indexPath.section == newIndexPath.section {
            sections[indexPath.section].moveRow(at: indexPath.row, to: newIndexPath.row)
        } else {
            let row = sections[indexPath.section].deleteRow(at: indexPath.row)
            sections[newIndexPath.section].insertRow(row, at: newIndexPath.row)
        }
        tableView?.moveRow(at: indexPath, to: newIndexPath)
    }

    open func addSection(_ section: Section<Model>, with animation: UITableViewRowAnimation = .automatic) {
        insertSection(section, at: sections.count)
    }

    open func insertSection(_ section: Section<Model>, at index: Int, with animation: UITableViewRowAnimation = .automatic) {
        sections.insert(section, at: index)
        if let tv = tableView, tv.window != nil {
            tv.insertSections([index], with: animation)
        }
    }

    open func deleteSections(at indexes: IndexSet, with animation: UITableViewRowAnimation) {
        indexes.reversed().forEach { removedSections[$0] = sections.remove(at: $0) }
        if let tv = tableView, tv.window != nil {
            tv.deleteSections(indexes, with: animation)
        }
    }

    open func reloadRows(at indexPaths: [IndexPath], with animation: UITableViewRowAnimation) {
        if let tv = tableView, tv.window != nil {
            tv.reloadRows(at: indexPaths, with: animation)
        }
    }

    open func reloadSections(_ sections: IndexSet, with animation: UITableViewRowAnimation) {
        if let tv = tableView, tv.window != nil {
            tv.reloadSections(sections, with: animation)
        }
    }

    open func didSelect(at indexPath: IndexPath) {
        sections[indexPath.section].didSelect(at: indexPath)
    }

    open func reload() {
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
    class Table: NSObject, UITableViewDelegate, UITableViewDataSource {
        unowned var form: Form

        init(_ form: Form) {
            self.form = form
        }

        func numberOfSections(in tableView: UITableView) -> Int {
            return form.sections.count
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            return form.sections[section].numberOfItems
        }

        func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
            return form.tableDelegate?.tableView?(tableView, heightForRowAt: indexPath) ?? 44.0
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

        func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
            return form.sections[section].footerTitle
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            return form.sections[indexPath.section].dequeueRow(at: indexPath.row).buildCell(for: tableView, at: indexPath)
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

        func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
            return form.tableDelegate?.tableView?(tableView, shouldHighlightRowAt: indexPath) ?? true
        }

        func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            tableView.deselectRow(at: indexPath, animated: true)
            form.didSelect(at: indexPath)
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

        func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {
            return form.tableDelegate.flatMap { $0.tableView?(tableView, editingStyleForRowAt: indexPath) } ?? .none
        }

        func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
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
