//
//  RealtimeTableController.swift
//  Realtime_Example
//
//  Created by Denis Koryttsev on 24/06/2018.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import UIKit
import Realtime

class TableCell: UITableViewCell {
    lazy var indicator: UIActivityIndicatorView = UIActivityIndicatorView(activityIndicatorStyle: .gray).add(to: self.contentView) {
        $0.center = self.contentView.center
    }
    lazy var label: UILabel = UILabel().add(to: self.contentView) {
        $0.numberOfLines = 0
    }

    func startIndicatorIfNeeeded() {
        guard label.text == nil else {
            return
        }
        indicator.startAnimating()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds.offsetBy(dx: 15, dy: 0)
    }

    override func prepareForReuse() {
        label.text = nil
    }
}

class RealtimeTableController: UIViewController {
    var store = ListeningDisposeStore()
    var tableView: UITableView! { return view as! UITableView }
    var delegate: SingleSectionTableViewDelegate<User>!
    weak var activityView: UIActivityIndicatorView!

    override func loadView() {
        view = UITableView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.rightBarButtonItems = [UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(edit)),
                                              UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addUser))]

        let iView = UIActivityIndicatorView(activityIndicatorStyle: .gray)
        navigationItem.titleView = iView
        self.activityView = iView

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: NSStringFromClass(UITableViewCell.self))
        tableView.register(TableCell.self, forCellReuseIdentifier: NSStringFromClass(TableCell.self))
        let users = Global.rtUsers
        delegate = SingleSectionTableViewDelegate(users) { (table, ip, _) -> UITableViewCell in
            return table.dequeueReusableCell(withIdentifier: NSStringFromClass(TableCell.self), for: ip)
        }
        delegate.register(UITableViewCell.self) { (item, user) in
            item.bind(user.name) { (cell, val) in
                cell.textLabel!.text =? val
            }
        }
        delegate.register(TableCell.self) { (item, user) in
            item.set(config: { (cell) in
                cell.startIndicatorIfNeeeded()
            })
            item.bind(user.name) { (cell, name) in
                cell.label.text =? name
                cell.indicator.stopAnimating()
            }
        }
        delegate.bind(tableView)
        delegate.tableDelegate = self
        delegate.editingDataSource = self

        iView.startAnimating()

        users.changes.listening(onValue: { [unowned self] change in
            if self.activityView.isAnimating {
                self.activityView.stopAnimating()
            }

            print(change)
            switch change {
            case .initial:
                self.tableView.reloadData()
            case .updated(let deleted, let inserted, let modified, let moved):
                self.tableView.beginUpdates()
                self.tableView.insertRows(at: inserted.map { IndexPath(row: $0, section: 0) }, with: .automatic)
                self.tableView.deleteRows(at: deleted.map { IndexPath(row: $0, section: 0) }, with: .automatic)
                self.tableView.reloadRows(at: modified.map { IndexPath(row: $0, section: 0) }, with: .automatic)
                moved.forEach({ (move) in
                    self.tableView.moveRow(at: IndexPath(row: move.from, section: 0), to: IndexPath(row: move.to, section: 0))
                })
                self.tableView.endUpdates()
            }
        }).add(to: &store)
        users.changes.listening { (err) in
            print(err.localizedDescription)
        }.add(to: &store)
        users.runObserving(.childAdded)
        users.runObserving(.childRemoved)
        users.runObserving(.childChanged)
    }

    @objc func addUser() {
        let controller = RealtimeViewController()
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc func edit(_ control: UIBarButtonItem) {
        tableView.setEditing(!tableView.isEditing, animated: true)
    }
}

extension RealtimeTableController: UITableViewDelegate, RealtimeEditingTableDataSource {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        print("Did select row at \(indexPath)")
    }

    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {
        return .delete
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        switch editingStyle {
        case .delete:
            activityView.startAnimating()
            Global.rtUsers.remove(at: indexPath.row).commit { (_, err) in
                self.activityView.stopAnimating()
                if let e = err?.first {
                    print(e.localizedDescription)
                }
            }
        default: break
        }
    }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {

    }
}
