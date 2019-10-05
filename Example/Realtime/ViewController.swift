//
//  ViewController.swift
//  Realtime
//
//  Created by k-o-d-e-n on 01/11/2018.
//  Copyright (c) 2018 k-o-d-e-n. All rights reserved.
//

import UIKit
import Realtime

class ViewController: UITableViewController {
    var disposeBag = ListeningDisposeStore()
    weak var activityView: UIActivityIndicatorView!

    override func viewDidLoad() {
        super.viewDidLoad()

        let iView = UIActivityIndicatorView(style: .gray)
        navigationItem.titleView = iView
        self.activityView = iView

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

        #if FIREBASE
        iView.startAnimating()
        tableView.isUserInteractionEnabled = false
        /// for testing implement function `auth(_ completion: @escaping () -> Void)` in Auth.swift
        auth {
            iView.stopAnimating()
            self.tableView.isUserInteractionEnabled = true
        }
        #endif
    }
}
extension ViewController {
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 4
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        switch indexPath.row {
        case 0:
            cell.textLabel?.text = "Console"
        case 1:
            cell.textLabel?.text = "Table"
        case 2:
            cell.textLabel?.text = "Form"
        case 3:
            cell.textLabel?.text = "Load"
        default: break
        }
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch indexPath.row {
        case 0: navigationController?.pushViewController(RealtimeViewController(), animated: true)
        case 1: navigationController?.pushViewController(RealtimeTableController(), animated: true)
        case 2: navigationController?.pushViewController(FormViewController(), animated: true)
        case 3:
            let alert = UIAlertController(title: "PATH", message: "", preferredStyle: .alert)
            var node: Node!
            var textField: UITextField!
            alert.addTextField { (tf) in
                textField = tf
            }
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { (_) in
                node = Node.root(textField.text ?? "")
                RealtimeApp.app.database.load(
                    for: node,
                    timeout: .never,
                    completion: { (data) in
                        print(data)
                        let alert = UIAlertController(title: "", message: "\(data)", preferredStyle: .alert)
                        self.present(alert, animated: true, completion: nil)
                },
                    onCancel: { (err) in
                        print(err)
                }
                )
            }))
            present(alert, animated: true, completion: nil)
        default: break
        }
    }
}
