//
//  ViewController.swift
//  Realtime
//
//  Created by k-o-d-e-n on 01/11/2018.
//  Copyright (c) 2018 k-o-d-e-n. All rights reserved.
//

import UIKit
import Realtime

class Object: RealtimeObject {
    lazy var id: StandartProperty<String?> = "id".property(from: self.dbRef)
    lazy var array: RealtimeArray<Object> = "array".array(from: self.dbRef)

    lazy var name: StandartProperty<String?> = "human/name/firstname".property(from: self.dbRef)
}

class ViewController: UIViewController {
    var disposeBag = ListeningDisposeStore()
    let node = RealtimeNode(rawValue: "node")

    override func viewDidLoad() {
        super.viewDidLoad()
        var logo = AsyncReadonlyProperty<String?>(value: nil) { (setter) in
        }

        _ = logo.insider.listen(.just { print($0 as Any) })
        _ = logo.insider.listen(as: { $0.queue(.main) }, .guarded(self) { _, _ in

        })
        var count = 0
        _ = logo.insider.listen(as: { $0.livetime(self) }, preprocessor: { $0.map { $0!.count } }, .just {
            count = $0
        })
        print(count)

        let object = Object(dbRef: .root())
        object.id.listening(Assign.guarded(self) { (v, o) in

        }.on(queue: .main)).add(to: &disposeBag)
        object.id.listeningItem(.on(.main) { v in

        }).add(to: &disposeBag)

        _ = object.array.contains(object)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)

        /// for testing implement your auth function in Auth.swift
        auth {
//            let users: RealtimeArray<Object> = "users".array(from: .root())
//            let usersController = TableViewController(list: users) { (adapter) in
//                adapter.register(UITableViewCell.self) { (proto, entity) -> [ListeningItem] in
//                    entity.name.runObserving()
//                    let assign: (String?) -> Void = proto.assign { cell, data in
//                        cell.textLabel?.text = data ?? "No name"
//                    }
//
//                    return [entity.name.listeningItem(.just(assign))]
//                }
//                adapter.cellForIndexPath = { _ in UITableViewCell.self }
//            }
            let realtimeViewController = RealtimeViewController()
            self.navigationController?.pushViewController(realtimeViewController, animated: true)
        }
    }
}

class TableViewController<Collection: RealtimeCollection>: UITableViewController where Collection.Index == Int, Collection.IndexDistance == Int {
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

        list.prepare(forUse: { _ in })
    }
}
