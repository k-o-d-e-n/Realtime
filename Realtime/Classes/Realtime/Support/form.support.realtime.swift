//
//  form.support.realtime.swift
//  Realtime
//
//  Created by Denis Koryttsev on 11/09/2018.
//

import Foundation

public enum CellBuilder {
    case reuseIdentifier(String)
    case custom(() -> UITableViewCell)
}

// probably `ReuseItem` should be a subclass of static item
// can add row dependency didSelect to hide/show optional cells
open class Row<View: AnyObject, Model: AnyObject>: ReuseItem<View> {
    lazy var _model: ValueStorage<Model?> = ValueStorage.unsafe(weak: nil)
    lazy var _update: Accumulator = Accumulator(repeater: .unsafe(), _view.compactMap(), _model.compactMap())
    lazy var _didSelect: Repeater<IndexPath> = .unsafe()

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
        _update.listeningItem(onValue: Closure.guarded(self, assign: doit)).add(to: &disposeStorage)
    }

    open func onSelect(_ doit: @escaping ((IndexPath), Row<View, Model>) -> Void) {
        _didSelect.listeningItem(onValue: Closure.guarded(self, assign: doit)).add(to: &disposeStorage)
    }

    override func free() {
        super.free()
        _model.value = nil
    }

    func buildCell(for tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        switch cellBuilder {
        case .reuseIdentifier(let identifier):
            return tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)
        case .custom(let closure):
            return closure()
        }
    }
}

open class Section<Model: AnyObject> {
    open var footerTitle: String?
    open var headerTitle: String?

    var numberOfItems: Int { return 0 }

    public init(headerTitle: String?, footerTitle: String?) {
        self.headerTitle = headerTitle
        self.footerTitle = footerTitle
    }

    open func addRow<Cell: UITableViewCell>(_ row: Row<Cell, Model>) {}
    open func insertRow<Cell: UITableViewCell>(_ row: Row<Cell, Model>, at index: Int) {}
    open func deleteRow(at index: Int) {}
    func item(at index: Int) -> Row<UITableViewCell, Model> { fatalError() }
    func willDisplay(_ cell: UITableViewCell, at indexPath: IndexPath, with model: Model) {
        let item = self.item(at: indexPath.row)

        item.view = cell
        item._model.value = model
    }

    func didEndDisplay(_ cell: UITableViewCell, at indexPath: IndexPath) {
        // no call `free` because item does not have the binders that initializes in a display time
    }

    func didSelect(at indexPath: IndexPath) {}
}

open class StaticSection<Model: AnyObject>: Section<Model> {
    var cells: [Row<UITableViewCell, Model>] = []

    override var numberOfItems: Int { return cells.count }

    override func item(at index: Int) -> Row<UITableViewCell, Model> {
        return cells[index]
    }

    override open func addRow<Cell: UITableViewCell>(_ row: Row<Cell, Model>) {
        insertRow(row, at: cells.count)
    }

    override open func insertRow<Cell: UITableViewCell>(_ row: Row<Cell, Model>, at index: Int) {
        cells.insert(unsafeBitCast(row, to: Row<UITableViewCell, Model>.self), at: index)
    }

    override open func deleteRow(at index: Int) {
        cells.remove(at: index)
    }

    override func didSelect(at indexPath: IndexPath) {
        cells[indexPath.row]._didSelect.send(.value(indexPath))
    }
}

struct ReuseRowController<Row, Key: Hashable> where Row: ReuseItemProtocol {
    private var freeItems: [Row] = []
    private var activeItems: [Key: Row] = [:]

    typealias RowBuilder = () -> Row

    func activeItem(at key: Key) -> Row? {
        return activeItems[key]
    }

    mutating func dequeueItem(at key: Key, rowBuilder: RowBuilder) -> Row {
        guard let item = activeItems[key] else {
            let item = freeItems.popLast() ?? rowBuilder()
            activeItems[key] = item
            return item
        }
        return item
    }

    mutating func free(at key: Key) {
        guard let item = activeItems.removeValue(forKey: key)
            else { return print("Try free non-active reuse item") }
        item.free()
        freeItems.append(item)
    }

    mutating func freeAll() {
        activeItems.forEach {
            $0.value.free()
            freeItems.append($0.value)
        }
        activeItems.removeAll()
    }
}

open class ReuseFormRow<View: AnyObject, Model: AnyObject, RowModel>: Row<View, Model> {
    lazy var bindsStorage: ListeningDisposeStore = ListeningDisposeStore()
    lazy var _rowModel: Repeater<RowModel> = Repeater.unsafe()

    public func onRowModel(_ doit: @escaping (RowModel, ReuseFormRow<View, Model, RowModel>) -> Void) {
        _rowModel.listeningItem(onValue: Closure.guarded(self, assign: doit)).add(to: &disposeStorage)
    }

