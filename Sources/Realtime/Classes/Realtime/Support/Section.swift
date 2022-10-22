//
//  Section.swift
//  Pods
//
//  Created by Denis Koryttsev on 09.06.2021.
//

import Foundation

#if os(iOS) || os(tvOS)
public typealias __SupplementaryView = UIView
public typealias __Cell = UITableViewCell
public typealias __TableView = UITableView
#elseif os(macOS)
public typealias __SupplementaryView = NSTableRowView
public typealias __Cell = NSTableRowView
public typealias __TableView = NSTableView
extension IndexPath {
    var row: Int { item }
    init(row: Int, section: Int) {
        self.init(item: row, section: section)
    }
}
#endif

struct SectionState: OptionSet {
    let rawValue: CShort

    init(rawValue: CShort) {
        self.rawValue = rawValue
    }
}
extension SectionState {
    static let headerDisplaying: SectionState = SectionState(rawValue: 1 << 0)
    static let footerDisplaying: SectionState = SectionState(rawValue: 1 << 1)
}

open class Section<Model: AnyObject>: RandomAccessCollection {
    open var footerTitle: String?
    open var headerTitle: String?
    open internal(set) var headerRow: Row<__SupplementaryView, Model>?
    open internal(set) var footerRow: Row<__SupplementaryView, Model>?

    var state: SectionState = []

    var numberOfItems: Int { fatalError("override") }

    public init(headerTitle: String?, footerTitle: String?) {
        self.headerTitle = headerTitle
        self.footerTitle = footerTitle
    }

    // TODO: set_Row does not recognize with code completer
    open func setHeaderRow<V: __SupplementaryView>(_ row: Row<V, Model>) {
        self.headerRow = unsafeBitCast(row, to: Row<__SupplementaryView, Model>.self)
    }
    open func setFooterRow<V: __SupplementaryView>(_ row: Row<V, Model>) {
        self.footerRow = unsafeBitCast(row, to: Row<__SupplementaryView, Model>.self)
    }

    internal func addRow<Cell: __Cell>(_ row: Row<Cell, Model>) { fatalError("Unimplemented or unavailable") }
    internal func insertRow<Cell: __Cell>(_ row: Row<Cell, Model>, at index: Int) { fatalError("Unimplemented or unavailable") }
    internal func moveRow(at index: Int, to newIndex: Int) { fatalError("Unimplemented or unavailable") }
    @discardableResult
    internal func deleteRow(at index: Int) -> Row<__Cell, Model> { fatalError("Unimplemented or unavailable") }

    func _hasVisibleRows(fromTop: Bool, excludingFinal cell: __Cell? = nil) -> Bool { fatalError("override") }

    func buildCell(for tableView: __TableView, at indexPath: IndexPath) -> __Cell { fatalError() }
    func reloadCell(at indexPath: IndexPath) { fatalError() }

    func didSelect(_ form: Form<Model>, didSelectRowAt indexPath: IndexPath) {}

    func willDisplay(_ tableView: __TableView, at index: Int) { }
    func didEndDisplay(_ tableView: __TableView, at index: Int) { }

    func willDisplayCell(_ cell: __Cell, tableView: __TableView, at indexPath: IndexPath, with model: Model) {
        if indexPath.row == 0, !(_hasVisibleRows(fromTop: true, excludingFinal: cell) || state.contains(.headerDisplaying)) {
            willDisplay(tableView, at: indexPath.section)
        } else if indexPath.row + 1 == numberOfItems, !(_hasVisibleRows(fromTop: false, excludingFinal: cell) || state.contains(.footerDisplaying)) {
            willDisplay(tableView, at: indexPath.section)
        }
    }
    func didEndDisplayCell(_ cell: __Cell, tableView: __TableView, at indexPath: IndexPath) {
        if indexPath.row == 0, !(_hasVisibleRows(fromTop: true, excludingFinal: cell) || state.contains(.headerDisplaying)) {
            didEndDisplay(tableView, at: indexPath.section)
        } else if indexPath.row + 1 == numberOfItems, !(_hasVisibleRows(fromTop: false, excludingFinal: cell) || state.contains(.footerDisplaying)) {
            didEndDisplay(tableView, at: indexPath.section)
        }
    }
    func willDisplayHeaderView(_ view: __SupplementaryView, tableView: __TableView, at section: Int, with model: Model) {
        if !(_hasVisibleRows(fromTop: true) || state.contains(.footerDisplaying)) {
            willDisplay(tableView, at: section)
        }
        state.insert(.headerDisplaying)
        headerRow?.willDisplay(with: view, model: model, indexPath: IndexPath(row: -1, section: section))
    }
    func didEndDisplayHeaderView(_ view: __SupplementaryView, tableView: __TableView, at section: Int, with model: Model) {
        if !(_hasVisibleRows(fromTop: true) || state.contains(.footerDisplaying)) {
            didEndDisplay(tableView, at: section)
        }
        state.remove(.headerDisplaying)
        headerRow?.didEndDisplay(with: view, indexPath: IndexPath(row: -1, section: section))
    }
    func willDisplayFooterView(_ view: __SupplementaryView, tableView: __TableView, at section: Int, with model: Model) {
        if !(_hasVisibleRows(fromTop: false) || state.contains(.headerDisplaying)) {
            willDisplay(tableView, at: section)
        }
        state.insert(.footerDisplaying)
        footerRow?.willDisplay(with: view, model: model, indexPath: IndexPath(row: .max, section: section))
    }
    func didEndDisplayFooterView(_ view: __SupplementaryView, tableView: __TableView, at section: Int, with model: Model) {
        if !(_hasVisibleRows(fromTop: false) || state.contains(.headerDisplaying)) {
            didEndDisplay(tableView, at: section)
        }
        state.remove(.footerDisplaying)
        footerRow?.didEndDisplay(with: view, indexPath: IndexPath(row: .max, section: section))
    }

