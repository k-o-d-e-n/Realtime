//
//  TableViewController.swift
//  Realtime_Example
//
//  Created by Denis Koryttsev on 09/09/2018.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import Foundation
import Realtime

class TableViewController<Model>: UITableViewController {
    var listeningStore: ListeningDisposeStore = ListeningDisposeStore()
    let delegate: SingleSectionTableViewDelegate<Model>

    /// events
    var onDismiss: (() -> Void)?

    required init(delegate: SingleSectionTableViewDelegate<Model>) {
        self.delegate = delegate
        super.init(style: .plain)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(dismissAnimated))

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: NSStringFromClass(UITableViewCell.self))
        tableView.keyboardDismissMode = .onDrag

        delegate.bind(tableView)
    }

    @objc func dismissAnimated() {
        dismiss(animated: true, completion: nil)
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        let event = onDismiss
        super.dismiss(animated: flag) {
            completion?()
            event?()
        }
    }
}

class PickTableViewController<Model>: TableViewController<Model> {
    var didSelect: ((TableViewController<Model>, IndexPath, Model) -> (animated: Bool, completion: (() -> Void)?)?)?
    required init(delegate: SingleSectionTableViewDelegate<Model>) {
        super.init(delegate: delegate)
        delegate.tableDelegate = self
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let (animated, completion) = didSelect?(self, indexPath, delegate.model(at: indexPath)) {
            dismiss(animated: animated, completion: completion)
        }
    }
}
