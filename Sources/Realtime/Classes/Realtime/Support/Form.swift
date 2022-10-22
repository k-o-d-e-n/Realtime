//
//  Form.swift
//  Pods
//
//  Created by Denis Koryttsev on 09.06.2021.
//

import Foundation

#if os(iOS) || os(tvOS)
public typealias __TableViewDelegate = UITableViewDelegate
public typealias __TableViewDataSource = UITableViewDataSource
#elseif os(macOS)
public typealias __TableViewDelegate = NSTableViewDelegate
public typealias __TableViewDataSource = NSTableViewDataSource
extension NSTableView {
    public typealias RowAnimation = AnimationOptions
}
extension NSTableView.AnimationOptions {
    public static var automatic: Self { [] }
}
#endif

open class Form<Model: AnyObject> {
    lazy var table: Table = Table(self)
    var sections: [Section<Model>]
    var removedSections: [Int: Section<Model>] = [:]
    var performsUpdates: Bool = false

    open var numberOfSections: Int { sections.count }

    open weak var tableDelegate: __TableViewDelegate?
    #if os(iOS) || os(tvOS)
    open weak var editingDataSource: UITableViewEditingDataSource?
    open weak var prefetchingDataSource: UITableViewDataSourcePrefetching?
    #endif

    open var model: Model
    open weak var tableView: __TableView? {
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

    open func addRow<Cell: __Cell>(
        _ row: Row<Cell, Model>, with animation: __TableView.RowAnimation = .automatic
        ) {
        guard let last = self.last else { fatalError("Form is empty") }
        last.addRow(row)
        if performsUpdates {
            #if os(iOS) || os(tvOS)
            tableView?.insertRows(at: [IndexPath(row: last.numberOfItems, section: numberOfSections - 1)], with: animation)
            #else
            let offset = rows(until: count - 1)
            tableView?.insertRows(at: [offset + last.lastItemIndex], withAnimation: animation)
            #endif
        }
    }

    open func insertRow<Cell: __Cell>(
        _ row: Row<Cell, Model>, at indexPath: IndexPath, with animation: __TableView.RowAnimation = .automatic
        ) {
        sections[indexPath.section].insertRow(row, at: indexPath.row)
        if performsUpdates {
            #if os(iOS) || os(tvOS)
            tableView?.insertRows(at: [indexPath], with: animation)
            #else
            tableView?.insertRows(at: [self.row(for: indexPath)], withAnimation: animation)
            #endif
        }
    }

    open func deleteRows(at indexPaths: [IndexPath], with animation: __TableView.RowAnimation = .automatic) {
        indexPaths.sorted(by: >).forEach { sections[$0.section].deleteRow(at: $0.row) }
        if performsUpdates {
            #if os(iOS) || os(tvOS)
            tableView?.deleteRows(at: indexPaths, with: animation)
            #else
            let indexes = indexPaths.reduce(into: IndexSet()) { pr, ip in
                let row = row(for: ip)
                pr.insert(row)
            }
            tableView?.removeRows(at: indexes, withAnimation: animation)
            #endif
        }
    }

    open func moveRow(at indexPath: IndexPath, to newIndexPath: IndexPath) {
        if indexPath.section == newIndexPath.section {
            sections[indexPath.section].moveRow(at: indexPath.row, to: newIndexPath.row)
        } else {
            let row = sections[indexPath.section].deleteRow(at: indexPath.row)
            sections[newIndexPath.section].insertRow(row, at: newIndexPath.row)
        }
        if performsUpdates {
            #if os(iOS) || os(tvOS)
            tableView?.moveRow(at: indexPath, to: newIndexPath)
            #else
            let from = row(for: indexPath), to = row(for: newIndexPath) // TODO: _
            tableView?.moveRow(at: from, to: to)
            #endif
        }
    }

    open func addSection(_ section: Section<Model>, with animation: __TableView.RowAnimation = .automatic) {
        insertSection(section, at: sections.count, with: animation)
    }

    open func insertSection(_ section: Section<Model>, at index: Int, with animation: __TableView.RowAnimation = .automatic) {
        sections.insert(section, at: index)
        if let tv = tableView {
            #if os(iOS) || os(tvOS)
            if tv.window != nil {
                tv.insertSections([index], with: animation)
            }
            #else
            let start = rows(until: index)
            tv.insertRows(at: IndexSet(start ..< start + section.numberOfRows), withAnimation: animation)
            #endif
        }
    }

    open func deleteSections(at indexes: IndexSet, with animation: __TableView.RowAnimation = .automatic) {
        #if os(iOS) || os(tvOS)
        indexes.reversed().forEach { removedSections[$0] = sections.remove(at: $0) }
        if performsUpdates {
            tableView?.deleteSections(indexes, with: animation)
        }
        #else
        if performsUpdates {
            let rowIndexes = rowIndexes(for: indexes)
            tableView?.removeRows(at: rowIndexes, withAnimation: .automatic)
        }
        indexes.reversed().forEach { removedSections[$0] = sections.remove(at: $0) }
        #endif
    }

    open func reloadRows(at indexPaths: [IndexPath], with animation: __TableView.RowAnimation = .automatic) {
        if performsUpdates, let tv = tableView {
            #if os(iOS) || os(tvOS)
            if tv.window != nil {
                tv.reloadRows(at: indexPaths, with: animation)
            }
            #else
            let indexes = indexPaths.reduce(into: IndexSet()) { pr, ip in
                let row = row(for: ip)
                pr.insert(row)
            }
            tv.reloadData(forRowIndexes: indexes, columnIndexes: [])
            #endif
        }
    }

    open func reloadSections(_ sections: IndexSet, with animation: __TableView.RowAnimation = .automatic) {
        if performsUpdates, let tv = tableView {
            #if os(iOS) || os(tvOS)
            if tv.window != nil {
                tv.reloadSections(sections, with: animation)
            }
            #else
            let rowIndexes = rowIndexes(for: sections)
            tv.reloadData(forRowIndexes: rowIndexes, columnIndexes: [])
            #endif
        }
    }

    open func didSelect(_ tableView: __TableView, didSelectRowAt indexPath: IndexPath) {
        sections[indexPath.section].didSelect(self, didSelectRowAt: indexPath)
    }

    open func reloadVisible() {
        if let tv = tableView {
            #if os(iOS) || os(tvOS)
            tv.indexPathsForVisibleRows?.forEach({ (ip) in
                sections[ip.section].reloadCell(at: ip)
            })
            #else
            let range = tv.rows(in: tv.bounds)
            for row in range.lowerBound ..< range.upperBound {
                let ip = indexPath(for: row).indexPath // TODO: Use explicit sections enumeration
                sections[ip.section].reloadCell(at: ip)
            }
            #endif
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

#if os(iOS) || os(tvOS)
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
            return form.editingDataSource?.tableView(tableView, canEditRowAt: indexPath) ?? false
        }

        func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
            return form.editingDataSource?.tableView(tableView, canMoveRowAt: indexPath) ?? false
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
#elseif os(macOS)
extension Section {
    fileprivate var hasHeader: Bool { headerTitle != nil || headerRow != nil }
    fileprivate var hasFooter: Bool { footerTitle != nil || footerRow != nil }
    fileprivate var numberOfRows: Int {
        numberOfItems + (hasHeader ? 1 : 0) + (hasFooter ? 1 : 0)
    }
    fileprivate var lastItemIndex: Int {
        numberOfItems + (hasHeader ? 1 : 0)
    }
}
extension Form {
    public enum RowType {
        case regular, header, footer
    }
    public func indexPath(for row: Int) -> (indexPath: IndexPath, type: RowType, section: Section<Model>) {
        var remaining = row
        var sectionIndex = -1
        while remaining >= 0 {
            sectionIndex += 1
            remaining -= self[sectionIndex].numberOfRows
        }
        let section = self[sectionIndex]
        let row: Int
        let type: RowType
        switch remaining {
        case 0:
            row = section.numberOfRows
            type = section.hasFooter ? .footer : .regular
        case -section.numberOfRows:
            row = 0
            type = section.hasHeader ? .header : .regular
        default:
            row = section.numberOfRows + remaining + (section.hasHeader ? -1 : 0)
            type = .regular
        }
        return (IndexPath(row: row, section: sectionIndex), type, section)
    }
    func rows(until sectionIndex: Int) -> Int {
        precondition(sectionIndex < count)
        var index = 0
        var rows = 0
        while index < sectionIndex {
            rows += self[index].numberOfRows
            index += 1
        }
        return rows
    }
    func row(for indexPath: IndexPath) -> Int {
        rows(until: indexPath.section) + indexPath.row + (self[indexPath.section].hasHeader ? 1 : 0)
    }
    func rowIndexes(for sections: IndexSet) -> IndexSet {
        sections.reduce(into: IndexSet()) { partialResult, index in
            let start = rows(until: index)
            partialResult.insert(integersIn: start ..< start + self[index].numberOfRows)
        }
    }
}
extension Form {
    final class TitledSupplementaryRow: NSTableRowView {
        let titleLabel: NSTextField
        convenience init(identifier: NSUserInterfaceItemIdentifier) {
            self.init(frame: .zero)
            self.identifier = identifier
        }
        override init(frame frameRect: NSRect) {
            if #available(macOS 10.12, *) {
                self.titleLabel = NSTextField(labelWithString: "")
            } else {
                self.titleLabel = NSTextField()
                self.titleLabel.isEditable = false
                self.titleLabel.isSelectable = false
            }
            if #available(macOS 11.0, *) {
                self.titleLabel.font = NSFont.preferredFont(forTextStyle: .title3)
            } else if #available(macOS 10.11, *) {
                self.titleLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .bold)
            } else {
                self.titleLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            }
            super.init(frame: frameRect)
            addSubview(titleLabel)
        }
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        override func layout() {
            super.layout()
            titleLabel.sizeToFit()
            titleLabel.setFrameOrigin(NSPoint(
                x: 10,
                y: bounds.height - titleLabel.frame.height
            ))
        }
    }
    final class Table: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        unowned var form: Form
        init(_ form: Form) {
            self.form = form
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            form.reduce(into: 0) { partialResult, section in
                partialResult += section.numberOfRows
            }
        }
        func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
            tableView.floatsGroupRows && form.indexPath(for: row).type == .header
        }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? { nil }
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let (indexPath, type, section) = form.indexPath(for: row)
            switch type {
            case .regular:
                return section.buildCell(for: tableView, at: indexPath)
            case .header:
                guard let headerView = section.headerRow?.build(for: tableView, at: indexPath.section) else {
                    guard let title = section.headerTitle else { return nil }
                    let identifier = NSUserInterfaceItemIdentifier("form.default-headerView")
                    let defaultView = tableView.makeView(withIdentifier: identifier, owner: tableView) as? TitledSupplementaryRow ?? TitledSupplementaryRow(identifier: identifier)
                    defaultView.titleLabel.stringValue = title
                    return defaultView
                }
                return headerView
            case .footer:
                guard let footerView = section.footerRow?.build(for: tableView, at: indexPath.section) else {
                    guard let title = section.footerTitle else { return nil }
                    let identifier = NSUserInterfaceItemIdentifier("form.default-footerView")
                    let defaultView = tableView.makeView(withIdentifier: identifier, owner: tableView) as? TitledSupplementaryRow ?? TitledSupplementaryRow(identifier: identifier)
                    defaultView.titleLabel.stringValue = title
                    return defaultView
                }
                return footerView
            }
        }
        func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
            let (indexPath, type, section) = form.indexPath(for: row)
            switch type {
            case .regular:
                section.willDisplayCell(rowView, tableView: tableView, at: indexPath, with: form.model)
            case .header:
                section.headerRow?.willDisplay(with: rowView, model: form.model, indexPath: indexPath)
            case .footer:
                section.footerRow?.willDisplay(with: rowView, model: form.model, indexPath: indexPath)
            }
        }
        func tableView(_ tableView: NSTableView, didRemove rowView: NSTableRowView, forRow row: Int) {
            guard row >= 0 else { return } /// moved off screen, else removed
            let (indexPath, type, section) = form.indexPath(for: row)
            if let removed = form.removedSections[indexPath.section] {
                removed.didEndDisplayCell(rowView, tableView: tableView, at: indexPath)
                /*if tableView.indexPathsForVisibleRows.map({ !$0.contains(where: { $0.section == indexPath.section }) }) ?? true {
                    form.removedSections.removeValue(forKey: indexPath.section)
                }*/
            } else if form.sections.indices.contains(indexPath.section) {
                switch type {
                case .regular:
                    section.didEndDisplayCell(rowView, tableView: tableView, at: indexPath)
                case .header:
                    section.headerRow?.didEndDisplay(with: rowView, indexPath: indexPath)
                case .footer:
                    section.footerRow?.didEndDisplay(with: rowView, indexPath: indexPath)
                }
            }
        }
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            form.tableDelegate?.tableView?(tableView, heightOfRow: row) ?? tableView.rowHeight
        }
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            form.tableDelegate?.tableView?(tableView, shouldSelectRow: row) ?? true
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            defer {
                form.tableDelegate?.tableViewSelectionDidChange?(notification)
            }
            guard let tv = notification.object as? NSTableView else { return }
            guard tv.selectedRow != -1 else { return }
            let (indexPath, type, section) = form.indexPath(for: tv.selectedRow)
            guard type == .regular else { return }
            section.didSelect(form, didSelectRowAt: indexPath)
        }
    }
}
#endif
