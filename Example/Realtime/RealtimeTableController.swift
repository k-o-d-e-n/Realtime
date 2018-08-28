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

        users.listening { [weak self] in
            self?.tableView.reloadData()
        }.add(to: &store)

        iView.startAnimating()
        users.prepare(forUse: .just { u, e in
            iView.stopAnimating()
            u.forEach({ (user) in
                /// unnecessary, is used for tests
                user.name.runObserving()
            })
        })
    }
}

extension RealtimeTableController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        print("Did select row at \(indexPath)")
    }
}