    override func addBinding(ofDisplayTime item: ListeningItem) {
        bindsStorage.add(item)
    }

    override func reload() {
        bindsStorage.resume()
    }
}

// Warning! is not responsible for update collection, necessary to make it.
open class ReuseRowSection<Model: AnyObject, RowModel>: Section<Model> {
    var reuseController: ReuseRowController<ReuseFormRow<UITableViewCell, Model, RowModel>, Int> = ReuseRowController()
    let rowBuilder: ReuseRowController<ReuseFormRow<UITableViewCell, Model, RowModel>, Int>.RowBuilder

    var collection: AnySharedCollection<RowModel>

    public init<C: BidirectionalCollection>(_ collection: C, row builder: @escaping () -> ReuseFormRow<UITableViewCell, Model, RowModel>)
        where C.Element == RowModel, C.Index == Int {
            self.collection = AnySharedCollection(collection)
            self.rowBuilder = builder
            super.init(headerTitle: nil, footerTitle: nil)
    }

    override var numberOfItems: Int { return collection.count }

    override func item(at index: Int) -> Row<UITableViewCell, Model> {
        let item = reuseController.dequeueItem(at: index, rowBuilder: rowBuilder)
        return item
    }

    override open func addRow<Cell: UITableViewCell>(_ row: Row<Cell, Model>) {
        fatalError()
    }

    override open func insertRow<Cell: UITableViewCell>(_ row: Row<Cell, Model>, at index: Int) {
        fatalError()
    }

    override open func deleteRow(at index: Int) {
        fatalError()
    }

    override func willDisplay(_ cell: UITableViewCell, at indexPath: IndexPath, with model: Model) {
        let item = reuseController.dequeueItem(at: indexPath.row, rowBuilder: rowBuilder)

        item._rowModel.send(.value(collection[indexPath.row]))
        item.view = cell
        item.model = model
    }

    override func didEndDisplay(_ cell: UITableViewCell, at indexPath: IndexPath) {
        reuseController.activeItem(at: indexPath.row)?.bindsStorage.dispose()
    }

    override func didSelect(at indexPath: IndexPath) {
        reuseController.activeItem(at: indexPath.row)?._didSelect.send(.value(indexPath))
    }
}

open class Form<Model: AnyObject> {
    lazy var table: Table = Table(self)
    var sections: [Section<Model>]

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
        tv.beginUpdates()
    }

    open func endUpdates() {
        guard let tv = tableView else { fatalError() }
        tv.endUpdates()
    }

    open func insertRow<Cell: UITableViewCell>(
        _ row: Row<Cell, Model>, at indexPath: IndexPath, with animation: UITableViewRowAnimation = .automatic
        ) {
        sections[indexPath.section].insertRow(row, at: indexPath.row)
        tableView?.insertRows(at: [indexPath], with: animation)
    }

    open func deleteRows(at indexPaths: [IndexPath], with animation: UITableViewRowAnimation) {
        indexPaths.forEach { sections[$0.section].deleteRow(at: $0.row) }
        tableView?.deleteRows(at: indexPaths, with: animation)
    }

    open func addSection(_ section: Section<Model>, with animation: UITableViewRowAnimation = .automatic) {
        insertSection(section, at: sections.count)
    }

    open func insertSection(_ section: Section<Model>, at index: Int, with animation: UITableViewRowAnimation = .automatic) {
        sections.insert(section, at: index)
        tableView?.insertSections([index], with: animation)
    }

    open func deleteSections(at indexes: IndexSet, with animation: UITableViewRowAnimation) {
        indexes.forEach { sections.remove(at: $0) }
        tableView?.deleteSections(indexes, with: animation)
    }

    open func reloadRows(at indexPaths: [IndexPath], with animation: UITableViewRowAnimation) {
        tableView?.reloadRows(at: indexPaths, with: animation)
    }

    open func reloadSections(_ sections: IndexSet, with animation: UITableViewRowAnimation) {
        tableView?.reloadSections(sections, with: animation)
    }

    open func didSelect(at indexPath: IndexPath) {
        sections[indexPath.section].didSelect(at: indexPath)
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
            return form.tableDelegate?.tableView?(tableView, heightForHeaderInSection: section) ?? 28.0
        }

        func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
            return form.tableDelegate?.tableView?(tableView, heightForFooterInSection: section) ?? 28.0
        }

        func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
            return form.sections[section].headerTitle
        }

        func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
            return form.sections[section].footerTitle
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            return form.sections[indexPath.section].item(at: indexPath.row).buildCell(for: tableView, at: indexPath)
        }

        func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            form.sections[indexPath.section].willDisplay(cell, at: indexPath, with: form.model)
        }

        func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            form.sections[indexPath.section].didEndDisplay(cell, at: indexPath)
        }

        func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            tableView.deselectRow(at: indexPath, animated: true)
            form.didSelect(at: indexPath)
        }

        func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
            return true
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
    }
}