    public typealias Element = Row<__Cell, Model>
    open var startIndex: Int { fatalError("override") }
    open var endIndex: Int { fatalError("override") }
    open func index(after i: Int) -> Int {
        fatalError("override")
    }
    open func index(before i: Int) -> Int {
        fatalError("override")
    }
    open subscript(position: Int) -> Row<__Cell, Model> {
        fatalError("override")
    }
}
public extension Section {
    var visibleIndexPaths: [IndexPath] {
        return compactMap({ $0.isVisible ? $0.indexPath : nil })
    }
}

open class StaticSection<Model: AnyObject>: Section<Model> {
    var rows: [Row<__Cell, Model>] = []
    var removedRows: [Int: Row<__Cell, Model>] = [:]

    override var numberOfItems: Int { rows.count }

    override func buildCell(for tableView: __TableView, at indexPath: IndexPath) -> __Cell {
        rows[indexPath.row].buildCell(for: tableView, at: indexPath)
    }

    override func _hasVisibleRows(fromTop: Bool, excludingFinal cell: __Cell? = nil) -> Bool {
        if fromTop {
            guard rows.first?.isVisible == true else { return false }
            return cell == nil || (rows.count > 1 ? false : rows[1].isVisible)
        } else {
            guard rows.last?.isVisible == true else { return false }
            return cell == nil || (rows.count > 1 ? false : rows[rows.count - 2].isVisible)
        }
    }

    override open func addRow<Cell: __Cell>(_ row: Row<Cell, Model>) {
        insertRow(row, at: rows.count)
    }

    override open func insertRow<Cell: __Cell>(_ row: Row<Cell, Model>, at index: Int) {
        rows.insert(unsafeBitCast(row, to: Row<__Cell, Model>.self), at: index)
    }

    override open func moveRow(at index: Int, to newIndex: Int) {
        rows.insert(rows.remove(at: index), at: newIndex)
    }

    @discardableResult
    override open func deleteRow(at index: Int) -> Row<__Cell, Model> {
        let removed = rows.remove(at: index)
        removedRows[index] = removed
        removed.state.insert(.removed)
        return removed
    }

    override func didEndDisplayCell(_ cell: __Cell, tableView: __TableView, at indexPath: IndexPath) {
        super.didEndDisplayCell(cell, tableView: tableView, at: indexPath)
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

    override func willDisplayCell(_ cell: __Cell, tableView: __TableView, at indexPath: IndexPath, with model: Model) {
        super.willDisplayCell(cell, tableView: tableView, at: indexPath, with: model)
        let item = rows[indexPath.row]
        item.willDisplay(with: cell, model: model, indexPath: indexPath)
    }

    override func didSelect(_ form: Form<Model>, didSelectRowAt indexPath: IndexPath) {
        #if os(iOS) || os(tvOS)
        form.tableView?.deselectRow(at: indexPath, animated: true)
        #else
        form.tableView?.deselectRow(indexPath.row)
        #endif
        rows[indexPath.row].didSelect(form, didSelectRowAt: indexPath)
    }

    override func reloadCell(at indexPath: IndexPath) {
        let row = rows[indexPath.row]
        if row.isVisible, let view = row.view, let model = row.model {
            #if COMBINE || REALTIME_UI
            row._update.send((view, model))
            #endif
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
    override open subscript(position: Int) -> Row<__Cell, Model> {
        return rows[position]
    }
}
