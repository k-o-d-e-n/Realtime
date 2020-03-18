//
//  ViewController.swift
//  Realtime
//
//  Created by k-o-d-e-n on 01/11/2018.
//  Copyright (c) 2018 k-o-d-e-n. All rights reserved.
//

import UIKit
import Realtime
#if canImport(SwiftUI)
import SwiftUI
#endif

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
        // for testing implement function `auth(_ completion: @escaping () -> Void)` in Auth.swift
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
        if #available(iOS 13.0, *) {
            return 5
        } else {
            return 4
        }
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
        case 4:
            cell.textLabel?.text = "SwiftUI"
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
            let useBranchSwitcher = UISwitch(frame: CGRect(x: 180, y: -7, width: 50, height: 20))
            useBranchSwitcher.backgroundColor = .white
            useBranchSwitcher.layer.cornerRadius = 5
            alert.addTextField { (tf) in
                textField = tf
            }
            alert.addTextField { (tf) in
                tf.addSubview(useBranchSwitcher)
                tf.text = "Использовать branch mode"
            }
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { (_) in
                node = useBranchSwitcher.isOn ? BranchNode(key: textField.text ?? "") :  Node.root(textField.text ?? "")
                RealtimeApp.app.database.load(
                    for: node,
                    timeout: .seconds(5),
                    completion: { (data) in
                        print(data.asDict())
                        let alert = UIAlertController(title: "", message: "\(data)", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "ok", style: .default, handler: nil))
                        self.present(alert, animated: true, completion: nil)
                },
                    onCancel: { (err) in
                        print(err)
                        let alert = UIAlertController(title: "", message: "\(err)", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "ok", style: .default, handler: nil))
                        self.present(alert, animated: true, completion: nil)
                    }
                )
            }))
            present(alert, animated: true, completion: nil)
        case 4:
            #if canImport(SwiftUI) && FIREBASE
            if #available(iOS 13.0, *) {
                let user = User1(in: Node.root("users/0312be1d-06b2-4ec8-a49d-84ab27c28ed1"))
                let view = SwiftUIView(user: user)
                let controller = UIHostingController(rootView: view)
                navigationController?.pushViewController(controller, animated: true)
            }
            #endif
        default: break
        }
    }
}

extension RealtimeDataProtocol {
    func asDict() -> [String: Any] {
        guard let n = node else { return [:] }
        guard hasChildren() else { return [n.key: try! asDatabaseValue()] }

        return reduce(into: [String: Any](), updateAccumulatingResult: { res, dataNode in
            if let n = dataNode.node {
                res[n.key] = dataNode.asDict()
            }
        })
    }
}
