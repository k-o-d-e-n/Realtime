//
//  ViewController.swift
//  Realtime
//
//  Created by k-o-d-e-n on 01/11/2018.
//  Copyright (c) 2018 k-o-d-e-n. All rights reserved.
//

import UIKit
import Realtime

class ViewController: UIViewController {
    var disposeBag = ListeningDisposeStore()

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)

        /// for testing implement your auth function in Auth.swift
        auth {
            let realtimeViewController = touches.first!.location(in: self.view).x > self.view.frame.width / 2 ? RealtimeViewController() : RealtimeTableController()
            self.navigationController?.pushViewController(realtimeViewController, animated: true)
        }
    }
}

class TableViewController<Collection: RealtimeCollection>: UITableViewController where Collection.Index == Int {
    let list: Collection
    var realtimeAdapter: RealtimeTableAdapter<Collection>!

    required init(list: Collection, configure: (RealtimeTableAdapter<Collection>) -> Void) {
        self.list = list
        super.init(style: .plain)
        self.realtimeAdapter = RealtimeTableAdapter<Collection>(tableView: self.tableView, collection: list)
        configure(self.realtimeAdapter)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        list.prepare(forUse: .just { _ in })
    }
}
