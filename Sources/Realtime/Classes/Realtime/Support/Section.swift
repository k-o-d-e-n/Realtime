//
//  Section.swift
//  Pods
//
//  Created by Denis Koryttsev on 09.06.2021.
//

import Foundation

#if os(iOS) || os(tvOS)

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
    func didSelect(_ form: Form<Model>, didSelectRowAt indexPath: IndexPath) {}

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

    override func didSelect(_ form: Form<Model>, didSelectRowAt indexPath: IndexPath) {
        form.tableView?.deselectRow(at: indexPath, animated: true)
        rows[indexPath.row].didSelect(form, didSelectRowAt: indexPath)
    }

    override func reloadCell(at indexPath: IndexPath) {
        let row = rows[indexPath.row]
        if row.isVisible, let view = row.view, let model = row.model {
            row._update.send((view, model))
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

#endif
