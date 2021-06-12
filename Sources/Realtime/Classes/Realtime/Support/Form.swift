//
//  Form.swift
//  Pods
//
//  Created by Denis Koryttsev on 09.06.2021.
//

import Foundation

#if os(iOS) || os(tvOS)

open class Form<Model: AnyObject> {
    lazy var table: Table = Table(self)
    var sections: [Section<Model>]
    var removedSections: [Int: Section<Model>] = [:]
    var performsUpdates: Bool = false

    open var numberOfSections: Int { sections.count }

    open weak var tableDelegate: UITableViewDelegate?
    open weak var editingDataSource: UITableViewEditingDataSource?
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
        sections[indexPath.section].didSelect(self, didSelectRowAt: indexPath)
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
            form.sections[indexPath.section].willDisplayCell(cell, tableView: tableView, at: indexPath, with: form.model)
        }

        func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            if let removed = form.removedSections[indexPath.section] {
                removed.didEndDisplayCell(cell, tableView: tableView, at: indexPath)
                if tableView.indexPathsForVisibleRows.map({ !$0.contains(where: { $0.section == indexPath.section }) }) ?? true {
                    form.removedSections.removeValue(forKey: indexPath.section)
                }
            } else if form.sections.indices.contains(indexPath.section) {
                form.sections[indexPath.section].didEndDisplayCell(cell, tableView: tableView, at: indexPath)
            }
        }

        func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
            let s = form[section]
            s.willDisplayHeaderView(view, tableView: tableView, at: section, with: form.model)
            form.tableDelegate?.tableView?(tableView, willDisplayHeaderView: view, forSection: section)
        }

        func tableView(_ tableView: UITableView, didEndDisplayingHeaderView view: UIView, forSection section: Int) {
            let s = form[section]
            s.didEndDisplayHeaderView(view, tableView: tableView, at: section, with: form.model)
            form.tableDelegate?.tableView?(tableView, didEndDisplayingHeaderView: view, forSection: section)
        }

        func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
            let s = form[section]
            s.willDisplayFooterView(view, tableView: tableView, at: section, with: form.model)
            form.tableDelegate?.tableView?(tableView, willDisplayFooterView: view, forSection: section)
        }

        func tableView(_ tableView: UITableView, didEndDisplayingFooterView view: UIView, forSection section: Int) {
            let s = form[section]
            s.didEndDisplayFooterView(view, tableView: tableView, at: section, with: form.model)
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
