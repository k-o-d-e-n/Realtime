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
    lazy var label: UILabel = UILabel().add(to: self.contentView) {
        $0.numberOfLines = 0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds
    }
}

class RealtimeTableController: UIViewController {
    var store = ListeningDisposeStore()
    var tableView: UITableView! { return view as! UITableView }
    var delegate: SingleSectionTableViewDelegate<User>!

    override func loadView() {
        view = UITableView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: NSStringFromClass(UITableViewCell.self))
        tableView.register(TableCell.self, forCellReuseIdentifier: NSStringFromClass(TableCell.self))
        let users = Values<User>(in: Node(key: "users", parent: .root))
        delegate = SingleSectionTableViewDelegate(users) { (table, ip, _) -> UITableViewCell in
            return table.dequeueReusableCell(withIdentifier: NSStringFromClass(TableCell.self), for: ip)
        }
        delegate.register(UITableViewCell.self) { (item, user) in
            item.bind(user.name) { (cell, val) in
                cell.textLabel!.text =? val
            }
        }
        delegate.register(TableCell.self) { (item, user) in
            item.bind(user.name) { (cell, name) in
                cell.label.text =? name
            }
        }
        delegate.bind(tableView)
        delegate.tableDelegate = self

        users.listening { [weak self] in
            self?.tableView.reloadData()
        }.add(to: &store)

        users.prepare(forUse: .just { _ in })
    }
}

extension RealtimeTableController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        print("Did select row at \(indexPath)")
    }
}
