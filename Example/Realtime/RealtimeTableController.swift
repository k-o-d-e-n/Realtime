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
    lazy var indicator: UIActivityIndicatorView = UIActivityIndicatorView(style: .gray).add(to: self.contentView) {
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

class RealtimeTableController: UITableViewController {
    var store = ListeningDisposeStore()
    var delegate: SingleSectionTableViewDelegate<User>!
    weak var activityView: UIActivityIndicatorView!

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.rightBarButtonItems = [UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(edit)),
                                              UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addUser))]

        let iView = UIActivityIndicatorView(style: .gray)
        navigationItem.titleView = iView
        self.activityView = iView

        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshData), for: .valueChanged)
        if #available(iOS 10.0, *) {
            tableView.refreshControl = refreshControl
        } else {
            tableView.addSubview(refreshControl)
        }

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: NSStringFromClass(UITableViewCell.self))
        tableView.register(TableCell.self, forCellReuseIdentifier: NSStringFromClass(TableCell.self))
        let users = Global.rtUsers
        delegate = SingleSectionTableViewDelegate(users) { (table, ip, _) -> UITableViewCell in
            return table.dequeueReusableCell(withIdentifier: NSStringFromClass(TableCell.self), for: ip)
        }
        delegate.register(UITableViewCell.self) { (item, _, user, ip) in
            item.bind(user.name, { (cell, val) in
                cell.textLabel!.text <== val
            }, nil)
        }
        delegate.register(TableCell.self) { (item, cell, user, ip) in
            cell.startIndicatorIfNeeeded()
            item.bind(user.name, { (cell, name) in
                cell.label.text <== name
                cell.indicator.stopAnimating()
            }, nil)
        }
        delegate.bind(tableView)
        delegate.tableDelegate = self
        delegate.editingDataSource = self

        if !users.isObserved {
            iView.startAnimating()
        }

        users.changes
            .do({ [unowned self] e in
                refreshControl.endRefreshing()
                iView.stopAnimating()
                let titleView: UILabel = (self.navigationItem.titleView as? UILabel) ?? UILabel()
                switch e {
                case .value(let e):
                    titleView.text = "Event: \(e)"
                    titleView.textColor = .black
                case .error(let e):
                    titleView.textColor = UIColor.red.withAlphaComponent(0.7)
                    titleView.text = String(describing: e)
                }
                self.navigationItem.titleView = titleView
            })
            .listening(
                onValue: { [unowned self] change in
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
                },
                onError: { err in
                    print("Changes error:", err.localizedDescription)
                }
            ).add(to: store)

        /// second subscription to tests.
        users.changes
            .listening(
                onValue: { (e) in
                    print(e)
                },
                onError: { (err) in
                    print(err)
                }
        ).add(to: store)
    }

    let ascending: Bool = false
    let pagingControl: PagingControl = PagingControl()
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        #if FIREBASE
        Global.rtUsers.dataExplorer = .viewByPages(control: pagingControl, size: 2, ascending: ascending)
        #endif
        store.resume()
        Global.rtUsers.runObserving()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Global.rtUsers.stopObserving()
        store.pause()
        Global.rtUsers.dataExplorer = .view(ascending: ascending)
    }

    @objc func refreshData(_ control: UIRefreshControl) {
        if ascending {
            _ = pagingControl.next()
        } else {
            _ = pagingControl.previous()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(3)) {
            if control.isRefreshing {
                control.endRefreshing()
            }
        }
    }

    @objc func addUser() {
        let alertViewController = UIAlertController(title: "New user", message: "Fill form, please...", preferredStyle: .alert)

        var nameTF: UITextField! = nil
        alertViewController.addTextField { (tf) in
            tf.placeholder = "Name"
            nameTF = tf
        }
        var ageTF: UITextField! = nil
        alertViewController.addTextField { (tf) in
            tf.placeholder = "Age"
            ageTF = tf
        }
        alertViewController.addAction(UIAlertAction(title: "Save", style: .default, handler: { (_) in
            guard let name = nameTF.text else {
                nameTF.textColor = .red
                return
            }
            guard let age = ageTF.text.flatMap(Int8.init) else {
                ageTF.textColor = .red
                return
            }
            let transaction = Transaction()

            let user = User()
            user.name <== name
            user.age <== age

            try! Global.rtUsers.write(element: user, in: transaction)

            transaction.commit(with: { (_, error) in
                if let error = error {
                    debugPrint(error)
                    return
                }
            })
        }))
        alertViewController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        present(alertViewController, animated: true, completion: nil)
    }

    @objc func edit(_ control: UIBarButtonItem) {
        tableView.setEditing(!tableView.isEditing, animated: true)
    }
}

extension RealtimeTableController: RealtimeEditingTableDataSource {
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        print("Did select row at \(indexPath)")
    }

    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        return .delete
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        switch editingStyle {
        case .delete:
            guard Global.rtUsers.isSynced else {
                return print("Cannot be removed because collection is not synced")
            }
            activityView.startAnimating()
            presentDeleteAlert(
                collection: {
                    Global.rtUsers.remove(at: indexPath.row).commit { (_, err) in
                        self.activityView.stopAnimating()
                        if let e = err?.first {
                            print(e.localizedDescription)
                        }
                    }
                },
                object: {
                    Global.rtUsers[indexPath.row].delete().commit(with: { (_, err) in
                        self.activityView.stopAnimating()
                        if let e = err?.first {
                            print(e.localizedDescription)
                        }
                    })
            })
        default: break
        }
    }

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row == Global.rtUsers.count - 1, pagingControl.canMakeStep {
            _ = pagingControl.next()
        }
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return false
    }
}

extension RealtimeTableController {
    func presentDeleteAlert(collection: @escaping () -> Void, object: @escaping () -> Void) {
        let controller = UIAlertController(title: "", message: "Delete using:", preferredStyle: .alert)

        controller.addAction(UIAlertAction(title: "Collection", style: .default) { (_) in
            collection()
        })
        controller.addAction(UIAlertAction(title: "Object", style: .default) { (_) in
            object()
        })
        present(controller, animated: true, completion: nil)
    }
}
